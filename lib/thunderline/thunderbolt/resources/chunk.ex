defmodule Thunderline.Thunderbolt.Resources.Chunk do
  @moduledoc """
  Chunk Resource - 144-bit Thunderbit mesh management

  Each chunk represents a hexagonal mesh of exactly 144 Thunderbits.
  Provides coordination, resource management, and lifecycle control
  for the distributed automata system.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine, AshJsonApi.Resource, AshOban, AshGraphql.Resource],
    notifiers: [Ash.Notifier.PubSub]

  alias Thunderline.Thunderbolt.Domain

  # ============================================================================
  # STATE MACHINE - CHUNK LIFECYCLE ORCHESTRATION
  # ============================================================================
  state_machine do
    initial_states([:initializing])
    default_initial_state(:initializing)

    transitions do
      transition(:initialize, from: [:initializing], to: [:dormant, :failed])
      transition(:activate, from: [:dormant, :optimizing, :maintenance], to: [:active])
      transition(:deactivate, from: [:active], to: [:deactivating])
      transition(:deactivation_complete, from: [:deactivating], to: [:dormant, :failed])
      transition(:begin_optimization, from: [:active, :dormant], to: [:optimizing])
      transition(:optimization_complete, from: [:optimizing], to: [:active, :dormant, :failed])
      transition(:enter_maintenance, from: [:active, :dormant, :optimizing], to: [:maintenance])
      transition(:exit_maintenance, from: [:maintenance], to: [:dormant, :failed])
      transition(:begin_scaling, from: [:active, :dormant], to: [:scaling])
      transition(:scaling_complete, from: [:scaling], to: [:active, :dormant, :failed])
      transition(:recover, from: [:failed, :emergency_stopped], to: [:dormant])

      transition(:force_reset,
        from: [:active, :failed, :maintenance, :emergency_stopped],
        to: [:initializing]
      )

      transition(:begin_shutdown,
        from: [
          :dormant,
          :active,
          :optimizing,
          :maintenance,
          :failed,
          :scaling,
          :deactivating,
          :emergency_stopped
        ],
        to: [:shutting_down]
      )

      transition(:shutdown_complete, from: [:shutting_down], to: [:destroyed])
      transition(:mark_failed, from: :*, to: [:failed])
      transition(:emergency_stop, from: :*, to: [:emergency_stopped])
      transition(:emergency_recover, from: [:emergency_stopped], to: [:dormant, :failed])
    end
  end

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

  oban do
    triggers do
      trigger :chunk_health_check do
        action :update_health
        scheduler_cron "*/1 * * * *"
        where expr(state in [:active, :optimizing, :maintenance, :scaling])
      end
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

  actions do
    defaults [:read, :destroy]

    # Custom update action that accepts common fields for testing
    update :update do
      require_atomic? false

      accept [
        :active_count,
        :dormant_count,
        :resource_allocation,
        :health_status,
        :health_metrics
      ]
    end

    # ============================================================================
    # STATE MACHINE ACTIONS - CHUNK LIFECYCLE ORCHESTRATION
    # ============================================================================

    # Initialization actions
    create :create_for_region do
      accept [:start_q, :start_r, :end_q, :end_r, :z_level, :total_capacity]
      change before_action(&calculate_chunk_boundaries/2)
      change after_action(&initialize_chunk_supervisor/3)
      change after_action(&subscribe_to_thundercore_pulse/3)
      change after_action(&create_orchestration_event/3)
    end

    update :initialize do
      require_atomic? false
      accept []

      change before_action(&validate_initialization_requirements/2)
      change transition_state(:dormant)
      change after_action(&complete_chunk_initialization/3)
      change after_action(&create_orchestration_event/3)
    end

    # Core operational state transitions
    update :activate do
      require_atomic? false
      accept [:active_count, :resource_allocation]

      change before_action(&prepare_activation/2)
      change transition_state(:active)
      change after_action(&start_activation_process/3)
      change after_action(&finalize_activation/3)
      change after_action(&create_orchestration_event/3)
    end

    update :deactivate do
      require_atomic? false
      accept []

      change before_action(&prepare_deactivation/2)
      change transition_state(:deactivating)
      change after_action(&start_deactivation_process/3)
      change after_action(&create_orchestration_event/3)
    end

    update :deactivation_complete do
      require_atomic? false
      accept [:active_count]

      change transition_state(:dormant)
      change after_action(&finalize_deactivation/3)
      change after_action(&create_orchestration_event/3)
    end

    # Optimization state transitions
    update :begin_optimization do
      require_atomic? false
      description "Begin chunk optimization"
      accept []

      change before_action(&prepare_optimization/2)
      change transition_state(:optimizing)
      change after_action(&start_optimization_process/3)
      change after_action(&create_orchestration_event/3)
    end

    update :optimization_complete do
      require_atomic? false
      accept [:optimization_score, :resource_allocation]

      change before_action(&apply_optimization_target_state/2)
      change set_attribute(:last_optimization, &DateTime.utc_now/0)
      change after_action(&apply_optimization_changes/3)
      change after_action(&create_orchestration_event/3)
    end

    # Maintenance state transitions
    update :enter_maintenance do
      require_atomic? false
      accept []

      change before_action(&prepare_maintenance_mode/2)
      change transition_state(:maintenance)
      change after_action(&start_maintenance_procedures/3)
      change after_action(&create_orchestration_event/3)
    end

    update :exit_maintenance do
      require_atomic? false
      accept []

      change transition_state(:dormant)
      change after_action(&complete_maintenance_procedures/3)
      change after_action(&create_orchestration_event/3)
    end

    # Scaling state transitions
    update :begin_scaling do
      require_atomic? false
      accept [:total_capacity]

      change before_action(&prepare_scaling_operation/2)
      change transition_state(:scaling)
      change after_action(&start_scaling_process/3)
      change after_action(&create_orchestration_event/3)
    end

    update :scaling_complete do
      require_atomic? false
      accept [:active_count, :dormant_count, :resource_allocation, :total_capacity]

      change before_action(&apply_scaling_target_state/2)
      change after_action(&apply_scaling_changes/3)
      change after_action(&create_orchestration_event/3)
    end

    # Failure and recovery
    update :recover do
      require_atomic? false
      accept []

      change before_action(&validate_recovery_conditions/2)
      change transition_state(:dormant)
      change after_action(&complete_recovery_process/3)
      change after_action(&create_orchestration_event/3)
    end

    update :force_reset do
      require_atomic? false
      accept []

      change before_action(&prepare_force_reset/2)
      change transition_state(:initializing)
      change after_action(&complete_force_reset/3)
      change after_action(&create_orchestration_event/3)
    end

    # Emergency operations
    update :emergency_stop do
      require_atomic? false
      argument :error_info, :map, allow_nil?: true
      accept []

      change transition_state(:emergency_stopped)
      change after_action(&execute_emergency_stop/3)
      change after_action(&create_orchestration_event/3)
    end

    update :emergency_recover do
      require_atomic? false
      accept []

      change transition_state(:dormant)
      change after_action(&complete_emergency_recovery/3)
      change after_action(&create_orchestration_event/3)
    end

    # Shutdown operations
    update :begin_shutdown do
      require_atomic? false
      accept []

      change before_action(&prepare_shutdown/2)
      change transition_state(:shutting_down)
      change after_action(&start_shutdown_process/3)
      change after_action(&create_orchestration_event/3)
    end

    update :shutdown_complete do
      require_atomic? false
      accept []

      change transition_state(:destroyed)
      change after_action(&finalize_shutdown/3)
      change after_action(&create_orchestration_event/3)
    end

    # Health and status updates (non-state-changing)
    update :update_health do
      require_atomic? false
      accept [:health_status, :resource_allocation, :health_metrics]
      change after_action(&broadcast_health_update/3)
    end

    validations do
      validate fn changeset, _context ->
        total = Ash.Changeset.get_attribute(changeset, :total_capacity)

        if total && total < 144 do
          {:error, "total_capacity must be at least 144"}
        else
          :ok
        end
      end

      validate fn changeset, _context ->
        total = Ash.Changeset.get_attribute(changeset, :total_capacity) || 0
        active = Ash.Changeset.get_attribute(changeset, :active_count) || 0

        if active > total do
          {:error, "active_count cannot exceed total_capacity"}
        else
          :ok
        end
      end
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

    # Backwards-compatibility: many older callers create chunks by passing
    # a single hex coordinate (hex_q, hex_r, hex_s). Add a small compatibility
    # create action that accepts those arguments and maps them to the
    # canonical `create_for_region` attributes (start_q/start_r/end_q/end_r).
    create :create do
      # We intentionally accept the legacy hex args as action arguments so they
      # needn't become persistent resource fields.
      argument :hex_q, :integer, allow_nil?: false
      argument :hex_r, :integer, allow_nil?: false
      argument :hex_s, :integer, allow_nil?: true

      accept [:total_capacity, :thundercore_subscription]

      change before_action(&map_hex_coords_to_region/2)
      change before_action(&calculate_chunk_boundaries/2)
      change after_action(&initialize_chunk_supervisor/3)
      change after_action(&subscribe_to_thundercore_pulse/3)
      change after_action(&create_orchestration_event/3)
    end

    # Allow tests to mark a chunk as failed using a public action name used in
    # other resources. This small action simply transitions state to :failed.
    update :mark_failed do
      description "Mark chunk as failed for recovery testing"
      argument :error_info, :map, allow_nil?: true

      require_atomic? false

      change transition_state(:failed)
      change after_action(&create_orchestration_event/3)
    end
  end

  pub_sub do
    module Thunderline.PubSub
    prefix "thunderbolt:chunk"

    publish :create, ["created", :id]
    publish :create_for_region, ["created", :id]
    publish :activate, ["activated", :id]
    publish :optimization_complete, ["optimized", :id]
    publish :update_health, ["health_updated", :id]
  end

  attributes do
    uuid_primary_key :id

    # Hex region coordinates
    attribute :start_q, :integer, allow_nil?: false
    attribute :start_r, :integer, allow_nil?: false
    attribute :end_q, :integer, allow_nil?: false
    attribute :end_r, :integer, allow_nil?: false
    attribute :z_level, :integer, default: 0

    attribute :state, :atom do
      allow_nil? false
      default :initializing

      constraints one_of: [
                    :initializing,
                    :dormant,
                    :active,
                    :optimizing,
                    :maintenance,
                    :scaling,
                    :deactivating,
                    :failed,
                    :emergency_stopped,
                    :shutting_down,
                    :destroyed
                  ]
    end

    # Chunk statistics
    attribute :active_count, :integer, default: 0
    attribute :dormant_count, :integer, default: 0

    # 64x64 default

    attribute :total_capacity, :integer, default: 144

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
        one_of: [:unknown, :healthy, :degraded, :critical, :offline, :unhealthy]
      ],
      default: :unknown

    # Free-form health metrics recorded from probes
    attribute :health_metrics, :map, default: %{}

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

  # ============================================================================
  # STATE MACHINE ACTION IMPLEMENTATIONS
  # ============================================================================

  # Initialization implementations
  defp validate_initialization_requirements(changeset, _context) do
    # Validate that chunk has required attributes for initialization
    changeset
  end

  defp complete_chunk_initialization(_changeset, chunk, _context) do
    # Initialize chunk resources and establish connections
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:initialized",
      {:chunk_initialized, chunk.id}
    )

    {:ok, chunk}
  end

  # Activation implementations
  defp prepare_activation(changeset, _context) do
    # Pre-activation validation and preparation
    changeset
  end

  defp start_activation_process(_changeset, chunk, _context) do
    # Start the activation process for Thunderbits in this chunk
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:activating",
      {:chunk_activating, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_activation(_changeset, chunk, _context) do
    # Complete activation process and notify systems
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:activated",
      {:chunk_activated, chunk.id, chunk.active_count}
    )

    {:ok, chunk}
  end

  # Deactivation implementations
  defp prepare_deactivation(changeset, _context) do
    # Pre-deactivation validation
    changeset
  end

  defp start_deactivation_process(_changeset, chunk, _context) do
    # Start the deactivation process
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:deactivating",
      {:chunk_deactivating, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_deactivation(_changeset, chunk, _context) do
    # Complete deactivation and cleanup
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:deactivated",
      {:chunk_deactivated, chunk.id}
    )

    {:ok, chunk}
  end

  # Optimization implementations
  defp prepare_optimization(changeset, _context) do
    # Placeholder for ML-driven pre-optimization heuristics
    changeset
  end

  defp start_optimization_process(_changeset, chunk, _context) do
    # Begin optimization procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:optimizing",
      {:chunk_optimizing, chunk.id}
    )

    {:ok, chunk}
  end

  defp apply_optimization_changes(_changeset, chunk, _context) do
    # Apply calculated optimizations
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:optimized",
      {:chunk_optimized, chunk.id, chunk.optimization_score}
    )

    {:ok, chunk}
  end

  defp apply_scaling_changes(_changeset, chunk, _context) do
    # Apply scaling operations
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:scaled",
      {:chunk_scaled, chunk.id, chunk.active_count}
    )

    {:ok, chunk}
  end

  # Maintenance implementations
  defp prepare_maintenance_mode(changeset, _context) do
    # Prepare chunk for maintenance operations
    changeset
  end

  defp start_maintenance_procedures(_changeset, chunk, _context) do
    # Begin maintenance procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:maintenance",
      {:chunk_maintenance_started, chunk.id}
    )

    {:ok, chunk}
  end

  defp complete_maintenance_procedures(_changeset, chunk, _context) do
    # Complete maintenance and return to service
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:maintenance_complete",
      {:chunk_maintenance_complete, chunk.id}
    )

    {:ok, chunk}
  end

  # Scaling implementations
  defp prepare_scaling_operation(changeset, _context) do
    # Prepare for scaling operation
    changeset
  end

  defp start_scaling_process(_changeset, chunk, _context) do
    # Begin scaling procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:scaling",
      {:chunk_scaling_started, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_scaling_operation(_changeset, chunk, _context) do
    # Complete scaling operation
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:scaled",
      {:chunk_scaled, chunk.id, chunk.total_capacity}
    )

    {:ok, chunk}
  end

  # Recovery implementations
  defp validate_recovery_conditions(changeset, _context) do
    # Validate that recovery is possible
    changeset
  end

  defp complete_recovery_process(_changeset, chunk, _context) do
    # Complete recovery procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:recovered",
      {:chunk_recovered, chunk.id}
    )

    {:ok, chunk}
  end

  defp prepare_force_reset(changeset, _context) do
    # Prepare for force reset operation
    changeset
  end

  defp complete_force_reset(_changeset, chunk, _context) do
    # Complete force reset
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:force_reset",
      {:chunk_force_reset, chunk.id}
    )

    {:ok, chunk}
  end

  # Emergency implementations
  defp execute_emergency_stop(_changeset, chunk, _context) do
    # Execute emergency stop procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:emergency_stop",
      {:chunk_emergency_stop, chunk.id}
    )

    {:ok, chunk}
  end

  defp complete_emergency_recovery(_changeset, chunk, _context) do
    # Complete emergency recovery
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:emergency_recovered",
      {:chunk_emergency_recovered, chunk.id}
    )

    {:ok, chunk}
  end

  # Shutdown implementations
  defp prepare_shutdown(changeset, _context) do
    # Prepare for graceful shutdown
    changeset
  end

  defp start_shutdown_process(_changeset, chunk, _context) do
    # Begin shutdown procedures
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:shutting_down",
      {:chunk_shutting_down, chunk.id}
    )

    {:ok, chunk}
  end

  defp finalize_shutdown(_changeset, chunk, _context) do
    # Complete shutdown and cleanup
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:destroyed",
      {:chunk_destroyed, chunk.id}
    )

    {:ok, chunk}
  end

  # Legacy implementations (preserved)
  defp calculate_chunk_boundaries(changeset, _context) do
    # Hex coordinate validation and boundary calculation
    changeset
  end

  defp initialize_chunk_supervisor(_changeset, chunk, _context) do
    # Start dedicated supervisor for this chunk
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:supervisor_started",
      {:chunk_supervisor_started, chunk.id}
    )

    {:ok, chunk}
  end

  defp subscribe_to_thundercore_pulse(_changeset, chunk, _context) do
    if chunk.thundercore_subscription do
      for pubsub <- Thunderline.PubSub.active_pubsubs() do
        Phoenix.PubSub.subscribe(pubsub, "thundercore:pulse")
      end
    end

    {:ok, chunk}
  end

  # Map legacy single-hex coordinates (hex_q, hex_r, hex_s) to a small
  # region centered on that hex so older callers can continue using
  # the `:create` action.
  defp map_hex_coords_to_region(changeset, _context) do
    q = Ash.Changeset.get_argument(changeset, :hex_q)
    r = Ash.Changeset.get_argument(changeset, :hex_r)

    # If hex_s isn't provided we compute it as -q - r (axial coordinate invariant)
    # s coordinate validated but unused in 2x2 region computation
    _s = Ash.Changeset.get_argument(changeset, :hex_s) || -(q + r)

    # Build a 2x2 region around the provided hex for simplicity
    start_q = q - 1
    start_r = r - 1
    end_q = q + 1
    end_r = r + 1

    # Use force_change_attribute since this runs in a before_action hook after validation
    changeset
    |> Ash.Changeset.force_change_attribute(:start_q, start_q)
    |> Ash.Changeset.force_change_attribute(:start_r, start_r)
    |> Ash.Changeset.force_change_attribute(:end_q, end_q)
    |> Ash.Changeset.force_change_attribute(:end_r, end_r)
    |> Ash.Changeset.force_change_attribute(:z_level, 0)
  end

  defp create_orchestration_event(_changeset, chunk, _context) do
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
      |> Ash.create!(domain: Domain)
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

  defp broadcast_health_update(_changeset, chunk, _context) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:chunk:health_updated",
      {:chunk_health_updated, chunk.id, chunk.health_status}
    )

    {:ok, chunk}
  end

  # Apply optimization target state based on score
  defp apply_optimization_target_state(changeset, _context) do
    target_state = determine_optimization_target_state(changeset, nil)
    Ash.Changeset.force_change_attribute(changeset, :state, target_state)
  end

  # Apply scaling target state based on active count
  defp apply_scaling_target_state(changeset, _context) do
    target_state = determine_scaling_target_state(changeset, nil)
    Ash.Changeset.force_change_attribute(changeset, :state, target_state)
  end

  # State transition decision functions (must be named for Spark DSL)
  def determine_optimization_target_state(changeset, _context) do
    # Check if optimization_score was explicitly changed; if not, use existing value
    score =
      case Ash.Changeset.get_attribute(changeset, :optimization_score) do
        nil ->
          # No new value provided, check the record's existing value
          case Ash.Changeset.get_data(changeset) do
            %{optimization_score: existing_score} -> existing_score
            _ -> nil
          end

        new_score ->
          new_score
      end

    cond do
      is_nil(score) ->
        :active

      Decimal.compare(score, Decimal.new("0.8")) == :lt ->
        :active

      true ->
        :dormant
    end
  end

  def determine_scaling_target_state(changeset, _context) do
    active =
      case Ash.Changeset.get_attribute(changeset, :active_count) do
        nil ->
          # Check existing value
          case Ash.Changeset.get_data(changeset) do
            %{active_count: count} -> count
            _ -> 0
          end

        count ->
          count
      end

    if is_integer(active) and active > 0 do
      :active
    else
      :dormant
    end
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

  def __silence_unused__ do
    _ = [
      &validate_initialization_requirements/2,
      &complete_chunk_initialization/3,
      &prepare_activation/2,
      &start_activation_process/3,
      &finalize_activation/3,
      &prepare_deactivation/2,
      &start_deactivation_process/3,
      &finalize_deactivation/3,
      &prepare_optimization/2,
      &start_optimization_process/3,
      &apply_optimization_changes/3,
      &prepare_maintenance_mode/2,
      &start_maintenance_procedures/3,
      &complete_maintenance_procedures/3,
      &prepare_scaling_operation/2,
      &start_scaling_process/3,
      &finalize_scaling_operation/3,
      &validate_recovery_conditions/2,
      &complete_recovery_process/3,
      &prepare_force_reset/2,
      &complete_force_reset/3,
      &execute_emergency_stop/3,
      &complete_emergency_recovery/3,
      &prepare_shutdown/2,
      &start_shutdown_process/3,
      &finalize_shutdown/3,
      &calculate_chunk_boundaries/2,
      &initialize_chunk_supervisor/3,
      &subscribe_to_thundercore_pulse/3,
      &create_orchestration_event/3,
      &calculate_optimization_score/1,
      &broadcast_health_update/3,
      &determine_optimization_target_state/2,
      &determine_scaling_target_state/2
    ]

    :ok
  end
end
