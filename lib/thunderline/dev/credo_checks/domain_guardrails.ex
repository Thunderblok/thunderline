defmodule Thunderline.Dev.CredoChecks.DomainGuardrails do
  @moduledoc """
  Custom Credo checks enforcing domain guardrails (ANVIL / IRONWOLF).

  Escalation Plan:
    * Phase 1 (current dev): warnings
    * Phase 2 (CI toggle :repo_only_enforce) – direct Repo calls outside allowlist -> error

  Checks:
    * NoDirectRepoCallsOutsideBlock
    * NoPolicyInLink
    * NoEventsOutsideFlow (emission entrypoints)
  """
  @behaviour Credo.Check
  alias Credo.{Issue, SourceFile}

  @impl true
  def category, do: severity()
  @impl true
  def base_priority, do: 0
  @impl true
  def param_names, do: []
  @impl true
  def run(%SourceFile{filename: filename} = source_file, _params) do
    text = SourceFile.source(source_file)

    issues =
      []
      |> check_repo_calls(filename, text)
      |> check_policy_in_link(filename, text)
      |> check_event_emission(filename, text)

    {:ok, issues}
  end

  defp check_repo_calls(issues, filename, text) do
    allow? =
      String.contains?(filename, "/thunderblock/") or
        String.contains?(filename, "/priv/repo/migrations/")

    if String.contains?(text, "Repo.") and not allow? do
      [issue(issues, filename, "Direct Repo call outside Block domain")]
    else
      issues
    end
  end

  defp check_policy_in_link(issues, filename, text) do
    if String.contains?(filename, "/thunderlink/") and String.contains?(text, "Policy.") do
      [issue(issues, filename, "Policy reference inside Link domain")]
    else
      issues
    end
  end

  defp check_event_emission(issues, filename, text) do
    cond do
      String.contains?(text, "EventBus.emit") ->
        [
          issue(
            issues,
            filename,
            "Deprecated EventBus.emit usage detected (replace with publish_event/1)"
          )
          | issues
        ]

      String.contains?(text, "EventBus.publish_event(") and
          not String.contains?(filename, "/thunderflow/") ->
        [
          issue(
            issues,
            filename,
            "Event emission outside Flow domain (publish_event/1 should be invoked by Flow-centric modules or clearly justified)"
          )
          | issues
        ]

      true ->
        issues
    end
  end

  defp issue(issues, filename, message) do
    [
      %Issue{category: severity(), filename: filename, message: message, trigger: message}
      | issues
    ]
  end

  defp severity do
    # Escalate to :error in any CI context or when explicit env toggle set.
    # This moves guardrails from advisory -> enforcing without requiring every
    # pipeline to remember REPO_ONLY_ENFORCE. MIX_ENV=ci or CI=true triggers.
    enforce? =
      System.get_env("REPO_ONLY_ENFORCE") in ["1", "true", "TRUE"] or
        System.get_env("CI") in ["1", "true", "TRUE"] or
        System.get_env("MIX_ENV") == "ci"

    if enforce?, do: :error, else: :warning
  end
end
