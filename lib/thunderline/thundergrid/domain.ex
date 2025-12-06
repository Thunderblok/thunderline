defmodule Thunderline.Thundergrid.Domain do
  @moduledoc """
  Thundergrid Ash Domain - Spatial coordinate, Prism, & GraphQL interface

  Manages spatial coordinate systems, zone boundaries, and provides
  the GraphQL interface for spatial management of Thunderbolt meshes.

  ## Core Responsibilities:
  - Spatial coordinate management (hexagonal grids)
  - Zone boundary definitions and management
  - GraphQL API for spatial operations
  - Grid resource allocation
  - Spatial event tracking

  ## Prism (consolidated from Thunderprism):
  - ML decision DAG visualization (PrismNode/PrismEdge)
  - Automata introspection snapshots
  - Side-quest and criticality metrics

  ## GraphQL Queries:
  - Zones: `zones`, `available_zones`, `zone_by_coordinates`
  - Prism: `prism_nodes`, `prism_edges`, `automata_snapshots`
  """

  use Ash.Domain,
    validate_config_inclusion?: false,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain]

  graphql do
    authorize? true

    queries do
      # Zone queries
      list Thunderline.Thundergrid.Resources.Zone, :zones, :read
      list Thunderline.Thundergrid.Resources.Zone, :available_zones, :available_zones
      get Thunderline.Thundergrid.Resources.Zone, :zone_by_coordinates, :by_coordinates

      # Prism queries (ML decision DAG)
      list Thunderline.Thundergrid.Prism.PrismNode, :prism_nodes, :read
      get Thunderline.Thundergrid.Prism.PrismNode, :prism_node, :read
      list Thunderline.Thundergrid.Prism.PrismNode, :prism_nodes_by_pac, :by_pac

      list Thunderline.Thundergrid.Prism.PrismEdge, :prism_edges, :read

      # Automata introspection queries
      list Thunderline.Thundergrid.Prism.AutomataSnapshot, :automata_snapshots, :by_run
      list Thunderline.Thundergrid.Prism.AutomataSnapshot, :recent_automata_snapshots, :recent
      list Thunderline.Thundergrid.Prism.AutomataSnapshot, :critical_snapshots, :critical_snapshots

      # Doctrine Layer queries (Operation TIGER LATTICE)
      list Thunderline.Thundergrid.Prism.AutomataSnapshot, :doctrine_distribution, :doctrine_distribution
      list Thunderline.Thundergrid.Prism.AutomataSnapshot, :doctrine_history, :doctrine_history
    end

    mutations do
      # Zone mutations
      create Thunderline.Thundergrid.Resources.Zone, :spawn_zone, :spawn_zone
      update Thunderline.Thundergrid.Resources.Zone, :adjust_zone_entropy, :adjust_entropy
      update Thunderline.Thundergrid.Resources.Zone, :activate_zone, :activate
      update Thunderline.Thundergrid.Resources.Zone, :deactivate_zone, :deactivate

      # Prism mutations (mostly for admin/testing)
      create Thunderline.Thundergrid.Prism.PrismNode, :create_prism_node, :create
      create Thunderline.Thundergrid.Prism.PrismEdge, :create_prism_edge, :create
      create Thunderline.Thundergrid.Prism.AutomataSnapshot, :create_automata_snapshot, :create
    end
  end

  json_api do
    prefix "/api/thundergrid"
    log_errors? true
  end

  resources do
    # Spatial resources
    resource Thunderline.Thundergrid.Resources.SpatialCoordinate
    resource Thunderline.Thundergrid.Resources.ZoneBoundary
    resource Thunderline.Thundergrid.Resources.Zone
    resource Thunderline.Thundergrid.Resources.ZoneEvent
    resource Thunderline.Thundergrid.Resources.ChunkState

    # Prism resources (consolidated from Thunderprism)
    resource Thunderline.Thundergrid.Prism.PrismNode
    resource Thunderline.Thundergrid.Prism.PrismEdge
    resource Thunderline.Thundergrid.Prism.AutomataSnapshot
  end
end
