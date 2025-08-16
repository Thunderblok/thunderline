defmodule Thunderline do
  @moduledoc """
  Thunderline Root Convenience & Health Module

  Aggregates cross-domain runtime & health data over the 7-domain federation:
  Thunderbolt, Thunderflow, Thundergate, Thunderblock, Thunderlink, Thundercrown, Thundergrid.

  Responsibilities:
  - Surface consolidated system & queue metrics (system_health/0)
  - Provide simplified health_check/0 used by endpoints & readiness probes
  - Lightweight delegations to core compute helpers (Ising solver shortcuts)
  - Domain enumeration & status probing (for ops visibility)

  NOTE: No business logic lives here; keep it an ops-facing façade only.
  """

  require Logger

  @doc """
  Return a snapshot map of current system health & key runtime indicators.

  Fields (may evolve – treat as observational, not strict API):
  * :timestamp – UTC timestamp
  * :version – application version
  * :node / :connected_nodes – current BEAM distribution info
  * :memory – subset of :erlang.memory/0 data
  * :process_count – total process count
  * :event_queues – aggregated event queue stats (pending/processing/failed/etc.)
  * :agents / :chunks – ThunderMemory derived counts
  * :oban – configured queues + peer table presence flag
  * :domains_loaded – count of Ash domains configured
  * :repo – repo connectivity check & migration status heuristics
  * :warnings_pending – (lazy) approximate count of compilation warnings if available
  """
  def system_health do
    %{
      timestamp: DateTime.utc_now(),
      version: app_version(),
      node: node(),
      connected_nodes: Node.list(),
      memory: memory_snapshot(),
      process_count: :erlang.system_info(:process_count),
      event_queues: queue_stats_safe(),
      agents: safe_metric(&Thunderline.Thunderflow.MetricSources.active_agents/0),
      chunks: safe_metric(&Thunderline.Thunderflow.MetricSources.chunk_total/0),
      oban: oban_status(),
      domains_loaded: domains_loaded_count(),
      repo: repo_status(),
      warnings_pending: compilation_warning_estimate()
    }
  end

  @doc "Return only event queue statistics (shorthand for system_health().event_queues)."
  def event_queue_stats, do: queue_stats_safe()

  # ----- Internal helpers -----

  defp app_version do
    case Application.spec(:thunderline, :vsn) do
      nil -> :unknown
      vsn -> List.to_string(vsn)
    end
  end

  defp memory_snapshot do
    mem = :erlang.memory()
    %{
      total: mem[:total],
      processes: mem[:processes],
      processes_used: mem[:processes_used],
      system: mem[:system],
      atom: mem[:atom],
      binary: mem[:binary],
      code: mem[:code],
      ets: mem[:ets]
    }
  end

  defp queue_stats_safe do
    safe_metric(&Thunderline.Thunderflow.MetricSources.queue_depths/0)
  end

  defp safe_metric(fun) when is_function(fun, 0) do
    try do
      fun.()
    rescue
      _ -> :unavailable
    catch
      _ -> :unavailable
    end
  end

  defp domains_loaded_count do
    case Application.get_env(:thunderline, :ash_domains) do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp repo_status do
    repo = Thunderline.Repo

    connectivity =
      try do
        case repo.__adapter__().checked_out?() do
          _ -> :ok
        end
        # lightweight query
        case Ecto.Adapters.SQL.query(repo, "SELECT 1", []) do
          {:ok, _} -> :ok
          {:error, err} -> {:error, err}
        end
      rescue
        e -> {:error, e}
      end

    %{
      connectivity: connectivity,
      oban_peers_present: oban_peers_table?()
    }
  end

  defp oban_status do
    config = Application.get_env(:thunderline, Oban, [])
    queues = Keyword.get(config, :queues, []) |> Enum.map(fn {q, _c} -> q end)

    %{
      queues: queues,
      peers_table?: oban_peers_table?()
    }
  end

  defp oban_peers_table? do
    try do
      case Ecto.Adapters.SQL.query(Thunderline.Repo, "SELECT to_regclass('public.oban_peers')", []) do
        {:ok, %{rows: [[nil]]}} -> false
        {:ok, %{rows: [[_]]}} -> true
        _ -> false
      end
    rescue
      _ -> false
    end
  end

  # Best-effort heuristic – we cannot easily pull compile warnings at runtime without tools.
  defp compilation_warning_estimate do
    # If a previous run stored something in persistent_term, we reuse it; else :unknown
    case :persistent_term.get({__MODULE__, :warning_count}, :unknown) do
      :unknown -> :unknown
      count -> count
    end
  end
  # -------- Delegated compute helpers (thin shortcuts) --------
  @doc "Quick access to Ising machine optimization."
  defdelegate ising_solve(height, width, opts \\ []),
    to: Thunderline.Thunderbolt.IsingMachine,
    as: :quick_solve

  @doc "Quick access to Max-Cut optimization."
  defdelegate max_cut(edges, num_vertices, opts \\ []),
    to: Thunderline.Thunderbolt.IsingMachine,
    as: :solve_max_cut

  # -------- High-level health check (subset of system_health) --------
  @doc "Lightweight readiness/liveness style health summary."
  def health_check do
    %{
      beam_vm: check_beam_health(),
      compute_acceleration: Thunderline.Thunderbolt.IsingMachine.check_acceleration(),
      domains: check_domain_health(),
      timestamp: DateTime.utc_now()
    }
  end

  defp check_beam_health do
    %{
      schedulers: :erlang.system_info(:schedulers),
      processes: :erlang.system_info(:process_count),
      memory_mb: div(:erlang.memory(:total), 1024 * 1024),
      uptime_ms: :erlang.statistics(:wall_clock) |> elem(0)
    }
  end

  @doc "Enumerated Ash domain modules (ops visibility)."
  def domains do
    [
      Thunderline.Thunderbolt.Domain,
      Thunderline.Thunderflow.Domain,
      Thunderline.Thundergate.Domain,
      Thunderline.Thunderblock.Domain,
      Thunderline.Thunderlink.Domain,
      Thunderline.Thundercrown.Domain,
      Thunderline.Thundergrid.Domain
    ]
  end

  defp check_domain_health do
    Enum.reduce(domains(), %{}, fn domain, acc ->
      status =
        try do
          resources = Ash.Domain.Info.resources(domain)
          %{status: :healthy, resource_count: length(resources)}
        rescue
          error -> %{status: :error, error: inspect(error)}
        end

      Map.put(acc, domain, status)
    end)
  end
end
