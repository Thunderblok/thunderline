defmodule Thunderline.Thundergrid.Resources.ZoneBoundary do
  @moduledoc """
  ZoneBoundary Resource - Zone Edge & Transition Management

  Manages the edges and transitions between spatial zones.
  Handles zone boundary definitions, crossing permissions,
  and transition effects between different zone types.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]
  import Ash.Resource.Change.Builtins
  import Ash.Resource.Change.Builtins


  attributes do
    uuid_primary_key :id

    attribute :boundary_name, :string do
      allow_nil? false
      description "Human-readable boundary identifier"
      constraints min_length: 1, max_length: 100
    end

    attribute :boundary_type, :atom do
      allow_nil? false
      description "Type of zone boundary"
      default :standard
      constraints one_of: [:standard, :barrier, :gateway, :checkpoint, :membrane, :portal]
    end

    attribute :geometry_type, :atom do
      allow_nil? false
      description "Geometric representation of boundary"
      default :line
      constraints one_of: [:line, :arc, :polygon, :circle, :complex]
    end

    attribute :boundary_points, {:array, :map} do
      allow_nil? false
      description "Ordered list of boundary coordinate points"
      default []
      # Format: [%{"q" => 0, "r" => 0, "s" => 0}, ...]
    end

    attribute :permeability, :decimal do
      allow_nil? false
      description "Boundary permeability (0.0 = impermeable, 1.0 = fully permeable)"
      default Decimal.new("1.0")
      constraints precision: 3, scale: 2
    end

    attribute :crossing_rules, :map do
      allow_nil? false
      description "Rules governing boundary crossing"
      default %{
        "allow_agents" => true,
        "allow_resources" => true,
        "require_permission" => false,
        "crossing_cost" => 1.0,
        "delay_seconds" => 0
      }
    end

    attribute :directional_properties, :map do
      allow_nil? false
      description "Direction-specific boundary properties"
      default %{
        "bidirectional" => true,
        "entry_effects" => %{},
        "exit_effects" => %{},
        "preferred_direction" => nil
      }
    end

    attribute :security_level, :integer do
      allow_nil? false
      description "Security level for boundary crossing (0-10)"
      default 0
      constraints min: 0, max: 10
    end

    attribute :monitoring_enabled, :boolean do
      allow_nil? false
      description "Whether boundary crossings are monitored"
      default false
    end

    attribute :crossing_history, :map do
      allow_nil? false
      description "Recent crossing statistics"
      default %{
        "total_crossings" => 0,
        "recent_crossings" => 0,
        "last_crossing" => nil,
        "blocked_attempts" => 0
      }
    end

    attribute :environmental_effects, :map do
      allow_nil? false
      description "Environmental effects at boundary"
      default %{
        "energy_barrier" => false,
        "visibility_modifier" => 1.0,
        "communication_interference" => 0.0,
        "special_effects" => []
      }
    end

    attribute :maintenance_status, :atom do
      allow_nil? false
      description "Current maintenance status"
      default :stable
      constraints one_of: [:stable, :degrading, :unstable, :failing, :maintenance, :offline]
    end

    attribute :last_maintenance, :utc_datetime do
      allow_nil? true
      description "Timestamp of last maintenance check"
    end

    attribute :zone_id, :uuid do
      allow_nil? false
      description "ID of the primary zone"
    end

    attribute :adjacent_zone_id, :uuid do
      allow_nil? true
      description "ID of the adjacent zone (if applicable)"
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional boundary metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :zone, Thunderline.Thundergrid.Resources.GridZone do
      source_attribute :zone_id
      destination_attribute :id
    end

    belongs_to :adjacent_zone, Thunderline.Thundergrid.Resources.GridZone do
      source_attribute :adjacent_zone_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:boundary_name, :boundary_type, :geometry_type, :boundary_points,
              :permeability, :crossing_rules, :directional_properties,
              :security_level, :monitoring_enabled, :environmental_effects,
              :zone_id, :adjacent_zone_id, :metadata]

      change after_action(fn _changeset, boundary, _context ->
        # Initialize boundary monitoring if enabled
        if boundary.monitoring_enabled do
          setup_boundary_monitoring(boundary)
        end

        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "thundergrid:boundaries",
          {:boundary_created, %{
            boundary_id: boundary.id,
            zone_id: boundary.zone_id,
            adjacent_zone_id: boundary.adjacent_zone_id
          }}
        )

        {:ok, boundary}
      end)
    end

    update :update do
      accept [:boundary_name, :boundary_type, :permeability, :crossing_rules,
              :directional_properties, :security_level, :monitoring_enabled,
              :environmental_effects, :metadata]
    end

    update :record_crossing do
      argument :agent_id, :uuid, allow_nil?: false
      argument :direction, :atom, allow_nil?: false
      argument :crossing_time, :utc_datetime, allow_nil?: false

      change fn changeset, context ->
        current_history = Ash.Changeset.get_attribute(changeset, :crossing_history) || %{}

        updated_history = %{
          current_history |
          "total_crossings" => Map.get(current_history, "total_crossings", 0) + 1,
          "recent_crossings" => Map.get(current_history, "recent_crossings", 0) + 1,
          "last_crossing" => context.arguments.crossing_time
        }

        Ash.Changeset.change_attribute(changeset, :crossing_history, updated_history)
      end

      change after_action(fn _changeset, boundary, context ->
        if boundary.monitoring_enabled do
          Phoenix.PubSub.broadcast(
            Thunderline.PubSub,
            "thundergrid:boundaries:#{boundary.id}",
            {:boundary_crossed, %{
              boundary_id: boundary.id,
              agent_id: context.arguments.agent_id,
              direction: context.arguments.direction,
              timestamp: context.arguments.crossing_time
            }}
          )
        end

        {:ok, boundary}
      end)
    end

    update :update_permeability do
      accept [:permeability]

      argument :new_permeability, :decimal, allow_nil?: false

      change fn changeset, context ->
        Ash.Changeset.change_attribute(changeset, :permeability, context.arguments.new_permeability)
      end
    end

    update :set_maintenance_status do
      accept [:maintenance_status, :last_maintenance]

      argument :status, :atom, allow_nil?: false

      change fn changeset, context ->
        changeset
        |> Ash.Changeset.change_attribute(:maintenance_status, context.arguments.status)
        |> Ash.Changeset.change_attribute(:last_maintenance, DateTime.utc_now())
      end
    end

    action :check_crossing_permission do
      argument :agent_id, :uuid, allow_nil?: false
      argument :direction, :atom, allow_nil?: false

      run fn input, context ->
        boundary = input
        agent_id = context.arguments.agent_id
        direction = context.arguments.direction

        # Check crossing rules
        can_cross = check_crossing_permission_logic(boundary, agent_id, direction)

        {:ok, %{permitted: can_cross, boundary_id: boundary.id}}
      end
    end

    read :by_zone do
      argument :zone_id, :uuid, allow_nil?: false
      filter expr(zone_id == ^arg(:zone_id) or adjacent_zone_id == ^arg(:zone_id))
    end

    read :between_zones do
      argument :zone_a_id, :uuid, allow_nil?: false
      argument :zone_b_id, :uuid, allow_nil?: false

      filter expr(
        (zone_id == ^arg(:zone_a_id) and adjacent_zone_id == ^arg(:zone_b_id)) or
        (zone_id == ^arg(:zone_b_id) and adjacent_zone_id == ^arg(:zone_a_id))
      )
    end

    read :by_type do
      argument :boundary_type, :atom, allow_nil?: false
      filter expr(boundary_type == ^arg(:boundary_type))
    end

    read :monitored_boundaries do
      filter expr(monitoring_enabled == true)
    end

    read :high_security do
      filter expr(security_level >= 7)
    end

    read :maintenance_needed do
      filter expr(maintenance_status in [:degrading, :unstable, :failing])
    end

    read :active_boundaries do
      filter expr(maintenance_status not in [:offline, :maintenance])
    end

    read :recent_crossings do
      filter expr(
        fragment("(?->>'recent_crossings')::integer > 0", crossing_history)
      )
      prepare build(sort: [updated_at: :desc])
    end
  end

  # policies do
  #   bypass AshAuthentication.Checks.AshAuthenticationInteraction do
  #     authorize_if always()
  #   end

  #   policy always() do
  #     authorize_if always()
  #   end
  # end

  code_interface do
    define :create
    define :update
    define :record_crossing, args: [:agent_id, :direction, :crossing_time]
    define :update_permeability, args: [:new_permeability]
    define :set_maintenance_status, args: [:status]
    define :check_crossing_permission, args: [:agent_id, :direction]
    define :by_zone, args: [:zone_id]
    define :between_zones, args: [:zone_a_id, :zone_b_id]
    define :by_type, args: [:boundary_type]
    define :monitored_boundaries, action: :monitored_boundaries
    define :high_security, action: :high_security
    define :maintenance_needed, action: :maintenance_needed
    define :active_boundaries, action: :active_boundaries
    define :recent_crossings, action: :recent_crossings
  end

  postgres do
    table "thundergrid_zone_boundaries"
    repo Thunderline.Repo

    references do
      reference :zone, on_delete: :delete, on_update: :update
      reference :adjacent_zone, on_delete: :delete, on_update: :update
    end

    custom_indexes do
      index [:zone_id, :adjacent_zone_id], unique: true
      index [:boundary_type]
      index [:security_level]
      index [:monitoring_enabled]
      index [:maintenance_status]
      index "USING GIN (boundary_points)", name: "zone_boundaries_points_idx"
      index "USING GIN (crossing_history)", name: "zone_boundaries_history_idx"
    end

    check_constraints do
      check_constraint :valid_permeability, "permeability >= 0.0 AND permeability <= 1.0"
      check_constraint :valid_security, "security_level >= 0 AND security_level <= 10"
      check_constraint :different_zones, "zone_id != adjacent_zone_id"
    end
  end

  json_api do
    type "zone_boundary"

    routes do
      base "/zone_boundaries"
      get :read
      index :read
      post :create
      patch :update
      delete :destroy

      # TODO: Convert to Ash 3.x route syntax after MCP consolidation complete
      # post "/:id/record_crossing", :record_crossing
      # post "/:id/update_permeability", :update_permeability
      # post "/:id/set_maintenance", :set_maintenance_status
      # get "/:id/check_permission/:agent_id/:direction", :check_crossing_permission
      # get "/zone/:zone_id", :by_zone
            # get "/between_zones/:zone_a_id/:zone_b_id", :between_zones
      # get "/type/:boundary_type", :by_type
      # TODO: Convert to Ash 3.x route syntax - currently causing compilation issues
      # get "/monitored", :monitored_boundaries, []
      # get "/high_security", :high_security, []
      # get "/maintenance_needed", :maintenance_needed, []
      # get "/active", :active_boundaries, []
      # get "/recent_crossings", :recent_crossings, []
    end
  end

  identities do
    identity :unique_zone_boundary, [:zone_id, :adjacent_zone_id]
  end

  validations do
    validate present([:boundary_name, :zone_id, :adjacent_zone_id])
    # TODO: Implement Thundergrid.Validations module
    # validate {Thundergrid.Validations, :valid_boundary_points}, on: [:create, :update]
    # validate {Thundergrid.Validations, :different_zones}, on: [:create, :update]
  end

  preparations do
    prepare build(load: [:zone, :adjacent_zone])
  end

  # Helper functions for boundary geometry
  def point_on_boundary?(boundary, {q, r, s}) do
    # Implementation would check if point lies on boundary geometry
    # For now, simple check
    true
  end

  def calculate_crossing_cost(boundary, agent_properties \\ %{}) do
    base_cost = get_in(boundary.crossing_rules, ["crossing_cost"]) || 1.0

    # Apply modifiers based on agent properties and boundary conditions
    modifier = case boundary.boundary_type do
      :barrier -> 2.0
      :gateway -> 0.5
      :checkpoint -> 1.5
      _ -> 1.0
    end

    base_cost * modifier
  end

  # Private helper functions
  defp setup_boundary_monitoring(boundary) do
    # Implementation would set up monitoring systems
    :ok
  end

  defp check_crossing_permission_logic(boundary, agent_id, direction) do
    # Check permeability
    if Decimal.to_float(boundary.permeability) == 0.0 do
      false
    else
      # Check crossing rules
      rules = boundary.crossing_rules

      case direction do
        :entry -> Map.get(rules, "allow_agents", true)
        :exit -> Map.get(rules, "allow_agents", true)
        _ -> false
      end
    end
  end
end
