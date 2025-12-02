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
      generate_domain_metrics(),
      generate_oban_metrics()
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
      :thunderblock_vault,
      :thundercom,
      :thundereye
    ]

    Enum.map_join(domains, "\n", fn domain ->
      metrics = apply(DashboardMetrics, :"#{domain}_metrics", [])
      generate_domain_specific_metrics(domain, metrics)
    end)
  end

  defp generate_domain_specific_metrics(domain, metrics) do
    domain_str = to_string(domain)

    Enum.map_join(metrics, "", fn {key, value} ->
      metric_name = "thunderline_#{domain_str}_#{key}"
      metric_value = format_prometheus_value(value)

      """
      # HELP #{metric_name} #{String.capitalize(to_string(key))} for #{String.capitalize(domain_str)}
      # TYPE #{metric_name} gauge
      #{metric_name} #{metric_value}
      """
    end)
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

  defp generate_oban_metrics do
    import Ecto.Query, only: [from: 2]

    queues = Application.get_env(:thunderline, Oban, [])[:queues] || []

    queue_metrics =
      for {queue_name, _opts} <- queues do
        counts = get_oban_queue_counts(queue_name)

        """
        # HELP thunderline_oban_queue_available Jobs available in #{queue_name}
        # TYPE thunderline_oban_queue_available gauge
        thunderline_oban_queue_available{queue="#{queue_name}"} #{counts.available}

        # HELP thunderline_oban_queue_executing Jobs executing in #{queue_name}
        # TYPE thunderline_oban_queue_executing gauge
        thunderline_oban_queue_executing{queue="#{queue_name}"} #{counts.executing}

        # HELP thunderline_oban_queue_scheduled Jobs scheduled in #{queue_name}
        # TYPE thunderline_oban_queue_scheduled gauge
        thunderline_oban_queue_scheduled{queue="#{queue_name}"} #{counts.scheduled}

        # HELP thunderline_oban_queue_retryable Jobs retryable in #{queue_name}
        # TYPE thunderline_oban_queue_retryable gauge
        thunderline_oban_queue_retryable{queue="#{queue_name}"} #{counts.retryable}
        """
      end

    # Also get telemetry stats from the Oban telemetry module
    oban_stats = Thunderline.Thunderflow.Telemetry.Oban.stats()

    [
      """
      # HELP thunderline_oban_telemetry_events_total Total Oban telemetry events captured
      # TYPE thunderline_oban_telemetry_events_total counter
      thunderline_oban_telemetry_events_total #{oban_stats.total}
      """
      | queue_metrics
    ]
    |> Enum.join("\n")
  rescue
    _ -> ""
  end

  defp get_oban_queue_counts(queue_name) do
    import Ecto.Query, only: [from: 2]

    queue_str = to_string(queue_name)

    try do
      counts =
        from(j in "oban_jobs",
          where: j.queue == ^queue_str,
          group_by: j.state,
          select: {j.state, count(j.id)}
        )
        |> Thunderline.Repo.all()
        |> Map.new()

      %{
        available: Map.get(counts, "available", 0),
        executing: Map.get(counts, "executing", 0),
        scheduled: Map.get(counts, "scheduled", 0),
        retryable: Map.get(counts, "retryable", 0)
      }
    rescue
      _ ->
        %{available: 0, executing: 0, scheduled: 0, retryable: 0}
    end
  end
end
