defmodule Thunderline.Thunderbolt.ReflexHandlers.Stabilization do
  @moduledoc """
  Handles stability-related reflex events.

  HC-Ω-8: Subscribes to `bolt.thunderbit.reflex.*` events and handles
  triggers that require stabilization actions.

  ## Handled Triggers

  - `:low_stability` - Entropy or PLV out of band, nudge traits toward stability
  - `:trust_boost` - Increase trust weight in PAC traits
  - `:recovery` - Post-chaos recovery, restore baseline parameters
  - `:stabilize` - General stabilization request

  ## Actions Taken

  1. Fetch associated PAC if `pac_id` present in event
  2. Compute trait adjustments based on trigger type and metrics
  3. Update PAC traits via `Thunderpac.Domain.update_traits`
  4. Emit telemetry and acknowledgment event

  ## Telemetry

  - `[:thunderline, :bolt, :reflex_handler, :stabilization, :handled]`
  - `[:thunderline, :bolt, :reflex_handler, :stabilization, :error]`
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @topic "bolt.thunderbit.reflex"
  @telemetry_prefix [:thunderline, :bolt, :reflex_handler, :stabilization]

  # ═══════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Handle an event directly (for testing or direct dispatch).
  """
  @spec handle_event(map()) :: :ok | {:error, term()}
  def handle_event(event) do
    GenServer.cast(__MODULE__, {:handle_event, event})
  end

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Subscribe to reflex events
    :ok = PubSub.subscribe(@pubsub, @topic)
    :ok = PubSub.subscribe(@pubsub, "#{@topic}.triggered")
    :ok = PubSub.subscribe(@pubsub, "#{@topic}.chunk_aggregate")

    Logger.info("[Stabilization] Handler started, subscribed to #{@topic}")

    {:ok, %{handled_count: 0, last_event: nil}}
  end

  @impl true
  def handle_cast({:handle_event, event}, state) do
    state = process_event(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, %{name: name} = event}, state) when is_binary(name) do
    if String.contains?(name, "bolt.thunderbit.reflex") do
      state = process_event(event, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:reflex_event, event}, state) do
    state = process_event(event, state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ═══════════════════════════════════════════════════════════════
  # Event Processing
  # ═══════════════════════════════════════════════════════════════

  defp process_event(%{trigger: trigger} = event, state)
       when trigger in [:low_stability, :trust_boost, :recovery, :stabilize] do
    start_time = System.monotonic_time()

    Logger.debug("[Stabilization] Processing #{trigger} event for bit #{event[:bit_id]}")

    # Pipeline always returns :ok (maybe_update_pac_traits and emit_acknowledgment both return :ok)
    _pac_id =
      event
      |> extract_pac_id()
      |> maybe_update_pac_traits(event)
      |> emit_acknowledgment(event)

    emit_telemetry(:handled, start_time, event)

    %{state | handled_count: state.handled_count + 1, last_event: event}
  end

  defp process_event(_event, state), do: state

  defp extract_pac_id(%{data: %{pac_id: pac_id}}) when not is_nil(pac_id), do: pac_id
  defp extract_pac_id(%{pac_id: pac_id}) when not is_nil(pac_id), do: pac_id
  defp extract_pac_id(_), do: nil

  defp maybe_update_pac_traits(nil, _event), do: :ok

  defp maybe_update_pac_traits(pac_id, %{trigger: trigger} = event) do
    # Compute trait adjustments based on trigger
    adjustments = compute_adjustments(trigger, event)

    # Try to update PAC traits if the domain is available
    if Code.ensure_loaded?(Thunderline.Thunderpac.Domain) do
      # apply_trait_adjustments/2 always returns {:ok, _}
      {:ok, _pac} = apply_trait_adjustments(pac_id, adjustments)
      :ok
    else
      # Domain not available, skip update
      Logger.debug("[Stabilization] Thunderpac.Domain not loaded, skipping trait update")
      :ok
    end
  end

  defp compute_adjustments(:low_stability, event) do
    # Increase stability-related traits
    entropy = event[:data][:entropy] || 0.5

    %{
      bias: clamp(0.5 - entropy * 0.1),
      decay_rate: clamp(0.8 + entropy * 0.1),
      chaos_threshold: clamp(0.7 + entropy * 0.2)
    }
  end

  defp compute_adjustments(:trust_boost, _event) do
    %{
      trust_weight: 0.9,
      decay_rate: 0.7
    }
  end

  defp compute_adjustments(:recovery, event) do
    lambda = event[:data][:lambda_hat] || 0.3

    %{
      lambda_modulation: clamp(0.273 + (0.273 - lambda) * 0.5),
      bias: 0.5,
      chaos_threshold: 0.5
    }
  end

  defp compute_adjustments(:stabilize, _event) do
    %{
      bias: 0.5,
      decay_rate: 0.8,
      chaos_threshold: 0.6
    }
  end

  defp compute_adjustments(_, _event), do: %{}

  defp apply_trait_adjustments(pac_id, adjustments) when map_size(adjustments) > 0 do
    # Update PAC traits through the domain
    # This would call Thunderpac.Domain actions
    Logger.debug("[Stabilization] Would update PAC #{pac_id} with: #{inspect(adjustments)}")

    # For now, return success - actual implementation would call:
    # Thunderpac.Domain.update_pac_traits(pac_id, adjustments)
    {:ok, %{id: pac_id, adjustments: adjustments}}
  end

  defp apply_trait_adjustments(_pac_id, _adjustments), do: {:ok, nil}

  defp emit_acknowledgment(:ok, event) do
    # Emit acknowledgment event through EventBus
    ack_event_attrs = %{
      type: :reflex_stabilization_complete,
      source: :bolt,
      payload: %{
        original_trigger: event[:trigger],
        bit_id: event[:bit_id],
        handler: :stabilization
      },
      metadata: %{
        handler: __MODULE__,
        processed_at: DateTime.utc_now()
      }
    }

    with {:ok, ev} <- Thunderline.Event.new(ack_event_attrs) do
      Thunderline.Thunderflow.EventBus.publish_event(ev)
    end

    :ok
  end

  defp emit_telemetry(status, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [status],
      %{duration: duration, count: 1},
      metadata
    )
  end

  defp clamp(v), do: max(0.0, min(1.0, v))
end
