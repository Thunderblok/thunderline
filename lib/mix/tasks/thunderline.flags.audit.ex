defmodule Mix.Tasks.Thunderline.Flags.Audit do
  use Mix.Task
  @shortdoc "Audit feature flags vs documentation (stub)"
  @moduledoc """
  Stub task for HC-10.

  Future responsibilities:
    * Enumerate all atoms passed to Thunderline.Feature.enabled?/2
    * Compare with FEATURE_FLAGS.md table
    * Warn on undocumented or deprecated flags still referenced
    * Emit summary for CI
  """
  def run(_argv) do
    Mix.shell().info("[flags.audit] TODO: implement feature flag audit (see FEATURE_FLAGS.md TODOs)")
  end
end
