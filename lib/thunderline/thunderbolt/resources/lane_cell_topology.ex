defmodule Thunderline.Thunderbolt.Resources.CellTopology do
  @moduledoc """
  CellTopology Resource - 3D topological configuration for cellular automata grids.

  This resource defines the spatial topology and coordinates for CA cell grids,
  interfacing with THUNDERCELL compute nodes for distributed processing.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource, AshEvents.Events]

  postgres do
    table "thunderlane_cell_topology"
    repo Thunderline.Repo
  end

  # ============================================================================
  # JSON API
  # ============================================================================

  json_api do
    type "cell_topology"

    routes do
      base("/topologies")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      patch(:partition, route: "/:id/partition")
      patch(:distribute, route: "/:id/distribute")
      patch(:rebalance, route: "/:id/rebalance")
      patch(:update_distribution_health, route: "/:id/health")
    end
  end

  # ============================================================================
  # GRAPHQL
  # ============================================================================

  graphql do
    type :cell_topology

    queries do
      get :get_topology, :read
      list :list_topologies, :read
      list :active_topologies, :active_topologies
      list :topologies_needing_rebalancing, :needs_rebalancing
    end

    mutations do
      create :create_topology, :create
      update :update_topology, :update
      update :partition_topology, :partition
      update :distribute_topology, :distribute
      update :rebalance_topology, :rebalance
      update :update_topology_health, :update_distribution_health
    end
  end

  # ============================================================================
  # EVENTS
  # ============================================================================

  events do
    event_log(Thunderline.Thunderflow.Events.Event)
    current_action_versions(create: 1, update: 1, destroy: 1)
  end

  # ============================================================================
  # ACTIONS
  # ============================================================================

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :description,
        :width,
        :height,
        :depth,
        :topology_type,
        :boundary_x,
        :boundary_y,
        :boundary_z,
        :neighborhood_type,
        :neighborhood_radius,
        :partitioning_strategy,
        :partitioning_config,
        :initial_state_pattern,
        :initial_state_config,
        :initial_state_seed,
        :config,
        :metadata,
        :coordinator_id
      ]

      change fn changeset, _ ->
        width = Ash.Changeset.get_attribute(changeset, :width)
        height = Ash.Changeset.get_attribute(changeset, :height)
        depth = Ash.Changeset.get_attribute(changeset, :depth)

        total_cells = width * height * depth

        changeset
        |> Ash.Changeset.change_attribute(:total_cells, total_cells)
        |> Ash.Changeset.change_attribute(:status, :designed)
      end

      change after_action(&calculate_topology_metrics/2)
    end

    update :update do
      accept [
        :name,
        :description,
        :width,
        :height,
        :depth,
        :topology_type,
        :boundary_x,
        :boundary_y,
        :boundary_z,
        :neighborhood_type,
        :neighborhood_radius,
        :partitioning_strategy,
        :partitioning_config,
        :initial_state_pattern,
        :initial_state_config,
        :config,
        :metadata
      ]

      change fn changeset, _ ->
        # Recalculate total cells if dimensions changed
        case {Ash.Changeset.get_attribute(changeset, :width),
              Ash.Changeset.get_attribute(changeset, :height),
              Ash.Changeset.get_attribute(changeset, :depth)} do
          {nil, nil, nil} ->
            changeset

          {w, h, d} ->
            width = w || Ash.Changeset.get_data(changeset).width
            height = h || Ash.Changeset.get_data(changeset).height
            depth = d || Ash.Changeset.get_data(changeset).depth

            Ash.Changeset.change_attribute(changeset, :total_cells, width * height * depth)
        end
      end

      change after_action(&recalculate_topology_metrics/2)
    end

    update :partition do
      accept [:partitioning_strategy, :partitioning_config]

      change before_action(&validate_partitioning_strategy/1)
      change after_action(&execute_partitioning/2)
    end

    update :distribute do
      accept [:thundercell_nodes]

      change before_action(&validate_thundercell_nodes/1)
      change after_action(&execute_distribution/2)
    end

    update :rebalance do
      accept []
      change after_action(&execute_rebalancing/2)
    end

    update :update_distribution_health do
      accept [:distribution_health, :locality_score, :communication_overhead, :memory_efficiency]
    end

    read :by_coordinator do
      argument :coordinator_id, :uuid, allow_nil?: false
      filter expr(coordinator_id == ^arg(:coordinator_id))
    end

    read :active_topologies do
      filter expr(status == :active)
    end

    read :needs_rebalancing do
      filter expr(distribution_health < 0.7 or load_variance > 0.3)
    end

    read :by_dimensions do
      argument :width, :integer, allow_nil?: false
      argument :height, :integer, allow_nil?: false
      argument :depth, :integer, allow_nil?: false
      filter expr(width == ^arg(:width) and height == ^arg(:height) and depth == ^arg(:depth))
    end
  end

  # ============================================================================
  # ATTRIBUTES
  # ============================================================================

  attributes do
    uuid_primary_key :id

    # Core Identity
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    # Foreign Keys for Relationships
    attribute :lane_coordinator_id, :uuid, public?: true

    # 3D Grid Dimensions
    attribute :width, :integer, allow_nil?: false, public?: true, constraints: [min: 1, max: 4096]

    attribute :height, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 4096]

    attribute :depth, :integer, allow_nil?: false, public?: true, constraints: [min: 1, max: 1024]

    # Cell Configuration
    attribute :total_cells, :integer, public?: true
    attribute :cells_per_partition, :integer, public?: true
    attribute :partition_count, :integer, public?: true

    # Topology Type
    attribute :topology_type, :atom,
      allow_nil?: false,
      public?: true,
      default: :rectangular,
      constraints: [one_of: [:rectangular, :hexagonal, :triangular, :torus, :sphere, :custom]]

    # Boundary Conditions
    attribute :boundary_x, :atom,
      allow_nil?: false,
      public?: true,
      default: :wrap,
      constraints: [one_of: [:wrap, :fixed, :reflect, :absorb]]

    attribute :boundary_y, :atom,
      allow_nil?: false,
      public?: true,
      default: :wrap,
      constraints: [one_of: [:wrap, :fixed, :reflect, :absorb]]

    attribute :boundary_z, :atom,
      allow_nil?: false,
      public?: true,
      default: :wrap,
      constraints: [one_of: [:wrap, :fixed, :reflect, :absorb]]

    # Neighborhood Configuration
    attribute :neighborhood_type, :atom,
      allow_nil?: false,
      public?: true,
      default: :moore_3d,
      constraints: [one_of: [:moore_3d, :von_neumann_3d, :custom_3d]]

    attribute :neighborhood_radius, :integer,
      allow_nil?: false,
      public?: true,
      default: 1,
      constraints: [min: 1, max: 5]

    # Partitioning Strategy
    attribute :partitioning_strategy, :atom,
      allow_nil?: false,
      public?: true,
      default: :grid_3d,
      constraints: [one_of: [:grid_3d, :spatial_hash, :hilbert_curve, :load_balanced, :custom]]

    attribute :partitioning_config, :map, public?: true, default: %{}

    # THUNDERCELL Distribution
    attribute :thundercell_nodes, :map, public?: true, default: %{}
    attribute :partition_assignments, :map, public?: true, default: %{}
    attribute :node_load_balance, :map, public?: true, default: %{}

    # Performance Metrics
    attribute :average_neighbors_per_cell, :float, public?: true
    attribute :max_partition_size, :integer, public?: true
    attribute :min_partition_size, :integer, public?: true
    attribute :load_variance, :float, public?: true

    # Status and Health
    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      default: :designed,
      constraints: [one_of: [:designed, :partitioned, :distributed, :active, :error]]

    attribute :distribution_health, :float,
      public?: true,
      default: 1.0,
      constraints: [min: 0.0, max: 1.0]

    attribute :last_rebalance_at, :utc_datetime_usec, public?: true

    # Optimization
    attribute :locality_score, :float, public?: true
    attribute :communication_overhead, :float, public?: true
    attribute :memory_efficiency, :float, public?: true

    # Initialization State
    attribute :initial_state_pattern, :atom,
      public?: true,
      constraints: [one_of: [:random, :checkerboard, :stripes, :custom, :loaded]]

    attribute :initial_state_config, :map, public?: true, default: %{}
    attribute :initial_state_seed, :integer, public?: true

    # Configuration
    attribute :config, :map, public?: true, default: %{}
    attribute :metadata, :map, public?: true, default: %{}

    # Timestamps
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  # ============================================================================
  # RELATIONSHIPS
  # ============================================================================

  relationships do
    belongs_to :coordinator, Thunderline.Thunderbolt.Resources.LaneCoordinator do
      attribute_writable? true
      public? true
    end

    has_many :topology_metrics, Thunderline.Thunderbolt.Resources.LaneMetrics do
      public? true
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp calculate_topology_metrics(_changeset, topology) do
    # Calculate neighborhood metrics
    avg_neighbors = calculate_average_neighbors(topology)

    topology
    |> Ash.Changeset.for_update(:update, %{
      average_neighbors_per_cell: avg_neighbors
    })
    |> Ash.update()
  end

  defp recalculate_topology_metrics(_changeset, topology) do
    calculate_topology_metrics(nil, topology)
  end

  defp validate_partitioning_strategy(changeset) do
    strategy = Ash.Changeset.get_attribute(changeset, :partitioning_strategy)
    config = Ash.Changeset.get_attribute(changeset, :partitioning_config) || %{}

    case validate_strategy_config(strategy, config) do
      :ok ->
        changeset

      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :partitioning_config, message: message)
    end
  end

  defp validate_thundercell_nodes(changeset) do
    nodes = Ash.Changeset.get_attribute(changeset, :thundercell_nodes) || %{}

    # Validate that all nodes are reachable
    case validate_node_connectivity(nodes) do
      :ok ->
        changeset

      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :thundercell_nodes, message: message)
    end
  end

  defp execute_partitioning(_changeset, topology) do
    # Execute the partitioning algorithm
    case Thunderline.Thunderbolt.TopologyPartitioner.partition(topology) do
      {:ok, partition_result} ->
        topology
        |> Ash.Changeset.for_update(:update, %{
          partition_count: partition_result.partition_count,
          partition_assignments: partition_result.assignments,
          cells_per_partition: partition_result.cells_per_partition,
          max_partition_size: partition_result.max_size,
          min_partition_size: partition_result.min_size,
          load_variance: partition_result.load_variance,
          status: :partitioned
        })
        |> Ash.update()

      {:error, reason} ->
        topology
        |> Ash.Changeset.for_update(:update, %{status: :error})
        |> Ash.update()
        |> case do
          {:ok, _t} -> {:error, "Partitioning failed: #{reason}"}
          error -> error
        end
    end
  end

  defp execute_distribution(_changeset, topology) do
    # Distribute partitions to THUNDERCELL nodes
    case Thunderline.Thunderbolt.TopologyDistributor.distribute(topology) do
      {:ok, distribution_result} ->
        topology
        |> Ash.Changeset.for_update(:update, %{
          node_load_balance: distribution_result.load_balance,
          locality_score: distribution_result.locality_score,
          communication_overhead: distribution_result.communication_overhead,
          memory_efficiency: distribution_result.memory_efficiency,
          distribution_health: distribution_result.health_score,
          status: :distributed
        })
        |> Ash.update()

      {:error, reason} ->
        {:error, "Distribution failed: #{reason}"}
    end
  end

  defp execute_rebalancing(_changeset, topology) do
    # Rebalance the topology distribution
    case Thunderline.Thunderbolt.TopologyRebalancer.rebalance(topology) do
      {:ok, rebalance_result} ->
        topology
        |> Ash.Changeset.for_update(:update, %{
          partition_assignments: rebalance_result.new_assignments,
          node_load_balance: rebalance_result.load_balance,
          distribution_health: rebalance_result.health_score,
          last_rebalance_at: DateTime.utc_now()
        })
        |> Ash.update()

      {:error, reason} ->
        {:error, "Rebalancing failed: #{reason}"}
    end
  end

  defp calculate_average_neighbors(topology) do
    # Calculate based on topology type and neighborhood configuration
    case topology.neighborhood_type do
      :moore_3d ->
        radius = topology.neighborhood_radius
        (2 * radius + 1) * (2 * radius + 1) * (2 * radius + 1) - 1

      :von_neumann_3d ->
        radius = topology.neighborhood_radius
        2 * radius * (radius + 1) * (radius + 2) / 3

      :custom_3d ->
        # Default estimate for custom neighborhoods
        8.0
    end
  end

  defp validate_strategy_config(strategy, config) do
    case strategy do
      :grid_3d ->
        validate_grid_3d_config(config)

      :spatial_hash ->
        validate_spatial_hash_config(config)

      :hilbert_curve ->
        validate_hilbert_curve_config(config)

      :load_balanced ->
        validate_load_balanced_config(config)

      :custom ->
        validate_custom_config(config)

      _ ->
        :ok
    end
  end

  defp validate_grid_3d_config(_config), do: :ok
  defp validate_spatial_hash_config(_config), do: :ok
  defp validate_hilbert_curve_config(_config), do: :ok
  defp validate_load_balanced_config(_config), do: :ok
  defp validate_custom_config(_config), do: :ok

  defp validate_node_connectivity(_nodes) do
    # TODO: Implement actual node connectivity validation
    :ok
  end
end
