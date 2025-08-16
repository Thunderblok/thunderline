defmodule Thunderblock.Resources.SupervisionTree do
  @moduledoc """
  SupervisionTree Resource - Fault Isolation & Recovery

  Represents a supervision tree structure within a ZoneContainer, providing
  fault isolation boundaries and automatic recovery mechanisms for agent
  processes and system components. Tracks supervision hierarchy and handles
  failure recovery strategies.

  ## Core Responsibilities
  - Supervision tree lifecycle management and monitoring
  - Fault isolation and containment within zone boundaries
  - Automatic restart and recovery strategy execution
  - Process hierarchy tracking and health monitoring
  - Escalation and failure pattern detection
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
    table "thunderblock_supervision_trees"
    repo Thunderline.Repo

    references do
      reference :cluster_node, on_delete: :delete, on_update: :update
      reference :zone_container, on_delete: :delete, on_update: :update
      reference :parent_tree, on_delete: :nilify, on_update: :update
      reference :child_trees, on_delete: :delete, on_update: :update
      reference :system_events, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:tree_name, :zone_container_id],
        unique: true,
        name: "supervision_trees_name_zone_idx"

      index [:status, :health_score], name: "supervision_trees_health_idx"
      index [:tree_type, :status], name: "supervision_trees_type_idx"
      index [:zone_container_id, :depth_level], name: "supervision_trees_zone_depth_idx"
      index [:escalation_level, :status], name: "supervision_trees_escalation_idx"
      index [:parent_tree_id, :depth_level], name: "supervision_trees_hierarchy_idx"
      index "USING GIN (running_children)", name: "supervision_trees_children_idx"
      index "USING GIN (tags)", name: "supervision_trees_tags_idx"
    end

    check_constraints do
      check_constraint :valid_health_score, "health_score >= 0.0 AND health_score <= 1.0"

      check_constraint :valid_restart_counts,
                       "restart_count >= 0 AND max_restarts >= 0 AND max_seconds > 0"

      check_constraint :valid_escalation, "escalation_level >= 0 AND escalation_level <= 10"
      check_constraint :valid_depth, "depth_level >= 0 AND depth_level <= 10"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "supervision_tree"

    routes do
      base("/supervision_trees")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      # Tree management endpoints
      route(:post, "/:id/start", :start)
      route(:post, "/:id/stop", :stop)
      route(:post, "/:id/restart", :restart_tree)
      route(:post, "/:id/mark_degraded", :mark_degraded)
      route(:post, "/:id/check_recovery", :check_recovery)

      # Child management endpoints
      route(:post, "/:id/handle_child_failure", :handle_child_failure)
      route(:post, "/:id/add_child", :add_child)
      route(:post, "/:id/remove_child", :remove_child)

      # Query endpoints - using standard index with query parameters instead
      # Example: GET /supervision_trees?filter[status]=active
      # Example: GET /supervision_trees?filter[zone_id]=123
    end
  end

  # ===== POLICIES =====
  # ===== POLICIES =====
  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end

  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  # ===== CODE INTERFACE =====
  code_interface do
    define :create
    define :update
    define :start, action: :start, args: [:id]
    define :stop, args: [:id]
    define :restart_tree, args: []
    define :handle_child_failure, args: [:child_id, :failure_reason]
    define :add_child, args: [:id, :child_id]
    define :remove_child, args: [:id, :child_id]
    define :mark_degraded, args: []
    define :check_recovery, args: [:id]
    define :by_status, args: [:status]
    define :by_zone, args: [:zone_id]
    define :by_type, args: [:tree_type]
    define :unhealthy_trees, action: :unhealthy_trees
    define :high_escalation, action: :high_escalation
    define :root_trees, action: :root_trees
    define :child_trees_of, args: [:parent_tree_id]
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new supervision tree"

      accept [
        :tree_name,
        :tree_type,
        :supervision_strategy,
        :max_restarts,
        :max_seconds,
        :child_specs,
        :recovery_strategy,
        :monitoring_config,
        :parent_tree_id,
        :depth_level,
        :tags,
        :metadata,
        :cluster_node_id,
        :zone_container_id
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :starting)
      end

      change after_action(fn _changeset, tree, _context ->
               # Initialize the actual supervision tree process
               start_supervision_process(tree)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thunderblock:supervision",
                 {:tree_created,
                  %{tree_id: tree.id, tree_name: tree.tree_name, zone_id: tree.zone_container_id}}
               )

               {:ok, tree}
             end)
    end

    update :update do
      description "Update supervision tree configuration"

      accept [
        :tree_name,
        :supervision_strategy,
        :max_restarts,
        :max_seconds,
        :child_specs,
        :recovery_strategy,
        :monitoring_config,
        :tags,
        :metadata
      ]
    end

    action :start, :struct do
      description "Start the supervision tree"

      argument :id, :uuid do
        allow_nil? false
      end

      run fn input, _context ->
        case Thunderblock.Domain
             |> Ash.get(Thunderblock.Resources.SupervisionTree, input.arguments.id) do
          {:ok, tree} ->
            {:ok, updated_tree} =
              tree
              |> Ash.Changeset.for_update(:_internal_start, %{})
              |> Thunderblock.Domain.update()

            # Start supervision process
            Thunderblock.SupervisionManager.start_tree(tree.id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:supervision",
              {:tree_started, %{tree_id: tree.id, tree_name: tree.tree_name}}
            )

            {:ok, updated_tree}

          error ->
            error
        end
      end
    end

    update :_internal_start do
      description "Internal update action for starting supervision tree"
      accept []

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :active)
        |> reset_restart_count()
      end
    end

    action :stop, :struct do
      description "Stop the supervision tree"
      constraints instance_of: Thunderblock.Resources.SupervisionTree

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.SupervisionTree, input.arguments.id) do
          nil ->
            {:error, "Supervision tree not found"}

          tree ->
            updated_tree =
              Ash.update!(tree, :_stop_internal, %{
                status: :stopped,
                running_children: []
              })

            # Stop supervision process
            Thunderblock.SupervisionManager.stop_tree(updated_tree.id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:supervision",
              {:tree_stopped, %{tree_id: updated_tree.id, tree_name: updated_tree.tree_name}}
            )

            {:ok, updated_tree}
        end
      end
    end

    # Internal update action for stop
    update :_stop_internal do
      description "Internal update for stop operation"
      accept [:status, :running_children]
    end

    action :restart_tree do
      description "Restart the entire supervision tree"

      run fn changeset, _context ->
        current_time = DateTime.utc_now()
        current_count = Ash.Changeset.get_attribute(changeset, :restart_count) || 0

        changeset =
          changeset
          |> Ash.Changeset.change_attribute(:status, :active)
          |> Ash.Changeset.change_attribute(:restart_count, current_count + 1)
          |> Ash.Changeset.change_attribute(:last_restart, current_time)
          |> escalate_if_needed()

        case Ash.update!(changeset) do
          tree ->
            # Restart supervision tree
            Thunderblock.SupervisionManager.restart_tree(tree.id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:supervision",
              {:tree_restarted,
               %{
                 tree_id: tree.id,
                 restart_count: tree.restart_count,
                 escalation_level: tree.escalation_level
               }}
            )

            {:ok, tree}
        end
      end
    end

    action :handle_child_failure do
      description "Handle child process failure"

      argument :child_id, :string do
        allow_nil? false
      end

      argument :failure_reason, :string do
        allow_nil? false
      end

      run fn changeset, context ->
        child_id = context.arguments.child_id
        failure_reason = context.arguments.failure_reason
        current_time = DateTime.utc_now()

        # Add to failed children history
        current_failed = Ash.Changeset.get_attribute(changeset, :failed_children) || []

        new_failure = %{
          child_id: child_id,
          reason: failure_reason,
          timestamp: current_time
        }

        # Keep last 100 failures

        updated_failed = [new_failure | current_failed] |> Enum.take(100)

        # Remove from running children
        current_running = Ash.Changeset.get_attribute(changeset, :running_children) || []
        updated_running = Enum.reject(current_running, &(&1 == child_id))

        changeset =
          changeset
          |> Ash.Changeset.change_attribute(:failed_children, updated_failed)
          |> Ash.Changeset.change_attribute(:running_children, updated_running)
          |> calculate_health_score_from_failures()
          |> escalate_if_needed()

        case Ash.update!(changeset) do
          tree ->
            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:supervision",
              {:child_failed,
               %{
                 tree_id: tree.id,
                 child_id: child_id,
                 reason: failure_reason,
                 health_score: tree.health_score
               }}
            )

            {:ok, tree}
        end
      end
    end

    action :add_child, :struct do
      description "Add a new child to the supervision tree"
      constraints instance_of: Thunderblock.Resources.SupervisionTree

      argument :id, :uuid, allow_nil?: false
      argument :child_id, :string, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.SupervisionTree, input.arguments.id) do
          nil ->
            {:error, "Supervision tree not found"}

          tree ->
            child_id = input.arguments.child_id
            current_running = tree.running_children || []
            updated_running = [child_id | current_running] |> Enum.uniq()

            updated_tree =
              Ash.update!(tree, :_add_child_internal, %{
                running_children: updated_running
              })

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:supervision",
              {:child_added, %{tree_id: tree.id, child_id: child_id}}
            )

            {:ok, updated_tree}
        end
      end
    end

    # Internal update action for add_child
    update :_add_child_internal do
      description "Internal update for add_child operation"
      accept [:running_children]
    end

    action :remove_child, :struct do
      description "Remove a child from the supervision tree"
      constraints instance_of: Thunderblock.Resources.SupervisionTree

      argument :id, :uuid, allow_nil?: false
      argument :child_id, :string, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.SupervisionTree, input.arguments.id) do
          nil ->
            {:error, "Supervision tree not found"}

          tree ->
            child_id = input.arguments.child_id
            current_running = tree.running_children || []
            updated_running = Enum.reject(current_running, &(&1 == child_id))

            updated_tree =
              Ash.update!(tree, :_remove_child_internal, %{
                running_children: updated_running
              })

            {:ok, updated_tree}
        end
      end
    end

    # Internal update action for remove_child
    update :_remove_child_internal do
      description "Internal update for remove_child operation"
      accept [:running_children]
    end

    action :mark_degraded do
      description "Mark supervision tree as degraded"

      run fn changeset, _context ->
        changeset =
          changeset
          |> Ash.Changeset.change_attribute(:status, :degraded)
          |> decrease_health_score(0.3)

        case Ash.update!(changeset) do
          tree ->
            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:supervision",
              {:tree_degraded, %{tree_id: tree.id, health_score: tree.health_score}}
            )

            {:ok, tree}
        end
      end
    end

    action :check_recovery, :struct do
      description "Check and perform recovery procedures"
      constraints instance_of: Thunderblock.Resources.SupervisionTree

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.SupervisionTree, input.arguments.id) do
          nil ->
            {:error, "Supervision tree not found"}

          tree ->
            # Trigger recovery procedures based on tree state
            Thunderblock.RecoveryManager.assess_tree(tree.id)
            {:ok, tree}
        end
      end
    end

    # Read actions for supervision queries
    read :by_status do
      description "Get supervision trees by status"

      argument :status, :atom do
        allow_nil? false
      end

      filter expr(status == ^arg(:status))
      prepare build(sort: [:tree_name])
    end

    read :by_zone do
      description "Get supervision trees for a specific zone"

      argument :zone_id, :uuid do
        allow_nil? false
      end

      filter expr(zone_container_id == ^arg(:zone_id))
      prepare build(sort: [:depth_level, :tree_name])
    end

    read :by_type do
      description "Get supervision trees by type"

      argument :tree_type, :atom do
        allow_nil? false
      end

      filter expr(tree_type == ^arg(:tree_type))
      prepare build(sort: [:tree_name])
    end

    read :unhealthy_trees do
      description "Get supervision trees with low health scores"

      filter expr(health_score < 0.7 or status in [:degraded, :failing])
      prepare build(sort: [:health_score])
    end

    read :high_escalation do
      description "Get trees with high escalation levels"

      filter expr(escalation_level >= 3)
      prepare build(sort: [:escalation_level, :tree_name])
    end

    read :root_trees do
      description "Get root supervision trees (depth_level = 0)"

      filter expr(depth_level == 0)
      prepare build(sort: [:tree_name])
    end

    read :child_trees_of do
      description "Get child trees of a specific parent"

      argument :parent_tree_id, :uuid do
        allow_nil? false
      end

      filter expr(parent_tree_id == ^arg(:parent_tree_id))
      prepare build(sort: [:depth_level, :tree_name])
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    prepare build(load: [:cluster_node, :zone_container, :parent_tree, :child_trees])
  end

  # ===== OBAN CONFIGURATION =====
  # oban do
  #   # Recovery assessment
  #   trigger :recovery_assessment do
  #     action :check_recovery
  #     schedule "*/120 * * * * *"  # Every 2 minutes
  #     where expr(status == :degraded)
  #   end

  #   # Health monitoring
  #   trigger :health_monitoring do
  #     action :unhealthy_trees
  #     schedule "*/60 * * * * *"  # Every minute
  #   end

  #   # Reset restart counts outside window
  #   trigger :reset_restart_counts do
  #     action :by_status, args: [:active]
  #     schedule "*/300 * * * * *"  # Every 5 minutes
  #     where expr(
  #       restart_count > 0 and
  #       (last_restart < ago(max_seconds, :second) or is_nil(last_restart))
  #     )
  #   end
  # end

  # ===== VALIDATIONS =====
  validations do
    validate present([:tree_name, :tree_type, :zone_container_id])
    # validate {Thunderblock.Validations, :valid_tree_name}, on: [:create, :update]
    # validate {Thunderblock.Validations, :valid_child_specs}, on: [:create, :update]
    # validate {Thunderblock.Validations, :supervision_hierarchy}, on: [:create, :update]
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :tree_name, :string do
      allow_nil? false
      description "Unique name for this supervision tree"
      constraints min_length: 1, max_length: 100
    end

    attribute :tree_type, :atom do
      allow_nil? false
      description "Type of supervision tree"
      default :zone_supervisor
    end

    attribute :supervision_strategy, :atom do
      allow_nil? false
      description "Strategy for handling child failures"
      default :one_for_one
    end

    attribute :max_restarts, :integer do
      allow_nil? false
      description "Maximum restarts allowed within max_seconds"
      default 5
      constraints min: 0, max: 100
    end

    attribute :max_seconds, :integer do
      allow_nil? false
      description "Time window for restart counting in seconds"
      default 60
      constraints min: 1, max: 3600
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current status of the supervision tree"
      default :starting
    end

    attribute :restart_count, :integer do
      allow_nil? false
      description "Current restart count within time window"
      default 0
      constraints min: 0
    end

    attribute :last_restart, :utc_datetime do
      allow_nil? true
      description "Timestamp of last restart"
    end

    attribute :child_specs, {:array, :map} do
      allow_nil? false
      description "Child process specifications"
      default []
    end

    attribute :running_children, {:array, :string} do
      allow_nil? false
      description "List of currently running child process IDs"
      default []
    end

    attribute :failed_children, {:array, :map} do
      allow_nil? false
      description "History of failed children with timestamps and reasons"
      default []
    end

    attribute :escalation_level, :integer do
      allow_nil? false
      description "Current escalation level (0 = normal, higher = more escalated)"
      default 0
      constraints min: 0, max: 10
    end

    attribute :health_score, :decimal do
      allow_nil? false
      description "Health score from 0.0 to 1.0 based on failure patterns"
      default Decimal.new("1.0")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :recovery_strategy, :map do
      allow_nil? false
      description "Recovery strategy configuration"

      default %{
        immediate_restart: true,
        backoff_strategy: "exponential",
        max_backoff_seconds: 300,
        circuit_breaker: false
      }
    end

    attribute :monitoring_config, :map do
      allow_nil? false
      description "Monitoring and alerting configuration"

      default %{
        health_check_interval: 30,
        failure_threshold: 3,
        alert_on_degraded: true,
        escalate_after_failures: 5
      }
    end

    attribute :parent_tree_id, :uuid do
      allow_nil? true
      description "ID of parent supervision tree (for hierarchy)"
    end

    attribute :depth_level, :integer do
      allow_nil? false
      description "Depth level in supervision hierarchy (0 = root)"
      default 0
      constraints min: 0, max: 10
    end

    attribute :process_info, :map do
      allow_nil? false
      description "Runtime process information and PIDs"
      default %{}
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      description "Tags for supervision tree categorization"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional supervision tree metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ===== RELATIONSHIPS =====
  relationships do
    belongs_to :cluster_node, Thunderblock.Resources.ClusterNode do
      attribute_writable? true
      source_attribute :cluster_node_id
      destination_attribute :id
    end

    belongs_to :zone_container, Thunderblock.Resources.ZoneContainer do
      attribute_writable? true
      source_attribute :zone_container_id
      destination_attribute :id
    end

    belongs_to :parent_tree, Thunderblock.Resources.SupervisionTree do
      source_attribute :parent_tree_id
      destination_attribute :id
    end

    has_many :child_trees, Thunderblock.Resources.SupervisionTree do
      destination_attribute :parent_tree_id
    end

    has_many :system_events, Thunderblock.Resources.SystemEvent do
      destination_attribute :target_resource_id
      filter expr(target_resource_type == :supervision_tree)
    end
  end

  # ===== PRIVATE FUNCTIONS =====
  defp reset_restart_count(changeset) do
    changeset
    |> Ash.Changeset.change_attribute(:restart_count, 0)
    |> Ash.Changeset.change_attribute(:escalation_level, 0)
  end

  defp escalate_if_needed(changeset) do
    restart_count = Ash.Changeset.get_attribute(changeset, :restart_count) || 0
    max_restarts = Ash.Changeset.get_attribute(changeset, :max_restarts) || 5
    current_escalation = Ash.Changeset.get_attribute(changeset, :escalation_level) || 0

    new_escalation =
      cond do
        restart_count >= max_restarts * 3 -> min(10, current_escalation + 3)
        restart_count >= max_restarts * 2 -> min(10, current_escalation + 2)
        restart_count >= max_restarts -> min(10, current_escalation + 1)
        true -> current_escalation
      end

    status =
      if new_escalation >= 5, do: :failing, else: Ash.Changeset.get_attribute(changeset, :status)

    changeset
    |> Ash.Changeset.change_attribute(:escalation_level, new_escalation)
    |> Ash.Changeset.change_attribute(:status, status)
  end

  defp calculate_health_score_from_failures(changeset) do
    failed_children = Ash.Changeset.get_attribute(changeset, :failed_children) || []
    restart_count = Ash.Changeset.get_attribute(changeset, :restart_count) || 0

    # Calculate health based on recent failures (last hour)
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    recent_failures =
      Enum.count(failed_children, fn failure ->
        case DateTime.from_iso8601(failure["timestamp"]) do
          {:ok, timestamp, _} -> DateTime.compare(timestamp, one_hour_ago) == :gt
          _ -> false
        end
      end)

    # Health score calculation
    base_health = 1.0
    failure_penalty = min(0.8, recent_failures * 0.1)
    restart_penalty = min(0.5, restart_count * 0.05)

    new_health = max(0.0, base_health - failure_penalty - restart_penalty)

    Ash.Changeset.change_attribute(changeset, :health_score, Decimal.new(new_health))
  end

  defp decrease_health_score(changeset, amount) do
    current_score = Ash.Changeset.get_attribute(changeset, :health_score) || Decimal.new("1.0")
  # Structural comparison of Decimals is not meaningful here; future improvement: use Decimal.compare
  new_score = Decimal.sub(current_score, Decimal.new(amount))
    Ash.Changeset.change_attribute(changeset, :health_score, new_score)
  end

  defp start_supervision_process(tree) do
    # This would start the actual OTP supervision process
    # Implementation would depend on specific supervision requirements
    :ok
  end
end
