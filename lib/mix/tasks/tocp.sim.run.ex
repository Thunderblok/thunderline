defmodule Mix.Tasks.Tocp.Sim.Run do
  @shortdoc "Run TOCP simulation scaffold (produces empty JSON report)"
  @moduledoc """
  Runs the TOCP simulation harness stub and writes an empty JSON report.

  Usage:
      mix tocp.sim.run [--out path]
  """
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _rest, _} = OptionParser.parse(args, strict: [out: :string])
    path = opts[:out] || "tocp_sim_report.json"

    {:ok, file} = Thunderline.TOCP.Sim.Fabric.generate_report(path)
    Mix.shell().info("[TOCP][SIM] Wrote report: #{file}")
  end
end
