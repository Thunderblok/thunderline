defmodule Thunderline.Thunderblock.Domain do
  @moduledoc """
  ThunderBlock Ash Domain - Infrastructure & Storage

  **Boundary**: Exposes stateful capabilities, not business workflows

  Consolidated from: ThunderVault (storage, Postgres, Memento/Mnesia)

  **Vision**: The foundational runtime providing execution environment and
  storage infrastructure with infinite configurability.

  **Use Cases**:
  - 🎮 Community/gaming servers (Discord-like)
  - 🏢 ERP and business management systems
  - 🏠 Personal life management hubs
  - 🏭 Enterprise orchestration platforms
  - 🌐 Federated social networks
  - 🤖 AI agent coordination centers

  Core responsibilities:
  - Container runtime and execution environment
  - Storage layer (Postgres, Memento, ETS, caching)
  - Memory management and persistence
  - Distributed state coordination
  - Resource allocation and load balancing
  - Knowledge and memory management
  """

  use Ash.Domain

  resources do
    # Original ThunderBlock resources
    resource Thunderblock.Resources.ExecutionContainer
    resource Thunderblock.Resources.TaskOrchestrator
    resource Thunderblock.Resources.ZoneContainer
    resource Thunderblock.Resources.SupervisionTree
    resource Thunderblock.Resources.Community
    resource Thunderblock.Resources.ClusterNode
    resource Thunderblock.Resources.DistributedState
    resource Thunderblock.Resources.LoadBalancingRule
    resource Thunderblock.Resources.RateLimitPolicy
    resource Thunderblock.Resources.SystemEvent

    # ThunderChief Orchestration (integrated into ThunderBlock)
    resource Thunderline.Thunderblock.Resources.WorkflowTracker

    # ThunderVault → ThunderBlock (storage & memory)
    resource Thunderline.Thunderblock.Resources.VaultAction
    resource Thunderline.Thunderblock.Resources.VaultAgent
    resource Thunderline.Thunderblock.Resources.VaultCacheEntry
    resource Thunderline.Thunderblock.Resources.VaultDecision
    resource Thunderline.Thunderblock.Resources.VaultEmbeddingVector
    resource Thunderline.Thunderblock.Resources.VaultExperience
    resource Thunderline.Thunderblock.Resources.VaultKnowledgeNode
    resource Thunderline.Thunderblock.Resources.VaultMemoryNode
    resource Thunderline.Thunderblock.Resources.VaultMemoryRecord
    resource Thunderline.Thunderblock.Resources.VaultQueryOptimization
    resource Thunderline.Thunderblock.Resources.VaultUser
    resource Thunderline.Thunderblock.Resources.VaultUserToken

  # PAC user personal construct home (moved from Thunderlink)
  resource Thunderline.Thunderblock.Resources.PACHome
  end
end
