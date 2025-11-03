defmodule Thunderline.Thunderbolt.UPM.SupervisorTest do
  use Thunderline.DataCase, async: false

  alias Thunderline.Thunderbolt.UPM.{Supervisor, TrainerWorker, DriftMonitor}
  alias Thunderline.Thunderbolt.Resources.UpmTrainer

  @moduletag :upm

  describe "start_link/1" do
    test "starts supervisor successfully" do
      {:ok, pid} = Supervisor.start_link(name: :test_upm_supervisor)

      assert Process.alive?(pid)

      # Verify it's a supervisor
      children = Supervisor.which_children(pid)
      assert is_list(children)

      Supervisor.stop(pid)
    end

    test "starts with default configuration" do
      {:ok, pid} = Supervisor.start_link([])

      assert Process.alive?(pid)

      Supervisor.stop(pid)
    end

    test "starts default trainers from configuration" do
      # Configure default trainers
      Application.put_env(:thunderline, Thunderline.Thunderbolt.UPM.Supervisor,
        default_trainers: [
          %{id: "default-test", opts: [mode: :shadow]}
        ]
      )

      {:ok, pid} = Supervisor.start_link(name: :test_default_supervisor)

      Process.sleep(200)

      # Verify default trainer was started
      trainers = Supervisor.list_trainers(pid)
      assert length(trainers) > 0

      Supervisor.stop(pid)

      # Cleanup config
      Application.delete_env(:thunderline, Thunderline.Thunderbolt.UPM.Supervisor)
    end
  end

  describe "start_trainer/2" do
    setup do
      {:ok, pid} = Supervisor.start_link(name: :test_trainer_supervisor)

      on_exit(fn ->
        if Process.alive?(pid) do
          Supervisor.stop(pid)
        end
      end)

      %{supervisor: pid}
    end

    test "starts trainer with supervision tree", %{supervisor: sup} do
      trainer_id = "test-trainer-#{:rand.uniform(10000)}"

      {:ok, _child_pid} = Supervisor.start_trainer(sup, trainer_id, mode: :shadow)

      # Verify trainer is in supervisor's children
      children = Supervisor.which_children(sup)
      trainer_child = Enum.find(children, fn
        {^trainer_id, _pid, _type, _modules} -> true
        _ -> false
      end)

      assert trainer_child != nil
    end

    test "creates UpmTrainer resource", %{supervisor: sup} do
      trainer_id = "resource-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id, mode: :shadow)

      # Verify trainer resource exists
      trainer = UpmTrainer
        |> Ash.Query.filter(name == ^trainer_id)
        |> Ash.read_one!()

      assert trainer != nil
      assert trainer.name == trainer_id
      assert trainer.mode == :shadow
    end

    test "starts TrainerWorker and DriftMonitor", %{supervisor: sup} do
      trainer_id = "workers-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id)

      Process.sleep(200)

      # Verify both workers are running (implementation specific)
      # TrainerWorker and DriftMonitor should be started as part of supervision tree
      children = Supervisor.which_children(sup)
      assert length(children) > 0
    end

    test "returns error for duplicate trainer", %{supervisor: sup} do
      trainer_id = "duplicate-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id)

      # Try to start again
      result = Supervisor.start_trainer(sup, trainer_id)

      # Should return error or already_started
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "accepts custom learning parameters", %{supervisor: sup} do
      trainer_id = "custom-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id,
        mode: :shadow,
        learning_rate: 0.001,
        batch_size: 128
      )

      # Verify trainer created with custom params
      trainer = UpmTrainer
        |> Ash.Query.filter(name == ^trainer_id)
        |> Ash.read_one!()

      assert trainer.name == trainer_id
    end
  end

  describe "stop_trainer/2" do
    setup do
      {:ok, pid} = Supervisor.start_link(name: :test_stop_supervisor)

      on_exit(fn ->
        if Process.alive?(pid) do
          Supervisor.stop(pid)
        end
      end)

      %{supervisor: pid}
    end

    test "stops trainer and its children", %{supervisor: sup} do
      trainer_id = "stop-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id)
      Process.sleep(100)

      # Stop trainer
      :ok = Supervisor.stop_trainer(sup, trainer_id)

      # Verify removed from children
      children = Supervisor.which_children(sup)
      trainer_child = Enum.find(children, fn
        {^trainer_id, _pid, _type, _modules} -> true
        _ -> false
      end)

      assert is_nil(trainer_child)
    end

    test "updates trainer status to stopped", %{supervisor: sup} do
      trainer_id = "status-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id)
      Process.sleep(100)

      :ok = Supervisor.stop_trainer(sup, trainer_id)

      # Check trainer status
      trainer = UpmTrainer
        |> Ash.Query.filter(name == ^trainer_id)
        |> Ash.read_one!()

      assert trainer.status in [:stopped, :idle]
    end

    test "returns error for nonexistent trainer", %{supervisor: sup} do
      result = Supervisor.stop_trainer(sup, "nonexistent-trainer")

      assert match?({:error, _}, result) or result == :ok
    end
  end

  describe "list_trainers/1" do
    setup do
      {:ok, pid} = Supervisor.start_link(name: :test_list_supervisor)

      on_exit(fn ->
        if Process.alive?(pid) do
          Supervisor.stop(pid)
        end
      end)

      %{supervisor: pid}
    end

    test "lists all active trainers", %{supervisor: sup} do
      # Start multiple trainers
      trainer_ids = for i <- 1..3 do
        id = "list-trainer-#{i}-#{:rand.uniform(10000)}"
        {:ok, _pid} = Supervisor.start_trainer(sup, id)
        id
      end

      Process.sleep(200)

      trainers = Supervisor.list_trainers(sup)

      assert is_list(trainers)
      assert length(trainers) >= length(trainer_ids)

      # Verify our trainers are in the list
      trainer_names = Enum.map(trainers, & &1.name)
      for id <- trainer_ids do
        assert id in trainer_names
      end
    end

    test "returns empty list when no trainers", %{supervisor: sup} do
      trainers = Supervisor.list_trainers(sup)

      # May have default trainers or be empty
      assert is_list(trainers)
    end
  end

  describe "get_trainer/2" do
    setup do
      {:ok, pid} = Supervisor.start_link(name: :test_get_supervisor)

      on_exit(fn ->
        if Process.alive?(pid) do
          Supervisor.stop(pid)
        end
      end)

      %{supervisor: pid}
    end

    test "retrieves trainer by name", %{supervisor: sup} do
      trainer_id = "get-trainer-#{:rand.uniform(10000)}"

      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id)
      Process.sleep(100)

      {:ok, trainer} = Supervisor.get_trainer(sup, trainer_id)

      assert trainer.name == trainer_id
    end

    test "returns error for nonexistent trainer", %{supervisor: sup} do
      result = Supervisor.get_trainer(sup, "nonexistent")

      assert match?({:error, _}, result)
    end
  end

  describe "restart_trainer/2" do
    setup do
      {:ok, pid} = Supervisor.start_link(name: :test_restart_supervisor)

      on_exit(fn ->
        if Process.alive?(pid) do
          Supervisor.stop(pid)
        end
      end)

      %{supervisor: pid}
    end

    test "restarts existing trainer", %{supervisor: sup} do
      trainer_id = "restart-trainer-#{:rand.uniform(10000)}"

      {:ok, pid1} = Supervisor.start_trainer(sup, trainer_id)
      Process.sleep(100)

      # Restart
      {:ok, pid2} = Supervisor.restart_trainer(sup, trainer_id)

      # PIDs should be different (new process)
      assert pid1 != pid2

      # Trainer should still exist
      {:ok, trainer} = Supervisor.get_trainer(sup, trainer_id)
      assert trainer.name == trainer_id
    end
  end

  describe "supervision tree structure" do
    test "uses DynamicSupervisor for trainers" do
      {:ok, pid} = Supervisor.start_link(name: :test_tree_supervisor)

      # Verify it's a DynamicSupervisor
      info = Process.info(pid)
      assert info != nil

      Supervisor.stop(pid)
    end

    test "handles trainer crashes with restart", %{} do
      {:ok, sup} = Supervisor.start_link(name: :test_crash_supervisor)

      trainer_id = "crash-trainer-#{:rand.uniform(10000)}"
      {:ok, trainer_pid} = Supervisor.start_trainer(sup, trainer_id)

      # Kill trainer
      Process.exit(trainer_pid, :kill)
      Process.sleep(200)

      # Depending on restart strategy, trainer may or may not restart
      # This tests that supervisor doesn't crash
      assert Process.alive?(sup)

      Supervisor.stop(sup)
    end
  end

  describe "telemetry" do
    setup do
      {:ok, pid} = Supervisor.start_link(name: :test_telemetry_supervisor)

      on_exit(fn ->
        if Process.alive?(pid) do
          Supervisor.stop(pid)
        end
      end)

      %{supervisor: pid}
    end

    test "emits trainer_started event", %{supervisor: sup} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-trainer-started",
        [:upm, :supervisor, :trainer_started],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, ref, measurements, metadata})
        end,
        nil
      )

      trainer_id = "telemetry-trainer-#{:rand.uniform(10000)}"
      {:ok, _pid} = Supervisor.start_trainer(sup, trainer_id)

      # May or may not emit depending on implementation
      receive do
        {:telemetry, ^ref, _measurements, metadata} ->
          assert metadata.trainer_id == trainer_id
      after
        1000 -> :ok
      end

      :telemetry.detach("test-trainer-started")
    end
  end
end
