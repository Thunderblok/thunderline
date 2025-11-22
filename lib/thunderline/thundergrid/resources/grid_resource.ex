defmodule Thunderline.Thundergrid.Resources.GridResource do
  @moduledoc """
  GridResource Resource - Spatial Resource Management

  Manages resources, structures, and objects distributed across
  the spatial grid. Handles resource placement, availability,
  extraction, and spatial relationships.
  """

  use Ash.Resource,
    domain: Thunderline.Thundergrid.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  json_api do
    type "grid_resource"

    routes do
      base("/grid_resources")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)

      route(:patch, "/:id/extract", :extract_resource)
      route(:post, "/:id/claim", :claim_ownership)
      route(:post, "/:id/release", :release_ownership)
      route(:post, "/:id/relocate", :relocate)
      route(:post, "/:id/regenerate", :regenerate)
      get :at_coordinates, route: "/coordinates/:hex_q/:hex_r"
      get :in_zone, route: "/zone/:zone_id"
      get :by_type, route: "/type/:resource_type"
      get :by_owner, route: "/owner/:owner_id"
      get :extractable_resources, route: "/extractable"
      get :depleted_resources, route: "/depleted"
      get :high_value, route: "/high_value"
      get :recently_discovered, route: "/recently_discovered"
      get :within_range, route: "/range/:center_q/:center_r/:range"
    end
  end

  code_interface do
    domain Thunderline.Thundergrid.Domain

    define :at_coordinates, action: :at_coordinates, args: [:hex_q, :hex_r]
    define :within_range, action: :within_range, args: [:center_q, :center_r, :range]
    define :list_all, action: :read
    define :claim_ownership, action: :claim_ownership, args: [:id, :claimant_id, :claimant_type]
    define :release_ownership, action: :release_ownership, args: [:id]
    define :relocate, action: :relocate, args: [:id, :new_coordinates, :new_position]
    define :regenerate, action: :regenerate, args: [:id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :resource_name,
        :resource_type,
        :resource_subtype,
        :hex_coordinates,
        :precise_position,
        :quantity_data,
        :physical_properties,
        :interaction_rules,
        :ownership_data,
        :economic_data,
        :spatial_effects,
        :discovery_data,
        :zone_id,
        :coordinate_id,
        :metadata
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:resource_status, :active)
        |> update_coordinate_occupancy()
      end

      change after_action(fn _changeset, resource, _context ->
               # Update spatial index
               update_spatial_resource_index(resource)

               # Apply spatial effects to surrounding area
               apply_spatial_effects(resource)

               Phoenix.PubSub.broadcast(
                 Thunderline.PubSub,
                 "thundergrid:resources",
                 {:resource_placed,
                  %{
                    resource_id: resource.id,
                    coordinates: resource.hex_coordinates,
                    type: resource.resource_type
                  }}
               )

               {:ok, resource}
             end)
    end

    update :update do
      accept [
        :resource_name,
        :resource_subtype,
        :quantity_data,
        :physical_properties,
        :interaction_rules,
        :ownership_data,
        :economic_data,
        :spatial_effects,
        :discovery_data,
        :metadata
      ]
    end

    action :extract_resource do
      argument :extractor_id, :uuid, allow_nil?: false
      argument :extraction_amount, :integer, allow_nil?: false

      run fn input, context ->
        current_quantity = get_in(input.resource.quantity_data, ["current_quantity"]) || 0
        extraction_amount = context.arguments.extraction_amount

        # Calculate actual extraction based on extraction rate and available quantity
        quantity_data = input.resource.quantity_data || %{}
        extraction_rate = Map.get(quantity_data, "extraction_rate", 1.0)
        actual_extraction = min(extraction_amount * extraction_rate, current_quantity)

        new_quantity = max(0, current_quantity - actual_extraction)
        updated_quantity_data = Map.put(quantity_data, "current_quantity", new_quantity)

        # Update status if depleted
        new_status = if new_quantity == 0, do: :depleted, else: :active

        input.resource
        |> Ash.Changeset.for_update(:update, %{
          quantity_data: updated_quantity_data,
          resource_status: new_status,
          last_interaction: DateTime.utc_now()
        })
        |> Ash.update!(authorize?: false)
        |> then(fn resource ->
          Phoenix.PubSub.broadcast(
            Thunderline.PubSub,
            "thundergrid:resources:#{resource.id}",
            {:resource_extracted,
             %{
               resource_id: resource.id,
               extractor_id: context.arguments.extractor_id,
               amount: context.arguments.extraction_amount,
               remaining: get_in(resource.quantity_data, ["current_quantity"])
             }}
          )

          {:ok, resource}
        end)
      end
    end

    action :claim_ownership, :struct do
      description "Claim ownership of grid resource"
      constraints instance_of: Thunderline.Thundergrid.Resources.GridResource

      argument :id, :uuid, allow_nil?: false
      argument :claimant_id, :uuid, allow_nil?: false
      argument :claimant_type, :atom, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderline.Thundergrid.Resources.GridResource, input.arguments.id) do
          nil ->
            {:error, "Grid resource not found"}

          resource ->
            ownership_data = %{
              "owner_id" => input.arguments.claimant_id,
              "owner_type" => input.arguments.claimant_type,
              "access_level" => "private",
              "claimed_at" => DateTime.utc_now()
            }

            updated_resource =
              Ash.update!(resource, :_claim_ownership_internal, %{
                ownership_data: ownership_data,
                last_interaction: DateTime.utc_now()
              })

            {:ok, updated_resource}
        end
      end
    end

    # Internal update action for claim_ownership
    update :_claim_ownership_internal do
      description "Internal update for claim_ownership operation"
      accept [:ownership_data, :last_interaction]
    end

    action :release_ownership, :struct do
      description "Release ownership of grid resource"
      constraints instance_of: Thunderline.Thundergrid.Resources.GridResource

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderline.Thundergrid.Resources.GridResource, input.arguments.id) do
          nil ->
            {:error, "Grid resource not found"}

          resource ->
            ownership_data = %{
              "owner_id" => nil,
              "owner_type" => nil,
              "access_level" => "public",
              "claimed_at" => nil
            }

            updated_resource =
              Ash.update!(resource, :_release_ownership_internal, %{
                ownership_data: ownership_data,
                last_interaction: DateTime.utc_now()
              })

            {:ok, updated_resource}
        end
      end
    end

    # Internal update action for release_ownership
    update :_release_ownership_internal do
      description "Internal update for release_ownership operation"
      accept [:ownership_data, :last_interaction]
    end

    action :relocate, :struct do
      description "Relocate grid resource to new coordinates"
      constraints instance_of: Thunderline.Thundergrid.Resources.GridResource

      argument :id, :uuid, allow_nil?: false
      argument :new_coordinates, :map, allow_nil?: false
      argument :new_position, :map, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderline.Thundergrid.Resources.GridResource, input.arguments.id) do
          nil ->
            {:error, "Grid resource not found"}

          resource ->
            updated_resource =
              Ash.update!(resource, :_relocate_internal, %{
                hex_coordinates: input.arguments.new_coordinates,
                precise_position: input.arguments.new_position,
                last_interaction: DateTime.utc_now()
              })

            # Update spatial effects at new location
            apply_spatial_effects(updated_resource)

            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "thundergrid:resources:#{updated_resource.id}",
              {:resource_relocated,
               %{
                 resource_id: updated_resource.id,
                 new_coordinates: updated_resource.hex_coordinates
               }}
            )

            {:ok, updated_resource}
        end
      end
    end

    # Internal update action for relocate
    update :_relocate_internal do
      description "Internal update for relocate operation"
      accept [:hex_coordinates, :precise_position, :last_interaction]
    end

    action :regenerate, :struct do
      description "Regenerate resource quantities based on regeneration rate"
      constraints instance_of: Thunderline.Thundergrid.Resources.GridResource

      argument :id, :uuid, allow_nil?: false

      run fn input, _context ->
        case Ash.get!(Thunderline.Thundergrid.Resources.GridResource, input.arguments.id) do
          nil ->
            {:error, "Grid resource not found"}

          resource ->
            quantity_data = resource.quantity_data || %{}
            current = Map.get(quantity_data, "current_quantity", 0)
            max_qty = Map.get(quantity_data, "max_quantity", 100)
            regen_rate = Map.get(quantity_data, "regeneration_rate", 0.0)

            new_quantity = min(max_qty, current + regen_rate)
            updated_quantity_data = Map.put(quantity_data, "current_quantity", new_quantity)

            new_status =
              cond do
                new_quantity == 0 -> :depleted
                new_quantity < max_qty && regen_rate > 0 -> :regenerating
                true -> :active
              end

            updated_resource =
              Ash.update!(resource, :_regenerate_internal, %{
                quantity_data: updated_quantity_data,
                resource_status: new_status
              })

            {:ok, updated_resource}
        end
      end
    end

    # Internal update action for regenerate
    update :_regenerate_internal do
      description "Internal update for regenerate operation"
      accept [:quantity_data, :resource_status]
    end

    read :at_coordinates do
      argument :hex_q, :integer, allow_nil?: false
      argument :hex_r, :integer, allow_nil?: false

      filter expr(
               fragment("(?->>'q')::integer = ?", hex_coordinates, ^arg(:hex_q)) and
                 fragment("(?->>'r')::integer = ?", hex_coordinates, ^arg(:hex_r))
             )
    end

    read :in_zone do
      argument :zone_id, :uuid, allow_nil?: false
      filter expr(zone_id == ^arg(:zone_id))
    end

    read :by_type do
      argument :resource_type, :atom, allow_nil?: false
      filter expr(resource_type == ^arg(:resource_type))
    end

    read :by_owner do
      argument :owner_id, :uuid, allow_nil?: false
      filter expr(fragment("(?->>'owner_id') = ?", ownership_data, ^arg(:owner_id)))
    end

    read :extractable_resources do
      filter expr(
               resource_status in [:active, :regenerating] and
                 fragment("(?->>'extractable')::boolean = true", interaction_rules)
             )
    end

    read :depleted_resources do
      filter expr(resource_status == :depleted)
    end

    read :high_value do
      filter expr(fragment("(?->>'current_value')::float > 10.0", economic_data))
    end

    read :recently_discovered do
      filter expr(
               fragment("(?->>'discovered')::boolean = true", discovery_data) and
                 fragment("(?->>'discovered_at')::timestamp > ?", discovery_data, ago(24, :hour))
             )
    end

    read :within_range do
      argument :center_q, :integer, allow_nil?: false
      argument :center_r, :integer, allow_nil?: false
      argument :range, :integer, allow_nil?: false

      prepare fn query, _context ->
        # Hex distance calculation would be implemented here
        query
      end
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
    prepare build(load: [:zone, :coordinate])
  end

  validations do
    validate present(:quantity_data) do
      message "Quantity data must be present"
    end

    validate present(:hex_coordinates) do
      message "Hex coordinates must be present"
    end
  end

  validations do
    validate present([:resource_name, :resource_type, :hex_coordinates])
    # TODO: Fix validation syntax for Ash 3.x
    # validate {Thundergrid.Validations, :valid_resource_coordinates}, on: [:create, :update]
    # validate {Thundergrid.Validations, :valid_quantity_data}, on: [:create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :resource_name, :string do
      allow_nil? false
      description "Human-readable resource identifier"
      constraints min_length: 1, max_length: 100
    end

    attribute :resource_type, :atom do
      allow_nil? false
      description "Type of grid resource"
      default :material

      constraints one_of: [
                    :material,
                    :energy,
                    :structure,
                    :data,
                    :agent,
                    :landmark,
                    :portal,
                    :artifact
                  ]
    end

    attribute :resource_subtype, :string do
      allow_nil? true
      description "Specific subtype or category"
      constraints max_length: 50
    end

    attribute :hex_coordinates, :map do
      allow_nil? false
      description "Hex lattice position {q, r, s}"
      default %{"q" => 0, "r" => 0, "s" => 0}
    end

    attribute :precise_position, :map do
      allow_nil? false
      description "Precise position within hex tile"

      default %{
        "sub_hex_x" => 0.0,
        "sub_hex_y" => 0.0,
        "elevation" => 0.0
      }
    end

    attribute :resource_status, :atom do
      allow_nil? false
      description "Current resource status"
      default :active

      constraints one_of: [
                    :active,
                    :dormant,
                    :depleted,
                    :regenerating,
                    :damaged,
                    :destroyed,
                    :protected
                  ]
    end

    attribute :quantity_data, :map do
      allow_nil? false
      description "Resource quantity and capacity information"

      default %{
        "current_quantity" => 100,
        "max_quantity" => 100,
        "regeneration_rate" => 0.0,
        "extraction_rate" => 1.0
      }
    end

    attribute :physical_properties, :map do
      allow_nil? false
      description "Physical characteristics and properties"

      default %{
        "size" => 1.0,
        "mass" => 1.0,
        "density" => 1.0,
        "hardness" => 1.0,
        "visibility" => 1.0
      }
    end

    attribute :interaction_rules, :map do
      allow_nil? false
      description "Rules governing resource interaction"

      default %{
        "extractable" => true,
        "moveable" => false,
        "destructible" => true,
        "requires_tools" => false,
        "interaction_cooldown" => 0
      }
    end

    attribute :ownership_data, :map do
      allow_nil? false
      description "Ownership and access control"

      default %{
        "owner_id" => nil,
        "owner_type" => nil,
        "access_level" => "public",
        "claimed_at" => nil
      }
    end

    attribute :economic_data, :map do
      allow_nil? false
      description "Economic value and trading information"

      default %{
        "base_value" => 1.0,
        "current_value" => 1.0,
        "rarity" => "common",
        "trade_restrictions" => []
      }
    end

    attribute :spatial_effects, :map do
      allow_nil? false
      description "Effects on surrounding spatial area"

      default %{
        "influence_radius" => 0,
        "environmental_impact" => %{},
        "movement_effects" => %{},
        "visibility_effects" => %{}
      }
    end

    attribute :resource_connections, {:array, :uuid} do
      allow_nil? false
      description "Connected or related resource IDs"
      default []
    end

    attribute :discovery_data, :map do
      allow_nil? false
      description "Discovery and exploration information"

      default %{
        "discovered" => true,
        "discovered_by" => nil,
        "discovered_at" => nil,
        "survey_level" => "basic"
      }
    end

    attribute :last_interaction, :utc_datetime do
      allow_nil? true
      description "Timestamp of last interaction"
    end

    attribute :zone_id, :uuid do
      allow_nil? true
      description "ID of the zone containing this resource"
    end

    attribute :coordinate_id, :uuid do
      allow_nil? true
      description "ID of the spatial coordinate"
    end

    attribute :metadata, :map do
      allow_nil? false
      description "Additional resource metadata"
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

    belongs_to :coordinate, Thunderline.Thundergrid.Resources.SpatialCoordinate do
      source_attribute :coordinate_id
      destination_attribute :id
    end

    # Cross-domain relationships removed - invalid destination
    # TODO: Consider if direct Agent relationship is needed instead
  end

  # TODO: Fix AshOban extension loading issue
  # oban do
  #   trigger :resource_regeneration do
  #     action :regenerate
  #     schedule "*/60 * * * * *"  # Every minute
  #     where expr(
  #       resource_status == :regenerating and
  #       fragment("(?->>'regeneration_rate')::float > 0", quantity_data)
  #     )
  #   end

  #   trigger :cleanup_depleted do
  #     action :depleted_resources
  #     schedule "0 */6 * * *"  # Every 6 hours
  #   end
  # end

  identities do
    identity :unique_resource_position, [:hex_coordinates, :precise_position]
  end

  # Utility functions
  def calculate_distance_to({q1, r1, s1}, {q2, r2, s2}) do
    max(abs(q1 - q2), max(abs(r1 - r2), abs(s1 - s2)))
  end

  def is_within_influence?(resource, {target_q, target_r, target_s}) do
    influence_radius = get_in(resource.spatial_effects, ["influence_radius"]) || 0
    resource_coords = resource.hex_coordinates

    {res_q, res_r, res_s} = {
      Map.get(resource_coords, "q", 0),
      Map.get(resource_coords, "r", 0),
      Map.get(resource_coords, "s", 0)
    }

    distance = calculate_distance_to({res_q, res_r, res_s}, {target_q, target_r, target_s})
    distance <= influence_radius
  end

  # Private helper functions
  defp update_coordinate_occupancy(changeset) do
    # Implementation would update the associated SpatialCoordinate
    changeset
  end

  defp update_spatial_resource_index(_resource) do
    # Implementation would update spatial indexing systems
    :ok
  end

  defp apply_spatial_effects(_resource) do
    # Implementation would apply resource effects to surrounding area
    :ok
  end
end
