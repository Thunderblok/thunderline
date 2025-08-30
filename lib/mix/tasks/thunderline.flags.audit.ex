defmodule Mix.Tasks.Thunderline.Flags.Audit do
  use Mix.Task
  @shortdoc "List Feature.enabled? calls and configured flags"
  @moduledoc """
  Stub task for HC-10.

  Future responsibilities:
    * Enumerate all atoms passed to Thunderline.Feature.enabled?/2
    * Compare with FEATURE_FLAGS.md table
    * Warn on undocumented or deprecated flags still referenced
    * Emit summary for CI
  """
  @impl true
  def run(_args) do
    IO.puts("TODO: scan Feature.enabled?/1 usage and compare to configured flags")
  end
end
