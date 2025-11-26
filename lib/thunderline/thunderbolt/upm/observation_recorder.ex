defmodule Thunderline.Thunderbolt.UPM.ObservationRecorder do
  @moduledoc """
  Bridges LoopMonitor telemetry to UpmObservation persistence.

  Subscribes to LoopMonitor telemetry events and records observations
  to the UpmObservation resource, creating a persistent history of
  domain health metrics.

  ## Architecture

      LoopMonitor.observe/2
            │
            ▼
      [:thunderline, :loop_monitor, :observed] telemetry
            │
            ▼
      ObservationRecorder (this module)
            │
            ▼
      UpmObservation.record/1
            │
            ▼
      EventBus: "ai.upm.observation.recorded"

  ## Supervision

  Add to your application supervision tree:

      children = [
        Thunderline.Thunderbolt.UPM.ObservationRecorder
      ]

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.ObservationRecorder,
        enabled: true,
        pac_resolver: &MyModule.resolve_pac_id/1,  # optional
        batch_interval_ms: 1000,                    # batching for high-throughput
        max_batch_size: 100

  ## Events Produced

  - `ai.upm.observation.recorded` - After each observation is persisted
  - `ai.upm.health.degraded` - When band_status is not :healthy
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Resources.UpmObservation
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.Event
  alias Thunderline.UUID

  @type state :: %{
          enabled: boolean(),
          pac_resolver: (atom() -> binary() | nil) | nil,
          batch: [map()],
          batch_interval_ms: pos_integer(),
          max_batch_size: pos_integer(),
          last_flush: integer()
        }

  # Client API

  @doc """
  Starts the ObservationRecorder.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Manually record an observation (bypasses telemetry).

  Useful for testing or direct integration.
  """
  @spec record(map()) :: {:ok, term()} | {:error, term()}
  def record(observation) do
    GenServer.call(__MODULE__, {:record, observation})
  end

  @doc """
  Flush pending batch immediately.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Get current batch size (for monitoring).
  """
  @spec batch_size() :: non_neg_integer()
  def batch_size do
    GenServer.call(__MODULE__, :batch_size)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Application.get_env(:thunderline, __MODULE__, [])
    merged = Keyword.merge(config, opts)

    enabled = Keyword.get(merged, :enabled, true)
    pac_resolver = Keyword.get(merged, :pac_resolver)
    batch_interval_ms = Keyword.get(merged, :batch_interval_ms, 1000)
    max_batch_size = Keyword.get(merged, :max_batch_size, 100)

    state = %{
      enabled: enabled,
      pac_resolver: pac_resolver,
      batch: [],
      batch_interval_ms: batch_interval_ms,
      max_batch_size: max_batch_size,
      last_flush: System.monotonic_time(:millisecond)
    }

    if enabled do
      # Attach telemetry handler
      :telemetry.attach(
        "upm-observation-recorder",
        [:thunderline, :loop_monitor, :observed],
        &handle_telemetry_event/4,
        %{pid: self()}
      )

      # Schedule periodic flush
      schedule_flush(batch_interval_ms)

      Logger.info("[UPM.ObservationRecorder] Started - telemetry handler attached")
    else
      Logger.info("[UPM.ObservationRecorder] Started (disabled)")
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:record, observation}, _from, state) do
    case do_record(observation, state) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:flush, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:batch_size, _from, state) do
    {:reply, length(state.batch), state}
  end

  @impl true
  def handle_cast({:observation, observation}, state) do
    # Add to batch
    new_batch = [observation | state.batch]

    new_state =
      if length(new_batch) >= state.max_batch_size do
        # Flush immediately if batch is full
        do_flush(%{state | batch: new_batch})
      else
        %{state | batch: new_batch}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:flush_batch, state) do
    new_state = do_flush(state)
    schedule_flush(state.batch_interval_ms)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("[UPM.ObservationRecorder] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach("upm-observation-recorder")
    :ok
  end

  # Telemetry Handler (called in telemetry context)

  def handle_telemetry_event(
        [:thunderline, :loop_monitor, :observed],
        measurements,
        metadata,
        %{pid: pid}
      ) do
    observation = %{
      domain: metadata.domain,
      tick: metadata.tick,
      plv: metadata.plv,
      sigma: metadata.sigma,
      lambda: metadata.lambda,
      rtau: metadata.rtau,
      band_status: metadata.bands.overall,
      timestamp: measurements.timestamp
    }

    GenServer.cast(pid, {:observation, observation})
  end

  # Private Helpers

  defp do_record(observation, state) do
    # Resolve PAC ID if resolver provided
    pac_id =
      case state.pac_resolver do
        nil -> observation[:pac_id] || UUID.v7()
        resolver when is_function(resolver, 1) -> resolver.(observation[:domain]) || UUID.v7()
      end

    attrs = %{
      pac_id: pac_id,
      domain: observation[:domain] || :ml_pipeline,
      tick: observation[:tick] || 0,
      plv: observation[:plv],
      sigma: observation[:sigma],
      lambda: observation[:lambda],
      rtau: observation[:rtau],
      entropy: observation[:entropy],
      band_status: observation[:band_status] || :unknown,
      intervention_triggered: observation[:intervention_triggered] || false,
      intervention_type: observation[:intervention_type],
      activations_shape: observation[:activations_shape] || %{},
      metadata: observation[:metadata] || %{}
    }

    case UpmObservation.record(attrs) do
      {:ok, record} ->
        # Emit event
        emit_observation_event(record)

        # Check for health degradation
        if record.band_status != :healthy do
          emit_health_degraded_event(record)
        end

        {:ok, record, state}

      {:error, reason} ->
        Logger.error("[UPM.ObservationRecorder] Failed to record observation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_flush(%{batch: []} = state) do
    %{state | last_flush: System.monotonic_time(:millisecond)}
  end

  defp do_flush(state) do
    # Process batch in reverse order (oldest first)
    observations = Enum.reverse(state.batch)

    Enum.each(observations, fn observation ->
      # Resolve PAC ID
      pac_id =
        case state.pac_resolver do
          nil -> observation[:pac_id] || UUID.v7()
          resolver when is_function(resolver, 1) -> resolver.(observation[:domain]) || UUID.v7()
        end

      attrs = %{
        pac_id: pac_id,
        domain: observation[:domain] || :ml_pipeline,
        tick: observation[:tick] || 0,
        plv: observation[:plv],
        sigma: observation[:sigma],
        lambda: observation[:lambda],
        rtau: observation[:rtau],
        entropy: observation[:entropy],
        band_status: observation[:band_status] || :unknown,
        metadata: %{
          batch_flushed: true,
          original_timestamp: observation[:timestamp]
        }
      }

      case UpmObservation.record(attrs) do
        {:ok, record} ->
          emit_observation_event(record)

          if record.band_status != :healthy do
            emit_health_degraded_event(record)
          end

        {:error, reason} ->
          Logger.warning("[UPM.ObservationRecorder] Failed to record batch observation: #{inspect(reason)}")
      end
    end)

    Logger.debug("[UPM.ObservationRecorder] Flushed #{length(observations)} observations")

    %{state | batch: [], last_flush: System.monotonic_time(:millisecond)}
  end

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :flush_batch, interval_ms)
  end

  defp emit_observation_event(record) do
    attrs = [
      name: "ai.upm.observation.recorded",
      source: :bolt,
      payload: %{
        observation_id: record.id,
        pac_id: record.pac_id,
        domain: record.domain,
        tick: record.tick,
        plv: record.plv,
        sigma: record.sigma,
        lambda: record.lambda,
        rtau: record.rtau,
        band_status: record.band_status
      },
      meta: %{pipeline: :realtime}
    ]

    case Event.new(attrs) do
      {:ok, event} -> EventBus.publish_event(event)
      {:error, _} -> :ok
    end
  end

  defp emit_health_degraded_event(record) do
    attrs = [
      name: "ai.upm.health.degraded",
      source: :bolt,
      payload: %{
        observation_id: record.id,
        pac_id: record.pac_id,
        domain: record.domain,
        tick: record.tick,
        band_status: record.band_status,
        plv: record.plv,
        sigma: record.sigma,
        lambda: record.lambda
      },
      meta: %{pipeline: :realtime, priority: :high}
    ]

    case Event.new(attrs) do
      {:ok, event} -> EventBus.publish_event(event)
      {:error, _} -> :ok
    end
  end
end
