defmodule Thunderline.ML.Cerebros.Telemetry do
  @moduledoc """
  Telemetry helpers for Cerebros integration inside Thunderline.

  Events:
    [:cerebros, :trial, :completed]
      measurements: %{metric: float(), params: non_neg_integer()}
      metadata: %{spec: map(), id: term()}

    [:cerebros, :search, :completed]
      measurements: %{best_metric: float(), trials: non_neg_integer()}
      metadata: %{dataset: term(), task: term(), best_spec: map(), artifact: term()}

  Call `attach_logger/0` in dev/test to log events. Safe to call multiple times.
  """
  require Logger

  @trial_event [:cerebros, :trial, :completed]
  @search_event [:cerebros, :search, :completed]

  def emit_trial_completed(%{metric: metric, params: params, spec: spec, id: id}) do
    :telemetry.execute(@trial_event, %{metric: metric, params: params}, %{spec: spec, id: id})
  end

  def emit_search_completed(%{best_metric: best_metric, trials: trials, dataset: dataset, task: task, best_spec: best_spec, artifact: artifact}) do
    :telemetry.execute(@search_event, %{best_metric: best_metric, trials: trials}, %{dataset: dataset, task: task, best_spec: best_spec, artifact: artifact})
  end

  def attach_logger do
    attach(@trial_event, &log_trial/4)
    attach(@search_event, &log_search/4)
    :ok
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

  defp log_trial(_event, meas, meta, _cfg) do
    Logger.info("[Cerebros][trial] metric=#{meas.metric} params=#{meas.params} id=#{meta.id}")
  end

  defp log_search(_event, meas, meta, _cfg) do
    Logger.info("[Cerebros][search] best=#{meas.best_metric} trials=#{meas.trials} artifact=#{meta.artifact}")
  end
end
