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
    delay = Thunderline.Support.Backoff.exp(attempt)
    
    # Emit retry telemetry  
    JobTelemetry.emit_job_retry(:realtime, __MODULE__, attempt)
    
    delay
  end
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event}} = job) do
    start_time = System.monotonic_time()
    
    try do
      # Process event through gated interface
      case Ash.run!(Thunderline.Integrations.EventOps, :process_event, %{event: event}) do
        {:ok, result} ->
          # Record success telemetry
          duration = System.monotonic_time() - start_time
          JobTelemetry.emit_job_success(:realtime, __MODULE__, duration)
          JobTelemetry.emit_event_processed("job_worker", event["type"] || "unknown")
          
          {:ok, result}
          
        {:error, reason} ->
          # Classify error and record telemetry
          {error_kind, error_tag} = Thunderline.Support.ErrorKinds.classify(reason)
          JobTelemetry.emit_job_failure(:realtime, __MODULE__, error_tag)
          JobTelemetry.emit_event_failed("job_worker", error_tag)
          
          # Decide whether to retry or discard based on error classification
          case error_kind do
            :permanent -> {:discard, reason}
            :transient -> {:error, reason}
            :unknown -> {:error, reason}  # Err on the side of retrying
          end
      end
      
    rescue
      error ->
        # Classify exception and record telemetry
        {error_kind, error_tag} = Thunderline.Support.ErrorKinds.classify(error)
        JobTelemetry.emit_job_failure(:realtime, __MODULE__, error_tag)
        
        Logger.error("ProcessEvent job exception (#{error_kind}): #{inspect(error)}")
        reraise error, __STACKTRACE__
    end
  end
  
  # Handle missing event argument
  def perform(%Oban.Job{args: args} = job) do
    Logger.warning("ProcessEvent job missing event argument: #{inspect(args)}")
    JobTelemetry.emit_job_failure(:realtime, __MODULE__, :missing_event)
    {:discard, :missing_event}
  end
  
end