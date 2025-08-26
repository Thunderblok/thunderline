defmodule Thunderblock.Resources.ZoneContainer do
  @moduledoc """
  ZoneContainer Resource - Zone Management & Supervision

  Represents a logical zone within the Thunderblock execution container system.
  Each ZoneContainer manages a collection of agents/entities within a bounded
  spatial and logical context, providing fault isolation and resource management.

  ## Core Responsibilities
  - Zone lifecycle management (creation, activation, deactivation, termination)
  - Agent/entity supervision within zone boundaries
  - Resource allocation and consumption tracking
  - Inter-zone communication and coordination
  - Health monitoring and recovery procedures
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshOban.Resource],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  # ===== POSTGRES CONFIGURATION =====
  postgres do
    table "thunderblock_zone_containers"
    repo Thunderline.Repo

    references do
      reference :cluster_node, on_delete: :delete, on_update: :update
      reference :system_events, on_delete: :delete, on_update: :update
      reference :supervision_trees, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:zone_name], unique: true, name: "zone_containers_name_idx"
      index [:status, :health_score], name: "zone_containers_health_idx"
      index [:zone_type, :status], name: "zone_containers_type_idx"
      index [:cluster_node_id, :status], name: "zone_containers_node_idx"
      index [:phase_assignment], name: "zone_containers_phase_idx"
      index "USING GIN (neighbor_zones)", name: "zone_containers_neighbors_idx"
      index "USING GIN (tags)", name: "zone_containers_tags_idx"
      index "USING GIN (coordinates)", name: "zone_containers_coords_idx"
    end

    check_constraints do
      check_constraint :valid_health_score, "health_score >= 0.0 AND health_score <= 1.0"

      check_constraint :valid_restart_counts,
                       "restart_count >= 0 AND max_restarts >= 0 AND max_seconds > 0"

      check_constraint :valid_phase,
                       "phase_assignment >= 0 AND phase_assignment <= 11 OR phase_assignment IS NULL"
    end
  end

  # ===== JSON API CONFIGURATION =====
  json_api do
    type "zone_container"

    routes do
      base("/zone_containers")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      # Zone management endpoints
      route(:post, "/:id/activate", :activate)
      route(:post, "/:id/pause", :pause)
      route(:post, "/:id/restart", :restart)
      route(:post, "/:id/mark_degraded", :mark_degraded)
      route(:post, "/:id/mark_failed", :mark_failed)
      route(:post, "/:id/update_usage", :update_usage)
      route(:post, "/:id/health_check", :health_check)

      # Query endpoints - using standard index with query parameters instead
      # Example: GET /zone_containers?filter[status]=active
      # Example: GET /zone_containers?filter[node_id]=123
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
    define :activate, args: []
    define :pause, args: [:id], action: :pause
    define :restart, args: [:id]
    define :mark_degraded, args: [:id]
    define :mark_failed, args: [:id]
    define :update_usage, args: [:current_usage]
    define :health_check
    define :by_status, args: [:status]
    define :by_node, args: [:node_id]
    define :by_type, args: [:zone_type]
    define :unhealthy, action: :unhealthy
    define :overloaded, action: :overloaded
    define :neighbors, args: [:zone_id]
    define :by_phase, args: [:phase]
  end

  # ===== ACTIONS =====
  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a new zone container"

      accept [
        :zone_name,
        :zone_type,
        :coordinates,
        :capacity_config,
        :zone_config,
        :supervision_strategy,
        :max_restarts,
        :max_seconds,
        :neighbor_zones,
        :phase_assignment,
        :tags,
        :metadata,
        :cluster_node_id
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :initializing)
        |> Ash.Changeset.change_attribute(:last_health_check, DateTime.utc_now())
      end

      change after_action(fn _changeset, zone, _context ->
               # Initialize supervision tree
               create_supervision_tree(zone)

               # Broadcast zone creation
               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thunderblock:zones",
                 {:zone_created,
                  %{zone_id: zone.id, zone_name: zone.zone_name, node_id: zone.cluster_node_id}}
               )

               {:ok, zone}
             end)
    end

    update :update do
      description "Update zone configuration"

      accept [
        :zone_name,
        :zone_type,
        :capacity_config,
        :zone_config,
        :supervision_strategy,
        :max_restarts,
        :max_seconds,
        :neighbor_zones,
        :phase_assignment,
        :tags,
        :metadata
      ]
    end

    action :activate, :struct do
      description "Activate zone and start supervision"
      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        zone = Ash.get!(Thunderblock.Resources.ZoneContainer, input.arguments.id)

        zone =
          zone
          |> Ash.Changeset.for_update(:internal_activate)
          |> Thunderblock.Domain.update!()

        # Start zone supervision processes
        Thunderblock.ZoneManager.start_zone(zone.id)

        # Report to Thunderchief orchestrator
  Thunderline.Thunderflow.ClusterStateManager.register_zone(zone.id, %{
          zone_name: zone.zone_name,
          zone_type: zone.zone_type,
          capacity_config: zone.capacity_config
        })

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "thunderblock:zones",
          {:zone_activated, %{zone_id: zone.id, zone_name: zone.zone_name}}
        )

        {:ok, zone}
      end
    end

    update :internal_activate do
      description "Internal update for activate action"
      accept []

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :active)
        |> Ash.Changeset.change_attribute(:last_health_check, DateTime.utc_now())
      end
    end

    action :pause do
      description "Pause zone operations"

      argument :id, :uuid do
        allow_nil? false
        description "ID of the zone to pause"
      end

      run fn input, _context ->
        # Load and update zone status
        zone = Ash.get!(Thunderblock.Resources.ZoneContainer, input.arguments.id)

        zone
        |> Ash.Changeset.for_update(:internal_pause, %{})
        |> Ash.update()
        |> case do
          {:ok, zone} ->
            # Perform pause side-effects
            Thunderblock.ZoneManager.pause_zone(zone.id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:zones",
              {:zone_paused, %{zone_id: zone.id, zone_name: zone.zone_name}}
            )

            {:ok, zone}

          error ->
            error
        end
      end
    end

    action :restart, :struct do
      description "Restart zone and its supervision tree"
      constraints instance_of: Thunderblock.Resources.ZoneContainer

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.ZoneContainer, input.arguments.id) do
          nil ->
            {:error, "Zone container not found"}

          zone ->
            current_time = DateTime.utc_now()
            current_count = zone.restart_count || 0

            updated_zone =
              Ash.update!(zone, :_restart_internal, %{
                status: :active,
                restart_count: current_count + 1,
                last_restart: current_time
              })

            # Restart zone supervision
            Thunderblock.ZoneManager.restart_zone(updated_zone.id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:zones",
              {:zone_restarted,
               %{
                 zone_id: updated_zone.id,
                 zone_name: updated_zone.zone_name,
                 restart_count: updated_zone.restart_count
               }}
            )

            {:ok, updated_zone}
        end
      end
    end

    # Internal update action for restart
    update :_restart_internal do
      description "Internal update for restart operation"
      accept [:status, :restart_count, :last_restart]
    end

    action :mark_degraded, :struct do
      description "Mark zone as degraded due to issues"
      constraints instance_of: Thunderblock.Resources.ZoneContainer

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.ZoneContainer, input.arguments.id) do
          nil ->
            {:error, "Zone container not found"}

          zone ->
            # Calculate decreased health score
            current_health = zone.health_score || Decimal.new("1.0")
            new_health = Decimal.sub(current_health, Decimal.new("0.3"))

            updated_zone =
              Ash.update!(zone, :_mark_degraded_internal, %{
                status: :degraded,
                health_score: new_health
              })

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:zones",
              {:zone_degraded,
               %{
                 zone_id: updated_zone.id,
                 zone_name: updated_zone.zone_name,
                 health_score: updated_zone.health_score
               }}
            )

            {:ok, updated_zone}
        end
      end
    end

    # Internal update action for mark_degraded
    update :_mark_degraded_internal do
      description "Internal update for mark_degraded operation"
      accept [:status, :health_score]
    end

    action :mark_failed, :struct do
      description "Mark zone as failed"
      constraints instance_of: Thunderblock.Resources.ZoneContainer

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderblock.Resources.ZoneContainer, input.arguments.id) do
          nil ->
            {:error, "Zone container not found"}

          zone ->
            updated_zone =
              Ash.update!(zone, :_mark_failed_internal, %{
                status: :failed,
                health_score: Decimal.new("0.0")
              })

            # Stop zone processes
            Thunderblock.ZoneManager.stop_zone(updated_zone.id)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thunderblock:zones",
              {:zone_failed, %{zone_id: updated_zone.id, zone_name: updated_zone.zone_name}}
            )

            {:ok, updated_zone}
        end
      end
    end

    # Internal update action for mark_failed
    update :_mark_failed_internal do
      description "Internal update for mark_failed operation"
      accept [:status, :health_score]
    end

    action :update_usage do
      description "Update current resource usage"

      argument :current_usage, :map, allow_nil?: false

      run fn changeset, context ->
        changeset =
          changeset
          |> Ash.Changeset.change_attribute(:current_usage, context.arguments.current_usage)
          |> calculate_health_from_usage()
          |> Ash.Changeset.change_attribute(:last_health_check, DateTime.utc_now())

        case Ash.update!(changeset) do
          zone ->
            # Report health to Thunderchief orchestrator
            Thunderline.Thunderflow.ClusterStateManager.report_zone_health(zone.id, %{
              health_score: zone.health_score,
              status: zone.status,
              current_usage: zone.current_usage,
              last_health_check: zone.last_health_check
            })

            {:ok, zone}
        end
      end
    end

    action :health_check, :struct do
      description "Perform health check and update status"
      constraints instance_of: Thunderblock.Resources.ZoneContainer
      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get(Thunderblock.Resources.ZoneContainer, input.arguments.id, []) do
          {:ok, zone} ->
            zone
            |> Ash.Changeset.for_update(:internal_health_check, [])
            |> Ash.Changeset.change_attribute(:last_health_check, DateTime.utc_now())
            |> Ash.update()
            |> case do
              {:ok, updated_zone} ->
                # Report health status
                Phoenix.PubSub.broadcast(
                  Thunderline.PubSub,
                  "thunderblock:health",
                  {:zone_health_checked,
                   %{
                     zone_id: updated_zone.id,
                     health_score: updated_zone.health_score,
                     status: updated_zone.status
                   }}
                )

                {:ok, updated_zone}

              {:error, error} ->
                {:error, error}
            end

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :internal_health_check do
      description "Internal health check update action"
      accept []
      require_atomic? false
    end

    # Read actions for zone queries
    read :by_status do
      description "Get zones by status"

      argument :status, :atom do
        allow_nil? false
      end

      filter expr(status == ^arg(:status))
    end

    read :by_node do
      description "Get zones for a specific cluster node"

      argument :node_id, :uuid do
        allow_nil? false
      end

      filter expr(cluster_node_id == ^arg(:node_id))
    end

    read :by_type do
      description "Get zones by type"

      argument :zone_type, :atom do
        allow_nil? false
      end

      filter expr(zone_type == ^arg(:zone_type))
    end

    read :unhealthy do
      description "Get zones with low health scores"

      filter expr(health_score < 0.7 or status in [:degraded, :failed])
    end

    read :overloaded do
      description "Get zones approaching capacity limits"

      # Note: This would need custom logic to compare current_usage vs capacity_config
      prepare fn query, _context ->
        # Custom preparation for capacity checking would go here
        query
      end
    end

    read :neighbors do
      description "Get neighboring zones"

      argument :zone_id, :uuid do
        allow_nil? false
      end

      # Note: Would need custom logic to find zones whose neighbor_zones array contains zone_id
      prepare fn query, _context ->
        # Custom preparation for neighbor lookup would go here
        query
      end
    end

    read :by_phase do
      description "Get zones assigned to specific phase"

      argument :phase, :integer do
        allow_nil? false
      end

      filter expr(phase_assignment == ^arg(:phase))
      prepare build(sort: [:zone_name])
    end
  end

  # ===== PREPARATIONS =====
  preparations do
    prepare build(load: [:cluster_node, :system_events])
  end

  # ===== VALIDATIONS =====
  validations do
    validate present([:zone_name, :zone_type, :cluster_node_id])
    # validate {Thunderblock.Validations, :valid_zone_name}, on: [:create, :update]
    # validate {Thunderblock.Validations, :valid_coordinates}, on: [:create, :update]
    # validate {Thunderblock.Validations, :capacity_config_structure}, on: [:create, :update]
  end

  # ===== ATTRIBUTES =====
  attributes do
    uuid_primary_key :id

    attribute :zone_name, :string do
      allow_nil? false
      description "Human-readable zone identifier"
      constraints min_length: 1, max_length: 100
    end

    attribute :zone_type, :atom do
      allow_nil? false
      description "Type of zone for behavior specialization"
      default :general
      constraints one_of: [:core, :edge, :flow, :general, :specialized]
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current operational status"
      default :initializing
      constraints one_of: [:initializing, :active, :paused, :degraded, :failed, :terminating]
    end

    attribute :coordinates, :map do
      allow_nil? true
      description "Spatial coordinates in hexagonal grid (q, r, s)"
      default %{}
    end

    attribute :capacity_config, :map do
      allow_nil? false
      description "Zone capacity configuration"

      default %{
        max_agents: 1000,
        max_memory_mb: 512,
        max_cpu_percent: 80,
        max_connections: 100
      }
    end

    attribute :current_usage, :map do
      allow_nil? false
      description "Current resource usage metrics"

      default %{
        agent_count: 0,
        memory_mb: 0,
        cpu_percent: 0,
        connection_count: 0
      }
    end

    attribute :zone_config, :map do
      allow_nil? false
      description "Zone-specific configuration parameters"

      default %{
        tick_rate: 20,
        max_tick_time_ms: 50,
        batch_size: 100,
        enable_persistence: true
      }
    end

    attribute :supervision_strategy, :atom do
      allow_nil? false
      description "Supervision strategy for agents in this zone"
      default :one_for_one
      constraints one_of: [:one_for_one, :one_for_all, :rest_for_one]
    end

    attribute :max_restarts, :integer do
      allow_nil? false
      description "Maximum restarts allowed within max_seconds"
      default 5
      constraints min: 0, max: 100
    end

    attribute :max_seconds, :integer do
      allow_nil? false
      description "Time window for restart counting"
      default 60
      constraints min: 1, max: 3600
    end

    attribute :restart_count, :integer do
      allow_nil? false
      description "Current restart count in window"
      default 0
      constraints min: 0
    end

    attribute :last_restart, :utc_datetime do
      allow_nil? true
      description "Timestamp of last restart"
    end

    attribute :health_score, :decimal do
      allow_nil? false
      description "Health score from 0.0 to 1.0"
      default Decimal.new("1.0")
      constraints min: Decimal.new("0.0"), max: Decimal.new("1.0")
    end

    attribute :last_health_check, :utc_datetime do
      allow_nil? true
      description "Timestamp of last health check"
    end

    attribute :neighbor_zones, {:array, :uuid} do
      allow_nil? false
      description "List of neighboring zone IDs"
      default []
    end

    attribute :phase_assignment, :integer do
      allow_nil? true
      description "Assigned phase in 12-phase cycle (0-11)"
      constraints min: 0, max: 11
    end

    attribute :tags, {:array, :string} do
      allow_nil? false
      description "Tags for zone categorization"
      default []
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional zone metadata"
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

    has_many :system_events, Thunderblock.Resources.SystemEvent do
      destination_attribute :target_resource_id
      filter expr(target_resource_type == :zone_container)
    end

    has_many :supervision_trees, Thunderblock.Resources.SupervisionTree do
      destination_attribute :zone_container_id
    end

    # Note: In a real implementation, would relate to actual agent resources
    # has_many :agents, Thunderbit.Resources.Agent do
    #   destination_attribute :zone_container_id
    # end
  end

  # ===== OBAN CONFIGURATION =====
  # oban do
  #   # Regular health checks
  #   trigger :zone_health_check do
  #     action :health_check
  #     schedule "*/60 * * * * *"  # Every minute
  #     where expr(status in [:active, :degraded])
  #   end

  #   # Check for overloaded zones
  #   trigger :overload_monitoring do
  #     action :overloaded
  #     schedule "*/120 * * * * *"  # Every 2 minutes
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

  # ===== IDENTITIES =====
  identities do
    identity :unique_zone_name, [:zone_name]
  end

  # ===== PRIVATE FUNCTIONS =====
  defp decrease_health_score(changeset, amount) do
    current_score = Ash.Changeset.get_attribute(changeset, :health_score) || Decimal.new("1.0")
    new_score = max(Decimal.new("0.0"), Decimal.sub(current_score, Decimal.new(amount)))
    Ash.Changeset.change_attribute(changeset, :health_score, new_score)
  end

  defp calculate_health_from_usage(changeset) do
    current_usage = Ash.Changeset.get_attribute(changeset, :current_usage) || %{}
    capacity_config = Ash.Changeset.get_attribute(changeset, :capacity_config) || %{}

    # Calculate health score based on resource usage
    health_factors = [
      usage_factor(current_usage["agent_count"], capacity_config["max_agents"]),
      usage_factor(current_usage["memory_mb"], capacity_config["max_memory_mb"]),
      usage_factor(current_usage["cpu_percent"], capacity_config["max_cpu_percent"]),
      usage_factor(current_usage["connection_count"], capacity_config["max_connections"])
    ]

    avg_health =
      health_factors
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> 1.0
        factors -> Enum.sum(factors) / length(factors)
      end

    Ash.Changeset.change_attribute(changeset, :health_score, Decimal.new(avg_health))
  end

  defp usage_factor(nil, _max), do: nil
  defp usage_factor(_current, nil), do: nil

  defp usage_factor(current, max) when max > 0 do
    usage_ratio = current / max

    cond do
      usage_ratio <= 0.5 -> 1.0
      usage_ratio <= 0.7 -> 0.9
      usage_ratio <= 0.8 -> 0.7
      usage_ratio <= 0.9 -> 0.5
      usage_ratio <= 1.0 -> 0.3
      true -> 0.1
    end
  end

  defp usage_factor(_current, _max), do: 0.5

  defp create_supervision_tree(zone) do
    # This would create the initial supervision tree structure
    # Implementation would depend on SupervisionTree resource
    :ok
  end
end
