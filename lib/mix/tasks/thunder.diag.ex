defmodule Mix.Tasks.Thunder.Diag do
  use Mix.Task
  @shortdoc "Prints IO/Repo diagnostics"
  @moduledoc """
  Runs a minimal diagnostic to verify STDOUT, STDERR and DB connectivity.
  Set LOG_STDERR=1 to force logger to stderr. Useful when mix output appears silent.
  """
  def run(_args) do
    Mix.Task.run("app.start")
    IO.puts("STDOUT OK")
    IO.warn("STDERR OK")

    case Thunderline.Thunderblock.Health.now() do
      {:ok, _ts} -> IO.puts("Repo OK")
      {:error, err} -> IO.puts("Repo ERROR: #{inspect(err)}")
    end
  end
end
