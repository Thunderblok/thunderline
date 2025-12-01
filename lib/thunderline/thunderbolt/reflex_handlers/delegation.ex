defmodule Thunderline.Thunderbolt.ReflexHandlers.Delegation do
  @moduledoc """
  Handles complex reflex events requiring cross-domain delegation.

  HC-Ω-8: Subscribes to `bolt.thunderbit.reflex.*` events and handles
  triggers that require delegation to other domains or Reactor sagas.

  ## Handled Triggers

  - `:complex_decision` - Multi-factor decision, delegate to Reactor saga
  - `:cross_domain` - Event affects multiple domains, coordinate response
  - `:saga_required` - Explicit saga orchestration needed
  - `:quarantine_needed` - Segment needs isolation, delegate to Thunderwall

  ## Actions Taken

  1. Classify delegation target based on trigger and context
  2. For Reactor sagas: start appropriate saga with event context
  3. For Thunderwall: request quarantine or containment
  4. For cross-domain: broadcast to affected domain handlers

  ## Saga Integration

  When `TL_ENABLE_REACTOR=true`, delegates to Reactor sagas:
  - `ReflexResolutionSaga` - Multi-step reflex resolution
  - `EvolutionCoordinationSaga` - Coordinated PAC evolution
  - `ContainmentSaga` - Quarantine and containment orchestration

  ## Telemetry

  - `[:thunderline, :bolt, :reflex_handler, :delegation, :handled]`
  - `[:thunderline, :bolt, :reflex_handler, :delegation, :saga_started]`
  - `[:thunderline, :bolt, :reflex_handler, :delegation, :quarantine_requested]`
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub Thunderline.PubSub
  @topic "bolt.thunderbit.reflex"
  @telemetry_prefix [:thunderline, :bolt, :reflex_handler, :delegation]

  # Check if Reactor is enabled
  @reactor_enabled System.get_env("TL_ENABLE_REACTOR") == "true"

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

  @doc """
  Check if Reactor sagas are enabled.
  """
  def reactor_enabled?, do: @reactor_enabled

  # ═══════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Subscribe to reflex events
    :ok = PubSub.subscribe(@pubsub, @topic)
    :ok = PubSub.subscribe(@pubsub, "#{@topic}.triggered")
    :ok = PubSub.subscribe(@pubsub, "#{@topic}.chunk_aggregate")

    Logger.info("[Delegation] Handler started, subscribed to #{@topic}")

    Logger.info(
      "[Delegation] Reactor sagas: #{if @reactor_enabled, do: "enabled", else: "disabled"}"
    )

    {:ok,
     %{
       handled_count: 0,
       sagas_started: 0,
       quarantines_requested: 0,
       last_event: nil
     }}
  end

  @impl true
  def handle_cast({:handle_event, event}, state) do
    state = process_event(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:event, %{name: name} = event}, state)
      when is_binary(name) and name =~ "bolt.thunderbit.reflex" do
    state = process_event(event, state)
    {:noreply, state}
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
       when trigger in [:complex_decision, :cross_domain, :saga_required, :quarantine_needed] do
    start_time = System.monotonic_time()

    Logger.info("[Delegation] Processing #{trigger} event for bit #{event[:bit_id]}")

    state = handle_delegation(trigger, event, state)

    emit_telemetry(:handled, start_time, %{trigger: trigger})

    %{state | handled_count: state.handled_count + 1, last_event: event}
  end

  defp process_event(_event, state), do: state

  # ───────────────────────────────────────────────────────────────
  # Delegation Handlers
  # ───────────────────────────────────────────────────────────────

  defp handle_delegation(:complex_decision, event, state) do
    Logger.debug("[Delegation] Complex decision delegation")

    if @reactor_enabled do
      start_resolution_saga(event, state)
    else
      # Fallback: use heuristic decision
      fallback_heuristic_decision(event)
      state
    end
  end

  defp handle_delegation(:cross_domain, event, state) do
    Logger.debug("[Delegation] Cross-domain event, broadcasting to affected domains")

    affected_domains = determine_affected_domains(event)
    broadcast_to_domains(affected_domains, event)

    state
  end

  defp handle_delegation(:saga_required, event, state) do
    Logger.info("[Delegation] Saga explicitly required")

    if @reactor_enabled do
      start_appropriate_saga(event, state)
    else
      Logger.warning("[Delegation] Saga required but Reactor disabled, using fallback")
      emit_saga_fallback_event(event)
      state
    end
  end

  defp handle_delegation(:quarantine_needed, event, state) do
    Logger.warning("[Delegation] Quarantine needed for #{event[:bit_id]}")

    request_quarantine(event)

    emit_telemetry(:quarantine_requested, System.monotonic_time(), %{
      bit_id: event[:bit_id],
      chunk_id: get_in(event, [:data, :chunk_id])
    })

    %{state | quarantines_requested: state.quarantines_requested + 1}
  end

  defp handle_delegation(_, _, state), do: state

  # ───────────────────────────────────────────────────────────────
  # Saga Operations
  # ───────────────────────────────────────────────────────────────

  defp start_resolution_saga(event, state) do
    saga_input = %{
      trigger: event[:trigger],
      bit_id: event[:bit_id],
      pac_id: extract_pac_id(event),
      metrics: event[:data],
      context: %{
        timestamp: DateTime.utc_now(),
        handler: __MODULE__
      }
    }

    # Would start Reactor saga:
    # Thunderline.Thunderbolt.Sagas.ReflexResolution.run(saga_input)

    Logger.info("[Delegation] Would start ReflexResolutionSaga with: #{inspect(saga_input)}")

    emit_telemetry(:saga_started, System.monotonic_time(), %{
      saga: :reflex_resolution,
      bit_id: event[:bit_id]
    })

    %{state | sagas_started: state.sagas_started + 1}
  end

  defp start_appropriate_saga(event, state) do
    saga_type = determine_saga_type(event)

    saga_input = %{
      trigger: event[:trigger],
      bit_id: event[:bit_id],
      pac_id: extract_pac_id(event),
      metrics: event[:data],
      saga_type: saga_type,
      context: %{
        timestamp: DateTime.utc_now(),
        handler: __MODULE__
      }
    }

    # Would start appropriate Reactor saga based on saga_type
    Logger.info("[Delegation] Would start #{saga_type} saga with: #{inspect(saga_input)}")

    emit_telemetry(:saga_started, System.monotonic_time(), %{
      saga: saga_type,
      bit_id: event[:bit_id]
    })

    %{state | sagas_started: state.sagas_started + 1}
  end

  defp determine_saga_type(event) do
    cond do
      get_in(event, [:data, :evolution_needed]) -> :evolution_coordination
      get_in(event, [:data, :containment_needed]) -> :containment
      get_in(event, [:data, :pac_id]) -> :pac_lifecycle
      true -> :reflex_resolution
    end
  end

  # ───────────────────────────────────────────────────────────────
  # Cross-Domain Operations
  # ───────────────────────────────────────────────────────────────

  defp determine_affected_domains(event) do
    domains = [:bolt]

    domains =
      if get_in(event, [:data, :pac_id]) do
        [:pac | domains]
      else
        domains
      end

    domains =
      if get_in(event, [:data, :entropy]) && get_in(event, [:data, :entropy]) > 0.8 do
        [:wall | domains]
      else
        domains
      end

    domains =
      if get_in(event, [:data, :persistence_needed]) do
        [:block | domains]
      else
        domains
      end

    domains
  end

  defp broadcast_to_domains(domains, event) do
    Enum.each(domains, fn domain ->
      topic = "#{domain}.reflex.delegated"

      PubSub.broadcast(@pubsub, topic, {:delegated_event, event})

      Logger.debug("[Delegation] Broadcast to #{topic}")
    end)
  end

  # ───────────────────────────────────────────────────────────────
  # Quarantine Operations
  # ───────────────────────────────────────────────────────────────

  defp request_quarantine(event) do
    quarantine_attrs = %{
      type: :quarantine_request,
      source: :bolt,
      priority: :high,
      payload: %{
        bit_id: event[:bit_id],
        chunk_id: get_in(event, [:data, :chunk_id]),
        reason: event[:trigger],
        metrics: event[:data],
        action: :isolate,
        duration_ticks: 200
      },
      metadata: %{
        handler: __MODULE__,
        requested_at: DateTime.utc_now()
      }
    }

    emit_event(quarantine_attrs)

    # Also notify Thunderwall directly if available
    if Code.ensure_loaded?(Thunderline.Thunderwall.GCScheduler) do
      Logger.debug("[Delegation] Notifying Thunderwall of quarantine request")
      # Thunderwall.quarantine_segment(event[:bit_id], event[:data][:chunk_id])
    end
  end

  # ───────────────────────────────────────────────────────────────
  # Fallback Operations
  # ───────────────────────────────────────────────────────────────

  defp fallback_heuristic_decision(event) do
    entropy = get_in(event, [:data, :entropy]) || 0.5
    lambda = get_in(event, [:data, :lambda_hat]) || 0.3

    decision =
      cond do
        # High chaos - stabilize
        entropy > 0.8 -> :stabilize
        # Near critical point - observe
        lambda > 0.25 and lambda < 0.3 -> :observe
        # Too ordered - perturb
        entropy < 0.2 -> :perturb
        # Default - maintain
        true -> :maintain
      end

    Logger.info("[Delegation] Heuristic decision: #{decision}")

    fallback_attrs = %{
      type: :heuristic_decision,
      source: :bolt,
      payload: %{
        bit_id: event[:bit_id],
        decision: decision,
        metrics: %{entropy: entropy, lambda: lambda},
        fallback: true
      },
      metadata: %{handler: __MODULE__}
    }

    emit_event(fallback_attrs)
  end

  defp emit_saga_fallback_event(event) do
    fallback_attrs = %{
      type: :saga_fallback,
      source: :bolt,
      priority: :low,
      payload: %{
        original_trigger: event[:trigger],
        bit_id: event[:bit_id],
        reason: :reactor_disabled
      },
      metadata: %{handler: __MODULE__}
    }

    emit_event(fallback_attrs)
  end

  # ───────────────────────────────────────────────────────────────
  # Helpers
  # ───────────────────────────────────────────────────────────────

  defp extract_pac_id(%{data: %{pac_id: pac_id}}) when not is_nil(pac_id), do: pac_id
  defp extract_pac_id(%{pac_id: pac_id}) when not is_nil(pac_id), do: pac_id
  defp extract_pac_id(_), do: nil

  defp emit_event(attrs) do
    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      Thunderline.Thunderflow.EventBus.publish_event(ev)
    else
      {:error, reason} ->
        Logger.error("[Delegation] Failed to emit event: #{inspect(reason)}")
    end
  end

  defp emit_telemetry(status, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @telemetry_prefix ++ [status],
      %{duration: duration, count: 1},
      metadata
    )
  end
end
