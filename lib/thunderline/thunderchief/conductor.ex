defmodule Thunderline.Thunderchief.Conductor do
  @moduledoc """
  Chief Conductor - Orchestrates all domain Chiefs on each Thunderbeat tick.

  The Conductor subscribes to `system.flow.tick` events from Heartbeat and:
  1. Collects observations from all registered Chiefs
  2. Each Chief selects an action based on current state
  3. Actions are applied and outcomes logged for RL training

  ## Architecture

  ```
  Heartbeat (tick event)
       │
       ▼
  Conductor (orchestrates)
       │
       ├──▶ BitChief.observe_state()
       │         │
       │         └──▶ choose_action() ──▶ apply_action()
       │
       ├──▶ VineChief.observe_state()
       │         │
       │         └──▶ choose_action() ──▶ apply_action()
       │
       ├──▶ CrownChief.observe_state()
       │         │
       │         └──▶ choose_action() ──▶ apply_action()
       │
       └──▶ UIChief.observe_state()
                 │
                 └──▶ choose_action() ──▶ apply_action()
       │
       ▼
  Logger (trajectory data for Cerebros)
  ```

  ## Usage

      # Start conductor (usually via supervision tree)
      {:ok, pid} = Conductor.start_link()

      # Register additional chiefs dynamically
      Conductor.register_chief(:custom, MyApp.CustomChief)

      # Pause/resume orchestration
      Conductor.pause()
      Conductor.resume()

      # Get current chief states
      Conductor.get_states()
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderchief.Logger, as: TrajectoryLogger
  alias Thunderline.Thunderchief.State

  alias Thunderline.Thunderchief.Chiefs.{
    BitChief,
    VineChief,
    CrownChief,
    UIChief
  }

  @default_chiefs %{
    bit: BitChief,
    vine: VineChief,
    crown: CrownChief,
    ui: UIChief
  }

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts the Chief Conductor.

  ## Options

  - `:chiefs` - Map of chief_name => module, defaults to all domain chiefs
  - `:logger` - Trajectory logger server, default Thunderline.Thunderchief.Logger
  - `:enabled` - Whether orchestration is enabled, default true
  - `:name` - GenServer name, default __MODULE__
  """
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a chief dynamically.
  """
  @spec register_chief(atom(), module(), keyword()) :: :ok
  def register_chief(name, module, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, {:register_chief, name, module})
  end

  @doc """
  Unregisters a chief.
  """
  @spec unregister_chief(atom(), keyword()) :: :ok
  def unregister_chief(name, opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, {:unregister_chief, name})
  end

  @doc """
  Pauses orchestration (chiefs won't run on ticks).
  """
  @spec pause(keyword()) :: :ok
  def pause(opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, :pause)
  end

  @doc """
  Resumes orchestration.
  """
  @spec resume(keyword()) :: :ok
  def resume(opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, :resume)
  end

  @doc """
  Returns current state observations for all chiefs.
  """
  @spec get_states(keyword()) :: map()
  def get_states(opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, :get_states)
  end

  @doc """
  Forces a single orchestration cycle (useful for testing).
  """
  @spec tick(keyword()) :: :ok
  def tick(opts \\ []) do
    server = opts[:server] || __MODULE__
    GenServer.call(server, :manual_tick)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    chiefs = opts[:chiefs] || @default_chiefs
    logger = opts[:logger] || TrajectoryLogger
    enabled = Keyword.get(opts, :enabled, true)

    # Subscribe to heartbeat tick events
    subscribe_to_ticks()

    state = %{
      chiefs: chiefs,
      logger: logger,
      enabled: enabled,
      tick_count: 0,
      last_tick: nil,
      chief_states: %{},
      metrics: %{
        total_actions: 0,
        actions_by_chief: %{},
        avg_cycle_ms: 0.0
      }
    }

    Logger.info("[Conductor] started with chiefs: #{inspect(Map.keys(chiefs))}")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_chief, name, module}, _from, state) do
    chiefs = Map.put(state.chiefs, name, module)
    {:reply, :ok, %{state | chiefs: chiefs}}
  end

  @impl true
  def handle_call({:unregister_chief, name}, _from, state) do
    chiefs = Map.delete(state.chiefs, name)
    {:reply, :ok, %{state | chiefs: chiefs}}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | enabled: false}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | enabled: true}}
  end

  @impl true
  def handle_call(:get_states, _from, state) do
    {:reply, state.chief_states, state}
  end

  @impl true
  def handle_call(:manual_tick, _from, state) do
    state = run_orchestration_cycle(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:tick_event, payload}, %{enabled: true} = state) do
    # Run orchestration on heartbeat tick
    state = run_orchestration_cycle(state, payload)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tick_event, _payload}, state) do
    # Orchestration disabled, skip
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ===========================================================================
  # Orchestration Logic
  # ===========================================================================

  defp run_orchestration_cycle(state, tick_payload \\ %{}) do
    start_time = System.monotonic_time(:millisecond)
    tick = Map.get(tick_payload, :sequence, state.tick_count + 1)

    # Run each chief
    {chief_states, actions_taken} =
      Enum.reduce(state.chiefs, {%{}, 0}, fn {name, module}, {states_acc, actions_acc} ->
        case run_chief(name, module, tick, state.logger) do
          {:ok, chief_state, action_taken?} ->
            actions = if action_taken?, do: actions_acc + 1, else: actions_acc
            {Map.put(states_acc, name, chief_state), actions}

          {:error, reason} ->
            Logger.warning("[Conductor] chief #{name} failed: #{inspect(reason)}")
            {states_acc, actions_acc}
        end
      end)

    cycle_ms = System.monotonic_time(:millisecond) - start_time

    # Update metrics
    metrics = update_metrics(state.metrics, actions_taken, cycle_ms, state.chiefs)

    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :thunderchief, :cycle],
      %{duration_ms: cycle_ms, actions: actions_taken},
      %{tick: tick, chiefs: Map.keys(state.chiefs)}
    )

    %{state |
      tick_count: tick,
      last_tick: DateTime.utc_now(),
      chief_states: chief_states,
      metrics: metrics
    }
  end

  defp run_chief(name, module, tick, logger) do
    # 1. Observe state
    context = build_context(name, tick)

    with {:ok, chief_state} <- safe_call(module, :observe_state, [context]) do
      # 2. Choose action
      case safe_call(module, :choose_action, [chief_state]) do
        {:ok, {:no_action, _reason}} ->
          {:ok, chief_state, false}

        {:ok, action} ->
          # 3. Apply action
          case safe_call(module, :apply_action, [chief_state, action]) do
            {:ok, {result, updated_state}} ->
              # 4. Report outcome and log trajectory
              outcome = build_outcome(result, chief_state, updated_state)
              safe_call(module, :report_outcome, [outcome])

              # Log trajectory step
              log_trajectory(logger, name, chief_state, action, updated_state, outcome)

              {:ok, updated_state, true}

            {:error, reason} ->
              {:error, {:apply_failed, reason}}
          end

        {:error, reason} ->
          {:error, {:choose_failed, reason}}
      end
    end
  end

  defp safe_call(module, function, args) do
    apply(module, function, args)
  rescue
    e ->
      {:error, {:exception, Exception.format(:error, e, __STACKTRACE__)}}
  end

  defp build_context(chief_name, tick) do
    %{
      chief: chief_name,
      tick: tick,
      timestamp: DateTime.utc_now(),
      node: node()
    }
  end

  defp build_outcome(result, prev_state, next_state) do
    %{
      result: result,
      prev_state: prev_state,
      next_state: next_state,
      success?: result in [:ok, :success, :noop]
    }
  end

  defp log_trajectory(logger, chief, prev_state, action, next_state, outcome) do
    step = %{
      state: State.to_features(prev_state),
      action: action,
      reward: calculate_reward(outcome),
      next_state: State.to_features(next_state),
      done: false,
      metadata: %{
        tick: prev_state.tick,
        chief: chief
      }
    }

    TrajectoryLogger.log_step(chief, step, server: logger)
  rescue
    _ -> :ok
  end

  defp calculate_reward(%{success?: true}), do: 1.0
  defp calculate_reward(%{success?: false}), do: -0.5
  defp calculate_reward(_), do: 0.0

  defp update_metrics(metrics, actions, cycle_ms, chiefs) do
    total = metrics.total_actions + actions

    # Exponential moving average for cycle time
    alpha = 0.1
    avg = metrics.avg_cycle_ms * (1 - alpha) + cycle_ms * alpha

    %{metrics |
      total_actions: total,
      avg_cycle_ms: avg
    }
  end

  # ===========================================================================
  # Event Subscription
  # ===========================================================================

  defp subscribe_to_ticks do
    # Subscribe to heartbeat events via PubSub
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system.flow.tick")
  rescue
    _ ->
      # PubSub not available, use polling fallback
      Process.send_after(self(), :poll_for_ticks, 100)
  end
end
