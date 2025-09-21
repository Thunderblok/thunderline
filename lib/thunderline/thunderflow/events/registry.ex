defmodule Thunderline.Thunderflow.Events.Registry do
  @moduledoc """
  Canonical (seed) event registry backing the taxonomy linter.

  NOTE: This is a hard-coded seed snapshot (Docs/EVENT_TAXONOMY.md §7).
  In a later iteration this should be generated from a machine-readable
  artifact (JSON or extracted front‑matter) to avoid duplication.
  """

  @events %{
    "ui.command.email.requested" => %{version: 1, reliability: :persistent},
    "ai.intent.email.compose" => %{version: 1, reliability: :transient},
    "system.email.sent" => %{version: 1, reliability: :persistent},
    "system.email.failed" => %{version: 1, reliability: :persistent},
    "system.presence.join" => %{version: 1, reliability: :transient},
    "system.presence.leave" => %{version: 1, reliability: :transient},
  "ml.trial.started" => %{version: 1, reliability: :persistent},
  "ml.run.metrics" => %{version: 1, reliability: :transient},
  "ml.run.completed" => %{version: 1, reliability: :persistent},
  "ml.artifact.created" => %{version: 1, reliability: :persistent},
    "flow.reactor.retry" => %{version: 1, reliability: :transient},
    # AI runtime/tool events (whitelist)
    "ai.tool_start" => %{version: 1, reliability: :transient},
    "ai.tool_result" => %{version: 1, reliability: :transient},
    "ai.model_token" => %{version: 1, reliability: :transient},
    "ai.conversation_delta" => %{version: 1, reliability: :transient},
    # Voice / signaling subset
    "voice.signal.offer" => %{version: 1, reliability: :transient},
    "voice.signal.answer" => %{version: 1, reliability: :transient},
    "voice.signal.ice" => %{version: 1, reliability: :transient},
    # Governance / proofs
    "stone.proof.emitted" => %{version: 1, reliability: :persistent}
  }

  @categories_by_domain %{
    gate: ["ui.command", "system", "presence"],
    flow: ["flow.reactor", "system"],
    bolt: ["ml.run", "ml.trial", "ml.artifact", "system"],
    link: ["ui.command", "system", "voice.signal", "voice.room"],
    crown: ["ai.intent", "ai.plan", "system"],
    block: ["system"],
    bridge: ["system", "ui.command"],
    stone: ["stone.proof", "system"],
    foundry: ["foundry.blueprint", "foundry.factory", "foundry.resource", "system"],
    unknown: ["system"]
  }

  @ai_whitelist Enum.filter(Map.keys(@events), &String.starts_with?(&1, "ai."))

  @doc "Return the event metadata map (name => meta)."
  def events, do: @events

  @doc "True if an event name is registered."
  def registered?(name) when is_binary(name), do: Map.has_key?(@events, name)
  def registered?(_), do: false

  @doc "Return list of AI event names permitted (whitelist)."
  def ai_whitelist, do: @ai_whitelist

  @doc "Categories allowed per domain atom."
  def categories_by_domain, do: @categories_by_domain
end
