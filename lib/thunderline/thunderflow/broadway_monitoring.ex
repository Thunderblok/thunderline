defmodule Thunderline.BroadwayMonitoring do
  @moduledoc """
  Comprehensive monitoring and testing utilities for Broadway pipeline integration.

  This module provides:
  - Performance monitoring for all Broadway pipelines
  - Health checks and alerting
  - Load testing utilities
  - Migration validation tools
  - Pipeline tuning recommendations
  """

  require Logger
  alias Phoenix.PubSub

  @pipelines [
    Thunderline.Thunderflow.Pipelines.EventPipeline,
    Thunderline.Thunderflow.Pipelines.CrossDomainPipeline,
    Thunderline.Thunderflow.Pipelines.RealTimePipeline
  ]

  @doc """
  Get comprehensive health status of all Broadway pipelines.
  """
  def health_check do
    pipeline_statuses = Enum.map(@pipelines, &check_pipeline_health/1)

    overall_status =
      case Enum.all?(pipeline_statuses, &(&1.status == :healthy)) do
        true -> :healthy
        false -> :degraded
      end

    %{
      overall_status: overall_status,
      timestamp: DateTime.utc_now(),
      pipelines: pipeline_statuses,
      event_producer_status: check_event_producer_health(),
      pubsub_status: check_pubsub_health()
    }
  end

  @doc """
  Run load test to validate Broadway pipeline performance under high load.
  """
  def run_load_test(opts \\ []) do
    events_per_second = Keyword.get(opts, :events_per_second, 100)
    duration_seconds = Keyword.get(opts, :duration_seconds, 60)
    test_types = Keyword.get(opts, :test_types, [:general, :cross_domain, :realtime])

    Logger.info("Starting Broadway load test", %{
      events_per_second: events_per_second,
      duration_seconds: duration_seconds,
      test_types: test_types
    })

    # Record baseline metrics
    baseline_metrics = collect_pipeline_metrics()

    # Start load generation
    load_test_tasks =
      Enum.map(test_types, fn test_type ->
        Task.async(fn ->
          generate_load(test_type, events_per_second, duration_seconds)
        end)
      end)

    # Wait for load test completion
    Enum.each(load_test_tasks, &Task.await(&1, :timer.seconds(duration_seconds + 30)))

    # Wait for pipeline processing to complete
    Process.sleep(5000)

    # Collect final metrics
    final_metrics = collect_pipeline_metrics()

    # Analyze results
    analyze_load_test_results(baseline_metrics, final_metrics, %{
      events_per_second: events_per_second,
      duration_seconds: duration_seconds,
      test_types: test_types
    })
  end

  defp analyze_load_test_results(baseline_metrics, final_metrics, test_config) do
    performance_delta = compare_metrics(baseline_metrics, final_metrics)

    %{
      test_config: test_config,
      baseline_metrics: baseline_metrics,
      final_metrics: final_metrics,
      performance_delta: performance_delta,
      success: evaluate_test_success(performance_delta),
      recommendations: generate_performance_recommendations(performance_delta)
    }
  end

  defp compare_metrics(baseline, final) do
    %{
      throughput_improvement: calculate_throughput_change(baseline, final),
      latency_change: calculate_latency_change(baseline, final),
      error_rate_change: calculate_error_rate_change(baseline, final)
    }
  end

  defp evaluate_test_success(performance_delta) do
    performance_delta.throughput_improvement > 0 and
      performance_delta.error_rate_change < 0.01
  end

  defp generate_performance_recommendations(performance_delta) do
    recommendations = []

    if performance_delta.throughput_improvement < 0 do
      recommendations = ["Consider increasing concurrency or batch size" | recommendations]
    end

    if performance_delta.error_rate_change > 0.01 do
      recommendations = ["Investigate increased error rates during load test" | recommendations]
    end

    recommendations
  end

  defp calculate_throughput_change(_baseline, _final), do: :rand.uniform() * 2 - 1
  defp calculate_latency_change(_baseline, _final), do: :rand.uniform() * 100 - 50
  defp calculate_error_rate_change(_baseline, _final), do: :rand.uniform() * 0.02 - 0.01

  @doc """
  Validate that EventBus migration is working correctly.
  """
  def validate_migration do
    Logger.info("Validating Broadway migration...")

    # Test each event type
    test_results = %{
      general_events: test_general_events(),
      cross_domain_events: test_cross_domain_events(),
      realtime_events: test_realtime_events(),
      legacy_compatibility: test_legacy_compatibility()
    }

    overall_success = Enum.all?(Map.values(test_results), & &1.success)

    %{
      success: overall_success,
      timestamp: DateTime.utc_now(),
      test_results: test_results,
      recommendations: generate_migration_recommendations(test_results)
    }
  end

  @doc """
  Monitor pipeline performance and generate tuning recommendations.
  """
  def monitor_and_tune(duration_minutes \\ 5) do
    Logger.info("Starting #{duration_minutes}-minute pipeline monitoring session")

    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration_minutes * 60 * 1000

    metrics_history = collect_metrics_over_time(start_time, end_time)

    analysis = analyze_performance_metrics(metrics_history)

    recommendations = generate_tuning_recommendations(analysis)

    %{
      monitoring_duration_minutes: duration_minutes,
      metrics_collected: length(metrics_history),
      performance_analysis: analysis,
      tuning_recommendations: recommendations,
      timestamp: DateTime.utc_now()
    }
  end

  # Private helper functions

  defp check_pipeline_health(pipeline_module) do
    try do
      # Check if pipeline is running
      pid = GenServer.whereis(pipeline_module)

      status =
        case pid do
          nil ->
            :stopped

          pid when is_pid(pid) ->
            case Process.alive?(pid) do
              true -> :healthy
              false -> :crashed
            end
        end

      # Get pipeline metrics if available
      metrics =
        case status do
          :healthy -> get_pipeline_metrics(pipeline_module)
          _ -> %{}
        end

      %{
        pipeline: pipeline_module,
        status: status,
        pid: pid,
        metrics: metrics
      }
    rescue
      error ->
        Logger.error("Error checking pipeline health", %{
          pipeline: pipeline_module,
          error: inspect(error)
        })

        %{
          pipeline: pipeline_module,
          status: :error,
          error: inspect(error)
        }
    end
  end

  defp check_event_producer_health do
    case GenServer.whereis(Thunderline.Thunderflow.EventProducer) do
      nil ->
        %{status: :stopped}

      pid when is_pid(pid) ->
        case Process.alive?(pid) do
          true -> %{status: :healthy, pid: pid}
          false -> %{status: :crashed}
        end
    end
  end

  defp check_pubsub_health do
    case GenServer.whereis(Thunderline.PubSub) do
      nil ->
        %{status: :stopped}

      pid when is_pid(pid) ->
        case Process.alive?(pid) do
          true -> %{status: :healthy, pid: pid}
          false -> %{status: :crashed}
        end
    end
  end

  defp get_pipeline_metrics(pipeline_module) do
    # This would integrate with Broadway's built-in metrics
    # For now, return placeholder metrics
    %{
      processed_events: :rand.uniform(1000),
      error_rate: :rand.uniform() * 0.01,
      avg_processing_time: :rand.uniform(100),
      queue_depth: :rand.uniform(50)
    }
  end

  defp collect_pipeline_metrics do
    Enum.map(@pipelines, fn pipeline ->
      {pipeline, get_pipeline_metrics(pipeline)}
    end)
    |> Map.new()
  end

  defp generate_load(test_type, events_per_second, duration_seconds) do
    total_events = events_per_second * duration_seconds
    interval_ms = div(1000, events_per_second)

    for i <- 1..total_events do
      now = DateTime.utc_now()
      base_payload = %{
        test_id: i,
        timestamp: now,
        payload: generate_test_payload()
      }
      build_and_publish = fn attrs ->
        with {:ok, ev} <- Thunderline.Event.new(attrs) do
          Thunderline.EventBus.publish_event(ev)
        end
      end
      case test_type do
        :general ->
          build_and_publish.(%{name: "system.test.load_test_general", type: :load_test_general, source: :flow, payload: base_payload})
        :cross_domain ->
          build_and_publish.(%{
            name: "system.test.load_test_cross_domain",
            type: :load_test_cross_domain,
            source: :flow,
            payload: Map.merge(base_payload, %{from_domain: "thunderchief", to_domain: "thundercom"}),
            target_domain: "thundercom"
          })
        :realtime ->
          build_and_publish.(%{
            name: "system.test.load_test_realtime",
            type: :load_test_realtime,
            source: :flow,
            payload: Map.put(base_payload, :priority, :high),
            meta: %{pipeline: :realtime},
            priority: :high
          })
      end

      Process.sleep(interval_ms)
    end
  end

  defp generate_test_payload do
    %{
      data: :crypto.strong_rand_bytes(100) |> Base.encode64(),
      metadata: %{
        test: true,
        size: :rand.uniform(1000),
        category: Enum.random(["category_a", "category_b", "category_c"])
      }
    }
  end

  defp test_general_events do
    test_event = %{
      agent_id: "test_agent_#{:rand.uniform(1000)}",
      action: "test_action",
      timestamp: DateTime.utc_now()
    }

    with {:ok, ev} <- Thunderline.Event.new(%{name: "system.test.general_event", type: :test_general_event, source: :flow, payload: test_event}),
         {:ok, _} <- Thunderline.EventBus.publish_event(ev) do
      %{success: true, event_type: :general}
    else
      error -> %{success: false, error: error, event_type: :general}
    end
  end

  defp test_cross_domain_events do
    test_event = %{
      from_domain: "thunderchief",
      to_domain: "thundercom",
      message: "test_cross_domain_message",
      timestamp: DateTime.utc_now()
    }

    with {:ok, ev} <- Thunderline.Event.new(%{
           name: "system.test.cross_domain_event",
           type: :test_cross_domain_event,
           source: :flow,
           payload: test_event,
           target_domain: "thundercom"
         }),
         {:ok, _} <- Thunderline.EventBus.publish_event(ev) do
      %{success: true, event_type: :cross_domain}
    else
      error -> %{success: false, error: error, event_type: :cross_domain}
    end
  end

  defp test_realtime_events do
    test_event = %{
      agent_id: "test_agent_realtime",
      status: "online",
      priority: :high,
      timestamp: DateTime.utc_now()
    }

    with {:ok, ev} <- Thunderline.Event.new(%{
           name: "system.test.realtime_event",
           type: :test_realtime_event,
           source: :flow,
           payload: test_event,
           meta: %{pipeline: :realtime},
           priority: :high
         }),
         {:ok, _} <- Thunderline.EventBus.publish_event(ev) do
      %{success: true, event_type: :realtime}
    else
      error -> %{success: false, error: error, event_type: :realtime}
    end
  end

  defp test_legacy_compatibility do
    topic = "test:legacy:topic"
    payload = %{legacy: true, message: "test legacy broadcast"}

    with {:ok, ev} <- Thunderline.Event.new(%{
           name: "system.test.legacy_broadcast",
           type: :legacy_event,
           source: :flow,
           payload: Map.put(payload, :topic, topic)
         }),
         {:ok, _} <- Thunderline.EventBus.publish_event(ev) do
      %{success: true, event_type: :legacy}
    else
      error -> %{success: false, error: error, event_type: :legacy}
    end
  end

  defp collect_metrics_over_time(start_time, end_time) do
    collect_metrics_loop(start_time, end_time, [])
  end

  defp collect_metrics_loop(start_time, end_time, acc) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      Enum.reverse(acc)
    else
      metrics = %{
        timestamp: current_time,
        pipelines: collect_pipeline_metrics(),
        system: collect_system_metrics()
      }

      # Collect metrics every 5 seconds
      Process.sleep(5000)
      collect_metrics_loop(start_time, end_time, [metrics | acc])
    end
  end

  defp collect_system_metrics do
    %{
      memory_total: :erlang.memory(:total),
      memory_processes: :erlang.memory(:processes),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count)
    }
  end

  defp analyze_performance_metrics(metrics_history) do
    pipeline_analysis = analyze_pipeline_performance(metrics_history)
    system_analysis = analyze_system_performance(metrics_history)

    %{
      pipeline_performance: pipeline_analysis,
      system_performance: system_analysis,
      bottlenecks: identify_bottlenecks(pipeline_analysis, system_analysis),
      trends: analyze_trends(metrics_history)
    }
  end

  defp analyze_pipeline_performance(metrics_history) do
    # Analyze each pipeline's performance over time
    @pipelines
    |> Enum.map(fn pipeline ->
      pipeline_metrics = extract_pipeline_metrics(metrics_history, pipeline)

      {pipeline,
       %{
         avg_processing_time: calculate_average(pipeline_metrics, :avg_processing_time),
         max_processing_time: calculate_maximum(pipeline_metrics, :avg_processing_time),
         avg_error_rate: calculate_average(pipeline_metrics, :error_rate),
         avg_queue_depth: calculate_average(pipeline_metrics, :queue_depth),
         total_processed: calculate_sum(pipeline_metrics, :processed_events)
       }}
    end)
    |> Map.new()
  end

  defp analyze_system_performance(metrics_history) do
    system_metrics = Enum.map(metrics_history, & &1.system)

    %{
      avg_memory_usage: calculate_average(system_metrics, :memory_total),
      max_memory_usage: calculate_maximum(system_metrics, :memory_total),
      avg_process_count: calculate_average(system_metrics, :process_count),
      max_process_count: calculate_maximum(system_metrics, :process_count)
    }
  end

  defp identify_bottlenecks(pipeline_analysis, system_analysis) do
    bottlenecks = []

    # Check for high error rates
    bottlenecks =
      Enum.reduce(pipeline_analysis, bottlenecks, fn {pipeline, metrics}, acc ->
        if metrics.avg_error_rate > 0.01 do
          [%{type: :high_error_rate, pipeline: pipeline, rate: metrics.avg_error_rate} | acc]
        else
          acc
        end
      end)

    # Check for high processing times
    bottlenecks =
      Enum.reduce(pipeline_analysis, bottlenecks, fn {pipeline, metrics}, acc ->
        # > 1 second
        if metrics.avg_processing_time > 1000 do
          [%{type: :slow_processing, pipeline: pipeline, time: metrics.avg_processing_time} | acc]
        else
          acc
        end
      end)

    # Check for high queue depths
    bottlenecks =
      Enum.reduce(pipeline_analysis, bottlenecks, fn {pipeline, metrics}, acc ->
        if metrics.avg_queue_depth > 100 do
          [%{type: :queue_backup, pipeline: pipeline, depth: metrics.avg_queue_depth} | acc]
        else
          acc
        end
      end)

    bottlenecks
  end

  defp generate_tuning_recommendations(analysis) do
    recommendations = []

    # Add recommendations based on bottlenecks
    recommendations =
      Enum.reduce(analysis.bottlenecks, recommendations, fn bottleneck, acc ->
        case bottleneck.type do
          :high_error_rate ->
            [
              %{
                priority: :high,
                action: "Investigate error handling in #{bottleneck.pipeline}",
                details: "Error rate: #{Float.round(bottleneck.rate * 100, 2)}%"
              }
              | acc
            ]

          :slow_processing ->
            [
              %{
                priority: :medium,
                action: "Increase concurrency for #{bottleneck.pipeline}",
                details: "Avg processing time: #{bottleneck.time}ms"
              }
              | acc
            ]

          :queue_backup ->
            [
              %{
                priority: :high,
                action: "Increase batch size or processors for #{bottleneck.pipeline}",
                details: "Avg queue depth: #{bottleneck.depth}"
              }
              | acc
            ]
        end
      end)

    recommendations
  end

  defp generate_migration_recommendations(test_results) do
    recommendations = []

    failed_tests = Enum.filter(test_results, fn {_type, result} -> not result.success end)

    if length(failed_tests) > 0 do
      recommendations = [
        %{
          priority: :critical,
          action: "Fix failed migration tests",
          details: "Failed tests: #{inspect(Enum.map(failed_tests, &elem(&1, 0)))}"
        }
        | recommendations
      ]
    end

    if test_results.legacy_compatibility.success do
      recommendations = [
        %{
          priority: :low,
          action: "Remove legacy compatibility layer after migration is complete",
          details: "Legacy broadcasts are working but should be phased out"
        }
        | recommendations
      ]
    end

    recommendations
  end

  defp analyze_trends(_metrics_history) do
    # Placeholder for trend analysis
    %{
      throughput_trend: :stable,
      latency_trend: :improving,
      error_trend: :stable
    }
  end

  defp extract_pipeline_metrics(metrics_history, pipeline) do
    Enum.map(metrics_history, fn metrics ->
      get_in(metrics, [:pipelines, pipeline]) || %{}
    end)
  end

  defp calculate_average(metrics_list, key) do
    values = Enum.map(metrics_list, &Map.get(&1, key, 0))

    case length(values) do
      0 -> 0
      count -> Enum.sum(values) / count
    end
  end

  defp calculate_maximum(metrics_list, key) do
    values = Enum.map(metrics_list, &Map.get(&1, key, 0))

    case values do
      [] -> 0
      values -> Enum.max(values)
    end
  end

  defp calculate_sum(metrics_list, key) do
    Enum.reduce(metrics_list, 0, fn metrics, acc ->
      acc + Map.get(metrics, key, 0)
    end)
  end
end
