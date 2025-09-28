defmodule Thunderline.Thunderbolt.Cerebros.Telemetry do
  @moduledoc "Telemetry helpers for Thunderbolt Cerebros integration."
  require Logger

  @namespace [:thunderline, :thunderbolt, :cerebros]

  @run_events %{
    queued: @namespace ++ [:run, :queued],
    started: @namespace ++ [:run, :started],
    stopped: @namespace ++ [:run, :stopped],
    failed: @namespace ++ [:run, :failed]
  }

  @trial_events %{
    started: @namespace ++ [:trial, :started],
    stopped: @namespace ++ [:trial, :stopped],
    exception: @namespace ++ [:trial, :exception],
    completed: @namespace ++ [:trial, :completed]
  }

  @search_event @namespace ++ [:search, :completed]

  def metrics_namespace, do: @namespace

  # -------------------------------------------------------------------------
  # Run lifecycle helpers
  # -------------------------------------------------------------------------

  def emit_run_queued(attrs) when is_map(attrs) do
    measurements = %{queue_time_ms: Map.get(attrs, :queue_time_ms, 0)}

    metadata =
      attrs
      |> Map.take([:run_id, :priority, :queue, :attempts, :component])
      |> Map.put_new(:component, "run_worker")

    execute(@run_events.queued, measurements, metadata)
  end

  def emit_run_started(attrs) when is_map(attrs) do
    measurements = %{t0_mono: Map.get(attrs, :t0_mono, System.monotonic_time())}

    metadata =
      attrs
      |> Map.take([:run_id, :model, :dataset, :budget, :attempts, :component, :correlation_id])
      |> Map.put_new(:component, "run_worker")

    execute(@run_events.started, measurements, metadata)
  end

  def emit_run_stopped(attrs) when is_map(attrs) do
    measurements =
      %{
        duration_ms: Map.get(attrs, :duration_ms, 0),
        best_metric: Map.get(attrs, :best_metric),
        trials: Map.get(attrs, :trials)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    metadata =
      attrs
      |> Map.take([:run_id, :best_trial_id, :artifact_id, :status, :component, :correlation_id])
      |> Map.put_new(:status, :ok)
      |> Map.put_new(:component, "run_worker")

    execute(@run_events.stopped, measurements, metadata)
  end

  def emit_run_failed(attrs) when is_map(attrs) do
    measurements = %{duration_ms: Map.get(attrs, :duration_ms, 0)}

    metadata =
      attrs
      |> Map.take([:run_id, :class, :reason, :component, :correlation_id])
      |> Map.put_new(:component, "run_worker")

    execute(@run_events.failed, measurements, metadata)
  end

  # -------------------------------------------------------------------------
  # Trial lifecycle helpers
  # -------------------------------------------------------------------------

  def emit_trial_started(attrs) when is_map(attrs) do
    measurements = %{t0_mono: Map.get(attrs, :t0_mono, System.monotonic_time())}

    metadata =
      attrs
      |> Map.take([:run_id, :trial_id, :spec_hash, :component, :correlation_id])
      |> Map.put_new(:component, "run_worker")

    execute(@trial_events.started, measurements, metadata)
  end

  def emit_trial_stopped(attrs) when is_map(attrs) do
    measurements =
      %{
        duration_ms: Map.get(attrs, :duration_ms, 0),
        metric: Map.get(attrs, :metric),
        val_loss: Map.get(attrs, :val_loss)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    metadata =
      attrs
      |> Map.take([:run_id, :trial_id, :spec_hash, :status, :component, :correlation_id])
      |> Map.put_new(:status, :ok)
      |> Map.put_new(:component, "run_worker")

    execute(@trial_events.stopped, measurements, metadata)
  end

  def emit_trial_exception(attrs) when is_map(attrs) do
    measurements = %{duration_ms: Map.get(attrs, :duration_ms, 0)}

    metadata =
      attrs
      |> Map.take([:run_id, :trial_id, :spec_hash, :class, :reason, :component, :correlation_id])
      |> Map.put_new(:component, "run_worker")

    execute(@trial_events.exception, measurements, metadata)
  end

  # Legacy helpers retained for compatibility --------------------------------

  def emit_trial_completed(%{metric: metric, params: params, spec: spec, id: id}) do
    :telemetry.execute(@trial_events.completed, %{metric: metric, params: params}, %{
      spec: spec,
      id: id
    })
  end

  def emit_search_completed(%{
        best_metric: best_metric,
        trials: trials,
        dataset: dataset,
        task: task,
        best_spec: best_spec,
        artifact: artifact
      }) do
    :telemetry.execute(@search_event, %{best_metric: best_metric, trials: trials}, %{
      dataset: dataset,
      task: task,
      best_spec: best_spec,
      artifact: artifact
    })
  end

  # -------------------------------------------------------------------------
  # Attachment helpers
  # -------------------------------------------------------------------------

  def attach_logger do
    attach(@trial_events.completed, &log_trial_completed/4)
    attach(@trial_events.started, &log_trial_started/4)
    attach(@trial_events.stopped, &log_trial_stopped/4)
    attach(@trial_events.exception, &log_trial_exception/4)
    attach(@run_events.started, &log_run_started/4)
    attach(@run_events.stopped, &log_run_stopped/4)
    attach(@run_events.failed, &log_run_failed/4)
    attach(@run_events.queued, &log_run_queued/4)
    attach(@search_event, &log_search/4)
    :ok
  end

  defp execute(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    _ -> :ok
  end

  defp attach(event, fun) do
    handler_id = {:cerebros_logger, event}

    case :telemetry.attach(handler_id, event, fun, %{}) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp log_trial_completed(_event, meas, meta, _cfg) do
    Logger.info("[Cerebros][trial.completed] metric=#{inspect(meas.metric)} id=#{meta.id}")
  end

  defp log_trial_started(_event, _meas, meta, _cfg) do
    Logger.info("[Cerebros][trial.started] run=#{meta.run_id} trial=#{meta.trial_id}")
  end

  defp log_trial_stopped(_event, meas, meta, _cfg) do
    Logger.info(
      "[Cerebros][trial.stopped] run=#{meta.run_id} trial=#{meta.trial_id} metric=#{inspect(meas.metric)} duration=#{inspect(meas.duration_ms)}"
    )
  end

  defp log_trial_exception(_event, _meas, meta, _cfg) do
    Logger.error(
      "[Cerebros][trial.exception] run=#{meta.run_id} trial=#{meta.trial_id} class=#{meta.class} reason=#{meta.reason}"
    )
  end

  defp log_run_started(_event, _meas, meta, _cfg) do
    Logger.info(
      "[Cerebros][run.started] run=#{meta.run_id} model=#{meta.model} dataset=#{meta.dataset} attempts=#{meta.attempts}"
    )
  end

  defp log_run_stopped(_event, meas, meta, _cfg) do
    Logger.info(
      "[Cerebros][run.stopped] run=#{meta.run_id} best_metric=#{inspect(meas.best_metric)} trials=#{inspect(meas.trials)}"
    )
  end

  defp log_run_failed(_event, _meas, meta, _cfg) do
    Logger.error(
      "[Cerebros][run.failed] run=#{meta.run_id} class=#{meta.class} reason=#{meta.reason}"
    )
  end

  defp log_run_queued(_event, meas, meta, _cfg) do
    Logger.debug(
      "[Cerebros][run.queued] run=#{meta.run_id} queue=#{meta.queue} priority=#{meta.priority} queue_time=#{inspect(meas.queue_time_ms)}"
    )
  end

  defp log_search(_event, meas, meta, _cfg) do
    Logger.info(
      "[Cerebros][search.completed] best=#{meas.best_metric} trials=#{meas.trials} artifact=#{meta.artifact}"
    )
  end
end
