defmodule Thunderline.Thunderbolt.Resources.ResourceAllocation do
  @moduledoc """
  ResourceAllocation Resource - Dynamic resource management for meshes

  Manages CPU, memory, network, and neural compute resources across 144-bit
  meshes. Implements intelligent load balancing and optimization for
  automata execution and neural network operations.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: :embedded,
    extensions: [AshJsonApi.Resource, AshOban.Resource, AshGraphql.Resource]

  import Ash.Resource.Change.Builtins
  import Ash.Resource.Change.Builtins

  # IN-MEMORY CONFIGURATION (sqlite removed)
  # Using :embedded data layer

  json_api do
    type "resource_allocation"

    routes do
      base("/resource-allocations")
      get(:read)
      index :read
      post(:create)
      patch(:update)
      patch(:rebalance, route: "/:id/rebalance")
      patch(:scale_up, route: "/:id/scale-up")
      patch(:scale_down, route: "/:id/scale-down")
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :allocate_resources do
      accept [
        :cpu_allocation_percent,
        :memory_allocation_mb,
        :network_bandwidth_kbps,
        :storage_allocation_mb,
        :priority_class,
        :optimization_strategy
      ]

      change before_action(&validate_resource_availability/1)
      change after_action(&reserve_cluster_resources/2)
      change after_action(&create_orchestration_event/2)
    end

    update :rebalance do
      accept []
      argument :target_distribution, :map, default: %{}

      change before_action(&calculate_optimal_allocation/1)
      change set_attribute(:last_rebalance, &DateTime.utc_now/0)
      change after_action(&apply_rebalancing_changes/2)
      change after_action(&create_orchestration_event/2)
    end

    update :scale_up do
      accept []
      argument :scale_factor, :decimal, default: Decimal.new("1.5")

      change before_action(&calculate_scale_up_allocation/1)
      change set_attribute(:last_scaling_action, &DateTime.utc_now/0)
      change after_action(&broadcast_scaling_event/2)
    end

    update :scale_down do
      accept []
      argument :scale_factor, :decimal, default: Decimal.new("0.7")

      change before_action(&calculate_scale_down_allocation/1)
      change set_attribute(:last_scaling_action, &DateTime.utc_now/0)
      change after_action(&broadcast_scaling_event/2)
    end

    update :update_usage do
      accept [
        :cpu_usage_percent,
        :memory_usage_mb,
        :network_usage_kbps,
        :storage_usage_mb,
        :resource_contention_score
      ]

      change after_action(&evaluate_scaling_needs/2)
    end

    read :high_priority_allocations do
      filter expr(priority_class in [:high, :critical])
    end

    read :allocations_needing_scaling do
      filter expr(needs_scaling == true)
    end

    read :over_allocated do
      filter expr(overall_utilization > 90)
    end

    read :under_allocated do
      filter expr(overall_utilization < 20 and auto_scaling_enabled == true)
    end

    read :resource_constrained do
      filter expr(resource_pressure > 80)
    end
  end

  attributes do
    uuid_primary_key :id

    # Resource allocation targets
    attribute :cpu_allocation_percent, :decimal, default: Decimal.new("10.0")
    attribute :memory_allocation_mb, :integer, default: 512
    attribute :network_bandwidth_kbps, :integer, default: 1000
    attribute :storage_allocation_mb, :integer, default: 100

    # Current resource usage
    attribute :cpu_usage_percent, :decimal, default: Decimal.new("0.0")
    attribute :memory_usage_mb, :integer, default: 0
    attribute :network_usage_kbps, :integer, default: 0
    attribute :storage_usage_mb, :integer, default: 0

    # Resource limits and constraints
    attribute :cpu_limit_percent, :decimal, default: Decimal.new("50.0")
    attribute :memory_limit_mb, :integer, default: 2048
    attribute :network_limit_kbps, :integer, default: 10000
    attribute :storage_limit_mb, :integer, default: 1024

    # Dynamic scaling configuration
    attribute :auto_scaling_enabled, :boolean, default: true
    attribute :scale_up_threshold_percent, :decimal, default: Decimal.new("80.0")
    attribute :scale_down_threshold_percent, :decimal, default: Decimal.new("30.0")
    attribute :min_allocation_percent, :decimal, default: Decimal.new("5.0")
    attribute :max_allocation_percent, :decimal, default: Decimal.new("90.0")

    # Load balancing and optimization
    attribute :load_balancing_weight, :decimal, default: Decimal.new("1.0")

    attribute :priority_class, :atom,
      constraints: [
        one_of: [:low, :normal, :high, :critical]
      ],
      default: :normal

    attribute :optimization_strategy, :atom,
      constraints: [
        one_of: [:cpu_optimized, :memory_optimized, :network_optimized, :balanced]
      ],
      default: :balanced

    # Performance metrics
    attribute :allocation_efficiency, :decimal, default: Decimal.new("1.0")
    attribute :resource_contention_score, :decimal, default: Decimal.new("0.0")
    attribute :last_scaling_action, :utc_datetime
    attribute :last_rebalance, :utc_datetime

    # Environmental and cluster awareness
    attribute :cluster_node, :string, default: fn -> Atom.to_string(Node.self()) end
    attribute :node_capacity_percent, :decimal, default: Decimal.new("100.0")
    attribute :neighbor_resource_impact, :map, default: %{}

    timestamps()
  end

  relationships do
    belongs_to :chunk, Thunderline.Thunderbolt.Resources.Chunk do
      attribute_writable? true
    end

    has_many :orchestration_events, Thunderline.Thunderbolt.Resources.OrchestrationEvent
  end

  calculations do
    calculate :cpu_utilization_percent,
              :decimal,
              expr(
                if(
                  cpu_allocation_percent > 0,
                  cpu_usage_percent / cpu_allocation_percent * 100,
                  0
                )
              )

    calculate :memory_utilization_percent,
              :decimal,
              expr(
                if(
                  memory_allocation_mb > 0,
                  memory_usage_mb / memory_allocation_mb * 100,
                  0
                )
              )

    calculate :overall_utilization,
              :decimal,
              expr((cpu_utilization_percent + memory_utilization_percent) / 2)

    calculate :needs_scaling,
              :boolean,
              expr(
                auto_scaling_enabled == true and
                  (overall_utilization > scale_up_threshold_percent or
                     overall_utilization < scale_down_threshold_percent)
              )

    calculate :resource_pressure,
              :decimal,
              expr(
                cpu_utilization_percent * 0.4 +
                  memory_utilization_percent * 0.4 +
                  resource_contention_score * 0.2
              )
  end

  # oban do
  #   triggers do
  #     # TODO: Fix schedule syntax for AshOban 3.x
  #     # trigger :auto_scale_up do
  #     #   action :scale_up
  #     #   schedule "*/2 * * * *" # Every 2 minutes
  #     #   where expr(
  #     #     auto_scaling_enabled == true and
  #     #     overall_utilization > scale_up_threshold_percent
  #     #   )
  #     # end

  #     # trigger :auto_scale_down do
  #     #   action :scale_down
  #     #   schedule "*/2 * * * *" # Every 2 minutes
  #     #   where expr(
  #     #     auto_scaling_enabled == true and
  #     #     overall_utilization < scale_down_threshold_percent
  #     #   )
  #     # end

  #     # trigger :resource_optimization do
  #     #   action :rebalance
  #     #   schedule "0 */6 * * *"  # Every 6 hours
  #     #   where expr(resource_pressure > 50)
  #     # end
  #   end
  # end

  # TODO: Configure notifications when proper extension is available
  # notifications do
  #   publish :resources_allocated, ["thunderbolt:resources:allocated", :chunk_id]
  #   publish :resources_rebalanced, ["thunderbolt:resources:rebalanced", :chunk_id]
  #   publish :scaling_triggered, ["thunderbolt:resources:scaling", :chunk_id]
  #   publish :resource_pressure_high, ["thunderbolt:resources:pressure", :chunk_id]
  # end

  # Private action implementations
  defp validate_resource_availability(changeset) do
    # TODO: Check cluster-wide resource availability
    # Ensure requested resources don't exceed node capacity
    changeset
  end

  defp reserve_cluster_resources(_changeset, allocation) do
    # TODO: Reserve resources at cluster level to prevent over-allocation
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:resources:reserved",
      {:resources_reserved, allocation}
    )

    {:ok, allocation}
  end

  defp calculate_optimal_allocation(changeset) do
    # TODO: Implement sophisticated resource optimization algorithms
    # Consider current usage, predicted load, neighbor impact, etc.
    changeset
  end

  defp apply_rebalancing_changes(_changeset, allocation) do
    # TODO: Apply calculated resource changes to the chunk
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:resources:rebalanced",
      {:rebalancing_applied, allocation}
    )

    {:ok, allocation}
  end

  defp calculate_scale_up_allocation(changeset) do
    # TODO: Calculate new resource allocations for scaling up
    # Respect limits and cluster capacity
    current_cpu = Ash.Changeset.get_attribute(changeset, :cpu_allocation_percent)
    current_memory = Ash.Changeset.get_attribute(changeset, :memory_allocation_mb)
    cpu_limit = Ash.Changeset.get_attribute(changeset, :cpu_limit_percent)
    memory_limit = Ash.Changeset.get_attribute(changeset, :memory_limit_mb)

    # Scale up by 50% but respect limits
    new_cpu = min(Decimal.mult(current_cpu, Decimal.new("1.5")), cpu_limit)
    new_memory = min(round(current_memory * 1.5), memory_limit)

    changeset
    |> Ash.Changeset.change_attribute(:cpu_allocation_percent, new_cpu)
    |> Ash.Changeset.change_attribute(:memory_allocation_mb, new_memory)
  end

  defp calculate_scale_down_allocation(changeset) do
    # TODO: Calculate new resource allocations for scaling down
    # Respect minimum allocations
    current_cpu = Ash.Changeset.get_attribute(changeset, :cpu_allocation_percent)
    current_memory = Ash.Changeset.get_attribute(changeset, :memory_allocation_mb)
    min_percent = Ash.Changeset.get_attribute(changeset, :min_allocation_percent)

    # Scale down by 30% but respect minimums
    new_cpu = max(Decimal.mult(current_cpu, Decimal.new("0.7")), min_percent)
    # Min 128MB
    new_memory = max(round(current_memory * 0.7), 128)

    changeset
    |> Ash.Changeset.change_attribute(:cpu_allocation_percent, new_cpu)
    |> Ash.Changeset.change_attribute(:memory_allocation_mb, new_memory)
  end

  defp broadcast_scaling_event(_changeset, allocation) do
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:resources:scaling",
      {:scaling_completed, allocation}
    )

    {:ok, allocation}
  end

  defp evaluate_scaling_needs(_changeset, allocation) do
    # Check if resource usage indicates need for scaling
    if Decimal.gt?(allocation.overall_utilization, allocation.scale_up_threshold_percent) do
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "thunderbolt:resources:scale_needed",
        {:scale_up_needed, allocation}
      )
    end

    {:ok, allocation}
  end

  defp create_orchestration_event(_changeset, allocation) do
    # TODO: Create orchestration event record
    {:ok, allocation}
  end
end
