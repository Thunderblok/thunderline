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
  use Credo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Domain guardrails enforce Thunderline's ANVIL architecture principles.

      This check ensures:
      - Direct Repo calls only occur in the Block domain or migrations
      - Policy references don't leak into the Link domain
      - Event emissions use the canonical EventBus.publish_event/1 API
      """,
      params: []
    ],
    tags: [:domain, :architecture]

  alias Credo.SourceFile

  @doc false
  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    filename = source_file.filename
    text = SourceFile.source(source_file)

    []
    |> check_repo_calls(filename, text, issue_meta)
    |> check_policy_in_link(filename, text, issue_meta)
    |> check_event_emission(filename, text, issue_meta)
  end

  defp check_repo_calls(issues, filename, text, issue_meta) do
    allow? =
      String.contains?(filename, "/thunderblock/") or
        String.contains?(filename, "/priv/repo/migrations/")

    if String.contains?(text, "Repo.") and not allow? do
      [
        format_issue(
          issue_meta,
          message: "Direct Repo call outside Block domain",
          trigger: "Repo",
          line_no: 1
        )
        | issues
      ]
    else
      issues
    end
  end

  defp check_policy_in_link(issues, filename, text, issue_meta) do
    if String.contains?(filename, "/thunderlink/") and String.contains?(text, "Policy.") do
      [
        format_issue(
          issue_meta,
          message: "Policy reference inside Link domain",
          trigger: "Policy",
          line_no: 1
        )
        | issues
      ]
    else
      issues
    end
  end

  defp check_event_emission(issues, filename, text, issue_meta) do
    cond do
      String.contains?(text, "EventBus.emit") ->
        [
          format_issue(
            issue_meta,
            message: "Deprecated EventBus.emit usage detected (replace with publish_event/1)",
            trigger: "EventBus.emit",
            line_no: 1
          )
          | issues
        ]

      String.contains?(text, "EventBus.publish_event(") and
          not String.contains?(filename, "/thunderflow/") ->
        [
          format_issue(
            issue_meta,
            message:
              "Event emission outside Flow domain (publish_event/1 should be invoked by Flow-centric modules or clearly justified)",
            trigger: "EventBus.publish_event",
            line_no: 1
          )
          | issues
        ]

      true ->
        issues
    end
  end
end
