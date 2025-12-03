defmodule Thunderline.Thunderflow.Telemetry do
  @moduledoc """
  Telemetry helpers for Thunderflow subsystems.

  Provides instrumentation for:
  - NLP processing metrics
  - Event pipeline statistics
  - Broadway message throughput
  - Domain routing telemetry

  ## Telemetry Events

  ### NLP Events
  - `[:thunderline, :nlp, :analyze, :complete]` - Successful analysis
  - `[:thunderline, :nlp, :analyze, :error]` - Failed analysis

  ### Pipeline Events
  - `[:thunderline, :pipeline, :process, :start]`
  - `[:thunderline, :pipeline, :process, :stop]`
  - `[:thunderline, :pipeline, :process, :exception]`
  """

  @nlp_ns [:thunderline, :nlp, :analyze]
  @pipeline_ns [:thunderline, :pipeline, :process]

  # ============================================================================
  # NLP Telemetry
  # ============================================================================

  @doc """
  Emit telemetry for completed NLP analysis.

  ## Parameters
  - `duration_us` - Processing duration in microseconds
  - `metadata` - Map containing analysis details (lang, entity_count, token_count, text_length)
  """
  @spec nlp_analyze_complete(non_neg_integer(), map()) :: :ok
  def nlp_analyze_complete(duration_us, metadata \\ %{}) when is_integer(duration_us) do
    :telemetry.execute(
      @nlp_ns ++ [:complete],
      %{duration: duration_us, count: 1},
      metadata
    )
  end

  @doc """
  Emit telemetry for failed NLP analysis.

  ## Parameters
  - `duration_us` - Processing duration in microseconds before failure
  - `metadata` - Map containing error details (lang, error_type)
  """
  @spec nlp_analyze_error(non_neg_integer(), map()) :: :ok
  def nlp_analyze_error(duration_us, metadata \\ %{}) when is_integer(duration_us) do
    :telemetry.execute(
      @nlp_ns ++ [:error],
      %{duration: duration_us, count: 1},
      metadata
    )
  end

  # ============================================================================
  # Pipeline Telemetry
  # ============================================================================

  @doc """
  Emit telemetry for pipeline processing start.
  """
  @spec pipeline_start(atom(), map()) :: :ok
  def pipeline_start(pipeline, metadata \\ %{}) do
    :telemetry.execute(
      @pipeline_ns ++ [:start],
      %{count: 1},
      Map.put(metadata, :pipeline, pipeline)
    )
  end

  @doc """
  Emit telemetry for pipeline processing completion.
  """
  @spec pipeline_stop(atom(), non_neg_integer(), map()) :: :ok
  def pipeline_stop(pipeline, duration_us, metadata \\ %{}) do
    :telemetry.execute(
      @pipeline_ns ++ [:stop],
      %{duration: duration_us, count: 1},
      Map.put(metadata, :pipeline, pipeline)
    )
  end

  @doc """
  Emit telemetry for pipeline processing exception.
  """
  @spec pipeline_exception(atom(), term(), map()) :: :ok
  def pipeline_exception(pipeline, error, metadata \\ %{}) do
    :telemetry.execute(
      @pipeline_ns ++ [:exception],
      %{count: 1},
      Map.merge(metadata, %{pipeline: pipeline, error: error})
    )
  end
end
