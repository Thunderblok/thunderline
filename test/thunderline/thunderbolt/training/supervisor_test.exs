defmodule Thunderline.Thunderbolt.Training.SupervisorTest do
  @moduledoc """
  Tests for Training.Supervisor startup and child management.
  """
  use ExUnit.Case, async: false

  alias Thunderline.Thunderbolt.Training.Supervisor, as: TrainingSup
  alias Thunderline.Thunderbolt.Training.TPEClient
  alias Thunderline.Thunderbolt.Training.TrajectoryLogger

  describe "start_link/1" do
    test "starts the supervisor with default children" do
      # Start with unique name to avoid conflicts
      name = :"training_sup_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = TrainingSup.start_link(name: name)

      assert Process.alive?(pid)

      # Check children are started
      children = Supervisor.which_children(pid)
      assert length(children) == 2

      child_ids = children |> Enum.map(fn {id, _, _, _} -> id end) |> Enum.sort()
      expected = [TPEClient, TrajectoryLogger] |> Enum.sort()
      assert child_ids == expected

      # Cleanup
      Supervisor.stop(pid)
    end

    test "children are GenServer processes" do
      name = :"training_sup_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = TrainingSup.start_link(name: name)

      children = Supervisor.which_children(pid)

      for {id, child_pid, type, _modules} <- children do
        assert is_pid(child_pid), "Child #{id} should have a pid"
        assert Process.alive?(child_pid), "Child #{id} should be alive"
        assert type == :worker, "Child #{id} should be a worker"
      end

      Supervisor.stop(pid)
    end
  end
end
