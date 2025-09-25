defmodule Thunderline.Thunderflow.Flow.Telemetry do
  @moduledoc """
  Telemetry helpers and metric definitions for Event DAG stages.

  Namespaces:
  - [:thunderline, :flow, :stage, :start]
  - [:thunderline, :flow, :stage, :stop]
  - [:thunderline, :flow, :stage, :exception]
  - [:thunderline, :flow, :stage, :retry]
  - [:thunderline, :flow, :stage, :dlq]
  """
  @ns [:thunderline, :flow, :stage]
  def start(stage, meta \\ %{}) do
    :telemetry.execute(@ns ++ [:start], %{count: 1}, Map.put(meta, :stage, stage))
  end
  def stop(stage, duration_us, meta \\ %{}) do
    :telemetry.execute(@ns ++ [:stop], %{duration: duration_us}, Map.put(meta, :stage, stage))
  end
  def exception(stage, error, meta \\ %{}) do
    :telemetry.execute(@ns ++ [:exception], %{count: 1}, Map.merge(meta, %{stage: stage, error: error}))
  end
  def retry(stage, meta \\ %{}) do
    :telemetry.execute(@ns ++ [:retry], %{count: 1}, Map.put(meta, :stage, stage))
  end
  def dlq(stage, meta \\ %{}) do
    :telemetry.execute(@ns ++ [:dlq], %{count: 1}, Map.put(meta, :stage, stage))
  end
end
