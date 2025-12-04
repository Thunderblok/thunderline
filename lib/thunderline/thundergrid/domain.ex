defmodule Thunderline.Thundergrid.Domain do
  @moduledoc """
  Thundergrid Ash Domain - Spatial coordinate & GraphQL interface

  Manages spatial coordinate systems, zone boundaries, and provides
  the GraphQL interface for spatial management of Thunderbolt meshes.

  ## Core Responsibilities:
  - Spatial coordinate management (hexagonal grids)
  - Zone boundary definitions and management
  - GraphQL API for spatial operations
  - Grid resource allocation
  - Spatial event tracking
  """

  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain]

  graphql do
    authorize? true

    queries do
      list Thunderline.Thundergrid.Resources.Zone, :zones, :read
      list Thunderline.Thundergrid.Resources.Zone, :available_zones, :available_zones
      get Thunderline.Thundergrid.Resources.Zone, :zone_by_coordinates, :by_coordinates
    end

    mutations do
      create Thunderline.Thundergrid.Resources.Zone, :spawn_zone, :spawn_zone
      update Thunderline.Thundergrid.Resources.Zone, :adjust_zone_entropy, :adjust_entropy
      update Thunderline.Thundergrid.Resources.Zone, :activate_zone, :activate
      update Thunderline.Thundergrid.Resources.Zone, :deactivate_zone, :deactivate
    end
  end

  json_api do
    prefix "/api/thundergrid"
    log_errors? true
  end

  resources do
    # All Thundergrid resources
    resource Thunderline.Thundergrid.Resources.SpatialCoordinate
    resource Thunderline.Thundergrid.Resources.ZoneBoundary
    resource Thunderline.Thundergrid.Resources.Zone
    resource Thunderline.Thundergrid.Resources.ZoneEvent
    resource Thunderline.Thundergrid.Resources.ChunkState
    # GridZone and GridResource are embedded resources - not listed in domain
  end
end
