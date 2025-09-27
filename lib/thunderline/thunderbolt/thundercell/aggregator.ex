defmodule Thunderline.Thunderbolt.ThunderCell.Aggregator do
  @moduledoc """
  Pure Elixir system state aggregator for ThunderCell.

  Phase 1 migration component: replaces direct dependency on legacy
  Erlang `thundercell_*` modules by exposing an Elixir-only
  consolidated system snapshot used by `Thunderline.ThunderBridge`.

  Responsibilities:
  * Collect cluster stats from `ThunderCell.ClusterSupervisor`
  * Collect compute/telemetry metrics from `ThunderCell.Telemetry`
  * Synthesize a dashboard-friendly system map
  * Attach high-level Ash domain insight (count only for now)

  Returned data structure (subject to extension, kept stable for bridge):

      %{
        clusters: [ %{cluster_id: ..., generation: ..., cell_count: ..., performance: %{...}, dimensions: {x,y,z}, paused: bool} ],
        telemetry: %{ generation_stats: %{...}, cluster_metrics: %{...}, system_metrics: %{...} },
        system: %{
          node: atom(),
          connected_nodes: non_neg_integer(),
          memory_usage: integer(),
          uptime_ms: integer(),
          scheduler_utilization: term()
        },
        ash: %{ domains: non_neg_integer(), placeholder?: true }
      }

  All functions are defensive: any failure returns {:error, reason} so the
  bridge can fall back gracefully.
  """

  require Logger

  alias Thunderline.Thunderbolt.ThunderCell.{ClusterSupervisor, Telemetry}

  @spec get_system_state() :: {:ok, map()} | {:error, term()}
  def get_system_state do
    with {:ok, clusters} <- fetch_clusters(),
         {:ok, telemetry} <- fetch_telemetry() do
      {:ok,
       %{
         clusters: clusters,
         telemetry: telemetry,
         system: build_system_overview(),
         ash: build_ash_insight()
       }}
    else
      {:error, reason} -> {:error, reason}
      {:telemetry_error, reason} -> {:error, reason}
      {:clusters_error, reason} -> {:error, reason}
      other -> {:error, {:unexpected, other}}
    end
  rescue
    error ->
      Logger.error("Aggregator crashed assembling system state: #{inspect(error)}")
      {:error, error}
  end

  # ------------------------------------------------------------------
  # Internal collection helpers
  # ------------------------------------------------------------------
  defp fetch_clusters do
    try do
      stats = ClusterSupervisor.list_clusters()
      {:ok, Enum.map(stats, &normalize_cluster/1)}
    rescue
      error -> {:clusters_error, error}
    end
  end

  defp fetch_telemetry do
    case Telemetry.get_compute_metrics() do
      {:ok, metrics} ->
        {:ok, unwrap_metrics(metrics)}

      {:error, reason} ->
        # If telemetry server not started yet, provide minimal structure
        Logger.warning("Telemetry unavailable: #{inspect(reason)}")

        {:ok,
         %{
           generation_stats: %{},
           cluster_metrics: %{},
           system_metrics: %{}
         }}
    end
  rescue
    error -> {:telemetry_error, error}
  end

  defp build_system_overview do
    memory = :erlang.memory(:total)
    uptime = get_uptime_ms()
    sched_util = get_scheduler_utilization()

    %{
      node: Node.self(),
      connected_nodes: length(Node.list()) + 1,
      memory_usage: memory,
      uptime_ms: uptime,
      scheduler_utilization: sched_util
    }
  end

  # Placeholder for deeper Ash integration (Phase 1: awareness only)
  defp build_ash_insight do
    domains = ash_domain_count()

    %{
      domains: domains,
      placeholder?: true
    }
  end

  defp ash_domain_count do
    # Discover modules that `use Ash.Domain` under our namespace.
    # Simplistic approach: static list; will be extended with reflection later.
    domain_modules = [
      Thunderline.Thunderblock.Domain,
      Thunderline.Thunderflow.Domain,
      Thunderline.Thundergrid.Domain,
      Thunderline.Thunderbolt.Domain,
      Thunderline.Thundercrown.Domain,
      Thunderline.Thunderlink.Domain,
      Thunderline.Thundergate.Domain
    ]

    Enum.count(domain_modules, &Code.ensure_loaded?/1)
  rescue
    _ -> 0
  end

  # ------------------------------------------------------------------
  # Normalization helpers
  # ------------------------------------------------------------------
  defp normalize_cluster(%{cluster_id: id, generation: gen} = raw) do
    %{
      cluster_id: id,
      generation: gen,
      cell_count: Map.get(raw, :cell_count, 0),
      dimensions: Map.get(raw, :dimensions),
      paused: Map.get(raw, :paused, false),
      performance: Map.get(raw, :performance, %{})
    }
  end

  defp normalize_cluster(other) do
    %{
      cluster_id: Map.get(other, :cluster_id, :unknown),
      generation: Map.get(other, :generation, 0),
      cell_count: Map.get(other, :cell_count, 0),
      dimensions: Map.get(other, :dimensions, {0, 0, 0}),
      paused: Map.get(other, :paused, false),
      performance: Map.get(other, :performance, %{})
    }
  end

  defp unwrap_metrics(%{metrics: nested}) when is_map(nested) do
    %{
      generation_stats: Map.get(nested, :generation_stats, %{}),
      cluster_metrics: Map.get(nested, :cluster_metrics, %{}),
      system_metrics: Map.get(nested, :system_metrics, %{})
    }
  end

  defp unwrap_metrics(other) when is_map(other) do
    %{
      generation_stats: Map.get(other, :generation_stats, %{}),
      cluster_metrics: Map.get(other, :cluster_metrics, %{}),
      system_metrics: Map.get(other, :system_metrics, %{})
    }
  end

  defp get_uptime_ms do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_ms
  end

  defp get_scheduler_utilization do
    try do
      :erlang.statistics(:scheduler_wall_time_all)
    rescue
      _ -> nil
    end
  end
end
