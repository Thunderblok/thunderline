defmodule Thunderline.Thunderflow.Domain do
  @moduledoc """
  ThunderFlow Ash Domain - Event Processing & Telemetry

  **Boundary**: "If it's a stream, it's Flow" - Events, consciousness streams, telemetry flows

  Core responsibilities:
  - Event stream processing and consciousness flows
  - Real-time event telemetry and metrics
  - Event routing and processing pipelines
  - Consciousness flow management

  ## Broadway Pipeline Architecture

  Thunderflow uses Broadway for structured event processing:

  - **EventPipeline**: General domain event processing with batching
  - **CrossDomainPipeline**: Inter-domain communication and routing
  - **RealTimePipeline**: Low-latency processing for live updates
  - **EventProducer**: Captures PubSub events for pipeline processing

  This provides:
  - Automatic batching and backpressure handling
  - Dead letter queues for failed events
  - Structured error recovery and retries
  - Event flow monitoring and processing
  """

  use Ash.Domain

  resources do
    # Original ThunderFlow resources
    resource Thunderline.Thunderflow.Resources.ConsciousnessFlow
    resource Thunderline.Thunderflow.Resources.EventStream
    resource Thunderline.Thunderflow.Resources.SystemAction
    # Event logging resource
    resource Thunderline.Thunderflow.Events.Event
  # Probe & drift resources (integrated from Raincatcher)
  resource Thunderline.Thunderflow.Resources.ProbeRun
  resource Thunderline.Thunderflow.Resources.ProbeLap
  resource Thunderline.Thunderflow.Resources.ProbeAttractorSummary
  # Phase 0 Market/EDGAR + Feature/Lineage resources
  resource Thunderline.Markets.RawTick
  resource Thunderline.Filings.EDGARDoc
  resource Thunderline.Features.FeatureWindow
  resource Thunderline.Lineage.Edge
  end

  @doc """
  Start all Broadway pipelines for event processing
  """
  def start_broadway_pipelines do
    children = [
      Thunderline.Thunderflow.EventProducer,
      Thunderline.Thunderflow.Pipelines.EventPipeline,
      Thunderline.Thunderflow.Pipelines.CrossDomainPipeline,
      Thunderline.Thunderflow.Pipelines.RealTimePipeline
    ]

    # These would typically be started in the application supervision tree
    # but can be started manually for testing
    Enum.each(children, fn child ->
      case child.start_link([]) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        error ->
          require Logger
          Logger.error("Failed to start #{inspect(child)}: #{inspect(error)}")
      end
    end)
  end

  @doc """
  Send event to appropriate Broadway pipeline based on event type
  """
  def process_event(event_type, event_data, opts \\ []) do
    pipeline_hint = Keyword.get(opts, :pipeline, :auto)

    broadway_event = %{
      "event_type" => to_string(event_type),
      "data" => event_data,
      "timestamp" => DateTime.utc_now(),
      "source" => Keyword.get(opts, :source, "manual"),
      "pipeline_hint" => determine_pipeline(pipeline_hint, event_type)
    }

    case broadway_event["pipeline_hint"] do
      "realtime" ->
        GenStage.call(
          Thunderline.Thunderflow.Pipelines.RealTimePipeline,
          {:send_event, broadway_event}
        )

      "cross_domain" ->
        GenStage.call(
          Thunderline.Thunderflow.Pipelines.CrossDomainPipeline,
          {:send_event, broadway_event}
        )

      _ ->
        GenStage.call(
          Thunderline.Thunderflow.Pipelines.EventPipeline,
          {:send_event, broadway_event}
        )
    end
  end

  defp determine_pipeline(:auto, event_type) do
    cond do
      event_type in [:agent_updated, :system_metrics, :dashboard_update] -> "realtime"
      event_type in [:cross_domain_message, :domain_routing] -> "cross_domain"
      true -> "event"
    end
  end

  defp determine_pipeline(pipeline, _event_type), do: to_string(pipeline)
end
