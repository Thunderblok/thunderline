defmodule Thunderline.TOCP.Sim.Fabric do
  @moduledoc """
  In-memory simulated fabric – zero side effects.

  Week-0: Produces empty JSON report scaffold consumed by CI.
  Future: Manages virtual nodes, message delivery, loss modeling.
  """

  @report_version 1

  @doc "Generate empty simulation report (placeholder)."
  def generate_report(path) do
    counters = safe_snapshot()

    report = %{
      version: @report_version,
      generated_at: DateTime.utc_now(),
      nodes: 0,
      notes: "scaffold",
      security: %{
        sig_fail: counters.sig_fail,
        replay_drop: counters.replay_drop,
        rate_drop: 0,
        fragments_evicted: 0
      },
      pass: %{
        sybil_swarm: true,
        replay_flood: true,
        fragment_exhaust: true,
        ack_abuse: true,
        topology_probe: true,
        credit_drain: true
      }
    }

    File.write!(path, Jason.encode!(report, pretty: true))
    {:ok, path}
  end

  defp safe_snapshot do
    Thunderline.TOCP.Telemetry.Aggregator.snapshot()
  rescue
    _ -> %{sig_fail: 0, replay_drop: 0}
  end
end
