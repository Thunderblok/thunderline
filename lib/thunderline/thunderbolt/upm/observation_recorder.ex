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
            ├─→ Clustering analysis (if enabled)
            │
            ▼
      UpmObservation.record/1
            │
            ▼
      EventBus: "ai.upm.observation.recorded"

  ## Multi-Manifold Clustering (HC-22A)

  When clustering is enabled, the recorder:
  1. Collects recent observations (sliding window)
  2. Computes manifold_id via UMAP + HDBSCAN (optional)
  3. Calculates cluster_stability, manifold_distance, simplex_degree
  4. Persists all metrics with each observation

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
        max_batch_size: 100,
        clustering_enabled: true,                   # HC-22A clustering
        clustering_window_size: 50                  # observations for clustering

  ## Events Produced

  - `ai.upm.observation.recorded` - After each observation is persisted
  - `ai.upm.health.degraded` - When band_status is not :healthy
  - `ai.upm.cluster.transition` - When manifold_id changes
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
          last_flush: integer(),
          # HC-22A: Clustering state
          clustering_enabled: boolean(),
          clustering_window_size: pos_integer(),
          observation_windows: %{atom() => :queue.queue(map())},
          last_manifold_ids: %{atom() => integer() | nil}
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
    clustering_enabled = Keyword.get(merged, :clustering_enabled, true)
    clustering_window_size = Keyword.get(merged, :clustering_window_size, 50)

    state = %{
      enabled: enabled,
      pac_resolver: pac_resolver,
      batch: [],
      batch_interval_ms: batch_interval_ms,
      max_batch_size: max_batch_size,
      last_flush: System.monotonic_time(:millisecond),
      # HC-22A: Clustering state
      clustering_enabled: clustering_enabled,
      clustering_window_size: clustering_window_size,
      observation_windows: %{},
      last_manifold_ids: %{}
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
    # HC-22A: Compute clustering metrics
    {enriched_observation, new_state} = compute_clustering_metrics(observation, state)

    # Resolve PAC ID if resolver provided
    pac_id =
      case state.pac_resolver do
        nil -> enriched_observation[:pac_id] || UUID.v7()
        resolver when is_function(resolver, 1) -> resolver.(enriched_observation[:domain]) || UUID.v7()
      end

    attrs = %{
      pac_id: pac_id,
      domain: enriched_observation[:domain] || :ml_pipeline,
      tick: enriched_observation[:tick] || 0,
      plv: enriched_observation[:plv],
      sigma: enriched_observation[:sigma],
      lambda: enriched_observation[:lambda],
      rtau: enriched_observation[:rtau],
      entropy: enriched_observation[:entropy],
      # HC-22A: Clustering fields
      manifold_id: enriched_observation[:manifold_id],
      cluster_stability: enriched_observation[:cluster_stability],
      manifold_distance: enriched_observation[:manifold_distance],
      simplex_degree: enriched_observation[:simplex_degree],
      band_status: enriched_observation[:band_status] || :unknown,
      intervention_triggered: enriched_observation[:intervention_triggered] || false,
      intervention_type: enriched_observation[:intervention_type],
      activations_shape: enriched_observation[:activations_shape] || %{},
      metadata: enriched_observation[:metadata] || %{}
    }

    case UpmObservation.record(attrs) do
      {:ok, record} ->
        # Emit event
        emit_observation_event(record)

        # Check for health degradation
        if record.band_status != :healthy do
          emit_health_degraded_event(record)
        end

        {:ok, record, new_state}

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
        band_status: record.band_status,
        # HC-22A: Clustering fields
        manifold_id: record.manifold_id,
        cluster_stability: record.cluster_stability,
        simplex_degree: record.simplex_degree
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

  # ---------------------------------------------------------------------------
  # HC-22A: Multi-Manifold Clustering Helpers
  # ---------------------------------------------------------------------------

  @doc false
  @spec compute_clustering_metrics(map(), state()) :: {map(), state()}
  def compute_clustering_metrics(observation, %{clustering_enabled: false} = state) do
    {observation, state}
  end

  def compute_clustering_metrics(observation, state) do
    domain = observation[:domain] || :ml_pipeline

    # Update observation window for this domain
    window = Map.get(state.observation_windows, domain, :queue.new())

    window =
      window
      |> :queue.in(observation)
      |> trim_window(state.clustering_window_size)

    new_windows = Map.put(state.observation_windows, domain, window)

    # Compute clustering metrics from window
    window_list = :queue.to_list(window)
    clustering = compute_manifold_assignment(window_list, observation)

    # Check for cluster transition
    last_manifold = Map.get(state.last_manifold_ids, domain)
    new_manifold_ids = Map.put(state.last_manifold_ids, domain, clustering.manifold_id)

    new_state = %{state | observation_windows: new_windows, last_manifold_ids: new_manifold_ids}

    # Emit cluster transition event if manifold changed
    if last_manifold != nil and clustering.manifold_id != last_manifold do
      emit_cluster_transition_event(domain, last_manifold, clustering.manifold_id, observation[:tick])
    end

    enriched_observation =
      observation
      |> Map.put(:manifold_id, clustering.manifold_id)
      |> Map.put(:cluster_stability, clustering.stability)
      |> Map.put(:manifold_distance, clustering.distance)
      |> Map.put(:simplex_degree, clustering.simplex_degree)

    {enriched_observation, new_state}
  end

  defp trim_window(queue, max_size) do
    if :queue.len(queue) > max_size do
      {_, trimmed} = :queue.out(queue)
      trim_window(trimmed, max_size)
    else
      queue
    end
  end

  @doc """
  Compute manifold assignment for current observation based on window history.

  Uses a simplified distance-based clustering approach:
  1. Compute feature vector: [plv, sigma, lambda, rtau]
  2. Calculate centroid of recent observations
  3. Assign manifold based on distance to centroid + stability bands

  For full UMAP/HDBSCAN, this would call into a Python service or Nx-based impl.
  """
  @spec compute_manifold_assignment([map()], map()) :: %{
          manifold_id: integer(),
          stability: float(),
          distance: float(),
          simplex_degree: integer()
        }
  def compute_manifold_assignment([], _current) do
    %{manifold_id: 0, stability: 1.0, distance: 0.0, simplex_degree: 0}
  end

  def compute_manifold_assignment(window, current) do
    # Extract feature vectors
    features =
      Enum.map(window, fn obs ->
        [
          obs[:plv] || 0.0,
          obs[:sigma] || 1.0,
          obs[:lambda] || 0.0,
          obs[:rtau] || 0.0
        ]
      end)

    current_vec = [
      current[:plv] || 0.0,
      current[:sigma] || 1.0,
      current[:lambda] || 0.0,
      current[:rtau] || 0.0
    ]

    # Compute centroid
    centroid = compute_centroid(features)

    # Distance to centroid
    distance = euclidean_distance(current_vec, centroid)

    # Simple manifold assignment based on PLV and sigma bands
    manifold_id = assign_manifold(current_vec)

    # Stability = inverse of recent variance (normalized)
    stability = compute_stability(features, current_vec)

    # Simplex degree = count of neighbors within threshold distance
    simplex_degree = compute_simplex_degree(features, current_vec, 0.3)

    %{
      manifold_id: manifold_id,
      stability: Float.round(stability, 4),
      distance: Float.round(distance, 4),
      simplex_degree: simplex_degree
    }
  end

  defp compute_centroid([]), do: [0.0, 1.0, 0.0, 0.0]

  defp compute_centroid(features) do
    n = length(features)
    dims = length(hd(features))

    for d <- 0..(dims - 1) do
      sum = Enum.sum(Enum.map(features, fn f -> Enum.at(f, d) end))
      sum / n
    end
  end

  defp euclidean_distance(a, b) do
    a
    |> Enum.zip(b)
    |> Enum.map(fn {x, y} -> (x - y) * (x - y) end)
    |> Enum.sum()
    |> :math.sqrt()
  end

  # Assign manifold based on health bands (simplified HDBSCAN proxy)
  defp assign_manifold([plv, sigma, _lambda, _rtau]) do
    cond do
      # Healthy band: PLV 0.3-0.6, sigma 0.8-1.2
      plv >= 0.3 and plv <= 0.6 and sigma >= 0.8 and sigma <= 1.2 -> 0
      # Loop band: high PLV
      plv > 0.9 -> 1
      # Decay band: low sigma
      sigma < 0.5 -> 2
      # Amplification band: high sigma
      sigma > 1.5 -> 3
      # Edge band: PLV at boundaries
      plv < 0.3 or plv > 0.6 -> 4
      # Default/unknown
      true -> -1
    end
  end

  defp compute_stability(features, current) do
    if length(features) < 2 do
      1.0
    else
      # Compute variance of distances from current
      distances = Enum.map(features, &euclidean_distance(&1, current))
      mean_dist = Enum.sum(distances) / length(distances)

      variance =
        distances
        |> Enum.map(fn d -> (d - mean_dist) * (d - mean_dist) end)
        |> Enum.sum()
        |> Kernel./(length(distances))

      # Stability = 1 / (1 + variance) normalized to [0, 1]
      1.0 / (1.0 + variance)
    end
  end

  defp compute_simplex_degree(features, current, threshold) do
    features
    |> Enum.count(fn f -> euclidean_distance(f, current) <= threshold end)
  end

  defp emit_cluster_transition_event(domain, from_manifold, to_manifold, tick) do
    attrs = [
      name: "ai.upm.cluster.transition",
      source: :bolt,
      payload: %{
        domain: domain,
        from_manifold: from_manifold,
        to_manifold: to_manifold,
        tick: tick,
        transition_time: DateTime.utc_now()
      },
      meta: %{pipeline: :realtime}
    ]

    case Event.new(attrs) do
      {:ok, event} -> EventBus.publish_event(event)
      {:error, _} -> :ok
    end
  end
end
