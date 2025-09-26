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
    fabric = Thunderline.TOCP.Sim.Fabric

    cond do
      Code.ensure_loaded?(fabric) and function_exported?(fabric, :generate_report, 1) ->
        {:ok, file} = apply(fabric, :generate_report, [path])
        Mix.shell().info("[TOCP][SIM] Wrote report: #{file}")

      true ->
        :ok = File.write!(path, Jason.encode!(%{}))
        Mix.shell().info("[TOCP][SIM] Fabric module missing; wrote placeholder report to #{path}")
    end
  end
end
