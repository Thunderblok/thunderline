defmodule Thunderline.Thundergrid.Resources.GridZone do
  @moduledoc """
  GridZone Resource - Spatial zone management for GraphQL interface

  Manages discrete spatial zones within the hexagonal lattice.
  Each zone represents a bounded area with specific properties,
  resource allocations, and Thunderbolt mesh populations.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource, AshOban.Resource, AshGraphql.Resource],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  json_api do
    type "grid_zone"

    routes do
      base("/grid_zones")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      patch(:connect_zone, route: "/:id/connect")
      patch(:disconnect_zone, route: "/:id/disconnect")
      patch(:update_usage, route: "/:id/update_usage")
      get :by_coordinates, route: "/coordinates/:q/:r"
      get :within_radius, route: "/within/:center_q/:center_r/:radius"
      get :by_type, route: "/type/:zone_type"
      get :active_zones, route: "/active"
      get :high_activity, route: "/high_activity"
    end
  end

  code_interface do
    define :create
    define :update
    define :update_usage, args: [:current_usage]
    define :connect_zone, args: [:target_zone_id]
    define :disconnect_zone, args: [:target_zone_id]
    define :by_coordinates, args: [:q, :r]
    define :within_radius, args: [:center_q, :center_r, :radius]
    define :by_type, args: [:zone_type]
    define :active_zones, action: :active_zones
    define :high_activity, action: :high_activity
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :zone_name,
        :zone_type,
        :hex_coordinates,
        :zone_radius,
        :capacity_limits,
        :zone_properties,
        :governance_rules,
        :environmental_factors,
        :metadata
      ]

      change after_action(fn _changeset, zone, _context ->
               # Initialize zone boundaries
               create_zone_boundaries(zone)

               # Register zone in spatial index
               register_in_spatial_index(zone)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thundergrid:zones",
                 {:zone_created, %{zone_id: zone.id, coordinates: zone.hex_coordinates}}
               )

               {:ok, zone}
             end)
    end

    update :update do
      accept [
        :zone_name,
        :zone_type,
        :capacity_limits,
        :zone_properties,
        :governance_rules,
        :environmental_factors,
        :metadata
      ]
    end

    update :update_usage do
      accept [:current_usage, :last_activity]

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :last_activity, DateTime.utc_now())
      end
    end

    update :connect_zone do
      argument :target_zone_id, :uuid, allow_nil?: false

      change fn changeset, context ->
        target_id = context.arguments.target_zone_id
        current_connections = Ash.Changeset.get_attribute(changeset, :connected_zones) || []

        updated_connections =
          if target_id in current_connections do
            current_connections
          else
            [target_id | current_connections]
          end

        Ash.Changeset.change_attribute(changeset, :connected_zones, updated_connections)
      end
    end

    update :disconnect_zone do
      argument :target_zone_id, :uuid, allow_nil?: false

      change fn changeset, context ->
        target_id = context.arguments.target_zone_id
        current_connections = Ash.Changeset.get_attribute(changeset, :connected_zones) || []
        updated_connections = List.delete(current_connections, target_id)

        Ash.Changeset.change_attribute(changeset, :connected_zones, updated_connections)
      end
    end

    read :by_coordinates do
      argument :q, :integer, allow_nil?: false
      argument :r, :integer, allow_nil?: false

      filter expr(
               fragment("(?->>'q')::integer = ?", hex_coordinates, ^arg(:q)) and
                 fragment("(?->>'r')::integer = ?", hex_coordinates, ^arg(:r))
             )
    end

    read :within_radius do
      argument :center_q, :integer, allow_nil?: false
      argument :center_r, :integer, allow_nil?: false
      argument :radius, :integer, allow_nil?: false

      prepare fn query, context ->
        # Hex distance calculation would be implemented here
        # For now, simple bounding box
        query
      end
    end

    read :by_type do
      argument :zone_type, :atom, allow_nil?: false
      filter expr(zone_type == ^arg(:zone_type))
    end

    read :active_zones do
      filter expr(status == :active)
    end

    read :high_activity do
      filter expr(not is_nil(last_activity) and last_activity > ago(1, :hour))
      prepare build(sort: [last_activity: :desc])
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      authorize_if always()
    end
  end

  preparations do
    prepare build(load: [:spatial_coordinates, :zone_boundaries, :grid_resources])
  end

  validations do
    validate present(:zone_name), message: "Zone name is required"
    validate present(:zone_type), message: "Zone type is required"
    validate present(:hex_coordinates), message: "Coordinates are required"
    validate present(:zone_radius), message: "Zone radius is required"

    # Equivalent to former DB constraint: zone_radius > 0
    validate compare(:zone_radius, greater_than: 0), message: "Zone radius must be positive"

    # Equivalent to former DB constraint: jsonb_typeof(hex_coordinates) = 'object'
    validate match(:hex_coordinates, ~r/.+/),
      message: "Coordinates must be a valid object",
      where: [present(:hex_coordinates)]
  end

  validations do
    validate present([:zone_name, :hex_coordinates, :zone_radius])
  end

  attributes do
    uuid_primary_key :id

    attribute :zone_name, :string do
      allow_nil? false
      description "Human-readable zone identifier"
      constraints min_length: 1, max_length: 100
    end

    attribute :zone_type, :atom do
      allow_nil? false
      description "Type of spatial zone"
      default :standard
      constraints one_of: [:standard, :settlement, :resource, :transit, :restricted, :void]
    end

    attribute :hex_coordinates, :map do
      allow_nil? false
      description "Hex lattice coordinates {q, r, s}"
      default %{"q" => 0, "r" => 0, "s" => 0}
    end

    attribute :zone_radius, :integer do
      allow_nil? false
      description "Zone radius in hex tiles"
      default 10
      constraints min: 1, max: 1000
    end

    attribute :capacity_limits, :map do
      allow_nil? false
      description "Zone capacity and resource limits"

      default %{
        "max_agents" => 100,
        "max_resources" => 50,
        "max_structures" => 25,
        "energy_capacity" => 1000
      }
    end

    attribute :current_usage, :map do
      allow_nil? false
      description "Current zone utilization"

      default %{
        "agent_count" => 0,
        "resource_count" => 0,
        "structure_count" => 0,
        "energy_usage" => 0
      }
    end

    attribute :zone_properties, :map do
      allow_nil? false
      description "Zone-specific properties and modifiers"

      default %{
        "movement_cost" => 1.0,
        "visibility_range" => 5,
        "energy_efficiency" => 1.0,
        "resource_multiplier" => 1.0
      }
    end

    attribute :governance_rules, :map do
      allow_nil? false
      description "Zone governance and access control"

      default %{
        "access_level" => "public",
        "owner_id" => nil,
        "entry_permissions" => [],
        "special_rules" => []
      }
    end

    attribute :status, :atom do
      allow_nil? false
      description "Current zone operational status"
      default :active
      constraints one_of: [:active, :dormant, :restricted, :quarantined, :maintenance]
    end

    attribute :environmental_factors, :map do
      allow_nil? false
      description "Environmental conditions affecting the zone"

      default %{
        "temperature" => 20.0,
        "energy_density" => 1.0,
        "interference_level" => 0.0,
        "hazard_level" => 0
      }
    end

    attribute :connected_zones, {:array, :uuid} do
      allow_nil? false
      description "List of directly connected zone IDs"
      default []
    end

    attribute :last_activity, :utc_datetime do
      allow_nil? true
      description "Timestamp of last significant activity"
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional zone metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :spatial_coordinates, Thunderline.Thundergrid.Resources.SpatialCoordinate do
      destination_attribute :zone_id
    end

    has_many :zone_boundaries, Thunderline.Thundergrid.Resources.ZoneBoundary do
      destination_attribute :zone_id
    end

    has_many :grid_resources, Thunderline.Thundergrid.Resources.GridResource do
      destination_attribute :zone_id
    end

    # Cross-domain relationships removed - invalid destination
    # TODO: Consider if direct GridZone->Agent relationship is needed
  # PAC Homes managed via ZoneContainer relationships (resource moved to Thunderblock domain)
  end

  # oban do
  #   scheduled_actions do
  #     schedule :zone_maintenance, "0 */6 * * *", action: :active_zones
  #   end
  # end

  identities do
    identity :unique_zone_name, [:zone_name]
  end

  # Private helper functions
  defp create_zone_boundaries(zone) do
    # Implementation would create ZoneBoundary records
    :ok
  end

  defp register_in_spatial_index(zone) do
    # Implementation would register zone in spatial indexing system
    :ok
  end
end
