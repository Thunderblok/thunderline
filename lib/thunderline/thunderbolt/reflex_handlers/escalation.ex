defmodule Thunderline.Thunderbolt.ReflexHandlers.Escalation do
  @moduledoc """
  Handles escalation-related reflex events (chaos, critical thresholds).

  HC-Ω-8: Subscribes to `bolt.thunderbit.reflex.*` events and handles
  triggers that require escalation actions.

  ## Handled Triggers

  - `:chaos_spike` - Sudden entropy increase, may trigger evolution or GC
  - `:critical_threshold` - Metrics crossed critical bounds, emergency response
  - `:evolution_needed` - PAC traits should evolve, enqueue evolution job
  - `:cascade_risk` - Risk of cascading failures, preemptive action

  ## Actions Taken

  1. Assess severity from event metrics
  2. For evolution triggers: enqueue `TraitsEvolutionJob`
  3. For critical triggers: notify Thunderwall GC
  4. For cascade risk: emit warning events, prepare containment

  ## Telemetry

  - `[:thunderline, :bolt, :reflex_handler, :escalation, :handled]`
  - `[:thunderline, :bolt, :reflex_handler, :escalation, :evolution_enqueued]`
  - `[:thunderline, :bolt, :reflex_handler, :escalation, :gc_triggered]`
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias Thunderline.Thunderpac.Workers.EvolutionWorker

  @pubsub Thunderline.PubSub
  @topic "bolt.thunderbit.reflex"
  @telemetry_prefix [:thunderline, :bolt, :reflex_handler, :escalation]

  # Severity thresholds
  @critical_entropy_threshold 0.85
  @critical_lambda_threshold 0.8

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

    Logger.info("[Escalation] Handler started, subscribed to #{@topic}")

    {:ok,
     %{
       handled_count: 0,
       evolution_jobs_enqueued: 0,
       gc_triggers: 0,
       last_event: nil
     }}
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
       when trigger in [:chaos_spike, :critical_threshold, :evolution_needed, :cascade_risk] do
    start_time = System.monotonic_time()

    Logger.info("[Escalation] Processing #{trigger} event for bit #{event[:bit_id]}")

    severity = assess_severity(event)
    state = handle_escalation(trigger, severity, event, state)

    emit_telemetry(:handled, start_time, %{trigger: trigger, severity: severity})

    %{state | handled_count: state.handled_count + 1, last_event: event}
  end

  defp process_event(_event, state), do: state

  defp assess_severity(event) do
    entropy = get_in(event, [:data, :entropy]) || 0.5
    lambda = get_in(event, [:data, :lambda_hat]) || 0.3

    cond do
      entropy > @critical_entropy_threshold and lambda > @critical_lambda_threshold ->
        :critical

      entropy > @critical_entropy_threshold or lambda > @critical_lambda_threshold ->
        :high

      entropy > 0.7 or lambda > 0.6 ->
        :medium

      true ->
        :low
    end
  end

  defp handle_escalation(:chaos_spike, severity, event, state)
       when severity in [:critical, :high] do
    # High severity chaos - trigger GC and possibly evolution
    Logger.warning("[Escalation] High severity chaos spike, triggering GC")

    trigger_gc_cleanup(event)
    maybe_enqueue_evolution(event, state)
  end

  defp handle_escalation(:chaos_spike, _severity, event, state) do
    # Lower severity - just monitor
    Logger.debug("[Escalation] Low severity chaos spike, monitoring")
    emit_chaos_warning(event)
    state
  end

  defp handle_escalation(:critical_threshold, _severity, event, state) do
    Logger.error("[Escalation] Critical threshold crossed, emergency response")

    # Always trigger GC for critical thresholds
    state = trigger_gc_cleanup(event)

    # Emit emergency event
    emit_emergency_event(event)

    state
  end

  defp handle_escalation(:evolution_needed, _severity, event, state) do
    Logger.info("[Escalation] Evolution needed, enqueuing job")
    maybe_enqueue_evolution(event, state)
  end

  defp handle_escalation(:cascade_risk, severity, event, state) do
    Logger.warning("[Escalation] Cascade risk detected (severity: #{severity})")

    # Emit warning to all handlers
    emit_cascade_warning(event)

    # If critical, trigger preemptive containment
    if severity == :critical do
      trigger_preemptive_containment(event)
    end

    state
  end

  defp handle_escalation(_, _, _, state), do: state

  # ───────────────────────────────────────────────────────────────
  # GC and Evolution Actions
  # ───────────────────────────────────────────────────────────────

  defp trigger_gc_cleanup(event) do
    # Request GC cleanup from Thunderwall
    if Code.ensure_loaded?(Thunderline.Thunderwall.GCScheduler) do
      Logger.debug("[Escalation] Requesting GC cleanup")

      # Async GC trigger - don't block the handler
      Task.start(fn ->
        Thunderline.Thunderwall.GCScheduler.run_gc()
      end)
    end

    emit_telemetry(:gc_triggered, System.monotonic_time(), %{
      bit_id: event[:bit_id],
      trigger: event[:trigger]
    })

    # Return updated state with GC count
    :ok
  end

  defp maybe_enqueue_evolution(event, state) do
    pac_id = extract_pac_id(event)

    if pac_id && Code.ensure_loaded?(EvolutionWorker) do
      # Determine evolution profile based on event data
      profile = determine_evolution_profile(event)

      Logger.info(
        "[Escalation] Enqueuing evolution job for PAC #{pac_id} with profile #{profile}"
      )

      job_args = %{
        "pac_id" => pac_id,
        "profile" => Atom.to_string(profile),
        "fitness_window" => 50,
        "triggered_by" => "reflex_handler",
        "trigger_event" => event[:trigger]
      }

      case EvolutionWorker.new(job_args) |> Oban.insert() do
        {:ok, job} ->
          Logger.info("[Escalation] Evolution job #{job.id} enqueued")
          emit_telemetry(:evolution_enqueued, System.monotonic_time(), %{job_id: job.id})
          %{state | evolution_jobs_enqueued: state.evolution_jobs_enqueued + 1}

        {:error, reason} ->
          Logger.error("[Escalation] Failed to enqueue evolution: #{inspect(reason)}")
          state
      end
    else
      Logger.debug("[Escalation] No PAC ID or EvolutionWorker not available")
      state
    end
  end

  defp determine_evolution_profile(event) do
    entropy = get_in(event, [:data, :entropy]) || 0.5
    lambda = get_in(event, [:data, :lambda_hat]) || 0.3

    cond do
      # High chaos - need resilience
      entropy > 0.8 -> :resilient
      # Edge of chaos - explore
      lambda > 0.25 and lambda < 0.3 -> :explorer
      # Too ordered - need exploration
      entropy < 0.3 -> :aggressive
      # Default balanced
      true -> :balanced
    end
  end

  defp extract_pac_id(%{data: %{pac_id: pac_id}}) when not is_nil(pac_id), do: pac_id
  defp extract_pac_id(%{pac_id: pac_id}) when not is_nil(pac_id), do: pac_id
  defp extract_pac_id(_), do: nil

  # ───────────────────────────────────────────────────────────────
  # Warning and Emergency Events
  # ───────────────────────────────────────────────────────────────

  defp emit_chaos_warning(event) do
    warning_attrs = %{
      type: :reflex_chaos_warning,
      source: :bolt,
      payload: %{
        bit_id: event[:bit_id],
        entropy: get_in(event, [:data, :entropy]),
        lambda_hat: get_in(event, [:data, :lambda_hat]),
        severity: :warning
      },
      metadata: %{handler: __MODULE__}
    }

    emit_event(warning_attrs)
  end

  defp emit_emergency_event(event) do
    emergency_attrs = %{
      type: :reflex_emergency,
      source: :bolt,
      priority: :critical,
      payload: %{
        bit_id: event[:bit_id],
        trigger: event[:trigger],
        metrics: event[:data],
        severity: :critical
      },
      metadata: %{handler: __MODULE__, emergency: true}
    }

    emit_event(emergency_attrs)
  end

  defp emit_cascade_warning(event) do
    warning_attrs = %{
      type: :reflex_cascade_warning,
      source: :bolt,
      priority: :high,
      payload: %{
        bit_id: event[:bit_id],
        cascade_risk: true,
        affected_region: get_in(event, [:data, :chunk_id])
      },
      metadata: %{handler: __MODULE__}
    }

    emit_event(warning_attrs)
  end

  defp trigger_preemptive_containment(event) do
    Logger.warning("[Escalation] Triggering preemptive containment")

    containment_attrs = %{
      type: :containment_requested,
      source: :bolt,
      priority: :critical,
      payload: %{
        bit_id: event[:bit_id],
        chunk_id: get_in(event, [:data, :chunk_id]),
        action: :freeze,
        duration_ticks: 100
      },
      metadata: %{handler: __MODULE__, preemptive: true}
    }

    emit_event(containment_attrs)
  end

  defp emit_event(attrs) do
    with {:ok, ev} <- Thunderline.Event.new(attrs) do
      Thunderline.Thunderflow.EventBus.publish_event(ev)
    else
      {:error, reason} ->
        Logger.error("[Escalation] Failed to emit event: #{inspect(reason)}")
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
