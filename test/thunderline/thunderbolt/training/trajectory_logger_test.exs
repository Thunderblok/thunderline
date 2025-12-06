defmodule Thunderline.Thunderbolt.Training.TrajectoryLoggerTest do
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.Training.TrajectoryLogger

  setup do
    # Start a logger with a unique name for each test
    name = :"trajectory_logger_test_#{:erlang.unique_integer([:positive])}"
    export_path = Path.join(System.tmp_dir!(), "trajectory_test_#{:erlang.unique_integer()}")

    {:ok, pid} =
      TrajectoryLogger.start_link(
        name: name,
        backend: :ets,
        export_path: export_path,
        max_steps: 1000
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 1000)
      end

      File.rm_rf(export_path)
    end)

    {:ok, name: name, export_path: export_path}
  end

  describe "log_thunderbit_step/6" do
    test "logs a thunderbit step", %{name: name} do
      bit = %{
        id: "bit_1",
        category: :task,
        energy: 0.8,
        health: 0.9,
        status: :active
      }

      next_bit = %{
        id: "bit_1",
        category: :task,
        energy: 0.7,
        health: 0.85,
        status: :active
      }

      context = %{tick: 100, active_bits: [bit]}

      :ok = TrajectoryLogger.log_thunderbit_step(bit, :transition, 1.0, next_bit, context, server: name)

      # Give cast time to process
      Process.sleep(50)

      stats = TrajectoryLogger.stats(server: name)
      assert stats.total_steps == 1
      assert :thunderbit in stats.sources
    end
  end

  describe "log_chief_step/5" do
    test "logs a chief step", %{name: name} do
      chief_state = %{
        active_count: 10,
        pending_count: 5,
        total_energy: 7.5,
        avg_health: 0.8,
        tick: 500
      }

      outcome = %{
        success?: true,
        next_state: %{active_count: 11, pending_count: 4}
      }

      :ok = TrajectoryLogger.log_chief_step(:bit, chief_state, :activate_pending, outcome, server: name)

      # Give cast time to process
      Process.sleep(50)

      stats = TrajectoryLogger.stats(server: name)
      assert stats.total_steps == 1
      assert :bit in stats.sources
    end
  end

  describe "log_episode/3" do
    test "logs a complete episode", %{name: name} do
      steps = [
        %{state: List.duplicate(0.5, 24), action: :wait, action_idx: 0, reward: 0.0, next_state: List.duplicate(0.5, 24), done: false, metadata: %{}},
        %{state: List.duplicate(0.5, 24), action: :activate_pending, action_idx: 3, reward: 1.0, next_state: List.duplicate(0.6, 24), done: false, metadata: %{}},
        %{state: List.duplicate(0.6, 24), action: :transition, action_idx: 4, reward: 0.5, next_state: List.duplicate(0.7, 24), done: true, metadata: %{}}
      ]

      :ok = TrajectoryLogger.log_episode(:test_episode, steps, server: name)

      # Give cast time to process
      Process.sleep(50)

      stats = TrajectoryLogger.stats(server: name)
      assert stats.step_counts[:test_episode] == 3
    end
  end

  describe "export_training_batch/2" do
    test "exports empty batch when no data", %{name: name} do
      {:ok, batch} = TrajectoryLogger.export_training_batch(:nonexistent, server: name)

      assert batch.count == 0
      assert batch.states == []
    end

    test "exports training batch in numpy format", %{name: name} do
      # Log some steps
      chief_state = %{active_count: 10, tick: 100}
      outcome = %{success?: true}

      for i <- 1..5 do
        TrajectoryLogger.log_chief_step(:test, %{chief_state | tick: i * 100}, :wait, outcome, server: name)
      end

      Process.sleep(100)

      {:ok, batch} = TrajectoryLogger.export_training_batch(:test, server: name, format: :numpy)

      assert batch.count == 5
      assert length(batch.states) == 5
      assert length(batch.actions) == 5
      assert length(batch.rewards) == 5
      assert length(batch.next_states) == 5
      assert length(batch.dones) == 5
    end

    test "respects limit option", %{name: name} do
      # Log many steps
      chief_state = %{active_count: 10, tick: 100}
      outcome = %{success?: true}

      for i <- 1..20 do
        TrajectoryLogger.log_chief_step(:limited, %{chief_state | tick: i * 100}, :wait, outcome, server: name)
      end

      Process.sleep(100)

      {:ok, batch} = TrajectoryLogger.export_training_batch(:limited, server: name, limit: 5)

      assert batch.count == 5
    end
  end

  describe "stats/1" do
    test "returns stats for empty logger", %{name: name} do
      stats = TrajectoryLogger.stats(server: name)

      assert stats.backend == :ets
      assert stats.total_steps == 0
      assert stats.sources == []
    end
  end

  describe "clear/2" do
    test "clears data for specific source", %{name: name} do
      chief_state = %{active_count: 10}
      outcome = %{success?: true}

      TrajectoryLogger.log_chief_step(:source_a, chief_state, :wait, outcome, server: name)
      TrajectoryLogger.log_chief_step(:source_b, chief_state, :wait, outcome, server: name)
      Process.sleep(50)

      :ok = TrajectoryLogger.clear(:source_a, server: name)

      stats = TrajectoryLogger.stats(server: name)
      assert stats.step_counts[:source_a] == nil
      assert stats.step_counts[:source_b] == 1
    end

    test "clears all data", %{name: name} do
      chief_state = %{active_count: 10}
      outcome = %{success?: true}

      TrajectoryLogger.log_chief_step(:source_a, chief_state, :wait, outcome, server: name)
      TrajectoryLogger.log_chief_step(:source_b, chief_state, :wait, outcome, server: name)
      Process.sleep(50)

      :ok = TrajectoryLogger.clear(:all, server: name)

      stats = TrajectoryLogger.stats(server: name)
      assert stats.total_steps == 0
    end
  end

  describe "action_to_index/1" do
    test "returns correct index for known actions" do
      assert TrajectoryLogger.action_to_index(:wait) == 0
      assert TrajectoryLogger.action_to_index(:consolidate) == 1
      assert TrajectoryLogger.action_to_index(:activate_pending) == 3
      assert TrajectoryLogger.action_to_index(:transition) == 4
      assert TrajectoryLogger.action_to_index(:cerebros_evaluate) == 5
      assert TrajectoryLogger.action_to_index(:spawn_workflow) == 10
    end

    test "returns 99 for unknown actions" do
      assert TrajectoryLogger.action_to_index(:unknown_action) == 99
      assert TrajectoryLogger.action_to_index("string_action") == 99
      assert TrajectoryLogger.action_to_index(123) == 99
    end

    test "handles tuple actions with params" do
      assert TrajectoryLogger.action_to_index({:wait, %{}}) == 0
      assert TrajectoryLogger.action_to_index({:transition, %{reason: :test}}) == 4
    end
  end

  describe "stream_to_file/2" do
    test "streams data to JSONL file", %{name: name, export_path: export_path} do
      # Log some steps
      chief_state = %{active_count: 10}
      outcome = %{success?: true}

      for _ <- 1..3 do
        TrajectoryLogger.log_chief_step(:test, chief_state, :wait, outcome, server: name)
      end

      Process.sleep(100)

      output_file = Path.join(export_path, "export.jsonl")
      :ok = TrajectoryLogger.stream_to_file(output_file, server: name)

      assert File.exists?(output_file)
      lines = File.read!(output_file) |> String.split("\n", trim: true)
      assert length(lines) == 3

      # Verify each line is valid JSON
      for line <- lines do
        assert {:ok, _} = Jason.decode(line)
      end
    end
  end
end
