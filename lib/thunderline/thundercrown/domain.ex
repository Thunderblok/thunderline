defmodule Thunderline.Thundercrown.Domain do
  @moduledoc """
  # ⚡👑 THUNDERCROWN - GOVERNANCE & ORCHESTRATION SUPREMACY 👑⚡

  **Boundary**: "Crown decides" - When/why, scheduling, governance, coordination

  Consolidated from: ThunderChief (job/orchestration), ThunderClock (scheduling)

  The sovereign governance and coordination layer for the Thunderline federation.

  ## Purpose
  - Decides when/why operations occur (temporal orchestration)
  - System-wide scheduling and job orchestration
  - AI governance and multi-agent coordination
  - Policy management and compliance
  - Workflow orchestration and delegation
  - MCP tools integration and coordination

  ## Architecture Components

  ### 🟩 AshAI Integration
  - Every "official" workflow defined as Ash resource with `ai do ... end`
  - Policies, prompts, input/output, toolchain as declarative code
  - LLM-backed tools become first-class, schema-validated, auditable

  ### 🟦 Hermes MCP Integration
  - Runs the Hermes MCP bus for multi-agent orchestration
  - Coordinates agent/LLM/tool job distribution
  - Handles fallback/retry logic and human-in-the-loop escalation
  - Manages checkpoints, plan branching, and state tracking

  ## Event Flow
  ```
  [Thunderline UI] --> [Thundercrown: Hermes MCP Bus]
        |                         |
        |        ┌───────────────┴─────┐
        |        | [AshAI Resources]   |
        |        └───────────────┬─────┘
        |                        |
  [ThunderBolt (execution)] <----> [Thundercrown]
        |                        |
  [ThunderBlock (storage)] <──────┘
  """

  use Ash.Domain, otp_app: :thunderline, extensions: [AshAi]

  # Expose governance-approved actions as AshAI MCP tools (initial slice).
  # Additional tools should be added only after Crown policy review.
  tools do
    # Run an approved agent/tool with a prompt under governance.
    tool :run_agent, Thunderline.Thundercrown.Resources.AgentRunner, :run

    tool :conversation_context,
         Thunderline.Thundercrown.Resources.ConversationTools,
         :context_snapshot

    tool :conversation_run_digest,
         Thunderline.Thundercrown.Resources.ConversationTools,
         :run_digest

    tool :conversation_reply, Thunderline.Thundercrown.Resources.ConversationAgent, :respond
  end

  resources do
    # ThunderChief → ThunderCrown (orchestration)
    resource Thunderline.Thundercrown.Resources.OrchestrationUI
    # Agent runner for AI/Jido tools
    resource Thunderline.Thundercrown.Resources.AgentRunner
    resource Thunderline.Thundercrown.Resources.ConversationTools
    resource Thunderline.Thundercrown.Resources.ConversationAgent

    # TODO: Add other resources when implemented:
    # resource Thunderline.Thundercrown.Resources.AiPolicy
    # resource Thunderline.Thundercrown.Resources.McpBus
    # resource Thunderline.Thundercrown.Resources.WorkflowOrchestrator

    # ThunderClock → ThunderCrown (temporal orchestration)
    # Note: ThunderClock resources will be added when implemented
  end
end
