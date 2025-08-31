defmodule Thunderline.Dev.CredoChecks.DomainGuardrails do
  @moduledoc """
  Custom Credo checks for WARHORSE guardrails (Phase 1: advisory warnings).

  Implemented lightweight regex scans; escalate & refine Week 3.
  Checks:
    * NoDirectRepoCallsOutsideBlock
    * NoPolicyInLink
    * NoZoneWritesOutsideGrid (stub - pattern placeholder)
    * NoEventsOutsideFlow (emission entrypoints)
  """
  @behaviour Credo.Check
  alias Credo.{Issue, SourceFile}

  @impl true
  def category, do: :warning
  @impl true
  def base_priority, do: 0
  @impl true
  def param_names, do: []
  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    text = SourceFile.source(source_file)
    issues =
      []
      |> check_repo_calls(filename, text)
      |> check_policy_in_link(filename, text)
      |> check_event_emission(filename, text)
    {:ok, issues}
  end

  defp check_repo_calls(issues, filename, text) do
    if String.contains?(text, "Repo.") and not String.contains?(filename, "/thunderblock/") do
      [issue(issues, filename, "Direct Repo call outside Block domain")] else issues end
  end

  defp check_policy_in_link(issues, filename, text) do
    if String.contains?(filename, "/thunderlink/") and String.contains?(text, "Policy.") do
      [issue(issues, filename, "Policy reference inside Link domain")] else issues end
  end

  defp check_event_emission(issues, filename, text) do
    if String.contains?(text, "EventBus.emit") and not String.contains?(filename, "/thunderflow/") do
      [issue(issues, filename, "Event emission outside Flow domain (except allowed transitional paths)")] else issues end
  end

  defp issue(issues, filename, message) do
    [%Issue{
      category: :warning,
      filename: filename,
      message: message,
      trigger: message
    } | issues]
  end
end
