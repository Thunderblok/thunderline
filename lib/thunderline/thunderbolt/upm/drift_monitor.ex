defmodule Thunderline.Thunderbolt.UPM.DriftMonitor do
  @moduledoc """
  Drift monitor for UPM that compares shadow predictions vs ground truth.

  Tracks prediction drift between shadow UPM model and production agents,
  raising quarantine flags when drift exceeds configured thresholds.

  ## Responsibilities

  - Monitor shadow model predictions vs actual agent decisions
  - Calculate drift scores (P95, mean, max)
  - Emit `ai.upm.shadow_delta` events
  - Create and manage UpmDriftWindow resources
  - Trigger quarantine when drift exceeds threshold
  - Coordinate with ThunderCrown for rollback approval

  ## Configuration

      config :thunderline, Thunderline.Thunderbolt.UPM.DriftMonitor,
        window_duration_ms: 3_600_000,  # 1 hour
        drift_threshold: 0.2,
        sample_size: 1000,
        quarantine_enabled: true

  ## Telemetry Events

  - `[:upm, :drift, :score]` - Drift score calculated
  - `[:upm, :drift, :quarantine]` - Quarantine triggered
  - `[:upm, :drift, :resolve]` - Drift resolved
  """

  use GenServer
  require Logger

  alias Thunderline.Thunderbolt.Resources.{UpmDriftWindow, UpmSnapshot, UpmTrainer}
  alias Thunderline.Thunderflow.EventBus
  alias Thunderline.UUID

  @type comparison :: %{
          window_id: binary(),
          shadow_prediction: term(),
          ground_truth: term(),
          drift_score: float(),
          timestamp: DateTime.t()
        }

  @type state :: %{
          trainer_id: binary(),
          snapshot_id: binary() | nil,
          window_id: binary() | nil,
          window_start: DateTime.t() | nil,
          window_duration_ms: pos_integer(),
          drift_threshold: float(),
          sample_size: pos_integer(),
          quarantine_enabled: boolean(),
          comparisons: [comparison()],
          window_timer: reference() | nil
        }

  # Client API

  @doc """
  Starts the drift monitor.

  ## Options

  - `:trainer_id` - Associated trainer ID (required)
  - `:window_duration_ms` - Duration of drift measurement window (default: 3600000)
  - `:drift_threshold` - P95 drift threshold for quarantine (default: 0.2)
  - `:sample_size` - Minimum samples before evaluation (default: 1000)
  - `:quarantine_enabled` - Enable automatic quarantine (default: true)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    trainer_id = Keyword.fetch!(opts, :trainer_id)
    GenServer.start_link(__MODULE__, opts, name: via(trainer_id))
  end

  @doc """
  Records a shadow comparison for drift calculation.

  ## Parameters

  - `server` - GenServer reference
  - `comparison` - Map with `:shadow_prediction`, `:ground_truth`, and optional `:metadata`
  """
  @spec record_comparison(GenServer.server(), map()) :: :ok
  def record_comparison(server, comparison) do
    GenServer.cast(server, {:record_comparison, comparison})
  end

  @doc """
  Gets current drift statistics.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server) do
    GenServer.call(server, :get_stats)
  end

  @doc """
  Forces drift window evaluation (for testing/debugging).
  """
  @spec evaluate_now(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def evaluate_now(server) do
    GenServer.call(server, :evaluate_now)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    trainer_id = Keyword.fetch!(opts, :trainer_id)
    window_duration_ms = Keyword.get(opts, :window_duration_ms, 3_600_000)
    drift_threshold = Keyword.get(opts, :drift_threshold, 0.2)
    sample_size = Keyword.get(opts, :sample_size, 1000)
    quarantine_enabled = Keyword.get(opts, :quarantine_enabled, true)

    state = %{
      trainer_id: trainer_id,
      snapshot_id: nil,
      window_id: nil,
      window_start: nil,
      window_duration_ms: window_duration_ms,
      drift_threshold: drift_threshold,
      sample_size: sample_size,
      quarantine_enabled: quarantine_enabled,
      comparisons: [],
      window_timer: nil
    }

    # Start first window
    new_state = start_new_window(state)

    Logger.info("""
    [UPM.DriftMonitor] Initialized
      trainer_id: #{trainer_id}
      window_duration: #{window_duration_ms}ms
      drift_threshold: #{drift_threshold}
      sample_size: #{sample_size}
    """)

    {:ok, new_state}
  end

  @impl true
  def handle_cast({:record_comparison, comparison}, state) do
    # Calculate drift score for this comparison
    drift_score = calculate_drift(comparison.shadow_prediction, comparison.ground_truth)

    comparison_entry = %{
      window_id: comparison[:window_id] || UUID.v7(),
      shadow_prediction: comparison.shadow_prediction,
      ground_truth: comparison.ground_truth,
      drift_score: drift_score,
      timestamp: DateTime.utc_now()
    }

    new_comparisons = [comparison_entry | state.comparisons]

    # Emit individual delta event
    emit_shadow_delta_event(state.trainer_id, comparison_entry)

    {:noreply, %{state | comparisons: new_comparisons}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_drift_stats(state.comparisons)

    stats_map = %{
      trainer_id: state.trainer_id,
      window_id: state.window_id,
      window_start: state.window_start,
      sample_count: length(state.comparisons),
      drift_p95: stats.p95,
      drift_mean: stats.mean,
      drift_max: stats.max,
      threshold: state.drift_threshold,
      quarantine_risk: stats.p95 >= state.drift_threshold
    }

    {:reply, stats_map, state}
  end

  def handle_call(:evaluate_now, _from, state) do
    case evaluate_window(state) do
      {:ok, result} ->
        # Start new window
        new_state = start_new_window(%{state | comparisons: []})
        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:window_complete, state) do
    # Evaluate current window
    case evaluate_window(state) do
      {:ok, _result} ->
        # Start new window
        new_state = start_new_window(%{state | comparisons: []})
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[UPM.DriftMonitor] Window evaluation failed: #{inspect(reason)}")
        # Start new window anyway
        new_state = start_new_window(%{state | comparisons: []})
        {:noreply, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("[UPM.DriftMonitor] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helpers

  defp via(trainer_id) do
    {:via, Registry, {Thunderline.Registry, {__MODULE__, trainer_id}}}
  end

  defp start_new_window(state) do
    # Cancel existing timer
    if state.window_timer, do: Process.cancel_timer(state.window_timer)

    window_id = UUID.v7()
    window_start = DateTime.utc_now()

    # Get current snapshot
    {:ok, trainer} = Ash.get(UpmTrainer, state.trainer_id)
    snapshot_id = get_current_snapshot_id(trainer)

    # Create drift window resource
    case create_drift_window(state.trainer_id, snapshot_id, state.drift_threshold) do
      {:ok, drift_window} ->
        # Schedule window completion
        timer = Process.send_after(self(), :window_complete, state.window_duration_ms)

        Logger.debug("""
        [UPM.DriftMonitor] Started new window
          window_id: #{window_id}
          drift_window_id: #{drift_window.id}
          duration: #{state.window_duration_ms}ms
        """)

        %{
          state
          | window_id: drift_window.id,
            snapshot_id: snapshot_id,
            window_start: window_start,
            window_timer: timer,
            comparisons: []
        }

      {:error, reason} ->
        Logger.error("[UPM.DriftMonitor] Failed to create drift window: #{inspect(reason)}")
        state
    end
  end

  defp create_drift_window(trainer_id, snapshot_id, threshold) do
    %{
      trainer_id: trainer_id,
      snapshot_id: snapshot_id,
      threshold: threshold,
      score_p95: 0.0,
      sample_count: 0,
      metadata: %{started_at: DateTime.utc_now() |> DateTime.to_iso8601()}
    }
    |> UpmDriftWindow.open()
    |> Ash.create()
  end

  defp get_current_snapshot_id(trainer) do
    # Get latest shadow snapshot for this trainer
    case Ash.read(UpmSnapshot,
           filter: [trainer_id: trainer.id, status: :shadow],
           limit: 1,
           sort: [version: :desc]
         ) do
      {:ok, [snapshot]} -> snapshot.id
      {:ok, []} -> nil
      {:error, _} -> nil
    end
  end

  defp evaluate_window(state) do
    if length(state.comparisons) < state.sample_size do
      Logger.warn("""
      [UPM.DriftMonitor] Insufficient samples for evaluation
        expected: #{state.sample_size}
        actual: #{length(state.comparisons)}
      """)

      {:ok, :insufficient_samples}
    else
      stats = calculate_drift_stats(state.comparisons)

      # Update drift window resource
      case update_drift_window(state.window_id, stats, length(state.comparisons)) do
        {:ok, drift_window} ->
          # Emit telemetry
          emit_drift_telemetry(state.trainer_id, stats)

          # Check quarantine threshold
          if stats.p95 >= state.drift_threshold and state.quarantine_enabled do
            trigger_quarantine(drift_window, stats)
          end

          {:ok, %{drift_window: drift_window, stats: stats}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp calculate_drift(shadow_pred, ground_truth)
       when is_number(shadow_pred) and is_number(ground_truth) do
    abs(shadow_pred - ground_truth)
  end

  defp calculate_drift(shadow_pred, ground_truth)
       when is_map(shadow_pred) and is_map(ground_truth) do
    # For structured predictions, calculate normalized distance
    # Simple implementation: count mismatched keys
    all_keys = MapSet.union(MapSet.new(Map.keys(shadow_pred)), MapSet.new(Map.keys(ground_truth)))
    total_keys = MapSet.size(all_keys)

    mismatches =
      Enum.count(all_keys, fn key ->
        Map.get(shadow_pred, key) != Map.get(ground_truth, key)
      end)

    if total_keys > 0, do: mismatches / total_keys, else: 0.0
  end

  defp calculate_drift(shadow_pred, ground_truth) do
    # Fallback: binary match
    if shadow_pred == ground_truth, do: 0.0, else: 1.0
  end

  defp calculate_drift_stats([]), do: %{p95: 0.0, mean: 0.0, max: 0.0}

  defp calculate_drift_stats(comparisons) do
    scores = Enum.map(comparisons, & &1.drift_score) |> Enum.sort()

    p95_index = floor(length(scores) * 0.95)
    p95 = Enum.at(scores, p95_index, 0.0)

    mean = Enum.sum(scores) / length(scores)
    max_val = List.last(scores)

    %{p95: p95, mean: mean, max: max_val}
  end

  defp update_drift_window(window_id, stats, sample_count) do
    %{
      score_p95: stats.p95,
      sample_count: sample_count,
      metadata: %{
        mean: stats.mean,
        max: stats.max,
        evaluated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
    |> then(&UpmDriftWindow.resolve(window_id, &1))
    |> Ash.update()
  end

  defp trigger_quarantine(drift_window, stats) do
    Logger.warn("""
    [UPM.DriftMonitor] QUARANTINE TRIGGERED
      window_id: #{drift_window.id}
      trainer_id: #{drift_window.trainer_id}
      p95_drift: #{stats.p95}
      threshold: #{drift_window.threshold}
    """)

    # Update window to quarantined status
    case UpmDriftWindow.quarantine(drift_window.id) |> Ash.update() do
      {:ok, _} ->
        # Emit quarantine telemetry
        :telemetry.execute(
          [:upm, :drift, :quarantine],
          %{p95_score: stats.p95, threshold: drift_window.threshold},
          %{trainer_id: drift_window.trainer_id, window_id: drift_window.id}
        )

        # Publish quarantine event
        EventBus.publish_event(%{
          name: "ai.upm.drift.quarantine",
          source: :bolt,
          payload: %{
            trainer_id: drift_window.trainer_id,
            snapshot_id: drift_window.snapshot_id,
            window_id: drift_window.id,
            drift_p95: stats.p95,
            threshold: drift_window.threshold,
            recommendation: "rollback"
          },
          correlation_id: UUID.v7()
        })

      {:error, reason} ->
        Logger.error("[UPM.DriftMonitor] Failed to quarantine window: #{inspect(reason)}")
    end
  end

  defp emit_shadow_delta_event(trainer_id, comparison) do
    EventBus.publish_event(%{
      name: "ai.upm.shadow_delta",
      source: :bolt,
      payload: %{
        trainer_id: trainer_id,
        drift_score: comparison.drift_score,
        timestamp: DateTime.to_iso8601(comparison.timestamp)
      },
      correlation_id: UUID.v7()
    })
  end

  defp emit_drift_telemetry(trainer_id, stats) do
    :telemetry.execute(
      [:upm, :drift, :score],
      %{p95: stats.p95, mean: stats.mean, max: stats.max},
      %{trainer_id: trainer_id}
    )
  end
end
