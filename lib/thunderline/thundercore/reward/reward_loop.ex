defmodule Thunderline.Thundercore.Reward.RewardLoop do
  @moduledoc """
  RewardLoop — Full Automata Reward Cycle Coordinator.

  Orchestrates the complete reward loop:
  1. Subscribes to CA metrics events from EventBus
  2. Computes rewards via RewardSchema
  3. Applies tuning via RewardController
  4. Optionally persists snapshots for analysis

  ## Usage

      # Start the reward loop for a CA run
      {:ok, _pid} = RewardLoop.start_link(run_id: "run_123")

      # Or attach to existing run
      RewardLoop.attach("run_123")

      # The loop automatically processes metrics and applies tuning

  ## Architecture

  ```
  EventBus                          RewardLoop
      │                                  │
      │ bolt.ca.metrics.snapshot         │
      ├─────────────────────────────────▶│
      │                                  │ ──▶ RewardSchema.compute
      │ bolt.automata.side_quest.snapshot│
      ├─────────────────────────────────▶│
      │                                  │ ──▶ RewardController.process
      │                                  │
      │ core.reward.computed             │
      │◀─────────────────────────────────┤ ──▶ CA.Runner.tune
      │                                  │
  ```

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Thread 3
  """

  use GenServer
  require Logger

  alias Thunderline.Thundercore.Reward.{RewardSchema, RewardController}
  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @metrics_topic "events:ca_metrics"
  @side_quest_topic "events:side_quest"

  # ═══════════════════════════════════════════════════════════════
  # Type Definitions
  # ═══════════════════════════════════════════════════════════════

  @type state :: %{
          run_id: String.t(),
          subscriptions: [reference()],
          last_criticality: map() | nil,
          last_side_quest: map() | nil,
          auto_tune: boolean(),
          process_count: non_neg_integer()
        }

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Starts a RewardLoop for a specific CA run.

  Options:
  - `:run_id` — Required. The CA run to monitor.
  - `:auto_tune` — Whether to auto-apply tuning (default: true)
  - `:controller` — RewardController to use (default: RewardController)
  """
  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    name = via_tuple(run_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Attaches a reward loop to an existing run.
  """
  @spec attach(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def attach(run_id, opts \\ []) do
    opts = Keyword.put(opts, :run_id, run_id)
    start_link(opts)
  end

  @doc """
  Detaches the reward loop from a run.
  """
  @spec detach(String.t()) :: :ok
  def detach(run_id) do
    case Registry.lookup(Thunderline.Thundercore.Reward.Registry, run_id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  @doc """
  Manually triggers a reward computation with provided metrics.
  """
  @spec process(String.t(), map(), map(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def process(run_id, criticality, side_quest, tick) do
    case Registry.lookup(Thunderline.Thundercore.Reward.Registry, run_id) do
      [{pid, _}] ->
        GenServer.call(pid, {:process, criticality, side_quest, tick})

      [] ->
        # Process directly without a running loop
        RewardSchema.compute(criticality, side_quest, tick: tick)
    end
  end

  @doc """
  Gets the current state of a reward loop.
  """
  @spec get_state(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_state(run_id) do
    case Registry.lookup(Thunderline.Thundercore.Reward.Registry, run_id) do
      [{pid, _}] -> GenServer.call(pid, :get_state)
      [] -> {:error, :not_found}
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # GenServer Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    auto_tune = Keyword.get(opts, :auto_tune, true)

    # Register with controller
    RewardController.register_run(run_id)

    # Subscribe to metrics events
    subscriptions = subscribe_to_events(run_id)

    state = %{
      run_id: run_id,
      subscriptions: subscriptions,
      last_criticality: nil,
      last_side_quest: nil,
      auto_tune: auto_tune,
      process_count: 0
    }

    Logger.info("[RewardLoop] started for run=#{run_id} auto_tune=#{auto_tune}")

    {:ok, state}
  end

  @impl true
  def handle_call({:process, criticality, side_quest, tick}, _from, state) do
    result = do_process(state.run_id, criticality, side_quest, tick, state.auto_tune)

    new_state = %{
      state
      | last_criticality: criticality,
        last_side_quest: side_quest,
        process_count: state.process_count + 1
    }

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # Handle PubSub messages for metrics events
  @impl true
  def handle_info(%Thunderline.Event{name: "bolt.ca.metrics.snapshot"} = event, state) do
    if event.payload[:run_id] == state.run_id do
      new_state = handle_event({:criticality, event.payload}, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(%Thunderline.Event{name: "bolt.automata.side_quest.snapshot"} = event, state) do
    if event.payload[:run_id] == state.run_id do
      new_state = handle_event({:side_quest, event.payload}, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # Handle raw map payloads (fallback for direct telemetry/PubSub broadcasts)
  @impl true
  def handle_info({:metrics, type, payload}, state) when type in [:criticality, :side_quest] do
    if payload[:run_id] == state.run_id do
      new_state = handle_event({type, payload}, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # Unsubscribe from PubSub topics
    PubSub.unsubscribe(@pubsub, @metrics_topic)
    PubSub.unsubscribe(@pubsub, @side_quest_topic)

    # Unregister from controller
    RewardController.unregister_run(state.run_id)

    Logger.info("[RewardLoop] terminated for run=#{state.run_id} reason=#{inspect(reason)}")

    :ok
  end

  # ═══════════════════════════════════════════════════════════════
  # Event Handling
  # ═══════════════════════════════════════════════════════════════

  defp subscribe_to_events(run_id) do
    # Subscribe to PubSub topics for metrics
    # Events are broadcast by CA.Runner via Criticality and SideQuestMetrics
    :ok = PubSub.subscribe(@pubsub, @metrics_topic)
    :ok = PubSub.subscribe(@pubsub, @side_quest_topic)

    Logger.debug("[RewardLoop] subscribed to metrics topics for run=#{run_id}")

    # Return empty list since we don't track refs with PubSub
    []
  rescue
    e ->
      Logger.warning("[RewardLoop] Failed to subscribe to events for run=#{run_id}: #{inspect(e)}")
      []
  end

  defp handle_event({:criticality, payload}, state) do
    criticality = extract_criticality(payload)

    # If we have both metrics, process
    if state.last_side_quest do
      tick = payload[:tick] || 0
      do_process(state.run_id, criticality, state.last_side_quest, tick, state.auto_tune)

      %{
        state
        | last_criticality: criticality,
          last_side_quest: nil,
          process_count: state.process_count + 1
      }
    else
      %{state | last_criticality: criticality}
    end
  end

  defp handle_event({:side_quest, payload}, state) do
    side_quest = extract_side_quest(payload)

    # If we have both metrics, process
    if state.last_criticality do
      tick = payload[:tick] || 0
      do_process(state.run_id, state.last_criticality, side_quest, tick, state.auto_tune)

      %{
        state
        | last_criticality: nil,
          last_side_quest: side_quest,
          process_count: state.process_count + 1
      }
    else
      %{state | last_side_quest: side_quest}
    end
  end

  defp handle_event(_, state), do: state

  # ═══════════════════════════════════════════════════════════════
  # Processing
  # ═══════════════════════════════════════════════════════════════

  defp do_process(run_id, criticality, side_quest, tick, auto_tune) do
    case RewardController.process_metrics(run_id, criticality, side_quest, tick) do
      {:ok, result} ->
        # Emit the reward event
        RewardSchema.emit(run_id, result)

        # Apply tuning if enabled
        if auto_tune and result[:applied_params] do
          apply_tuning_to_runner(run_id, result.applied_params)
        end

        {:ok, result}

      {:error, reason} = error ->
        Logger.warning("[RewardLoop] process failed for run=#{run_id}: #{inspect(reason)}")
        error
    end
  end

  defp apply_tuning_to_runner(run_id, params) do
    # Attempt to tune the running CA
    try do
      if Code.ensure_loaded?(Thunderline.Thunderbolt.CA.Runner) do
        Thunderline.Thunderbolt.CA.Runner.update_params(run_id, params)
      end
    rescue
      e ->
        Logger.debug("[RewardLoop] could not apply tuning: #{inspect(e)}")
    catch
      :exit, _ ->
        Logger.debug("[RewardLoop] runner not available for tuning")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Metric Extraction
  # ═══════════════════════════════════════════════════════════════

  defp extract_criticality(payload) do
    %{
      plv: payload[:plv] || 0.5,
      entropy: payload[:entropy] || 0.5,
      lambda_hat: payload[:lambda_hat] || 0.5,
      lyapunov: payload[:lyapunov] || 0.0,
      edge_score: payload[:edge_score] || 0.5,
      zone: payload[:zone] || :critical
    }
  end

  defp extract_side_quest(payload) do
    %{
      clustering: payload[:clustering] || 0.5,
      sortedness: payload[:sortedness] || 0.5,
      healing_rate: payload[:healing_rate] || 0.5,
      pattern_stability: payload[:pattern_stability] || 0.5,
      emergence_score: payload[:emergence_score] || 0.5
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # Registry
  # ═══════════════════════════════════════════════════════════════

  defp via_tuple(run_id) do
    {:via, Registry, {Thunderline.Thundercore.Reward.Registry, run_id}}
  end
end
