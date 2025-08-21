defmodule Mix.Tasks.Thunderline.Oban.Verbose do
  @shortdoc "Print instructions for enabling verbose Oban health/diagnostics logging"
  @moduledoc """
  Prints guidance and current env related to Oban verbose logging.

  Usage:
      mix thunderline.oban.verbose

  Then restart your server with (for temporary shell):
      OBAN_HEALTH_VERBOSE=1 OBAN_DIAGNOSTICS_VERBOSE=1 iex -S mix phx.server
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    IO.puts("\nOban Verbose Logging Helper\n")
    IO.puts("Current ENV values:")
    for {k, v} <- System.get_env() |> Enum.filter(fn {k, _} -> String.starts_with?(k, "OBAN") end) do
      IO.puts("  #{k}=#{v}")
    end
    IO.puts("\nSet the following to increase visibility each tick:")
    IO.puts("  OBAN_HEALTH_VERBOSE=1 -> per-tick ObanHealth line with running?/queues")
    IO.puts("  OBAN_DIAGNOSTICS=1     -> enable diagnostics process (already default)")
    IO.puts("  OBAN_DIAGNOSTICS_VERBOSE=1 -> include table & queue detail lines")
    IO.puts("\nExample run:\n  OBAN_HEALTH_VERBOSE=1 OBAN_DIAGNOSTICS_VERBOSE=1 iex -S mix phx.server\n")
  end
end
