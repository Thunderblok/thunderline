defmodule Thunderline.Thunderflow.Telemetry.Jobs do
  @moduledoc """
  ThunderFlow telemetry metrics for job processing, event handling, and cross-domain operations.
  
  Provides observability into retry rates, failure patterns, and latency distribution
  to identify performance bottlenecks and reliability issues.
  """
  
  import Telemetry.Metrics
  
  @doc """
  Returns telemetry metrics for job and event processing.
  
  Add these to your telemetry supervisor to collect operational metrics.
  """
  def metrics do
    [
      # Job processing metrics
      counter("thunderline.jobs.retries",
        description: "Number of job retries by queue and worker",
        tags: [:queue, :worker]
      ),
      
      counter("thunderline.jobs.failures", 
        description: "Number of job failures by queue, worker, and error type",
        tags: [:queue, :worker, :error_type]
      ),
      
      counter("thunderline.jobs.successes",
        description: "Number of successful job completions",
        tags: [:queue, :worker]
      ),
      
      summary("thunderline.jobs.duration",
        description: "Job execution duration by queue and worker",
        unit: {:native, :millisecond},
        tags: [:queue, :worker]
      ),
      
      # Event processing metrics  
      counter("thunderline.events.processed",
        description: "Number of events processed by source",
        tags: [:source, :event_type]
      ),
      
      counter("thunderline.events.failed",
        description: "Number of events that failed processing",
        tags: [:source, :error_type]
      ),
      
      summary("thunderline.event_processor.emit",
        description: "Event emission latency for parallel processing",
        unit: {:native, :millisecond},
        tags: [:source_domain, :target_domain]
      ),
      
      # Cross-domain operation metrics
      summary("thunderline.cross_domain.latency",
        description: "End-to-end latency for cross-domain operations",
        unit: {:native, :millisecond}, 
        tags: [:source_domain, :target_domain]
      ),
      
      counter("thunderline.cross_domain.routing_failures",
        description: "Number of cross-domain routing failures",
        tags: [:source_domain, :target_domain, :error_type]
      ),
      
      # Broadway pipeline metrics
      summary("thunderline.broadway.batch_size",
        description: "Size of batches processed by Broadway pipelines",
        tags: [:pipeline, :batcher]
      ),
      
      summary("thunderline.broadway.processing_time",
        description: "Time spent processing Broadway batches",
        unit: {:native, :millisecond},
        tags: [:pipeline, :batcher]
      ),
      
      # Circuit breaker metrics
      counter("thunderline.circuit_breaker.state_changes",
        description: "Circuit breaker state transitions",
        tags: [:service, :from_state, :to_state]
      ),
      
      counter("thunderline.circuit_breaker.calls",
        description: "Circuit breaker call attempts",
        tags: [:service, :result]
      )
    ]
  end
  
  @doc """
  Emit telemetry for job retry events.
  
  Call this when a job is being retried.
  """
  def emit_job_retry(queue, worker, attempt \\ 1) do
    :telemetry.execute(
      [:thunderline, :jobs, :retries],
      %{count: 1},
      %{queue: to_string(queue), worker: to_string(worker), attempt: attempt}
    )
  end
  
  @doc """
  Emit telemetry for job failure events.
  
  Call this when a job fails with error classification.
  """
  def emit_job_failure(queue, worker, error_type) do
    :telemetry.execute(
      [:thunderline, :jobs, :failures],
      %{count: 1},
      %{queue: to_string(queue), worker: to_string(worker), error_type: to_string(error_type)}
    )
  end
  
  @doc """
  Emit telemetry for successful job completion.
  """
  def emit_job_success(queue, worker, duration_native \\ nil) do
    measurements = %{count: 1}
    measurements = if duration_native, do: Map.put(measurements, :duration, duration_native), else: measurements
    
    :telemetry.execute(
      [:thunderline, :jobs, :successes],
      measurements,
      %{queue: to_string(queue), worker: to_string(worker)}
    )
  end
  
  @doc """
  Emit telemetry for event processing.
  """
  def emit_event_processed(source, event_type) do
    :telemetry.execute(
      [:thunderline, :events, :processed],
      %{count: 1},
      %{source: to_string(source), event_type: to_string(event_type)}
    )
  end
  
  @doc """
  Emit telemetry for event processing failures.
  """
  def emit_event_failed(source, error_type) do
    :telemetry.execute(
      [:thunderline, :events, :failed],
      %{count: 1},
      %{source: to_string(source), error_type: to_string(error_type)}
    )
  end
  
  @doc """
  Emit telemetry for cross-domain operation latency.
  """
  def emit_cross_domain_latency(source_domain, target_domain, duration_native) do
    :telemetry.execute(
      [:thunderline, :cross_domain, :latency],
      %{duration: duration_native},
      %{source_domain: to_string(source_domain), target_domain: to_string(target_domain)}
    )
  end
  
  @doc """
  Emit telemetry for cross-domain routing failures.
  """
  def emit_routing_failure(source_domain, target_domain, error_type) do
    :telemetry.execute(
      [:thunderline, :cross_domain, :routing_failures],
      %{count: 1},
      %{
        source_domain: to_string(source_domain),
        target_domain: to_string(target_domain),
        error_type: to_string(error_type)
      }
    )
  end
  
  @doc """
  Emit telemetry for circuit breaker state changes.
  """
  def emit_circuit_breaker_state_change(service_key, from_state, to_state) do
    :telemetry.execute(
      [:thunderline, :circuit_breaker, :state_changes],
      %{count: 1},
      %{
        service: to_string(service_key),
        from_state: to_string(from_state),
        to_state: to_string(to_state)
      }
    )
  end
  
  @doc """
  Emit telemetry for circuit breaker call attempts.
  """
  def emit_circuit_breaker_call(service_key, result) do
    :telemetry.execute(
      [:thunderline, :circuit_breaker, :calls],
      %{count: 1},
      %{
        service: to_string(service_key),
        result: to_string(result)
      }
    )
  end
end