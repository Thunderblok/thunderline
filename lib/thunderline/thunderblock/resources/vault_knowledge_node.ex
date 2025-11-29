defmodule Thunderline.Thunderblock.Resources.VaultKnowledgeNode do
  @moduledoc """
  KnowledgeNode Resource - Memory Graph & Relationship Intelligence

  The neural network of Thunderline's knowledge system. Each KnowledgeNode represents
  a concept, entity, or knowledge cluster within the vast memory graph, forming the
  connective tissue that transforms isolated memories into interconnected wisdom.
  This is where understanding emerges from data.

  ## Core Responsibilities
  - Graph-based knowledge representation and relationships
  - Concept clustering and semantic grouping
  - Cross-domain knowledge linking and association
  - Knowledge consolidation and duplicate resolution
  - Hierar    # TODO: Fix fragment expression referencing relationship_data in Ash 3.x
    # read :find_contradictions do
    #   description "Find knowledge contradictions"
    #
    #   prepare fn query, _context ->
    #     query
    #     |> Ash.Query.filter(
    #       fragment("jsonb_array_length(?->'contradicts_nodes') > 0", relationship_data) and
    #       verification_status != :deprecated
    #     )
    #     |> Ash.Query.sort([evidence_strength: :desc])
    #   end
    # endedge organization and taxonomy
  - Intelligent knowledge discovery and traversal

  ## Knowledge Philosophy
  "Isolated facts are mere data. Connected knowledge becomes wisdom.
   The graph reveals what the mind cannot see alone."

  KnowledgeNodes form the synapses of Thunderline's collective intelligence,
  enabling the system to think, reason, and discover patterns across the
  entire federation's accumulated knowledge and experience.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins
  import Ash.Expr

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_knowledge_nodes"
    repo Thunderline.Repo

    references do
      # reference :audit_logs, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:node_type, :knowledge_domain], name: "knowledge_nodes_type_domain_idx"
      index [:verification_status, :centrality_score], name: "knowledge_nodes_verification_idx"
      index [:confidence_level, :evidence_strength], name: "knowledge_nodes_quality_idx"
      index [:indexing_status], name: "knowledge_nodes_indexing_idx"
      index "USING GIN (aliases)", name: "knowledge_nodes_aliases_idx"
      index "USING GIN (semantic_tags)", name: "knowledge_nodes_tags_idx"
      index "USING GIN (source_domains)", name: "knowledge_nodes_sources_idx"
      index "USING GIN (relationship_data)", name: "knowledge_nodes_relationships_idx"
      index "USING GIN (taxonomy_path)", name: "knowledge_nodes_taxonomy_idx"
      index "USING GIN (memory_record_ids)", name: "knowledge_nodes_memories_idx"
      index "USING GIN (embedding_vector_ids)", name: "knowledge_nodes_embeddings_idx"
    end

    check_constraints do
      check_constraint :valid_confidence, "confidence_level >= 0.0 AND confidence_level <= 1.0"
      check_constraint :valid_evidence, "evidence_strength >= 0.0 AND evidence_strength <= 1.0"
      check_constraint :valid_centrality, "centrality_score >= 0.0 AND centrality_score <= 1.0"
      check_constraint :valid_title_length, "char_length(title) > 0"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "knowledge_node"

    routes do
      base("/knowledge")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  # ===== CODE INTERFACE =====
  code_interface do
    define :create
    define :update
    define :add_relationship, args: [:target_node_id, :relationship_type, :relationship_strength]
    define :remove_relationship, args: [:target_node_id, :relationship_type]
    define :consolidate_knowledge, args: [:duplicate_node_ids]
    define :record_access, args: [:access_type, :user_context]
    define :verify_knowledge, args: [:verification_result, :verification_evidence]

    define :search_knowledge,
      args: [:search_term, :knowledge_domains, :node_types, :min_confidence]

    define :traverse_graph, args: [:start_node_id, :relationship_types, :max_depth, :direction]
    define :by_domain, args: [:knowledge_domain]
    # TODO: Comment out interface for commented-out actions
    # define :high_centrality, args: [:min_centrality]
    # define :find_related, args: [:node_id, :relationship_strength_threshold]
    # define :contradictions, action: :contradictions
    # define :taxonomy_level, args: [:taxonomy_path]
    define :optimize_relationships, action: :optimize_relationships
    define :recalculate_metrics, action: :recalculate_metrics
    define :cleanup_deprecated, action: :cleanup_deprecated
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new knowledge node"

      accept [
        :node_type,
        :title,
        :description,
        :aliases,
        :knowledge_domain,
        :source_domains,
        :confidence_level,
        :evidence_strength,
        :memory_record_ids,
        :embedding_vector_ids,
        :relationship_data,
        :semantic_tags,
        :temporal_data,
        :spatial_data,
        :taxonomy_path,
        :metadata,
        :verification_status,
        :indexing_status
      ]

      change fn changeset, _context ->
        current_time = DateTime.utc_now()
        temporal_data = Ash.Changeset.get_attribute(changeset, :temporal_data) || %{}

        updated_temporal =
          temporal_data
          |> Map.put("created_timestamp", current_time)
          |> Map.put("last_updated", current_time)

        changeset
        |> Ash.Changeset.change_attribute(:temporal_data, updated_temporal)
        |> Ash.Changeset.change_attribute(:indexing_status, :pending)
      end

      change after_action(fn _changeset, node, _context ->
               # Link to memory records and embeddings
               link_knowledge_resources(node)

               # Calculate initial graph metrics
               calculate_graph_metrics(node)

               # Schedule knowledge indexing
               schedule_knowledge_indexing(node)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thunderblock:knowledge",
                 {:knowledge_node_created,
                  %{
                    node_id: node.id,
                    node_type: node.node_type,
                    knowledge_domain: node.knowledge_domain
                  }}
               )

               {:ok, node}
             end)
    end

    update :update do
      description "Update knowledge node information"

      accept [
        :title,
        :description,
        :aliases,
        :knowledge_domain,
        :confidence_level,
        :evidence_strength,
        :relationship_data,
        :semantic_tags,
        :temporal_data,
        :spatial_data,
        :taxonomy_path,
        :metadata,
        :verification_status,
        :indexing_status
      ]

      require_atomic? false

      change fn changeset, _context ->
        temporal_data = Ash.Changeset.get_attribute(changeset, :temporal_data) || %{}
        updated_temporal = Map.put(temporal_data, "last_updated", DateTime.utc_now())

        changeset = Ash.Changeset.change_attribute(changeset, :temporal_data, updated_temporal)

        # Only set reindex_needed if user didn't explicitly provide indexing_status
        if Ash.Changeset.changing_attribute?(changeset, :indexing_status) do
          changeset
        else
          Ash.Changeset.change_attribute(changeset, :indexing_status, :reindex_needed)
        end
      end

      change after_action(fn _changeset, node, _context ->
               # Recalculate graph metrics
               calculate_graph_metrics(node)

               # Schedule reindexing
               schedule_knowledge_indexing(node)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thunderblock:knowledge",
                 {:knowledge_node_updated, %{node_id: node.id}}
               )

               {:ok, node}
             end)
    end

    update :add_relationship do
      description "Add relationship to another knowledge node"
      accept [:relationship_data]
      require_atomic? false

      argument :target_node_id, :uuid do
        allow_nil? false
      end

      argument :relationship_type, :string do
        allow_nil? false
        # constraints [one_of: ["parent", "child", "related", "contradicts", "supports",
        #                     "temporal_next", "causal_effect"]]
      end

      argument :relationship_strength, :decimal do
        default Decimal.new("1.0")
        constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
      end

      change fn changeset, _context ->
        target_id = Ash.Changeset.get_argument(changeset, :target_node_id)
        rel_type = Ash.Changeset.get_argument(changeset, :relationship_type)
        strength = Ash.Changeset.get_argument(changeset, :relationship_strength)

        current_relationships = Ash.Changeset.get_attribute(changeset, :relationship_data) || %{}

        # Add to appropriate relationship list
        relationship_key =
          case rel_type do
            "parent" -> "parent_nodes"
            "child" -> "child_nodes"
            "related" -> "related_nodes"
            "related_to" -> "related_nodes"
            "contradicts" -> "contradicts_nodes"
            "supports" -> "supports_nodes"
            "temporal_next" -> "temporal_next"
            "causal_effect" -> "causal_effects"
            # Default to related_nodes for unknown types
            _ -> "related_nodes"
          end

        current_list = Map.get(current_relationships, relationship_key, [])

        relationship_entry = %{
          "node_id" => target_id,
          "strength" => strength,
          "created_at" => DateTime.utc_now()
        }

        # Avoid duplicates
        updated_list =
          if Enum.any?(current_list, &(&1["node_id"] == target_id)) do
            current_list
          else
            [relationship_entry | current_list]
          end

        updated_relationships = Map.put(current_relationships, relationship_key, updated_list)

        Ash.Changeset.change_attribute(changeset, :relationship_data, updated_relationships)
      end

      change after_action(fn _changeset, node, _context ->
               # Recalculate graph metrics for affected nodes
               recalculate_network_metrics(node)
               {:ok, node}
             end)
    end

    update :remove_relationship do
      description "Remove relationship to another knowledge node"
      accept [:relationship_data]
      require_atomic? false

      argument :target_node_id, :uuid do
        allow_nil? false
      end

      argument :relationship_type, :string do
        allow_nil? false
      end

      change fn changeset, _context ->
        target_id = Ash.Changeset.get_argument(changeset, :target_node_id)
        rel_type = Ash.Changeset.get_argument(changeset, :relationship_type)

        current_relationships = Ash.Changeset.get_attribute(changeset, :relationship_data) || %{}

        relationship_key =
          case rel_type do
            "parent" -> "parent_nodes"
            "child" -> "child_nodes"
            "related" -> "related_nodes"
            "related_to" -> "related_nodes"
            "contradicts" -> "contradicts_nodes"
            "supports" -> "supports_nodes"
            "temporal_next" -> "temporal_next"
            "causal_effect" -> "causal_effects"
            # Default to related_nodes for unknown types
            _ -> "related_nodes"
          end

        current_list = Map.get(current_relationships, relationship_key, [])
        updated_list = Enum.reject(current_list, &(&1["node_id"] == target_id))

        updated_relationships = Map.put(current_relationships, relationship_key, updated_list)

        Ash.Changeset.change_attribute(changeset, :relationship_data, updated_relationships)
      end
    end

    update :consolidate_knowledge do
      description "Consolidate this node with other duplicate nodes"
      accept [:consolidation_data, :memory_record_ids, :embedding_vector_ids]
      require_atomic? false

      argument :duplicate_node_ids, {:array, :uuid} do
        allow_nil? false
      end

      change fn changeset, _context ->
        duplicate_ids = Ash.Changeset.get_argument(changeset, :duplicate_node_ids)

        current_consolidation = Ash.Changeset.get_attribute(changeset, :consolidation_data) || %{}
        current_memories = Ash.Changeset.get_attribute(changeset, :memory_record_ids) || []
        current_embeddings = Ash.Changeset.get_attribute(changeset, :embedding_vector_ids) || []

        # Merge data from duplicate nodes (this would fetch and merge their data)
        {merged_memories, merged_embeddings} = merge_duplicate_node_data(duplicate_ids)

        updated_consolidation =
          current_consolidation
          |> Map.put("consolidated_from", duplicate_ids)
          |> Map.put("consolidation_status", "consolidated")
          |> Map.put("consolidation_timestamp", DateTime.utc_now())

        changeset
        |> Ash.Changeset.change_attribute(:consolidation_data, updated_consolidation)
        |> Ash.Changeset.change_attribute(:memory_record_ids, current_memories ++ merged_memories)
        |> Ash.Changeset.change_attribute(
          :embedding_vector_ids,
          current_embeddings ++ merged_embeddings
        )
      end

      change after_action(fn changeset, node, _context ->
               # Mark duplicate nodes as consolidated
               duplicate_ids = Ash.Changeset.get_argument(changeset, :duplicate_node_ids)
               mark_nodes_as_duplicates(duplicate_ids, node.id)
               {:ok, node}
             end)
    end

    update :record_access do
      description "Record access to this knowledge node"
      accept [:access_patterns]
      require_atomic? false

      argument :access_type, :string do
        allow_nil? false
        # constraints [one_of: ["read", "search", "traverse", "query", "reference"]]
      end

      argument :user_context, :map, allow_nil?: true

      change fn changeset, _context ->
        access_type = Ash.Changeset.get_argument(changeset, :access_type)
        user_context = Ash.Changeset.get_argument(changeset, :user_context) || %{}

        current_patterns = Ash.Changeset.get_attribute(changeset, :access_patterns) || %{}
        access_count = Map.get(current_patterns, "access_count", 0) + 1

        updated_patterns =
          current_patterns
          |> Map.put("access_count", access_count)
          |> Map.put("last_accessed", DateTime.utc_now())
          |> Map.put("access_frequency", calculate_access_frequency(current_patterns))
          |> update_access_patterns(access_type, user_context)

        Ash.Changeset.change_attribute(changeset, :access_patterns, updated_patterns)
      end
    end

    update :verify_knowledge do
      description "Update verification status of knowledge node"
      accept [:verification_status, :knowledge_quality]
      require_atomic? false

      argument :verification_result, :atom do
        allow_nil? false
        # constraints [one_of: [:verified, :disputed, :deprecated]]
      end

      argument :verification_evidence, :map, allow_nil?: true

      change fn changeset, _context ->
        result = Ash.Changeset.get_argument(changeset, :verification_result)
        evidence = Ash.Changeset.get_argument(changeset, :verification_evidence) || %{}

        current_quality = Ash.Changeset.get_attribute(changeset, :knowledge_quality) || %{}

        # Update quality metrics based on verification
        updated_quality =
          case result do
            :verified ->
              current_quality
              |> Map.put("accuracy", 1.0)
              |> Map.put("currency", 1.0)
              |> Map.put("citation_count", Map.get(current_quality, "citation_count", 0) + 1)

            :disputed ->
              current_quality
              |> Map.put("accuracy", 0.5)
              |> Map.put("consistency", 0.5)

            :deprecated ->
              current_quality
              |> Map.put("currency", 0.0)
              |> Map.put("relevance", 0.0)
          end

        changeset
        |> Ash.Changeset.change_attribute(:verification_status, result)
        |> Ash.Changeset.change_attribute(:knowledge_quality, updated_quality)
      end
    end

    # Query actions
    read :search_knowledge do
      description "Search knowledge nodes by content and relationships"

      argument :search_term, :string do
        allow_nil? false
      end

      argument :knowledge_domains, {:array, :string}, allow_nil?: true
      argument :node_types, {:array, :atom}, allow_nil?: true
      argument :min_confidence, :decimal, allow_nil?: true

      # Comment out complex prepare function due to fragment expression issues
      # prepare fn query, context ->
      #   search_term = context.arguments.search_term
      #   domains = context.arguments.knowledge_domains
      #   types = context.arguments.node_types
      #   min_confidence = context.arguments.min_confidence

      #   # Text search across title, description, and semantic tags
      #   query = Ash.Query.filter(query,
      #     ilike(title, ^"%#{search_term}%") or
      #     ilike(description, ^"%#{search_term}%") or
      #     fragment("? && string_to_array(?, ' ')", semantic_tags, ^search_term)
      #   )

      #   query = if domains do
      #     Ash.Query.filter(query, knowledge_domain in ^domains)
      #   else
      #     query
      #   end

      #   query = if types do
      #     Ash.Query.filter(query, node_type in ^types)
      #   else
      #     query
      #   end

      #   query = if min_confidence do
      #     Ash.Query.filter(query, confidence_level >= ^min_confidence)
      #   else
      #     query
      #   end

      #   query
      #   |> Ash.Query.filter(verification_status != :deprecated)
      # end
    end

    read :traverse_graph do
      description "Traverse knowledge graph from a starting node"

      argument :start_node_id, :uuid do
        allow_nil? false
      end

      argument :relationship_types, {:array, :string}, allow_nil?: true
      argument :max_depth, :integer, default: 3

      argument :direction, :atom do
        default :both
        # constraints one_of: [:inbound, :outbound, :both]
      end

      prepare fn query, context ->
        start_id = context.arguments.start_node_id
        rel_types = context.arguments.relationship_types || ["parent", "child", "related"]
        max_depth = context.arguments.max_depth
        direction = context.arguments.direction

        # This would implement graph traversal logic
        # For now, return related nodes based on relationship data

        # TODO: Fix filter for Ash 3.x - commented out variable references
        # query
        # |> Ash.Query.filter(verification_status != :deprecated)
        # |> Ash.Query.sort([centrality_score: :desc])
        query
      end
    end

    read :by_domain do
      description "Get knowledge nodes by domain"

      argument :knowledge_domain, :string do
        allow_nil? false
      end

      filter expr(
               knowledge_domain == ^arg(:knowledge_domain) and verification_status != :deprecated
             )

      prepare build(sort: [centrality_score: :desc, confidence_level: :desc])
    end

    # TODO: Fix variable references in prepare block for Ash 3.x
    # read :high_centrality do
    #   description "Get highly central knowledge nodes"
    #
    #   argument :min_centrality, :decimal, default: Decimal.new("0.7")
    #
    #   prepare fn query, context ->
    #     min_centrality = context.arguments.min_centrality
    #     query
    #     |> Ash.Query.filter(
    #       centrality_score >= ^min_centrality and
    #       verification_status == :verified
    #     )
    #     |> Ash.Query.sort([centrality_score: :desc])
    #   end
    # end

    read :find_related do
      description "Find nodes related to a specific node"

      argument :node_id, :uuid do
        allow_nil? false
      end

      argument :relationship_strength_threshold, :decimal, default: Decimal.new("0.5")

      prepare fn query, context ->
        node_id = context.arguments.node_id
        # TODO: Fix filter for Ash 3.x - commented out variable references
        # query
        # |> Ash.Query.filter(verification_status != :deprecated)
        # |> Ash.Query.sort([centrality_score: :desc])
        query
      end
    end

    # TODO: Fix fragment expression referencing relationship_data in Ash 3.x
    # read :contradictions do
    #   description "Find knowledge contradictions"
    #
    #   prepare fn query, _context ->
    #     query
    #     |> Ash.Query.filter(
    #       fragment("jsonb_array_length(?->'contradicts_nodes') > 0", relationship_data) and
    #       verification_status != :deprecated
    #     )
    #     |> Ash.Query.sort([evidence_strength: :desc])
    #   end
    # end

    read :taxonomy_level do
      description "Get nodes at specific taxonomy level"

      argument :taxonomy_path, {:array, :string} do
        allow_nil? false
      end

      # TODO: Fix filter expression for Ash 3.x
      # filter expr(taxonomy_path == ^arg(:taxonomy_path) and verification_status != :deprecated)

      prepare build(sort: [:title])
    end

    # Maintenance actions
    update :optimize_relationships do
      description "Optimize knowledge relationships and remove weak connections"
      require_atomic? false

      filter expr(verification_status != :deprecated)

      change fn changeset, _context ->
        # This would implement relationship optimization logic
        Ash.Changeset.change_attribute(changeset, :indexing_status, :reindex_needed)
      end
    end

    update :recalculate_metrics do
      description "Recalculate knowledge node metrics"
      require_atomic? false
      filter expr(verification_status != :deprecated)

      change fn changeset, _context ->
        # This would recalculate centrality and other graph metrics
        changeset
      end
    end

    destroy :cleanup_deprecated do
      description "Remove deprecated knowledge nodes"
      require_atomic? false

      filter expr(verification_status == :deprecated and updated_at < ago(90, :day))

      change after_action(fn _changeset, nodes, _context ->
               for node <- nodes do
                 cleanup_knowledge_references(node)
               end

               {:ok, nodes}
             end)
    end
  end

  # ===== POLICIES =====
  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Create: Tenant-scoped or system
    policy action_type(:create) do
      authorize_if expr(not is_nil(^actor(:tenant_id)))
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end

    # Read: Tenant isolation with global admin access
    policy action_type(:read) do
      authorize_if expr(tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :admin and ^actor(:scope) == :global)
      authorize_if expr(^actor(:role) == :system)
    end

    # Update: Tenant + unlocked verification status
    policy action_type(:update) do
      authorize_if expr(
                     tenant_id == ^actor(:tenant_id) and
                       verification_status != :locked
                   )

      authorize_if expr(^actor(:role) == :admin and tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end

    # Destroy: Admin within tenant or system
    policy action_type(:destroy) do
      authorize_if expr(tenant_id == ^actor(:tenant_id) and ^actor(:role) == :admin)
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end

    # Graph operations: Tenant-scoped with system override
    # System actors bypass all tenant restrictions
    bypass expr(^actor(:role) == :system) do
      authorize_if always()
    end

    policy action(:add_relationship) do
      # Regular users: forbid if not in same tenant as source
      forbid_unless expr(tenant_id == ^actor(:tenant_id))

      # Regular users: forbid if target not in same tenant as source
      forbid_unless Thunderline.Thunderblock.Resources.VaultKnowledgeNode.Checks.TargetNodeSameTenant

      # If both checks pass, authorize
      authorize_if always()
    end

    policy action(:remove_relationship) do
      authorize_if expr(tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :admin and tenant_id == ^actor(:tenant_id))
    end

    policy action(:traverse_graph) do
      authorize_if expr(tenant_id == ^actor(:tenant_id))
      authorize_if expr(^actor(:role) == :system)
    end

    # Search: Tenant-scoped with system access
    policy action(:search_knowledge) do
      authorize_if expr(not is_nil(^actor(:tenant_id)))
      authorize_if expr(^actor(:role) == :system)
    end

    # Knowledge management: Admin or system only
    policy action(:consolidate_knowledge) do
      authorize_if expr(tenant_id == ^actor(:tenant_id) and ^actor(:role) == :admin)
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end

    policy action(:verify_knowledge) do
      authorize_if expr(tenant_id == ^actor(:tenant_id) and ^actor(:role) in [:admin, :curator])
      authorize_if expr(^actor(:role) == :system)
    end

    # Access tracking: Any authenticated user
    policy action(:record_access) do
      authorize_if expr(not is_nil(^actor(:id)))
    end

    # System maintenance: System role only
    policy action(:optimize_relationships) do
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end

    policy action(:recalculate_metrics) do
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end

    policy action(:cleanup_deprecated) do
      authorize_if expr(^actor(:role) == :system and ^actor(:scope) == :maintenance)
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    # Removed load preparation - :memory_records and :embedding_vectors relationships don't exist

    # System actors with maintenance scope can bypass tenant isolation for all read operations
    prepare Thunderline.Thunderblock.Resources.VaultKnowledgeNode.Preparations.RemoveTenantFilterForSystem,
      on: [:read]
  end

  # ===== VALIDATIONS =====
  validations do
    validate present([:node_type, :title, :knowledge_domain])

    # (Legacy validation hooks retained for reference - original Thundervault module names commented out)
    # validate {ThunderblockVault.Validations, :valid_relationship_structure}, on: [:create, :update]
    # validate {ThunderblockVault.Validations, :valid_taxonomy_path}, on: [:create, :update]
  end

  # ===== MULTITENANCY CONFIGURATION =====
  multitenancy do
    strategy :attribute
    attribute :tenant_id

    # Allow global queries (tenant optional) - tenant isolation enforced via policies for non-system actors
    global? true
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :tenant_id, :uuid do
      allow_nil? false
      description "Owning tenant for knowledge isolation"
      public? false
    end

    attribute :node_type, :atom do
      allow_nil? false
      description "Type of knowledge node"
      default :concept

      constraints one_of: [
                    :concept,
                    :entity,
                    :relationship,
                    :cluster,
                    :taxonomy,
                    :pattern,
                    :rule,
                    :hypothesis,
                    :insight,
                    :contradiction
                  ]
    end

    attribute :title, :string do
      allow_nil? false
      description "Primary title or name of the knowledge node"
      constraints min_length: 1, max_length: 500
    end

    attribute :description, :string do
      allow_nil? true
      description "Detailed description of the knowledge node"
      constraints max_length: 5000
    end

    attribute :aliases, {:array, :string} do
      allow_nil? false
      description "Alternative names and synonyms"
      default []
    end

    attribute :knowledge_domain, :string do
      allow_nil? false
      description "Primary knowledge domain or category"
      # constraints [one_of: ["general", "technical", "social", "temporal", "spatial",
      #                     "causal", "procedural", "declarative", "episodic", "semantic"]]
    end

    attribute :source_domains, {:array, :string} do
      allow_nil? false
      description "Thunderline domains contributing to this knowledge"
      default []
    end

    attribute :confidence_level, :decimal do
      allow_nil? false
      description "Confidence in the knowledge accuracy (0.0 to 1.0)"
      default Decimal.new("1.0")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :evidence_strength, :decimal do
      allow_nil? false
      description "Strength of supporting evidence (0.0 to 1.0)"
      default Decimal.new("1.0")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :centrality_score, :decimal do
      allow_nil? false
      description "Importance within the knowledge graph (0.0 to 1.0)"
      default Decimal.new("0.5")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :memory_record_ids, {:array, :uuid} do
      allow_nil? false
      description "Associated memory records providing evidence"
      default []
    end

    attribute :embedding_vector_ids, {:array, :uuid} do
      allow_nil? false
      description "Associated embedding vectors for semantic similarity"
      default []
    end

    attribute :relationship_data, :map do
      allow_nil? false
      description "Relationships to other knowledge nodes"
      # Broader concepts
      default %{
        "parent_nodes" => [],

        # More specific concepts
        "child_nodes" => [],

        # Peer concepts
        "related_nodes" => [],

        # Contradictory concepts
        "contradicts_nodes" => [],

        # Supporting concepts
        "supports_nodes" => [],

        # Sequential knowledge
        "temporal_next" => [],

        # Cause-effect relationships
        "causal_effects" => []
      }
    end

    attribute :semantic_tags, {:array, :string} do
      allow_nil? false
      description "Semantic tags for categorization and discovery"
      default []
    end

    attribute :temporal_data, :map do
      allow_nil? false
      description "Temporal aspects of the knowledge"

      default %{
        "created_timestamp" => nil,
        "last_updated" => nil,
        "validity_period" => nil,
        "temporal_context" => nil,
        "historical_versions" => []
      }
    end

    attribute :spatial_data, :map do
      allow_nil? false
      description "Spatial or contextual location information"

      default %{
        "coordinates" => nil,
        "regions" => [],
        "domains" => [],
        "scope" => "global"
      }
    end

    attribute :graph_metrics, :map do
      allow_nil? false
      description "Graph analysis metrics"

      default %{
        "degree_centrality" => 0.0,
        "betweenness_centrality" => 0.0,
        "clustering_coefficient" => 0.0,
        "pagerank_score" => 0.0,
        "connected_components" => 1
      }
    end

    attribute :knowledge_quality, :map do
      allow_nil? false
      description "Quality assessment metrics"

      default %{
        "completeness" => 0.0,
        "consistency" => 1.0,
        "currency" => 1.0,
        "accuracy" => 1.0,
        "relevance" => 1.0,
        "citation_count" => 0
      }
    end

    attribute :consolidation_data, :map do
      allow_nil? false
      description "Knowledge consolidation and deduplication info"

      default %{
        "consolidated_from" => [],
        "duplicate_candidates" => [],
        "consolidation_status" => "active",
        "merge_history" => []
      }
    end

    attribute :discovery_data, :map do
      allow_nil? false
      description "Knowledge discovery and emergence tracking"

      default %{
        "discovery_method" => "manual",
        "discovery_confidence" => 1.0,
        "discovery_sources" => [],
        "emergence_patterns" => []
      }
    end

    attribute :access_patterns, :map do
      allow_nil? false
      description "Usage and access pattern analysis"

      default %{
        "access_count" => 0,
        "last_accessed" => nil,
        "access_frequency" => 0.0,
        "query_patterns" => [],
        "user_interactions" => []
      }
    end

    attribute :verification_status, :atom do
      allow_nil? false
      description "Knowledge verification and validation status"
      default :unverified
      constraints one_of: [:unverified, :pending, :verified, :disputed, :deprecated, :archived]
    end

    attribute :indexing_status, :atom do
      allow_nil? false
      description "Graph indexing and search status"
      default :pending
      constraints one_of: [:pending, :indexing, :indexed, :reindex_needed, :index_failed]
    end

    attribute :taxonomy_path, {:array, :string} do
      allow_nil? false
      description "Hierarchical taxonomy classification path"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional flexible metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ===== RELATIONSHIPS =====
  relationships do
    # has_many :audit_logs, Thunderline.Thunderblock.Resources.VaultAuditLog do
    #   source_attribute :id
    #   destination_attribute :knowledge_node_id
    # end
  end

  # ===== OBAN CONFIGURATION =====
  # oban do
  #   # Graph metrics calculation
  #   trigger :calculate_graph_metrics do
  #     action :recalculate_metrics
  #     schedule "0 5 * * *"  # Daily at 5 AM
  #   end

  #   # Relationship optimization
  #   trigger :optimize_knowledge_relationships do
  #     action :optimize_relationships
  #     schedule "0 6 * * *"  # Daily at 6 AM
  #   end

  #   # Cleanup deprecated nodes
  #   trigger :cleanup_deprecated_knowledge do
  #     action :cleanup_deprecated
  #     schedule "0 3 * * *"  # Daily at 3 AM
  #   end
  # end

  # ===== IDENTITIES =====
  identities do
    identity :unique_title_domain, [:title, :knowledge_domain]
  end

  # ===== PRIVATE FUNCTIONS =====
  defp link_knowledge_resources(_node) do
    # Link memory records and embedding vectors
    :ok
  end

  defp calculate_graph_metrics(_node) do
    # Calculate centrality and other graph metrics
    :ok
  end

  defp schedule_knowledge_indexing(_node) do
    # Schedule knowledge indexing job
    :ok
  end

  defp recalculate_network_metrics(_node) do
    # Recalculate metrics for connected nodes
    :ok
  end

  defp merge_duplicate_node_data(_duplicate_ids) do
    # Merge data from duplicate nodes
    {[], []}
  end

  defp mark_nodes_as_duplicates(_node_ids, _consolidated_into_id) do
    # Mark nodes as consolidated duplicates
    :ok
  end

  defp calculate_access_frequency(_access_patterns) do
    # Calculate access frequency metric
    0.0
  end

  defp update_access_patterns(patterns, _access_type, _user_context) do
    # Update access pattern tracking
    patterns
  end

  defp cleanup_knowledge_references(_node) do
    # Clean up references to deleted knowledge node
    :ok
  end
end
