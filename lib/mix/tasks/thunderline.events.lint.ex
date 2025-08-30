defmodule Mix.Tasks.Thunderline.Events.Lint do
  use Mix.Task
  @shortdoc "List telemetry emit sites (baseline)"
  @impl true
  def run(_args) do
    IO.puts("TODO: grep for :telemetry.execute occurrences and build a baseline list")
  end
end
