defmodule Thunderline.Thunderblock.Domain do
  @moduledoc """
  ThunderBlock Ash Domain - Infrastructure & Storage

  **Boundary**: Exposes stateful capabilities, not business workflows

  Consolidated from: legacy "Thundervault" (storage, Postgres, Memento/Mnesia) -> now ThunderBlock Vault namespace (:thunderblock_vault)

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

  use Ash.Domain, extensions: [AshAdmin.Domain]

  alias Thunderline.Thunderblock.Resources.VaultKnowledgeNode

  # VaultKnowledgeNode relationship management functions
  defdelegate add_relationship!(
                node,
                target_node_id,
                relationship_type,
                relationship_strength,
                opts \\ []
              ),
              to: VaultKnowledgeNode

  defdelegate remove_relationship!(node, target_node_id, relationship_type, opts \\ []),
    to: VaultKnowledgeNode

  defdelegate consolidate_knowledge!(node, duplicate_node_ids, opts \\ []),
    to: VaultKnowledgeNode

  # VaultKnowledgeNode other operations
  defdelegate verify_knowledge!(node, verification_result, verification_evidence, opts \\ []),
    to: VaultKnowledgeNode

  defdelegate record_access!(node, access_type, user_context, opts \\ []),
    to: VaultKnowledgeNode

  defdelegate search_knowledge!(
                search_term,
                knowledge_domains,
                node_types,
                min_confidence \\ nil,
                opts \\ []
              ),
              to: VaultKnowledgeNode

  defdelegate traverse_graph!(
                start_node_id,
                relationship_types,
                max_depth,
                direction,
                opts \\ []
              ),
              to: VaultKnowledgeNode

  defdelegate by_domain!(knowledge_domain, opts \\ []),
    to: VaultKnowledgeNode

  defdelegate optimize_relationships!(opts \\ []),
    to: VaultKnowledgeNode

  defdelegate recalculate_metrics!(opts \\ []),
    to: VaultKnowledgeNode

  defdelegate cleanup_deprecated!(opts \\ []),
    to: VaultKnowledgeNode

  admin do
    show? true
  end

  resources do
    # Original ThunderBlock resources
    resource Thunderblock.Resources.ExecutionContainer
    resource Thunderblock.Resources.TaskOrchestrator
    resource Thunderblock.Resources.ZoneContainer
    resource Thunderblock.Resources.SupervisionTree

    # Renamed: Thunderblock.Resources.Community -> Thunderline.Thunderblock.Resources.ExecutionTenant
    resource Thunderline.Thunderblock.Resources.ExecutionTenant
    resource Thunderblock.Resources.ClusterNode
    resource Thunderblock.Resources.DistributedState
    resource Thunderblock.Resources.LoadBalancingRule
    resource Thunderblock.Resources.RateLimitPolicy
    resource Thunderblock.Resources.SystemEvent
    resource Thunderline.Thunderblock.Resources.RetentionPolicy

    # ThunderChief Orchestration (integrated into ThunderBlock)
    resource Thunderline.Thunderblock.Resources.WorkflowTracker

    # Legacy rename: ThunderVault → ThunderBlock (storage & memory) -> metrics & resources exposed as :thunderblock and :thunderblock_vault
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
