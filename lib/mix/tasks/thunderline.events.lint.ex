defmodule Mix.Tasks.Thunderline.Events.Lint do
  use Mix.Task
  @shortdoc "Validate event taxonomy adherence (stub)"
  @moduledoc """
  Stub task for HC-03.

  Future responsibilities:
    * Parse EVENT_TAXONOMY.md and build registry
    * Scan code for event name usages
    * Validate domain/category constraints & correlation rules
    * Output machine-readable JSON for CI gating
  """
  def run(_argv) do
    Mix.shell().info("[events.lint] TODO: implement taxonomy validation (see EVENT_TAXONOMY.md Section 14)")
  end
end
