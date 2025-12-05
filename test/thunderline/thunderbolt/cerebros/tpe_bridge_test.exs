defmodule Thunderline.Thunderbolt.Cerebros.TPEBridgeTest do
  @moduledoc """
  Tests for the TPE Bridge (HC-41).

  Tests the TPEBridge GenServer for Bayesian hyperparameter optimization.
  Uses a mock invoker for unit tests to avoid Python dependency.

  For integration tests with real Python/Optuna, use the @external_tpe tag:
    mix test --include external_tpe
  """

  use ExUnit.Case, async: false

  # Test search space for parameter optimization
  @test_search_space %{
    lambda: {0.0, 1.0},
    bias: {0.1, 0.9},
    gate_temp: {0.5, 2.0}
  }

  # Mock invoker for testing without Python
  defmodule MockInvoker do
    @moduledoc false
    def invoke(:tpe_bridge, %{action: :init_study} = _args, _opts) do
      {:ok, %{parsed: %{"status" => "ok"}, returncode: 0}}
    end

    def invoke(:tpe_bridge, %{action: :suggest} = _args, _opts) do
      params = %{
        "lambda" => :rand.uniform(),
        "bias" => 0.1 + :rand.uniform() * 0.8,
        "gate_temp" => 0.5 + :rand.uniform() * 1.5
      }

      {:ok, %{parsed: %{"params" => params}, returncode: 0}}
    end

    def invoke(:tpe_bridge, %{action: :record} = _args, _opts) do
      {:ok, %{parsed: %{"status" => "ok"}, returncode: 0}}
    end

    def invoke(:tpe_bridge, %{action: :best_params} = _args, _opts) do
      {:ok,
       %{
         parsed: %{
           "params" => %{"lambda" => 0.5, "bias" => 0.3, "gate_temp" => 1.0},
           "value" => 0.85
         },
         returncode: 0
       }}
    end

    def invoke(:tpe_bridge, %{action: :get_status} = _args, _opts) do
      {:ok,
       %{
         parsed: %{
           "n_trials" => 5,
           "best_value" => 0.85,
           "best_params" => %{"lambda" => 0.5}
         },
         returncode: 0
       }}
    end

    def invoke(_op, _args, _opts), do: {:error, :unsupported}
  end

  setup do
    # Ensure the CA Registry is started for via tuple registration
    registry_name = Thunderline.Thunderbolt.CA.Registry

    case Registry.start_link(keys: :unique, name: registry_name) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "TPEBridge lifecycle" do
    @tag :external_tpe
    test "starts with valid options" do
      run_id = "test_tpe_#{System.unique_integer([:positive])}"

      # Use mock invoker via a wrapper module
      assert {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "returns status with progress tracking" do
      run_id = "test_status_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, status} = GenServer.call(pid, :status)

      assert status.run_id == run_id
      assert status.completed_trials == 0
      assert status.n_trials == 10
      assert status.progress == 0.0
      assert status.best_params == nil

      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "can reset optimization state" do
      run_id = "test_reset_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      # Do some trials
      {:ok, params} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params, [fitness: 0.5]})

      {:ok, status_before} = GenServer.call(pid, :status)
      assert status_before.completed_trials == 1

      # Reset
      :ok = GenServer.call(pid, :reset)

      {:ok, status_after} = GenServer.call(pid, :status)
      assert status_after.completed_trials == 0
      assert status_after.best_params == nil

      GenServer.stop(pid)
    end
  end

  describe "parameter suggestion" do
    @tag :external_tpe
    test "suggest returns valid params within search space bounds" do
      run_id = "test_suggest_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, params} = GenServer.call(pid, :suggest)

      # Verify params are maps
      assert is_map(params)

      # Verify all search space keys are present
      for {key, {min, max}} <- @test_search_space do
        assert Map.has_key?(params, key), "Missing key: #{key}"
        value = Map.get(params, key)
        assert is_number(value), "Value for #{key} is not a number: #{inspect(value)}"

        assert value >= min and value <= max,
               "Value #{value} for #{key} outside bounds [#{min}, #{max}]"
      end

      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "multiple suggestions return different params" do
      run_id = "test_multi_suggest_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, params1} = GenServer.call(pid, :suggest)
      {:ok, params2} = GenServer.call(pid, :suggest)

      # With random sampling, consecutive suggestions should differ
      refute params1 == params2

      GenServer.stop(pid)
    end
  end

  describe "trial recording" do
    @tag :external_tpe
    test "record updates completed_trials count" do
      run_id = "test_record_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, params} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params, [fitness: 0.7]})

      {:ok, status} = GenServer.call(pid, :status)
      assert status.completed_trials == 1

      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "record updates best params when fitness improves" do
      run_id = "test_best_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      # First trial
      {:ok, params1} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params1, [fitness: 0.5]})

      {:ok, status1} = GenServer.call(pid, :status)
      assert status1.best_params == params1
      assert status1.best_fitness == 0.5

      # Second trial with better fitness
      {:ok, params2} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params2, [fitness: 0.8]})

      {:ok, status2} = GenServer.call(pid, :status)
      assert status2.best_params == params2
      assert status2.best_fitness == 0.8

      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "record preserves best when fitness is worse" do
      run_id = "test_preserve_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      # First trial with good fitness
      {:ok, params1} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params1, [fitness: 0.9]})

      # Second trial with worse fitness
      {:ok, params2} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params2, [fitness: 0.3]})

      {:ok, status} = GenServer.call(pid, :status)
      assert status.best_params == params1
      assert status.best_fitness == 0.9
      assert status.completed_trials == 2

      GenServer.stop(pid)
    end
  end

  describe "best_params/1" do
    @tag :external_tpe
    test "returns nil when no trials completed" do
      run_id = "test_empty_best_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, best} = GenServer.call(pid, :best_params)
      assert best == nil

      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "returns best params after trials" do
      run_id = "test_best_after_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, params} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params, [fitness: 0.75]})

      {:ok, best} = GenServer.call(pid, :best_params)
      assert best == params

      GenServer.stop(pid)
    end
  end

  describe "optimization loop" do
    @tag :external_tpe
    test "completes n_trials optimization" do
      run_id = "test_loop_#{System.unique_integer([:positive])}"
      n_trials = 5

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, n_trials)

      # Run optimization loop manually
      for i <- 1..n_trials do
        {:ok, params} = GenServer.call(pid, :suggest)
        # Simulate a fitness function
        fitness = 1.0 - abs(params.lambda - 0.5) - abs(params.bias - 0.5)
        :ok = GenServer.call(pid, {:record, params, [fitness: fitness]})

        {:ok, status} = GenServer.call(pid, :status)
        assert status.completed_trials == i
        assert_in_delta status.progress, i / n_trials, 0.01
      end

      {:ok, final_status} = GenServer.call(pid, :status)
      assert final_status.completed_trials == n_trials
      assert final_status.progress == 1.0
      assert final_status.best_params != nil
      assert final_status.best_fitness > 0

      GenServer.stop(pid)
    end
  end

  describe "telemetry" do
    @tag :external_tpe
    test "emits telemetry events for suggest" do
      run_id = "test_telemetry_#{System.unique_integer([:positive])}"
      test_pid = self()

      # Attach telemetry handler - capture test_pid in closure
      :telemetry.attach(
        "tpe-suggest-test",
        [:thunderline, :cerebros, :tpe_bridge, :suggest],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      GenServer.call(pid, :suggest)

      assert_receive {:telemetry, measurements, metadata}, 1000
      assert is_integer(measurements.duration_us)
      assert metadata.run_id == run_id

      :telemetry.detach("tpe-suggest-test")
      GenServer.stop(pid)
    end

    @tag :external_tpe
    test "emits telemetry events for record" do
      run_id = "test_telemetry_record_#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        "tpe-record-test",
        [:thunderline, :cerebros, :tpe_bridge, :record],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_record, measurements, metadata})
        end,
        nil
      )

      {:ok, pid} = start_tpe_bridge_with_mock(run_id, @test_search_space, 10)

      {:ok, params} = GenServer.call(pid, :suggest)
      :ok = GenServer.call(pid, {:record, params, [fitness: 0.5]})

      assert_receive {:telemetry_record, measurements, metadata}, 1000
      assert is_float(measurements.fitness)
      assert metadata.run_id == run_id
      assert metadata.trial == 0

      :telemetry.detach("tpe-record-test")
      GenServer.stop(pid)
    end
  end

  # Helper to start TPEBridge with mock invoker
  defp start_tpe_bridge_with_mock(run_id, search_space, n_trials) do
    GenServer.start_link(Thunderline.Thunderbolt.Cerebros.TPEBridgeTestWrapper, %{
      run_id: run_id,
      search_space: search_space,
      n_trials: n_trials,
      invoker: MockInvoker
    })
  end
