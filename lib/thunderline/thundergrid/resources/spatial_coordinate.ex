defmodule Thunderline.Thundergrid.Resources.SpatialCoordinate do
  @moduledoc """
  SpatialCoordinate Resource - Precise Position Tracking

  Manages individual coordinate points within the infinite hex lattice.
  Provides precise positioning for agents, resources, and structures
  with support for sub-hex precision and 3D elevation.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  import Ash.Resource.Change.Builtins
  import Ash.Resource.Change.Builtins

  postgres do
    table "thundergrid_spatial_coordinates"
    repo Thunderline.Repo

    custom_indexes do
      index [:hex_q, :hex_r], unique: false
      index [:hex_q, :hex_r, :hex_s], unique: false
      index [:zone_id]
      index [:occupant_id]
      index [:occupancy_status]
      index [:coordinate_type]
      index [:last_accessed]
      index "USING GIN (properties)", name: "spatial_coordinates_properties_idx"
    end

    check_constraints do
      check_constraint :valid_hex_sum, "hex_q + hex_r + hex_s = 0"
      check_constraint :valid_sub_hex_x, "sub_hex_x >= -0.5 AND sub_hex_x <= 0.5"
      check_constraint :valid_sub_hex_y, "sub_hex_y >= -0.5 AND sub_hex_y <= 0.5"
    end
  end

  json_api do
    type "spatial_coordinate"

    routes do
      base("/spatial_coordinates")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      # TODO: Convert to Ash 3.x route syntax after MCP consolidation complete
      # post "/:id/occupy", :occupy
      # post "/:id/vacate", :vacate
      # post "/:id/reserve", :reserve
      # post "/:id/move_to", :move_to
      # get "/hex/:hex_q/:hex_r", :at_hex
      # TODO: Convert to Ash 3.x route syntax - currently causing compilation issues
      # get "/zone/:zone_id", :in_zone, []
      # get "/occupant/:occupant_id", :by_occupant, []
      # get "/vacant", :vacant_coordinates, []
      # get "/range/:center_q/:center_r/:range", :within_range, []
      # get "/type/:coordinate_type", :by_type, []
      # get "/recent_activity", :recent_activity, []
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
    define :occupy, args: [:occupant_id, :occupant_type]
    define :vacate, args: []
    define :reserve, args: [:reserving_agent_id]
    define :move_to, args: [:hex_q, :hex_r, :sub_hex_x, :sub_hex_y, :elevation]
    define :at_hex, args: [:hex_q, :hex_r]
    define :in_zone, args: [:zone_id]
    define :by_occupant, args: [:occupant_id]
    define :vacant_coordinates, action: :vacant_coordinates
    define :within_range, args: [:center_q, :center_r, :range]
    define :by_type, args: [:coordinate_type]
    define :recent_activity, action: :recent_activity
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :hex_q,
        :hex_r,
        :sub_hex_x,
        :sub_hex_y,
        :elevation,
        :coordinate_type,
        :properties,
        :navigation_data,
        :zone_id,
        :metadata
      ]

      change fn changeset, _context ->
        # Calculate hex_s coordinate (q + r + s = 0)
        q = Ash.Changeset.get_attribute(changeset, :hex_q)
        r = Ash.Changeset.get_attribute(changeset, :hex_r)
        s = -(q + r)

        Ash.Changeset.change_attribute(changeset, :hex_s, s)
      end

      change after_action(fn _changeset, coordinate, _context ->
               # Update spatial index
               update_spatial_index(coordinate)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thundergrid:coordinates",
                 {:coordinate_created,
                  %{
                    id: coordinate.id,
                    hex_coordinates: {coordinate.hex_q, coordinate.hex_r, coordinate.hex_s}
                  }}
               )

               {:ok, coordinate}
             end)
    end

    update :update do
      accept [
        :sub_hex_x,
        :sub_hex_y,
        :elevation,
        :coordinate_type,
        :properties,
        :navigation_data,
        :metadata
      ]
    end

    update :occupy do
      accept [:occupancy_status, :occupant_id, :occupant_type, :last_accessed]
      require_atomic? false

      argument :occupant_id, :uuid, allow_nil?: false
      argument :occupant_type, :atom, allow_nil?: false

      change fn changeset, context ->
        changeset
        |> Ash.Changeset.change_attribute(:occupancy_status, :occupied)
        |> Ash.Changeset.change_attribute(:occupant_id, context.arguments.occupant_id)
        |> Ash.Changeset.change_attribute(:occupant_type, context.arguments.occupant_type)
        |> Ash.Changeset.change_attribute(:last_accessed, DateTime.utc_now())
      end

      change after_action(fn _changeset, coordinate, _context ->
               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thundergrid:coordinates:#{coordinate.id}",
                 {:coordinate_occupied,
                  %{
                    coordinate_id: coordinate.id,
                    occupant_id: coordinate.occupant_id,
                    occupant_type: coordinate.occupant_type
                  }}
               )

               {:ok, coordinate}
             end)
    end

    update :vacate do
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:occupancy_status, :vacant)
        |> Ash.Changeset.change_attribute(:occupant_id, nil)
        |> Ash.Changeset.change_attribute(:occupant_type, nil)
        |> Ash.Changeset.change_attribute(:last_accessed, DateTime.utc_now())
      end

      change after_action(fn _changeset, coordinate, _context ->
               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thundergrid:coordinates:#{coordinate.id}",
                 {:coordinate_vacated, %{coordinate_id: coordinate.id}}
               )

               {:ok, coordinate}
             end)
    end

    update :reserve do
      require_atomic? false

      argument :reserving_agent_id, :uuid, allow_nil?: false

      change fn changeset, context ->
        changeset
        |> Ash.Changeset.change_attribute(:occupancy_status, :reserved)
        |> Ash.Changeset.change_attribute(:occupant_id, context.arguments.reserving_agent_id)
        |> Ash.Changeset.change_attribute(:occupant_type, :reservation)
        |> Ash.Changeset.change_attribute(:last_accessed, DateTime.utc_now())
      end
    end

    update :move_to do
      accept [:hex_q, :hex_r, :sub_hex_x, :sub_hex_y, :elevation]

      change fn changeset, _context ->
        # Recalculate hex_s when coordinates change
        q = Ash.Changeset.get_attribute(changeset, :hex_q)
        r = Ash.Changeset.get_attribute(changeset, :hex_r)
        s = -(q + r)

        changeset
        |> Ash.Changeset.change_attribute(:hex_s, s)
        |> Ash.Changeset.change_attribute(:last_accessed, DateTime.utc_now())
      end
    end

    read :at_hex do
      argument :hex_q, :integer, allow_nil?: false
      argument :hex_r, :integer, allow_nil?: false

      filter expr(hex_q == ^arg(:hex_q) and hex_r == ^arg(:hex_r))
    end

    read :in_zone do
      argument :zone_id, :uuid, allow_nil?: false
      filter expr(zone_id == ^arg(:zone_id))
    end

    read :by_occupant do
      argument :occupant_id, :uuid, allow_nil?: false
      filter expr(occupant_id == ^arg(:occupant_id))
    end

    read :vacant_coordinates do
      filter expr(occupancy_status == :vacant)
    end

    read :within_range do
      argument :center_q, :integer, allow_nil?: false
      argument :center_r, :integer, allow_nil?: false
      argument :range, :integer, allow_nil?: false

      prepare fn query, context ->
        # Hex distance calculation: max(|dq|, |dr|, |ds|)
        # For now, simple implementation
        query
      end
    end

    read :by_type do
      argument :coordinate_type, :atom, allow_nil?: false
      filter expr(coordinate_type == ^arg(:coordinate_type))
    end

    read :recent_activity do
      filter expr(not is_nil(last_accessed) and last_accessed > ago(1, :hour))
      prepare build(sort: [last_accessed: :desc])
    end
  end

  preparations do
    prepare build(load: [:zone])
  end

  validations do
    validate present([:hex_q, :hex_r])
    validate Thunderline.Thundergrid.Validations.ValidHexCoordinates
    validate Thunderline.Thundergrid.Validations.ValidSubHexRange
  end

  attributes do
    uuid_primary_key :id

    attribute :hex_q, :integer do
      allow_nil? false
      description "Hex coordinate Q (column)"
    end

    attribute :hex_r, :integer do
      allow_nil? false
      description "Hex coordinate R (row)"
    end

    attribute :hex_s, :integer do
      allow_nil? false
      description "Hex coordinate S (depth) - computed as -(q+r)"
    end

    attribute :sub_hex_x, :decimal do
      allow_nil? false
      description "Sub-hex X offset (-0.5 to 0.5)"
      default Decimal.new("0.0")
      constraints precision: 10, scale: 6
    end

    attribute :sub_hex_y, :decimal do
      allow_nil? false
      description "Sub-hex Y offset (-0.5 to 0.5)"
      default Decimal.new("0.0")
      constraints precision: 10, scale: 6
    end

    attribute :elevation, :decimal do
      allow_nil? false
      description "Z-axis elevation"
      default Decimal.new("0.0")
      constraints precision: 10, scale: 3
    end

    attribute :coordinate_type, :atom do
      allow_nil? false
      description "Type of coordinate point"
      default :position

      constraints one_of: [
                    :position,
                    :waypoint,
                    :landmark,
                    :boundary,
                    :spawn_point,
                    :resource_node
                  ]
    end

    attribute :occupancy_status, :atom do
      allow_nil? false
      description "Current occupancy status"
      default :vacant
      constraints one_of: [:vacant, :occupied, :reserved, :blocked, :unstable]
    end

    attribute :occupant_id, :uuid do
      allow_nil? true
      description "ID of current occupant (agent/resource/structure)"
    end

    attribute :occupant_type, :atom do
      allow_nil? true
      description "Type of current occupant"
      constraints one_of: [:thunderbit, :thunderbolt, :pac_home, :resource, :structure, :marker]
    end

    attribute :properties, :map do
      allow_nil? false
      description "Coordinate-specific properties"

      default %{
        "movement_cost" => 1.0,
        "visibility_modifier" => 1.0,
        "energy_level" => 1.0,
        "stability" => 1.0
      }
    end

    attribute :navigation_data, :map do
      allow_nil? false
      description "Navigation and pathfinding data"

      default %{
        "accessible" => true,
        "connections" => [],
        "pathfinding_weight" => 1.0,
        "special_movement_rules" => []
      }
    end

    attribute :last_accessed, :utc_datetime do
      allow_nil? true
      description "Timestamp of last access/interaction"
    end

    attribute :zone_id, :uuid do
      allow_nil? true
      description "ID of the zone this coordinate belongs to"
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional coordinate metadata"
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

    # Cross-domain relationships removed - invalid destination
    # TODO: Consider if direct Agent relationship is needed instead
  end

  identities do
    identity :unique_hex_position, [:hex_q, :hex_r, :sub_hex_x, :sub_hex_y, :elevation]
  end

  # Calculation helpers
  def hex_distance({q1, r1, s1}, {q2, r2, s2}) do
    max(abs(q1 - q2), max(abs(r1 - r2), abs(s1 - s2)))
  end

  def cube_to_axial({q, r, _s}), do: {q, r}
  def axial_to_cube({q, r}), do: {q, r, -(q + r)}

  def hex_neighbors({q, r, s}) do
    [
      {q + 1, r - 1, s},
      {q + 1, r, s - 1},
      {q, r + 1, s - 1},
      {q - 1, r + 1, s},
      {q - 1, r, s + 1},
      {q, r - 1, s + 1}
    ]
  end

  # Private helper functions
  defp update_spatial_index(_coordinate) do
    # Implementation would update spatial indexing system
    :ok
  end
end
