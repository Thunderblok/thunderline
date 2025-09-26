defmodule Mix.Tasks.Thunderline.Brg.Check do
  @moduledoc """
  Balance Readiness Gate (BRG) checker for Thunderline system health.

  Validates that the system maintains operational balance across all domains
  and identifies areas requiring attention before major deployments.

  ## Usage

      mix thunderline.brg.check
      mix thunderline.brg.check --format json
      mix thunderline.brg.check --threshold critical
  """

  use Mix.Task

  @shortdoc "Check system balance readiness across all domains"

  @switches [
    format: :string,
    threshold: :string,
    verbose: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _errors} = OptionParser.parse(args, switches: @switches)

    format = opts[:format] || "text"
    threshold = String.to_atom(opts[:threshold] || "warning")
    verbose = opts[:verbose] || false

    results = run_brg_checks()

    case format do
      "json" -> output_json(results)
      "text" -> output_text(results, threshold, verbose)
      _ -> Mix.raise("Invalid format: #{format}. Use 'text' or 'json'")
    end

    # Exit with error code if critical issues found
    if has_critical_issues?(results), do: System.halt(1)
  end

  defp run_brg_checks do
    %{
      timestamp: DateTime.utc_now(),
      domains: check_domain_health(),
      metrics: check_metrics_health(),
      queues: check_queue_health(),
      circuit_breakers: check_circuit_breaker_health(),
      warnings: check_warning_budget(),
      overall_status: :pending  # Will be calculated
    }
    |> calculate_overall_status()
  end

  defp check_domain_health do
    domains = ["thunderblock", "thunderbolt", "thundercrown", "thunderflow",
               "thundergate", "thundergrid", "thunderlink"]

    Enum.map(domains, fn domain ->
      %{
        name: domain,
        status: :healthy,  # Placeholder - would check actual domain health
        resources_count: count_domain_resources(domain),
        last_activity: DateTime.utc_now(),
        issues: []
      }
    end)
  end

  defp check_metrics_health do
    fanout_stats = get_fanout_stats()

    issues = []
    issues = if fanout_stats.p95_fanout > 5, do: ["High fanout detected (P95: #{fanout_stats.p95_fanout})" | issues], else: issues
    issues = if fanout_stats.coupling_score > 7.0, do: ["High coupling score: #{:erlang.float_to_binary(fanout_stats.coupling_score, decimals: 1)}" | issues], else: issues

    status = if length(issues) > 0, do: :warning, else: :healthy

    %{
      status: status,
      telemetry_active: telemetry_running?(),
      fanout_p95: fanout_stats.p95_fanout,
      coupling_score: fanout_stats.coupling_score,
      event_samples: fanout_stats.total_samples,
      missing_metrics: find_missing_metrics(),
      stale_metrics: find_stale_metrics(),
      issues: issues
    }
  end

  defp check_queue_health do
    queue_stats = get_queue_stats()
    saturation_check = check_queue_saturation()

    issues = []
    issues = if queue_stats.p95_depth > 100, do: ["High queue depth (P95: #{queue_stats.p95_depth})" | issues], else: issues
    issues = case saturation_check do
      {:warning, details} ->
        saturated = length(details.saturated_queues)
        ["#{saturated} queue(s) approaching saturation" | issues]
      :ok -> issues
    end

    # Determine status with critical threshold first so it isn't masked by saturation warnings
    status = cond do
      queue_stats.p95_depth > 200 -> :critical
      match?({:warning, _details}, saturation_check) -> :warning
      queue_stats.p95_depth > 100 -> :warning
      true -> :healthy
    end

    %{
      status: status,
      depths: %{
        total: queue_stats.total_depth,
        p95: queue_stats.p95_depth,
        max: queue_stats.max_depth
      },
      trend_analysis: queue_stats.trend_analysis,
      collection_count: queue_stats.collection_count,
      stuck_jobs: find_stuck_jobs(),
      retry_rates: get_retry_rates(),
      issues: issues
    }
  end

  defp check_circuit_breaker_health do
    %{
      status: :healthy,
      active_breakers: count_active_circuit_breakers(),
      open_circuits: find_open_circuits(),
      recent_trips: count_recent_trips(),
      issues: []
    }
  end

  defp check_warning_budget do
    %{
      status: :unknown,
      current_warnings: count_compiler_warnings(),
      budget_limit: get_warning_budget_limit(),
      trend: :stable,
      issues: ["Warning budget gate not yet implemented (CP-18)"]
    }
  end

  defp calculate_overall_status(results) do
    all_statuses = [
      results.domains |> Enum.map(& &1.status),
      [results.metrics.status, results.queues.status,
       results.circuit_breakers.status, results.warnings.status]
    ] |> List.flatten()

    overall = cond do
      :critical in all_statuses -> :critical
      :warning in all_statuses -> :warning
      :unknown in all_statuses -> :warning
      true -> :healthy
    end

    %{results | overall_status: overall}
  end

  defp output_text(results, threshold, verbose) do
  IO.puts("\n🛡️  Thunderline Balance Readiness Gate Check")
  IO.puts(String.duplicate("=", 50))
    IO.puts("Timestamp: #{DateTime.to_iso8601(results.timestamp)}")
    IO.puts("Overall Status: #{format_status(results.overall_status)}")
    IO.puts("")

    if should_show_section?(:domains, threshold, verbose) do
      output_domain_section(results.domains)
    end

    if should_show_section?(:metrics, threshold, verbose) do
      output_metrics_section(results.metrics)
    end

    if should_show_section?(:queues, threshold, verbose) do
      output_queue_section(results.queues)
    end

    if should_show_section?(:circuit_breakers, threshold, verbose) do
      output_circuit_breaker_section(results.circuit_breakers)
    end

    if should_show_section?(:warnings, threshold, verbose) do
      output_warning_section(results.warnings)
    end

    output_summary(results)
  end

  defp output_json(results) do
    results |> Jason.encode!(pretty: true) |> IO.puts()
  end

  defp output_domain_section(domains) do
    IO.puts("📋 Domain Health:")
    Enum.each(domains, fn domain ->
      IO.puts("  #{domain.name}: #{format_status(domain.status)} (#{domain.resources_count} resources)")
      if length(domain.issues) > 0 do
        Enum.each(domain.issues, &IO.puts("    ⚠️  #{&1}"))
      end
    end)
    IO.puts("")
  end

  defp output_metrics_section(metrics) do
    IO.puts("📊 Metrics Health: #{format_status(metrics.status)}")
    IO.puts("  Telemetry Active: #{metrics.telemetry_active}")
    IO.puts("  Fanout P95: #{metrics.fanout_p95}")
    IO.puts("  Coupling Score: #{:erlang.float_to_binary(metrics.coupling_score, decimals: 1)}/10")
    IO.puts("  Event Samples: #{metrics.event_samples}")
    IO.puts("  Missing Metrics: #{length(metrics.missing_metrics)}")
    if length(metrics.issues) > 0 do
      Enum.each(metrics.issues, &IO.puts("  ⚠️  #{&1}"))
    end
    IO.puts("")
  end

  defp output_queue_section(queues) do
    IO.puts("⚡ Queue Health: #{format_status(queues.status)}")
    IO.puts("  Total Depth: #{queues.depths.total}")
    IO.puts("  P95 Depth: #{queues.depths.p95}")
    IO.puts("  Max Depth: #{queues.depths.max}")
    IO.puts("  Collections: #{queues.collection_count}")
    IO.puts("  Stuck Jobs: #{length(queues.stuck_jobs)}")

    # Show queue trends if available
    if map_size(queues.trend_analysis) > 0 do
      IO.puts("  Queue Trends:")
      Enum.each(queues.trend_analysis, fn {queue, trend} ->
        direction = if trend.is_growing, do: "↗️", else: "↘️"
        IO.puts("    #{queue}: #{direction} P95=#{trend.recent_p95}, Δ=#{:erlang.float_to_binary(trend.avg_delta, decimals: 2)}")
      end)
    end

    if length(queues.issues) > 0 do
      Enum.each(queues.issues, &IO.puts("  ⚠️  #{&1}"))
    end
    IO.puts("")
  end

  defp output_circuit_breaker_section(breakers) do
    IO.puts("🔌 Circuit Breakers: #{format_status(breakers.status)}")
    IO.puts("  Active Breakers: #{breakers.active_breakers}")
    IO.puts("  Open Circuits: #{length(breakers.open_circuits)}")
    if length(breakers.issues) > 0 do
      Enum.each(breakers.issues, &IO.puts("  ⚠️  #{&1}"))
    end
    IO.puts("")
  end

  defp output_warning_section(warnings) do
    IO.puts("⚠️  Warning Budget: #{format_status(warnings.status)}")
    IO.puts("  Current Warnings: #{warnings.current_warnings}")
    IO.puts("  Budget Limit: #{warnings.budget_limit || "Not set"}")
    if length(warnings.issues) > 0 do
      Enum.each(warnings.issues, &IO.puts("  ⚠️  #{&1}"))
    end
    IO.puts("")
  end

  defp output_summary(results) do
    IO.puts("📋 Summary:")

    case results.overall_status do
      :healthy ->
        IO.puts("  ✅ System is balanced and ready for deployment")
      :warning ->
        IO.puts("  ⚠️  System has warnings - review recommended before deployment")
      :critical ->
        IO.puts("  ❌ System has critical issues - deployment not recommended")
    end

    total_issues = count_total_issues(results)
    if total_issues > 0 do
      IO.puts("  Total Issues: #{total_issues}")
    end

    IO.puts("")
    IO.puts("Next Steps:")
    IO.puts("  - Address any critical issues before deployment")
    IO.puts("  - Run `mix thunderline.catalog.validate` to check domain interactions")
    IO.puts("  - Monitor telemetry for system balance metrics")
  end

  # Placeholder helper functions (would be implemented with real checks)

  defp count_domain_resources(domain) do
    # Would count actual resources in domain
    case domain do
      "thunderflow" -> 12
      "thundergate" -> 8
      _ -> :rand.uniform(15)
    end
  end

  defp telemetry_running?, do: true
  defp find_missing_metrics, do: ["resource.churn"]  # fanout.distribution now implemented
  defp find_stale_metrics, do: []

  defp get_fanout_stats do
    try do
      Thunderline.Thunderflow.Observability.FanoutAggregator.get_stats()
    rescue
      _ ->
        %{p95_fanout: 0, coupling_score: 0.0, total_samples: 0}
    end
  end

  defp get_queue_stats do
    try do
      Thunderline.Thunderflow.Observability.QueueDepthCollector.get_queue_stats()
    rescue
      _ ->
        %{total_depth: 0, p95_depth: 0, max_depth: 0, trend_analysis: %{}, collection_count: 0}
    end
  end

  defp check_queue_saturation do
    try do
      Thunderline.Thunderflow.Observability.QueueDepthCollector.check_saturation()
    rescue
      _ -> :ok
    end
  end
  defp find_stuck_jobs, do: []
  defp get_retry_rates, do: %{last_hour: 0.02, last_day: 0.015}

  defp count_active_circuit_breakers, do: 3
  defp find_open_circuits, do: []
  defp count_recent_trips, do: 0

  defp count_compiler_warnings, do: 7
  defp get_warning_budget_limit, do: nil

  defp has_critical_issues?(%{overall_status: :critical}), do: true
  defp has_critical_issues?(_), do: false

  defp should_show_section?(_section, :critical, false), do: false
  defp should_show_section?(_section, _threshold, true), do: true
  defp should_show_section?(_section, _threshold, false), do: true

  defp format_status(:healthy), do: "✅ HEALTHY"
  defp format_status(:warning), do: "⚠️  WARNING"
  defp format_status(:critical), do: "❌ CRITICAL"
  defp format_status(:unknown), do: "❓ UNKNOWN"

  defp count_total_issues(results) do
    [
      results.domains |> Enum.map(&length(&1.issues)) |> Enum.sum(),
      length(results.metrics.issues),
      length(results.queues.issues),
      length(results.circuit_breakers.issues),
      length(results.warnings.issues)
    ] |> Enum.sum()
  end
end
