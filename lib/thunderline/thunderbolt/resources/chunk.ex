defmodule Thunderline.Thunderbolt.Resources.Chunk do
  @moduledoc """
  Chunk Resource - 144-bit Thunderbit mesh management

  Each chunk represents a hexagonal mesh of exactly 144 Thunderbits.
  Provides coordination, resource management, and lifecycle control
  for the distributed automata system.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource, AshOban.Resource, AshGraphql.Resource]

  # IN-MEMORY CONFIGURATION (sqlite removed)
  # Using :embedded data layer

  json_api do
    type "chunk"

    routes do
      base("/chunks")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
      get :chunk_status, route: "/:id/status"
      patch(:activate, route: "/:id/activate")
      patch(:begin_optimization, route: "/:id/optimize")
    end
  end

  graphql do
    type :chunk

    queries do
      get :get_chunk, :read
      list :list_chunks, :read
    end

    mutations do
      create :create_chunk, :create
      update :update_chunk, :update
      update :activate_chunk, :activate
      update :optimize_chunk, :begin_optimization
    end
  end

  # TODO: MCP Tool exposure for external orchestration
  # This would need proper AshAi tool definition
  def get_chunk_status(chunk) do
    %{
      id: chunk.id,
      region: chunk.region,
      active_count: chunk.active_count,
      dormant_count: chunk.dormant_count,
      health_status: chunk.health_status,
      resource_usage: chunk.resource_allocation
    }
  end

  # TODO: MCP Tool for chunk activation
  def activate_chunk_tool(chunk, params) do
    Ash.Changeset.for_update(chunk, :activate, params)
    |> Ash.update!()
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    # ============================================================================
    # STATE MACHINE ACTIONS - CHUNK LIFECYCLE ORCHESTRATION
    # ============================================================================

    # Initialization actions
    create :create_for_region do
      accept [:start_q, :start_r, :end_q, :end_r, :z_level, :total_capacity]

      # TODO: Fix function reference escaping
      # change before_action(&calculate_chunk_boundaries/1)
      # TODO: Fix function reference escaping
      # change after_action(&initialize_chunk_supervisor/2)
      # TODO: Fix function reference escaping
      # change after_action(&subscribe_to_thundercore_pulse/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :initialize do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:dormant)
      # TODO: Fix function reference escaping
      # change before_action(&validate_initialization_requirements/1)
      # TODO: Fix function reference escaping
      # change after_action(&complete_chunk_initialization/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Core operational state transitions
    update :activate do
      require_atomic? false
      accept [:active_count, :resource_allocation]

      # TODO: Fix state machine integration
      # change transition_state(:active)
      # TODO: Fix function reference escaping
      # change after_action(&finalize_activation/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :deactivate do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:deactivating)
      # TODO: Fix function reference escaping
      # change before_action(&prepare_deactivation/1)
      # TODO: Fix function reference escaping
      # change after_action(&start_deactivation_process/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :deactivation_complete do
      require_atomic? false
      accept [:active_count]

      # TODO: Fix state machine integration
      # change transition_state(:dormant)
      # TODO: Fix function reference escaping
      # change after_action(&finalize_deactivation/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Optimization state transitions
    update :begin_optimization do
      require_atomic? false
      description "Begin chunk optimization"
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:optimizing)
      # TODO: Fix function reference escaping
      # change before_action(&prepare_optimization/1)
      # TODO: Fix function reference escaping
      # change after_action(&start_optimization_process/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :optimization_complete do
      require_atomic? false
      accept [:optimization_score, :resource_allocation]

      # TODO: Fix state machine integration
      # change transition_state(fn changeset, context ->
      #   # Transition back to original state or stay optimized based on conditions
      #   case get_change(changeset, :optimization_score) do
      #     score when is_nil(score) or score < Decimal.new("0.8") -> :active
      #     _ -> :dormant
      #   end
      # end)
      # TODO: Fix DateTime.utc_now function reference
      # change set_attribute(:last_optimization, &DateTime.utc_now/0)
      # TODO: Fix function reference escaping
      # change after_action(&apply_optimization_changes/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Maintenance state transitions
    update :enter_maintenance do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:maintenance)
      # TODO: Fix function reference escaping
      # change before_action(&prepare_maintenance_mode/1)
      # TODO: Fix function reference escaping
      # change after_action(&start_maintenance_procedures/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :exit_maintenance do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:dormant)
      # TODO: Fix function reference escaping
      # change after_action(&complete_maintenance_procedures/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Scaling state transitions
    update :begin_scaling do
      require_atomic? false
      accept [:total_capacity]

      # TODO: Fix state machine integration
      # change transition_state(:scaling)
      # TODO: Fix function reference escaping
      # change before_action(&prepare_scaling_operation/1)
      # TODO: Fix function reference escaping
      # change after_action(&start_scaling_process/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :scaling_complete do
      require_atomic? false
      accept [:total_capacity, :resource_allocation]

      # TODO: Fix state machine integration
      # change transition_state(fn changeset, context ->
      #   # Return to active if was active, otherwise dormant
      #   case Map.get(context, :previous_state, :dormant) do
      #     :active -> :active
      #     _ -> :dormant
      #   end
      # end)
      # TODO: Fix function reference escaping
      # change after_action(&finalize_scaling_operation/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Failure and recovery
    update :recover do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:dormant)
      # TODO: Fix function reference escaping
      # change before_action(&validate_recovery_conditions/1)
      # TODO: Fix function reference escaping
      # change after_action(&complete_recovery_process/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :force_reset do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:initializing)
      # TODO: Fix function reference escaping
      # change before_action(&prepare_force_reset/1)
      # TODO: Fix function reference escaping
      # change after_action(&complete_force_reset/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Emergency operations
    update :emergency_stop do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:emergency_stopped)
      # TODO: Fix function reference escaping
      # change after_action(&execute_emergency_stop/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :emergency_recover do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:dormant)
      # TODO: Fix function reference escaping
      # change after_action(&complete_emergency_recovery/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Shutdown operations
    update :begin_shutdown do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:shutting_down)
      # TODO: Fix function reference escaping
      # change before_action(&prepare_shutdown/1)
      # TODO: Fix function reference escaping
      # change after_action(&start_shutdown_process/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    update :shutdown_complete do
      require_atomic? false
      accept []

      # TODO: Fix state machine integration
      # change transition_state(:destroyed)
      # TODO: Fix function reference escaping
      # change after_action(&finalize_shutdown/2)
      # TODO: Fix function reference escaping
      # change after_action(&create_orchestration_event/2)
    end

    # Health and status updates (non-state-changing)
    update :update_health do
      accept [:health_status, :resource_allocation]
      # TODO: Fix function reference escaping
      # change after_action(&broadcast_health_update/2)
    end

    read :chunk_status do
      get? true

      prepare build(
                load: [
                  :chunk_health_records,
                  :activation_rules,
                  :region,
                  :utilization_percentage,
                  :activation_ratio
                ]
              )
    end

    read :chunks_by_region do
      argument :start_q, :integer, allow_nil?: false
      argument :start_r, :integer, allow_nil?: false
      argument :end_q, :integer, allow_nil?: false
      argument :end_r, :integer, allow_nil?: false
      argument :z_level, :integer, default: 0

      filter expr(
               start_q >= ^arg(:start_q) and start_r >= ^arg(:start_r) and
                 end_q <= ^arg(:end_q) and end_r <= ^arg(:end_r) and
                 z_level == ^arg(:z_level)
             )
    end

    read :active_chunks do
      filter expr(health_status in [:healthy, :degraded])
    end

    read :chunks_needing_optimization do
      filter expr(
               is_nil(last_optimization) or
                 (last_optimization < ago(5, :minute) and
                    health_status == :healthy and
                    optimization_score < 0.7)
             )
    end
  end

  attributes do
    uuid_primary_key :id

    # Hex region coordinates
    attribute :start_q, :integer, allow_nil?: false
    attribute :start_r, :integer, allow_nil?: false
    attribute :end_q, :integer, allow_nil?: false
    attribute :end_r, :integer, allow_nil?: false
    attribute :z_level, :integer, default: 0

    # Chunk statistics
    attribute :active_count, :integer, default: 0
    attribute :dormant_count, :integer, default: 0

    # 64x64 default

    attribute :total_capacity, :integer, default: 4096

    # Resource management
    attribute :resource_allocation, :map,
      default: %{
        cpu: 0.0,
        memory: "0MB",
        network_throughput: "0KB/s"
      }

    # Health status (separate from state machine)
    attribute :health_status, :atom,
      constraints: [
        one_of: [:healthy, :degraded, :critical, :offline]
      ],
      default: :healthy

    # Orchestration metadata
    attribute :activation_triggers, {:array, :atom},
      default: [
        :high_energy,
        :external_request,
        :neighbor_activity
      ]

    attribute :optimization_score, :decimal, default: Decimal.new("0.5")
    attribute :last_optimization, :utc_datetime

    # Integration fields
    attribute :cluster_node, :string
    attribute :thundercore_subscription, :boolean, default: true

    timestamps()
  end

  # ============================================================================
  # STATE MACHINE - CHUNK LIFECYCLE ORCHESTRATION
  # ============================================================================
  # TODO: Fix AshStateMachine DSL syntax
  # state_machine do
  #   initial_states [:initializing]
  #   default_initial_state :initializing
  #
  #   transitions do
  #     # Initialization flow
  #     transition :initialize, from: :initializing, to: [:dormant, :failed]
  #
  #     # Core operational transitions
  #     transition :activate, from: [:dormant, :optimizing], to: [:active, :activating]
  #     transition :activation_complete, from: :activating, to: [:active, :failed]
  #     transition :deactivate, from: :active, to: [:dormant, :deactivating]
  #     transition :deactivation_complete, from: :deactivating, to: [:dormant, :failed]
  #
  #     # Optimization flow
  #     transition :begin_optimization, from: [:active, :dormant], to: [:optimizing, :failed]
  #     transition :optimization_complete, from: :optimizing, to: [:active, :dormant, :failed]
  #
  #     # Maintenance and recovery
  #     transition :enter_maintenance, from: [:active, :dormant, :optimizing], to: [:maintenance, :failed]
  #     transition :exit_maintenance, from: :maintenance, to: [:dormant, :failed]
  #
  #     # Scaling operations
  #     transition :begin_scaling, from: [:active, :dormant], to: [:scaling, :failed]
  #     transition :scaling_complete, from: :scaling, to: [:active, :dormant, :failed]
  #
  #     # Failure handling
  #     transition :recover, from: :failed, to: [:dormant, :failed]
  #     transition :force_reset, from: [:failed, :maintenance], to: :initializing
  #
  #     # Shutdown flow
  #     transition :begin_shutdown, from: [:dormant, :active, :optimizing, :maintenance, :failed], to: [:shutting_down, :failed]
  #     transition :shutdown_complete, from: :shutting_down, to: :destroyed
  #
  #     # Emergency transitions
  #     transition :emergency_stop, from: :any, to: :emergency_stopped
  #     transition :emergency_recover, from: :emergency_stopped, to: [:dormant, :failed]
  #   end
  # end

  relationships do
    has_many :chunk_health_records, Thunderline.Thunderbolt.Resources.ChunkHealth
    has_many :activation_rules, Thunderline.Thunderbolt.Resources.ActivationRule
    has_many :orchestration_events, Thunderline.Thunderbolt.Resources.OrchestrationEvent
  end

  calculations do
    calculate :region, :string, expr("#{start_q},#{start_r} to #{end_q},#{end_r} (z:#{z_level})")

    calculate :utilization_percentage,
              :decimal,
              expr((active_count + dormant_count) / total_capacity * 100)

    calculate :activation_ratio,
              :decimal,
              expr(
                if(
                  active_count + dormant_count > 0,
                  active_count / (active_count + dormant_count) * 100,
                  0
                )
              )
  end

  # TODO: Fix Oban trigger configuration
  # oban do
  #   triggers do
  #     trigger :chunk_health_check do
  #       action :update_health
  #       schedule "*/1 * * * *"  # Every minute
  #       where expr(status in [:active, :degraded])
  #     end
  #   end
  # end

  # TODO: Fix notifications configuration
  # notifications do
  #   publish :chunk_created, ["thunderbolt:chunk:created", :id]
  #   publish :chunk_activated, ["thunderbolt:chunk:activated", :id]
  #   publish :chunk_optimized, ["thunderbolt:chunk:optimized", :id]
  #   publish :chunk_health_updated, ["thunderbolt:chunk:health", :id]
  # end

  # ============================================================================
  # STATE MACHINE ACTION IMPLEMENTATIONS
  # ============================================================================

  # Initialization implementations
  defp validate_initialization_requirements(changeset) do
    # Validate that chunk has required attributes for initialization
    changeset
  end

  defp complete_chunk_initialization(_changeset, chunk) do
    # Initialize chunk resources and establish connections
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:initialized",
      {:chunk_initialized, chunk.id}
    )

    {:ok, chunk}
  end

  # Activation implementations
  defp prepare_activation(changeset) do
    # Pre-activation validation and preparation
    changeset
  end

  defp start_activation_process(_changeset, chunk) do
    # Start the activation process for Thunderbits in this chunk
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:activating",
      {:chunk_activating, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_activation(_changeset, chunk) do
    # Complete activation process and notify systems
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:activated",
      {:chunk_activated, chunk.id, chunk.active_count}
    )

    {:ok, chunk}
  end

  # Deactivation implementations
  defp prepare_deactivation(changeset) do
    # Pre-deactivation validation
    changeset
  end

  defp start_deactivation_process(_changeset, chunk) do
    # Start the deactivation process
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:deactivating",
      {:chunk_deactivating, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_deactivation(_changeset, chunk) do
    # Complete deactivation and cleanup
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:deactivated",
      {:chunk_deactivated, chunk.id}
    )

    {:ok, chunk}
  end

  # Optimization implementations
  defp start_optimization_process(_changeset, chunk) do
    # Begin optimization procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:optimizing",
      {:chunk_optimizing, chunk.id}
    )

    {:ok, chunk}
  end

  defp apply_optimization_changes(_changeset, chunk) do
    # Apply calculated optimizations
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:optimized",
      {:chunk_optimized, chunk.id, chunk.optimization_score}
    )

    {:ok, chunk}
  end

  # Maintenance implementations
  defp prepare_maintenance_mode(changeset) do
    # Prepare for maintenance operations
    changeset
  end

  defp start_maintenance_procedures(_changeset, chunk) do
    # Begin maintenance procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:maintenance",
      {:chunk_maintenance_started, chunk.id}
    )

    {:ok, chunk}
  end

  defp complete_maintenance_procedures(_changeset, chunk) do
    # Complete maintenance and return to service
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:maintenance_complete",
      {:chunk_maintenance_complete, chunk.id}
    )

    {:ok, chunk}
  end

  # Scaling implementations
  defp prepare_scaling_operation(changeset) do
    # Prepare for scaling operation
    changeset
  end

  defp start_scaling_process(_changeset, chunk) do
    # Begin scaling procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:scaling",
      {:chunk_scaling_started, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_scaling_operation(_changeset, chunk) do
    # Complete scaling operation
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:scaled",
      {:chunk_scaled, chunk.id, chunk.total_capacity}
    )

    {:ok, chunk}
  end

  # Recovery implementations
  defp validate_recovery_conditions(changeset) do
    # Validate that recovery is possible
    changeset
  end

  defp complete_recovery_process(_changeset, chunk) do
    # Complete recovery procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:recovered",
      {:chunk_recovered, chunk.id}
    )

    {:ok, chunk}
  end

  defp prepare_force_reset(changeset) do
    # Prepare for force reset operation
    changeset
  end

  defp complete_force_reset(_changeset, chunk) do
    # Complete force reset
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:force_reset",
      {:chunk_force_reset, chunk.id}
    )

    {:ok, chunk}
  end

  # Emergency implementations
  defp execute_emergency_stop(_changeset, chunk) do
    # Execute emergency stop procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:emergency_stop",
      {:chunk_emergency_stop, chunk.id}
    )

    {:ok, chunk}
  end

  defp complete_emergency_recovery(_changeset, chunk) do
    # Complete emergency recovery
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:emergency_recovered",
      {:chunk_emergency_recovered, chunk.id}
    )

    {:ok, chunk}
  end

  # Shutdown implementations
  defp prepare_shutdown(changeset) do
    # Prepare for graceful shutdown
    changeset
  end

  defp start_shutdown_process(_changeset, chunk) do
    # Begin shutdown procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:shutting_down",
      {:chunk_shutting_down, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_shutdown(_changeset, chunk) do
    # Complete shutdown and cleanup
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:destroyed",
      {:chunk_destroyed, chunk.id}
    )

    {:ok, chunk}
  end

  # Legacy implementations (preserved)
  defp calculate_chunk_boundaries(changeset) do
    # Hex coordinate validation and boundary calculation
    changeset
  end

  defp initialize_chunk_supervisor(_changeset, chunk) do
    # Start dedicated supervisor for this chunk
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:supervisor_started",
      {:chunk_supervisor_started, chunk.id}
    )

    {:ok, chunk}
  end

  defp subscribe_to_thundercore_pulse(_changeset, chunk) do
    if chunk.thundercore_subscription do
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "thundercore:pulse")
    end

    {:ok, chunk}
  end

  defp create_orchestration_event(_changeset, chunk) do
    # Create orchestration event record through Ash
    try do
      Thunderline.Thunderbolt.Resources.OrchestrationEvent
      |> Ash.Changeset.for_create(:create, %{
        event_type: "chunk_state_transition",
        event_data: %{
          chunk_id: chunk.id,
          state: chunk.state,
          timestamp: DateTime.utc_now()
        },
        source: "chunk_resource",
        node_name: node()
      })
      |> Ash.create!(domain: Thunderbolt.Domain)
    rescue
      # Gracefully handle event creation failures
      _error -> :ok
    end

    {:ok, chunk}
  end

  defp calculate_optimization_score(changeset) do
    # ML-based optimization scoring (placeholder)
    # In real implementation, would use metrics to calculate optimization score
    # Default score
    score = Decimal.new("0.8")
    Ash.Changeset.change_attribute(changeset, :optimization_score, score)
  end

  defp broadcast_health_update(_changeset, chunk) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:health_updated",
      {:chunk_health_updated, chunk.id, chunk.health_status}
    )

    {:ok, chunk}
  end

  # Keep list of strategic private hooks (names only to avoid compile capture ordering)
  @_keep [
    :complete_chunk_initialization,
    :apply_optimization_changes,
    :complete_maintenance_procedures,
    :complete_recovery_process,
    :complete_force_reset,
    :execute_emergency_stop,
    :complete_emergency_recovery,
    :calculate_chunk_boundaries,
    :create_orchestration_event,
    :calculate_optimization_score,
    :broadcast_health_update
  ]
  def __silence_unused__, do: :ok
end
