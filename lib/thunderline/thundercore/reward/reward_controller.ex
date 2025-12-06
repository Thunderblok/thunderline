defmodule Thunderline.Thundercore.Reward.RewardController do
  @moduledoc """
  RewardController — Closed-Loop Automata Tuning via Reward Signals.

  This GenServer implements the reward loop that:
  1. Subscribes to automata metrics events
  2. Computes reward signals via RewardSchema
  3. Applies tuning deltas back to running automata
  4. Maintains reward history for temporal credit assignment

  ## Architecture

  ```
  ┌────────────────────────────────────────────────────────────┐
  │                    RewardController                        │
  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐  │
  │  │   Metrics   │──▶│   Reward    │──▶│     Tuning      │  │
  │  │  Listener   │   │   Schema    │   │    Applier      │  │
  │  └─────────────┘   └─────────────┘   └─────────────────┘  │
  │         ▲                                     │            │
  │         │                                     ▼            │
  │  ┌──────┴──────┐                     ┌───────────────┐    │
  │  │  EventBus   │                     │  CA.Runner    │    │
  │  │ (metrics)   │                     │  (params)     │    │
  │  └─────────────┘                     └───────────────┘    │
  └────────────────────────────────────────────────────────────┘
  ```

  ## State

  - `run_subscriptions` — Active run_id → subscription mapping
  - `reward_history` — Per-run reward history for averaging
  - `tuning_config` — Global tuning parameters

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 3
  """

  use GenServer
  require Logger

  alias Thunderline.Thundercore.Reward.RewardSchema

  @default_history_size 50

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type run_state :: %{
          reward_history: [float()],
          tuning_history: [map()],
          last_criticality: map(),
          last_side_quest: map(),
          current_params: map(),
          tick: non_neg_integer()
        }

  @type state :: %{
          runs: %{String.t() => run_state()},
          tuning_config: map(),
          history_size: non_neg_integer()
        }

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts the RewardController.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a CA run for reward-based tuning.
  """
  @spec register_run(GenServer.server(), String.t(), map()) :: :ok
  def register_run(server \\ __MODULE__, run_id, initial_params \\ %{}) do
    GenServer.cast(server, {:register_run, run_id, initial_params})
  end

  @doc """
  Unregisters a CA run from reward tuning.
  """
  @spec unregister_run(GenServer.server(), String.t()) :: :ok
  def unregister_run(server \\ __MODULE__, run_id) do
    GenServer.cast(server, {:unregister_run, run_id})
  end

  @doc """
  Processes metrics for a run and computes reward + tuning signals.

  Returns the computed reward result.
  """
  @spec process_metrics(GenServer.server(), String.t(), map(), map(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def process_metrics(server \\ __MODULE__, run_id, criticality, side_quest, tick) do
    GenServer.call(server, {:process_metrics, run_id, criticality, side_quest, tick})
  end

  @doc """
  Gets the reward history for a run.
  """
  @spec get_reward_history(GenServer.server(), String.t()) :: {:ok, [float()]} | {:error, :not_found}
  def get_reward_history(server \\ __MODULE__, run_id) do
    GenServer.call(server, {:get_reward_history, run_id})
  end

  @doc """
  Gets the current tuning parameters for a run.
  """
  @spec get_current_params(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_current_params(server \\ __MODULE__, run_id) do
    GenServer.call(server, {:get_current_params, run_id})
  end

  @doc """
  Gets the average reward for a run (over history window).
  """
  @spec get_average_reward(GenServer.server(), String.t()) :: {:ok, float()} | {:error, :not_found}
  def get_average_reward(server \\ __MODULE__, run_id) do
    GenServer.call(server, {:get_average_reward, run_id})
  end

  @doc """
  Lists all registered runs.
  """
  @spec list_runs(GenServer.server()) :: [String.t()]
  def list_runs(server \\ __MODULE__) do
    GenServer.call(server, :list_runs)
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    history_size = Keyword.get(opts, :history_size, @default_history_size)

    tuning_config = %{
      enabled: Keyword.get(opts, :tuning_enabled, true),
      sensitivity: Keyword.get(opts, :sensitivity, 0.1),
      min_samples: Keyword.get(opts, :min_samples, 5),
      smooth_factor: Keyword.get(opts, :smooth_factor, 0.3)
    }

    state = %{
      runs: %{},
      tuning_config: tuning_config,
      history_size: history_size
    }

    Logger.info("[RewardController] started with history_size=#{history_size}")

    {:ok, state}
  end

  @impl true
  def handle_cast({:register_run, run_id, initial_params}, state) do
    run_state = %{
      reward_history: [],
      tuning_history: [],
      last_criticality: %{},
      last_side_quest: %{},
      current_params: initial_params,
      tick: 0
    }

    new_runs = Map.put(state.runs, run_id, run_state)

    Logger.debug("[RewardController] registered run=#{run_id}")

    {:noreply, %{state | runs: new_runs}}
  end

  @impl true
  def handle_cast({:unregister_run, run_id}, state) do
    new_runs = Map.delete(state.runs, run_id)

    Logger.debug("[RewardController] unregistered run=#{run_id}")

    {:noreply, %{state | runs: new_runs}}
  end

  @impl true
  def handle_call({:process_metrics, run_id, criticality, side_quest, tick}, _from, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        # Auto-register if not found
        run_state = %{
          reward_history: [],
          tuning_history: [],
          last_criticality: %{},
          last_side_quest: %{},
          current_params: %{},
          tick: 0
        }

        {result, new_run_state} = process_run_metrics(run_state, criticality, side_quest, tick, state.tuning_config, state.history_size)
        new_runs = Map.put(state.runs, run_id, new_run_state)

        {:reply, {:ok, result}, %{state | runs: new_runs}}

      run_state ->
        {result, new_run_state} = process_run_metrics(run_state, criticality, side_quest, tick, state.tuning_config, state.history_size)
        new_runs = Map.put(state.runs, run_id, new_run_state)

        {:reply, {:ok, result}, %{state | runs: new_runs}}
    end
  end

  @impl true
  def handle_call({:get_reward_history, run_id}, _from, state) do
    case Map.get(state.runs, run_id) do
      nil -> {:reply, {:error, :not_found}, state}
      run_state -> {:reply, {:ok, run_state.reward_history}, state}
    end
  end

  @impl true
  def handle_call({:get_current_params, run_id}, _from, state) do
    case Map.get(state.runs, run_id) do
      nil -> {:reply, {:error, :not_found}, state}
      run_state -> {:reply, {:ok, run_state.current_params}, state}
    end
  end

  @impl true
  def handle_call({:get_average_reward, run_id}, _from, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      run_state ->
        avg =
          if Enum.empty?(run_state.reward_history) do
            0.5
          else
            Enum.sum(run_state.reward_history) / length(run_state.reward_history)
          end

        {:reply, {:ok, Float.round(avg, 4)}, state}
    end
  end

  @impl true
  def handle_call(:list_runs, _from, state) do
    {:reply, Map.keys(state.runs), state}
  end

  # ═══════════════════════════════════════════════════════════════
  # Internal Processing
  # ═══════════════════════════════════════════════════════════════

  defp process_run_metrics(run_state, criticality, side_quest, tick, tuning_config, history_size) do
    # Compute reward
    {:ok, result} = RewardSchema.compute(criticality, side_quest, tick: tick)

    # Update history
    new_reward_history =
      [result.reward | run_state.reward_history]
      |> Enum.take(history_size)

    new_tuning_history =
      [result.tuning | run_state.tuning_history]
      |> Enum.take(history_size)

    # Compute smoothed tuning signals
    smoothed_tuning =
      if tuning_config.enabled and length(new_tuning_history) >= tuning_config.min_samples do
        smooth_tuning_signals(new_tuning_history, tuning_config.smooth_factor)
      else
        result.tuning
      end

    # Apply tuning to current params
    new_params = apply_tuning(run_state.current_params, smoothed_tuning, tuning_config)

    new_run_state = %{
      run_state
      | reward_history: new_reward_history,
        tuning_history: new_tuning_history,
        last_criticality: criticality,
        last_side_quest: side_quest,
        current_params: new_params,
        tick: tick
    }

    # Augment result with smoothed tuning and params
    augmented_result = Map.merge(result, %{
      smoothed_tuning: smoothed_tuning,
      applied_params: new_params,
      average_reward: average_of(new_reward_history)
    })

    {augmented_result, new_run_state}
  end

  defp smooth_tuning_signals(history, factor) do
    # Exponential moving average of tuning signals
    history
    |> Enum.with_index()
    |> Enum.reduce(%{lambda_delta: 0.0, temp_delta: 0.0, coupling_delta: 0.0}, fn {tuning, idx}, acc ->
      weight = :math.pow(1.0 - factor, idx) * factor
      %{
        lambda_delta: acc.lambda_delta + Map.get(tuning, :lambda_delta, 0.0) * weight,
        temp_delta: acc.temp_delta + Map.get(tuning, :temp_delta, 0.0) * weight,
        coupling_delta: acc.coupling_delta + Map.get(tuning, :coupling_delta, 0.0) * weight
      }
    end)
    |> Map.new(fn {k, v} -> {k, Float.round(v, 4)} end)
  end

  defp apply_tuning(current_params, tuning, tuning_config) do
    if tuning_config.enabled do
      sensitivity = tuning_config.sensitivity

      lambda = Map.get(current_params, :lambda, 0.5)
      temperature = Map.get(current_params, :temperature, 1.0)
      coupling = Map.get(current_params, :coupling, 0.5)

      %{
        lambda: clamp(lambda + tuning.lambda_delta * sensitivity, 0.0, 1.0),
        temperature: clamp(temperature + tuning.temp_delta * sensitivity, 0.1, 2.0),
        coupling: clamp(coupling + tuning.coupling_delta * sensitivity, 0.0, 1.0)
      }
    else
      current_params
    end
  end

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
    |> Float.round(4)
  end

  defp average_of([]), do: 0.5
  defp average_of(list), do: Float.round(Enum.sum(list) / length(list), 4)
end
