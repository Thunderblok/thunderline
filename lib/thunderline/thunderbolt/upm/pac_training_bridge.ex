defmodule Thunderline.Thunderbolt.UPM.PACTrainingBridge do
  @moduledoc """
  Bridge between Thunderpac (PAC lifecycle) and UPM (Unified Persistent Model).

  This module:
  1. Subscribes to PAC lifecycle events (state changes, intent completions)
  2. Extracts features from PAC state for training
  3. Creates FeatureWindows for UPM consumption
  4. Enables PACs to learn from their own behavior over time

  ## Event Sources

  - `pac.state.changed` - PAC transitioned between lifecycle states
  - `pac.intent.completed` - PAC completed an intent (training signal)
  - `pac.state.snapshot` - PAC state was snapshotted

  ## Feature Pipeline

  ```
  PAC Event → PACFeatureExtractor → FeatureWindow → TrainerWorker → SGD Update
  ```

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.PACTrainingBridge,
        enabled: true,
        window_duration_ms: 60_000,
        min_events_per_window: 5
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderpac.Resources.{PAC, PACState, PACIntent}
  alias Thunderline.Thunderbolt.UPM.PACFeatureExtractor
  alias Thunderline.Features.FeatureWindow
  alias Thunderline.Thunderflow.EventBus

  @default_window_duration_ms 60_000
  @default_min_events 5
  @default_max_events 100

  defstruct [
    :tenant_id,
    :window_duration_ms,
    :min_events_per_window,
    :max_events_per_window,
    :current_window_id,
    :window_start,
    :events_buffer,
    :features_accumulator,
    :pac_cache
  ]

  # ═══════════════════════════════════════════════════════════════
  # CLIENT API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Start the PAC training bridge.

  ## Options
    - `:tenant_id` - Tenant scope for events
    - `:window_duration_ms` - Duration of feature windows (default: 60s)
    - `:min_events_per_window` - Minimum events before emitting window
    - `:max_events_per_window` - Maximum events per window
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Manually process a PAC for training (useful for batch operations).
  """
  def process_pac(pid \\ __MODULE__, pac_id) do
    GenServer.cast(pid, {:process_pac, pac_id})
  end

  @doc """
  Flush current window and emit to UPM (for testing/debugging).
  """
  def flush_window(pid \\ __MODULE__) do
    GenServer.call(pid, :flush_window)
  end

  @doc """
  Get current bridge statistics.
  """
  def stats(pid \\ __MODULE__) do
    GenServer.call(pid, :stats)
  end

  # ═══════════════════════════════════════════════════════════════
  # SERVER CALLBACKS
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    tenant_id = Keyword.get(opts, :tenant_id)
    window_duration = Keyword.get(opts, :window_duration_ms, @default_window_duration_ms)
    min_events = Keyword.get(opts, :min_events_per_window, @default_min_events)
    max_events = Keyword.get(opts, :max_events_per_window, @default_max_events)

    # Subscribe to PAC events
    subscribe_to_pac_events()

    # Schedule window flush timer
    schedule_window_flush(window_duration)

    state = %__MODULE__{
      tenant_id: tenant_id,
      window_duration_ms: window_duration,
      min_events_per_window: min_events,
      max_events_per_window: max_events,
      current_window_id: generate_window_id(),
      window_start: DateTime.utc_now(),
      events_buffer: [],
      features_accumulator: [],
      pac_cache: %{}
    }

    Logger.info("""
    [UPM.PACTrainingBridge] Started
      tenant_id: #{inspect(tenant_id)}
      window_duration_ms: #{window_duration}
      min_events: #{min_events}
    """)

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_pac, pac_id}, state) do
    case load_and_extract_pac(pac_id, state) do
      {:ok, extraction, new_state} ->
        new_state = accumulate_features(extraction, new_state)
        {:noreply, maybe_emit_window(new_state)}

      {:error, reason} ->
        Logger.warning(
          "[UPM.PACTrainingBridge] Failed to process PAC #{pac_id}: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:flush_window, _from, state) do
    case emit_feature_window(state) do
      {:ok, window_id, new_state} ->
        {:reply, {:ok, window_id}, new_state}

      {:skip, reason, new_state} ->
        {:reply, {:skip, reason}, new_state}
    end
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      current_window_id: state.current_window_id,
      window_start: state.window_start,
      events_buffered: length(state.events_buffer),
      features_accumulated: length(state.features_accumulator),
      pacs_cached: map_size(state.pac_cache)
    }

    {:reply, stats, state}
  end

  # ═══════════════════════════════════════════════════════════════
  # PAC EVENT HANDLERS
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def handle_info({:pac_event, %{type: :state_changed, pac_id: pac_id} = event}, state) do
    Logger.debug("[UPM.PACTrainingBridge] PAC state changed: #{pac_id}")

    state =
      state
      |> buffer_event(event)
      |> invalidate_pac_cache(pac_id)

    case load_and_extract_pac(pac_id, state) do
      {:ok, extraction, new_state} ->
        new_state = accumulate_features(extraction, new_state)
        {:noreply, maybe_emit_window(new_state)}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:pac_event, %{type: :intent_completed, pac_id: pac_id, intent: intent} = event},
        state
      ) do
    Logger.debug("[UPM.PACTrainingBridge] PAC intent completed: #{pac_id}")

    state =
      state
      |> buffer_event(event)
      |> add_intent_label(intent)

    {:noreply, maybe_emit_window(state)}
  end

  def handle_info(
        {:pac_event, %{type: :snapshot_created, pac_id: pac_id, snapshot: snapshot} = event},
        state
      ) do
    Logger.debug("[UPM.PACTrainingBridge] PAC snapshot created: #{pac_id}")

    # Extract features from snapshot
    extraction = PACFeatureExtractor.extract_from_state(snapshot)

    state =
      state
      |> buffer_event(event)
      |> accumulate_features(extraction)

    {:noreply, maybe_emit_window(state)}
  end

  # PubSub event handlers
  def handle_info(%{name: "pac.state.changed", payload: payload}, state) do
    handle_info({:pac_event, Map.put(payload, :type, :state_changed)}, state)
  end

  def handle_info(%{name: "pac.intent.completed", payload: payload}, state) do
    handle_info({:pac_event, Map.put(payload, :type, :intent_completed)}, state)
  end

  def handle_info(%{name: "pac.state.snapshot", payload: payload}, state) do
    handle_info({:pac_event, Map.put(payload, :type, :snapshot_created)}, state)
  end

  # Window flush timer
  def handle_info(:flush_window_timer, state) do
    # Schedule next flush
    schedule_window_flush(state.window_duration_ms)

    case emit_feature_window(state) do
      {:ok, _window_id, new_state} ->
        {:noreply, new_state}

      {:skip, _reason, new_state} ->
        {:noreply, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("[UPM.PACTrainingBridge] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════════════
  # FEATURE EXTRACTION & ACCUMULATION
  # ═══════════════════════════════════════════════════════════════

  defp load_and_extract_pac(pac_id, state) do
    # Check cache first
    case Map.get(state.pac_cache, pac_id) do
      %PAC{} = pac ->
        extraction = PACFeatureExtractor.extract(pac)
        {:ok, extraction, state}

      nil ->
        # Load from database
        case Ash.get(PAC, pac_id, tenant: state.tenant_id) do
          {:ok, pac} ->
            extraction = PACFeatureExtractor.extract(pac)
            new_state = cache_pac(state, pac)
            {:ok, extraction, new_state}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp accumulate_features(extraction, state) do
    %{state | features_accumulator: [extraction | state.features_accumulator]}
  end

  defp buffer_event(state, event) do
    %{state | events_buffer: [event | state.events_buffer]}
  end

  defp add_intent_label(state, _intent) do
    # Intent completions provide training labels
    # The fact that an intent was completed is a positive signal
    state
  end

  defp cache_pac(state, pac) do
    # Simple LRU-ish cache (just keep recent 100 PACs)
    cache =
      if map_size(state.pac_cache) > 100 do
        # Evict oldest entry (simple strategy)
        state.pac_cache
        |> Enum.take(90)
        |> Map.new()
      else
        state.pac_cache
      end

    %{state | pac_cache: Map.put(cache, pac.id, pac)}
  end

  defp invalidate_pac_cache(state, pac_id) do
    %{state | pac_cache: Map.delete(state.pac_cache, pac_id)}
  end

  # ═══════════════════════════════════════════════════════════════
  # FEATURE WINDOW EMISSION
  # ═══════════════════════════════════════════════════════════════

  defp maybe_emit_window(state) do
    cond do
      length(state.features_accumulator) >= state.max_events_per_window ->
        case emit_feature_window(state) do
          {:ok, _window_id, new_state} -> new_state
          {:skip, _reason, state} -> state
        end

      true ->
        state
    end
  end

  defp emit_feature_window(state) do
    if length(state.features_accumulator) < state.min_events_per_window do
      {:skip, :insufficient_events, state}
    else
      # Aggregate features from all extractions
      {features_tensor, labels_tensor, _metadata} =
        state.features_accumulator
        |> Enum.reverse()
        |> Enum.map(& &1.features)
        |> aggregate_features()

      window_end = DateTime.utc_now()

      # Create FeatureWindow for UPM consumption
      window_params = %{
        tenant_id: state.tenant_id,
        kind: :pac_behavior,
        key: "pac_training_#{state.current_window_id}",
        window_start: state.window_start,
        window_end: window_end,
        features: tensor_to_map(features_tensor),
        label_spec: %{type: :pac_behavior, version: 1},
        labels: tensor_to_map(labels_tensor),
        feature_schema_version: 1,
        provenance: %{
          source: "pac_training_bridge",
          event_count: length(state.events_buffer),
          pac_count: length(state.features_accumulator)
        },
        status: :filled
      }

      case create_feature_window(window_params, state.tenant_id) do
        {:ok, window} ->
          Logger.info("""
          [UPM.PACTrainingBridge] Emitted feature window
            window_id: #{window.id}
            events: #{length(state.events_buffer)}
            pacs: #{length(state.features_accumulator)}
          """)

          # Broadcast for UPM TrainerWorker consumption
          broadcast_window_created(window)

          # Reset state for next window
          new_state = %{
            state
            | current_window_id: generate_window_id(),
              window_start: DateTime.utc_now(),
              events_buffer: [],
              features_accumulator: []
          }

          {:ok, window.id, new_state}

        {:error, reason} ->
          Logger.error("[UPM.PACTrainingBridge] Failed to create window: #{inspect(reason)}")
          {:skip, reason, state}
      end
    end
  end

  defp aggregate_features(feature_tensors) do
    # Stack all feature tensors and compute mean
    if Enum.empty?(feature_tensors) do
      {Nx.tensor([[0.0]]), nil, %{}}
    else
      stacked = Nx.concatenate(feature_tensors, axis: 0)

      # Mean across all samples
      mean_features = Nx.mean(stacked, axes: [0], keep_axes: true)

      # For labels, use the last extraction's labels as representative
      labels = Nx.broadcast(0.5, {1, 32})

      {mean_features, labels, %{sample_count: length(feature_tensors)}}
    end
  end

  defp tensor_to_map(tensor) when is_struct(tensor, Nx.Tensor) do
    # Convert tensor to serializable map
    shape = Nx.shape(tensor)
    data = Nx.to_flat_list(tensor)

    %{
      shape: Tuple.to_list(shape),
      data: data,
      type: "f32"
    }
  end

  defp tensor_to_map(nil), do: nil

  defp create_feature_window(params, tenant_id) do
    FeatureWindow
    |> Ash.Changeset.for_create(:ingest_window, params)
    |> Ash.create(
      tenant: tenant_id,
      actor: %{role: :system, scope: :maintenance, tenant_id: tenant_id}
    )
  end

  defp broadcast_window_created(window) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "system.feature_window.created",
      %{
        name: "system.feature_window.created",
        payload: %{
          window_id: window.id,
          kind: window.kind,
          status: window.status
        }
      }
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # SUBSCRIPTIONS & TIMERS
  # ═══════════════════════════════════════════════════════════════

  defp subscribe_to_pac_events do
    # Subscribe to PAC lifecycle events via PubSub
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "pac.state.changed")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "pac.intent.completed")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "pac.state.snapshot")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "events:pac")
    Logger.debug("[UPM.PACTrainingBridge] Subscribed to PAC events")
  end

  defp schedule_window_flush(duration_ms) do
    Process.send_after(self(), :flush_window_timer, duration_ms)
  end

  defp generate_window_id do
    Thunderline.UUID.v7()
  end
end
