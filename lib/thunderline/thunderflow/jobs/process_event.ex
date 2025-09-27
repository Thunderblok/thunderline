defmodule Thunderline.Thunderflow.Jobs.ProcessEvent do
  @moduledoc """
  Oban worker for processing events through the gated EventOps interface.

  Uses exponential backoff with jitter and comprehensive telemetry.
  Routes to either simple EventProcessor or Reactor based on TL_ENABLE_REACTOR.
  """

  use Oban.Worker, queue: :realtime, max_attempts: 5

  require Logger
  alias Thunderline.Thunderflow.Telemetry.Jobs, as: JobTelemetry

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    delay = Thunderline.Thunderflow.Support.Backoff.exp(attempt)

    # Emit retry telemetry
    JobTelemetry.emit_job_retry(:realtime, __MODULE__, attempt)

    delay
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event}} = _job) do
    start_time = System.monotonic_time()

    try do
      # Process event through gated interface
      case Thunderline.Thunderflow.Resources.EventOps.process_event!(%{event: event}) do
        %{status: :processed} = result ->
          duration = System.monotonic_time() - start_time
          JobTelemetry.emit_job_success(:realtime, __MODULE__, duration)
          JobTelemetry.emit_event_processed("job_worker", event["type"] || "unknown")
          {:ok, result}

        %{status: :error, reason: reason} ->
          {error_kind, error_tag} = Thunderline.Thunderflow.Support.ErrorKinds.classify(reason)
          JobTelemetry.emit_job_failure(:realtime, __MODULE__, error_tag)
          JobTelemetry.emit_event_failed("job_worker", error_tag)

          case error_kind do
            :permanent -> {:discard, reason}
            _ -> {:error, reason}
          end

        other ->
          # Unexpected shape, treat as ok to avoid infinite retries but log
          Logger.warning("Unexpected EventOps result shape: #{inspect(other)}")
          {:ok, other}
      end
    rescue
      error ->
        # Classify exception and record telemetry
        {error_kind, error_tag} = Thunderline.Thunderflow.Support.ErrorKinds.classify(error)
        JobTelemetry.emit_job_failure(:realtime, __MODULE__, error_tag)

        Logger.error("ProcessEvent job exception (#{error_kind}): #{inspect(error)}")
        reraise error, __STACKTRACE__
    end
  end

  # Handle missing event argument
  def perform(%Oban.Job{args: args} = _job) do
    Logger.warning("ProcessEvent job missing event argument: #{inspect(args)}")
    JobTelemetry.emit_job_failure(:realtime, __MODULE__, :missing_event)
    {:discard, :missing_event}
  end
end
