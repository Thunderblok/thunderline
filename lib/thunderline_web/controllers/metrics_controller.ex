defmodule ThunderlineWeb.MetricsController do
  @moduledoc """
  MetricsController - Prometheus-style metrics endpoint

  Provides structured metrics in Prometheus format for:
  - External monitoring systems
  - APM tools integration
  - Custom metrics collection
  """

  use ThunderlineWeb, :controller

  alias Thunderline.DashboardMetrics

  @doc """
  Prometheus-compatible metrics endpoint
  """
  def index(conn, _params) do
    metrics = collect_prometheus_metrics()

    conn
    |> put_resp_content_type("text/plain; version=0.0.4; charset=utf-8")
    |> text(metrics)
  end

  ## Private Functions

  defp collect_prometheus_metrics do
    system_metrics = DashboardMetrics.get_system_metrics()
    event_metrics = DashboardMetrics.get_event_metrics()
    agent_metrics = DashboardMetrics.get_agent_metrics()

    [
      generate_system_metrics(system_metrics),
      generate_event_metrics(event_metrics),
      generate_agent_metrics(agent_metrics),
      generate_domain_metrics()
    ]
    |> Enum.join("\n")
  end

  defp generate_system_metrics(metrics) do
    memory = Map.get(metrics, :memory, %{})

    """
    # HELP thunderline_system_uptime_seconds System uptime in seconds
    # TYPE thunderline_system_uptime_seconds counter
    thunderline_system_uptime_seconds #{Map.get(metrics, :uptime, 0)}

    # HELP thunderline_system_process_count Number of Erlang processes
    # TYPE thunderline_system_process_count gauge
    thunderline_system_process_count #{Map.get(metrics, :process_count, 0)}

    # HELP thunderline_system_schedulers_online Number of online schedulers
    # TYPE thunderline_system_schedulers_online gauge
    thunderline_system_schedulers_online #{Map.get(metrics, :schedulers, 0)}

    # HELP thunderline_memory_total_bytes Total memory usage in bytes
    # TYPE thunderline_memory_total_bytes gauge
    thunderline_memory_total_bytes #{Map.get(memory, :total, 0)}

    # HELP thunderline_memory_processes_bytes Process memory usage in bytes
    # TYPE thunderline_memory_processes_bytes gauge
    thunderline_memory_processes_bytes #{Map.get(memory, :processes, 0)}

    # HELP thunderline_memory_system_bytes System memory usage in bytes
    # TYPE thunderline_memory_system_bytes gauge
    thunderline_memory_system_bytes #{Map.get(memory, :system, 0)}
    """
  end

  defp generate_event_metrics(metrics) do
    """
    # HELP thunderline_events_processed_total Total number of events processed
    # TYPE thunderline_events_processed_total counter
    thunderline_events_processed_total #{Map.get(metrics, :total_processed, 0)}

    # HELP thunderline_events_processing_rate Events processed per second
    # TYPE thunderline_events_processing_rate gauge
    thunderline_events_processing_rate #{Map.get(metrics, :processing_rate, 0)}

    # HELP thunderline_events_failed_total Total number of failed events
    # TYPE thunderline_events_failed_total counter
    thunderline_events_failed_total #{Map.get(metrics, :failed_events, 0)}

    # HELP thunderline_events_queue_size Current event queue size
    # TYPE thunderline_events_queue_size gauge
    thunderline_events_queue_size #{Map.get(metrics, :queue_size, 0)}

    # HELP thunderline_events_latency_milliseconds Average event processing latency
    # TYPE thunderline_events_latency_milliseconds gauge
    thunderline_events_latency_milliseconds #{Map.get(metrics, :average_latency, 0)}
    """
  end

  defp generate_agent_metrics(metrics) do
    """
    # HELP thunderline_agents_total Total number of agents
    # TYPE thunderline_agents_total gauge
    thunderline_agents_total #{Map.get(metrics, :total_agents, 0)}

    # HELP thunderline_agents_active Number of active agents
    # TYPE thunderline_agents_active gauge
    thunderline_agents_active #{Map.get(metrics, :active_agents, 0)}

    # HELP thunderline_agents_inactive Number of inactive agents
    # TYPE thunderline_agents_inactive gauge
    thunderline_agents_inactive #{Map.get(metrics, :inactive_agents, 0)}

    # HELP thunderline_agents_performance_average Average agent performance score
    # TYPE thunderline_agents_performance_average gauge
    thunderline_agents_performance_average #{Map.get(metrics, :average_performance, 0)}
    """
  end

  defp generate_domain_metrics do
    domains = [
      :thundercore,
      :thunderbit,
      :thunderbolt,
      :thunderblock,
      :thundergrid,
      :thundervault,
      :thundercom,
      :thundereye
    ]

    Enum.map(domains, fn domain ->
      metrics = apply(DashboardMetrics, :"#{domain}_metrics", [])
      generate_domain_specific_metrics(domain, metrics)
    end)
    |> Enum.join("\n")
  end

  defp generate_domain_specific_metrics(domain, metrics) do
    domain_str = to_string(domain)

    Enum.map(metrics, fn {key, value} ->
      metric_name = "thunderline_#{domain_str}_#{key}"
      metric_value = format_prometheus_value(value)

      """
      # HELP #{metric_name} #{String.capitalize(to_string(key))} for #{String.capitalize(domain_str)}
      # TYPE #{metric_name} gauge
      #{metric_name} #{metric_value}
      """
    end)
    |> Enum.join("")
  end

  defp format_prometheus_value(value) when is_number(value), do: value

  defp format_prometheus_value(value) when is_atom(value) do
    case value do
      true -> 1
      false -> 0
      :healthy -> 1
      :unhealthy -> 0
      :excellent -> 1
      :good -> 0.8
      :fair -> 0.6
      :poor -> 0.4
      :critical -> 0.2
      _ -> 0
    end
  end

  defp format_prometheus_value(_), do: 0
end
