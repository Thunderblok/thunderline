defmodule Thunderline.Thunderpac.SurpriseEventHandler do
  @moduledoc """
  Surprise Event Handler - Connects Bolt surprise signals to PAC memory writes.

  Implements HC-75/HC-76 MIRAS/Titans memory integration by:
  1. Subscribing to `bolt.ca.surprise.*` events from Thunderbolt domain
  2. Looking up the associated PAC's MemoryModule
  3. Triggering memory writes when surprise threshold exceeded
  4. Emitting `pac.memory.*` events for downstream processing

  ## Event Flow

  ```
  LoopMonitor (Bolt)
      │
      ▼
  SurpriseMetrics.publish_surprise_event/3
      │
      ▼
  EventBus: "bolt.ca.surprise.threshold_exceeded"
      │
      ▼
  SurpriseEventHandler (subscribes via PubSub)
      │
      ▼
  MemoryModule.maybe_write/4 or force_write/2
      │
      ▼
  EventBus: "pac.memory.write"
  ```

  ## Subscription Patterns

  - `bolt.ca.surprise.*` - All surprise-related events
  - `bolt.ca.criticality.*` - Criticality updates (derived surprise)
  - `pac.tick` - Periodic memory decay application

  ## Configuration

  The handler can be configured via application env:

      config :thunderline, Thunderline.Thunderpac.SurpriseEventHandler,
        auto_create_memory: true,
        default_memory_config: [depth: 3, width: 64],
        decay_on_tick: true,
        decay_interval: 7  # Apply decay every N ticks
  """

  use GenServer

  require Logger

  alias Thunderline.Thunderpac.MemoryModule
  alias Thunderline.Thunderpac.Registry
  alias Thunderline.Thunderpac.Supervisor, as: PacSupervisor

  @default_config %{
    auto_create_memory: true,
    default_memory_config: [depth: 3, width: 64, input_dim: 32, output_dim: 32],
    decay_on_tick: true,
    decay_interval: 7
  }

  # ===========================================================================
  # Client API
  # ===========================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a memory write for a PAC.

  Useful for testing or forcing memory updates outside the normal
  surprise-driven flow.
  """
  @spec trigger_memory_write(String.t(), list(float()), list(float()), list(float())) ::
          {:ok, map()} | {:error, term()}
  def trigger_memory_write(pac_id, input, predicted, actual) do
    GenServer.call(__MODULE__, {:trigger_write, pac_id, input, predicted, actual})
  end

  @doc """
  Get current handler statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    config = build_config(opts)

    # Subscribe to surprise events via PubSub
    subscribe_to_events()

    state = %{
      config: config,
      stats: %{
        events_received: 0,
        writes_triggered: 0,
        writes_skipped: 0,
        memory_modules_created: 0,
        errors: 0,
        last_event_at: nil
      },
      tick_count: 0
    }

    Logger.info("[SurpriseEventHandler] Started with config: #{inspect(config)}")

    {:ok, state}
  end

  @impl true
  def handle_call({:trigger_write, pac_id, input, predicted, actual}, _from, state) do
    result = do_memory_write(pac_id, input, predicted, actual, state.config)
    {:reply, result, update_stats(state, result)}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Handle surprise threshold exceeded events
  @impl true
  def handle_info({:surprise_event, event}, state) do
    state = handle_surprise_event(event, state)
    {:noreply, state}
  end

  # Handle PubSub broadcasts for surprise events
  @impl true
  def handle_info({:pubsub_event, topic, event}, state) do
    state =
      cond do
        String.starts_with?(topic, "bolt.ca.surprise") ->
          handle_surprise_event(event, state)

        String.starts_with?(topic, "bolt.ca.criticality") ->
          handle_criticality_event(event, state)

        String.starts_with?(topic, "pac.tick") ->
          handle_pac_tick(event, state)

        true ->
          Logger.debug("[SurpriseEventHandler] Ignoring event on topic: #{topic}")
          state
      end

    {:noreply, state}
  end

  # Handle direct EventBus subscription messages
  @impl true
  def handle_info(%{name: name, payload: payload} = event, state) when is_binary(name) do
    state =
      cond do
        String.starts_with?(name, "bolt.ca.surprise") ->
          handle_surprise_event(event, state)

        String.starts_with?(name, "bolt.ca.criticality") ->
          handle_criticality_event(event, state)

        String.starts_with?(name, "pac.tick") ->
          handle_pac_tick(payload, state)

        true ->
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[SurpriseEventHandler] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  defp handle_surprise_event(event, state) do
    state = %{state | stats: %{state.stats | events_received: state.stats.events_received + 1, last_event_at: DateTime.utc_now()}}

    payload = extract_payload(event)

    case payload do
      %{pac_id: pac_id, should_write: true} = data ->
        # Extract vectors if available, or use scalar surprise to generate synthetic vectors
        {input, predicted, actual} = extract_or_synthesize_vectors(data)

        result = do_memory_write(pac_id, input, predicted, actual, state.config)
        update_stats(state, result)

      %{pac_id: pac_id, surprise: surprise} when is_number(surprise) and surprise > 0.1 ->
        # High surprise without explicit should_write - still trigger
        Logger.debug("[SurpriseEventHandler] High surprise #{surprise} for PAC #{pac_id}, triggering write")
        {input, predicted, actual} = synthesize_vectors_from_surprise(surprise)
        result = do_memory_write(pac_id, input, predicted, actual, state.config)
        update_stats(state, result)

      %{pac_id: _pac_id, should_write: false} ->
        %{state | stats: %{state.stats | writes_skipped: state.stats.writes_skipped + 1}}

      _ ->
        Logger.debug("[SurpriseEventHandler] Skipping event without pac_id or surprise data")
        state
    end
  end

  defp handle_criticality_event(event, state) do
    payload = extract_payload(event)

    case payload do
      %{pac_id: pac_id, criticality: criticality} when is_number(criticality) ->
        # Derive surprise from criticality metrics
        surprise = derive_surprise_from_criticality(criticality, payload)

        if surprise > 0.1 do
          {input, predicted, actual} = synthesize_vectors_from_surprise(surprise)
          result = do_memory_write(pac_id, input, predicted, actual, state.config)
          update_stats(state, result)
        else
          state
        end

      _ ->
        state
    end
  end

  defp handle_pac_tick(payload, state) do
    tick_count = state.tick_count + 1
    state = %{state | tick_count: tick_count}

    # Apply decay periodically if configured
    if state.config.decay_on_tick and rem(tick_count, state.config.decay_interval) == 0 do
      apply_global_decay()
    end

    # Handle tick for specific PAC if provided
    case payload do
      %{pac_id: pac_id} ->
        # Optionally apply per-PAC decay
        maybe_apply_decay(pac_id)
        state

      _ ->
        state
    end
  end

  # ===========================================================================
  # Memory Write Logic
  # ===========================================================================

  defp do_memory_write(pac_id, input, predicted, actual, config) do
    with {:ok, pid} <- ensure_memory_module(pac_id, config) do
      # Use maybe_write which applies surprise gating internally
      case MemoryModule.maybe_write(pid, input, predicted, actual) do
        {:ok, result} ->
          # Emit pac.memory.write event
          emit_memory_event(pac_id, :write, result)
          {:ok, result}

        {:skipped, reason} ->
          {:skipped, reason}

        {:error, reason} ->
          Logger.warning("[SurpriseEventHandler] Memory write failed for PAC #{pac_id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.error("[SurpriseEventHandler] Failed to get memory module for PAC #{pac_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_memory_module(pac_id, config) do
    case Registry.get_memory_pid(pac_id) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :not_found} ->
        if config.auto_create_memory do
          PacSupervisor.start_memory_module(pac_id, config.default_memory_config)
        else
          {:error, :memory_module_not_found}
        end
    end
  end

  defp maybe_apply_decay(pac_id) do
    case Registry.get_memory_pid(pac_id) do
      {:ok, pid} ->
        MemoryModule.apply_decay(pid)

      _ ->
        :ok
    end
  end

  defp apply_global_decay do
    Registry.all_memory_modules()
    |> Enum.each(fn %{pac_id: pac_id} ->
      maybe_apply_decay(pac_id)
    end)
  end

  # ===========================================================================
  # Event Emission
  # ===========================================================================

  defp emit_memory_event(pac_id, action, result) do
    event_name = "pac.memory.#{action}"

    payload = %{
      pac_id: pac_id,
      action: action,
      timestamp: DateTime.utc_now()
    }

    payload = case result do
      %{surprise: s, written: w} -> Map.merge(payload, %{surprise: s, written: w})
      %{wrote: w} -> Map.put(payload, :wrote, w)
      _ -> payload
    end

    # Try to publish via EventBus
    case Thunderline.Thunderflow.EventBus.publish_event(%{
      name: event_name,
      source: :pac,
      payload: payload,
      meta: %{pipeline: :general}
    }) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.debug("[SurpriseEventHandler] Failed to emit event: #{inspect(reason)}")
    end

    # Also emit telemetry
    :telemetry.execute(
      [:thunderline, :pac, :memory, action],
      %{count: 1},
      %{pac_id: pac_id, action: action}
    )
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp subscribe_to_events do
    # Subscribe to PubSub for surprise events
    topics = [
      "bolt.ca.surprise.*",
      "bolt.ca.criticality.*",
      "pac.tick"
    ]

    Enum.each(topics, fn topic ->
      Phoenix.PubSub.subscribe(Thunderline.PubSub, topic)
    end)

    Logger.debug("[SurpriseEventHandler] Subscribed to topics: #{inspect(topics)}")
  end

  defp build_config(opts) do
    app_config =
      Application.get_env(:thunderline, __MODULE__, [])
      |> Map.new()

    opts_config = Map.new(opts)

    Map.merge(@default_config, app_config)
    |> Map.merge(opts_config)
  end

  defp extract_payload(%{payload: payload}), do: payload
  defp extract_payload(payload) when is_map(payload), do: payload
  defp extract_payload(_), do: %{}

  defp extract_or_synthesize_vectors(%{input: input, predicted: predicted, actual: actual})
       when is_list(input) and is_list(predicted) and is_list(actual) do
    {input, predicted, actual}
  end

  defp extract_or_synthesize_vectors(%{surprise: surprise}) when is_number(surprise) do
    synthesize_vectors_from_surprise(surprise)
  end

  defp extract_or_synthesize_vectors(_) do
    # Default: zero vectors (no-op write)
    dim = 32
    zeros = List.duplicate(0.0, dim)
    {zeros, zeros, zeros}
  end

  defp synthesize_vectors_from_surprise(surprise) do
    # Create synthetic input/predicted/actual vectors where the difference
    # between predicted and actual encodes the surprise magnitude
    dim = 32

    # Random input vector (normalized)
    input = for _ <- 1..dim, do: :rand.uniform() - 0.5

    # Predicted is similar to input (with some noise)
    predicted = Enum.map(input, fn x -> x + (:rand.uniform() - 0.5) * 0.1 end)

    # Actual deviates from predicted by surprise amount
    actual = Enum.map(predicted, fn x -> x + surprise * (:rand.uniform() - 0.5) end)

    {input, predicted, actual}
  end

  defp derive_surprise_from_criticality(criticality, payload) do
    # Use criticality metrics to estimate surprise
    # Higher criticality = closer to edge of chaos = higher surprise
    base_surprise = criticality / 10.0

    # Adjust based on other metrics if available
    adjustment =
      case payload do
        %{health_delta: delta} when is_number(delta) -> abs(delta) * 0.1
        %{lyapunov: l} when is_number(l) -> min(abs(l), 0.5)
        _ -> 0.0
      end

    min(base_surprise + adjustment, 1.0)
  end

  defp update_stats(state, result) do
    stats = state.stats

    updated_stats =
      case result do
        {:ok, _} ->
          %{stats | writes_triggered: stats.writes_triggered + 1}

        {:skipped, _} ->
          %{stats | writes_skipped: stats.writes_skipped + 1}

        {:error, _} ->
          %{stats | errors: stats.errors + 1}

        _ ->
          stats
      end

    %{state | stats: updated_stats}
  end
end