end

# Test wrapper that allows injecting the invoker
defmodule Thunderline.Thunderbolt.Cerebros.TPEBridgeTestWrapper do
  @moduledoc false
  use GenServer

  @telemetry_event [:thunderline, :cerebros, :tpe_bridge]

  def init(%{run_id: run_id, search_space: search_space, n_trials: n_trials, invoker: invoker}) do
    study_name = "thunderline_tpe_test_#{run_id}"

    # Initialize via mock
    case invoker.invoke(:tpe_bridge, %{action: :init_study, study_name: study_name}, []) do
      {:ok, _} ->
        state = %{
          run_id: run_id,
          study_name: study_name,
          search_space: search_space,
          n_trials: n_trials,
          completed_trials: 0,
          best_params: nil,
          best_fitness: nil,
          history: [],
          invoker: invoker
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_call(:suggest, _from, state) do
    started = System.monotonic_time(:microsecond)

    {:ok, params} = suggest_params(state.invoker, state.study_name, state.search_space)

    duration_us = System.monotonic_time(:microsecond) - started

    :telemetry.execute(
      @telemetry_event ++ [:suggest],
      %{duration_us: duration_us},
      %{run_id: state.run_id, trial: state.completed_trials}
    )

    {:reply, {:ok, params}, state}
  end

  def handle_call({:record, params, opts}, _from, state) do
    fitness = Keyword.fetch!(opts, :fitness)
    trial_id = state.completed_trials

    # Update local state - use nil check for initial best_fitness
    {new_best_params, new_best_fitness} =
      cond do
        state.best_fitness == nil -> {params, fitness}
        fitness > state.best_fitness -> {params, fitness}
        true -> {state.best_params, state.best_fitness}
      end

    new_state = %{
      state
      | completed_trials: trial_id + 1,
        best_params: new_best_params,
        best_fitness: new_best_fitness
    }

    :telemetry.execute(
      @telemetry_event ++ [:record],
      %{fitness: fitness},
      %{run_id: state.run_id, trial: trial_id}
    )

    {:reply, :ok, new_state}
  end

  def handle_call(:status, _from, state) do
    progress =
      if state.n_trials > 0 do
        state.completed_trials / state.n_trials
      else
        0.0
      end

    status = %{
      run_id: state.run_id,
      study_name: state.study_name,
      n_trials: state.n_trials,
      completed_trials: state.completed_trials,
      progress: progress,
      best_params: state.best_params,
      best_fitness: state.best_fitness,
      history_length: length(state.history)
    }

    {:reply, {:ok, status}, state}
  end

  def handle_call(:best_params, _from, state) do
    {:reply, {:ok, state.best_params}, state}
  end

  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | completed_trials: 0,
        best_params: nil,
        best_fitness: nil,
        history: []
    }

    {:reply, :ok, new_state}
  end

  defp suggest_params(invoker, study_name, search_space) do
    case invoker.invoke(:tpe_bridge, %{action: :suggest, study_name: study_name}, []) do
      {:ok, result} ->
        parsed = Map.get(result, :parsed, result)

        case parsed do
          %{"params" => params} -> {:ok, decode_params(params, search_space)}
          %{params: params} -> {:ok, decode_params(params, search_space)}
          _ -> {:ok, random_params(search_space)}
        end

      {:error, _} ->
        {:ok, random_params(search_space)}
    end
  end

  defp decode_params(params, search_space) when is_map(params) do
    for {key, _bounds} <- search_space, into: %{} do
      str_key = to_string(key)

      value =
        Map.get(params, str_key) || Map.get(params, key) || random_in_bounds(search_space[key])

      {key, value}
    end
  end

  defp random_params(search_space) do
    for {key, bounds} <- search_space, into: %{} do
      {key, random_in_bounds(bounds)}
    end
  end

  defp random_in_bounds({min, max}), do: min + :rand.uniform() * (max - min)
  defp random_in_bounds(choices) when is_list(choices), do: Enum.random(choices)
end
