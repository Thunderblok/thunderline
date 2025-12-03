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
    extensions: [AshJsonApi.Resource, AshOban, AshGraphql.Resource]

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
    attribute :network_limit_kbps, :integer, default: 10_000
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
    # Check cluster-wide resource availability
    # Ensure requested resources don't exceed node capacity
    cpu_requested = Ash.Changeset.get_attribute(changeset, :cpu_allocation_percent)
    memory_requested = Ash.Changeset.get_attribute(changeset, :memory_allocation_mb)
    cpu_limit = Ash.Changeset.get_attribute(changeset, :cpu_limit_percent)
    memory_limit = Ash.Changeset.get_attribute(changeset, :memory_limit_mb)
    node_capacity = Ash.Changeset.get_attribute(changeset, :node_capacity_percent)

    # Validate CPU allocation
    changeset =
      if Decimal.gt?(cpu_requested, cpu_limit) do
        Ash.Changeset.add_error(changeset, field: :cpu_allocation_percent, message: "exceeds CPU limit")
      else
        changeset
      end

    # Validate memory allocation
    changeset =
      if memory_requested > memory_limit do
        Ash.Changeset.add_error(changeset, field: :memory_allocation_mb, message: "exceeds memory limit")
      else
        changeset
      end

    # Validate against node capacity
    effective_cpu = Decimal.mult(cpu_requested, Decimal.div(node_capacity, Decimal.new("100")))
    if Decimal.lt?(effective_cpu, Decimal.new("1.0")) do
      Ash.Changeset.add_error(changeset, field: :node_capacity_percent, message: "insufficient node capacity for allocation")
    else
      changeset
    end
  end

  defp reserve_cluster_resources(_changeset, allocation) do
    # Reserve resources at cluster level to prevent over-allocation
    # Broadcast reservation event with full allocation context
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:resources:reserved",
      {:resources_reserved, %{
        allocation_id: allocation.id,
        cpu_percent: allocation.cpu_allocation_percent,
        memory_mb: allocation.memory_allocation_mb,
        network_kbps: allocation.network_bandwidth_kbps,
        cluster_node: allocation.cluster_node,
        priority_class: allocation.priority_class,
        timestamp: DateTime.utc_now()
      }}
    )

    {:ok, allocation}
  end

  defp calculate_optimal_allocation(changeset) do
    # Implement resource optimization algorithms
    # Consider current usage, predicted load, neighbor impact
    current_cpu = Ash.Changeset.get_attribute(changeset, :cpu_allocation_percent)
    current_memory = Ash.Changeset.get_attribute(changeset, :memory_allocation_mb)
    cpu_usage = Ash.Changeset.get_attribute(changeset, :cpu_usage_percent)
    memory_usage = Ash.Changeset.get_attribute(changeset, :memory_usage_mb)
    strategy = Ash.Changeset.get_attribute(changeset, :optimization_strategy)
    contention = Ash.Changeset.get_attribute(changeset, :resource_contention_score)

    # Calculate utilization ratios
    cpu_util = calculate_utilization(cpu_usage, current_cpu)
    memory_util = calculate_memory_utilization(memory_usage, current_memory)

    # Apply optimization strategy
    {cpu_factor, memory_factor} = apply_strategy(strategy, cpu_util, memory_util, contention)

    # Apply calculated optimizations
    new_cpu = Decimal.mult(current_cpu, cpu_factor)
    new_memory = round(Decimal.to_float(Decimal.mult(Decimal.new(current_memory), memory_factor)))

    changeset
    |> Ash.Changeset.change_attribute(:cpu_allocation_percent, new_cpu)
    |> Ash.Changeset.change_attribute(:memory_allocation_mb, new_memory)
    |> Ash.Changeset.change_attribute(:allocation_efficiency,
        calculate_efficiency(cpu_util, memory_util, contention))
  end

  defp calculate_utilization(usage, allocation) do
    if Decimal.gt?(allocation, Decimal.new("0")),
      do: Decimal.div(usage, allocation),
      else: Decimal.new("0")
  end

  defp calculate_memory_utilization(usage, allocation) do
    if allocation > 0,
      do: Decimal.new(usage / allocation),
      else: Decimal.new("0")
  end

  defp apply_strategy(:cpu_optimized, cpu_util, _memory_util, contention) do
    # Favor CPU allocation, reduce memory if contention high
    cpu_f = if Decimal.gt?(cpu_util, Decimal.new("0.7")), do: Decimal.new("1.2"), else: Decimal.new("1.0")
    mem_f = if Decimal.gt?(contention, Decimal.new("0.5")), do: Decimal.new("0.9"), else: Decimal.new("1.0")
    {cpu_f, mem_f}
  end

  defp apply_strategy(:memory_optimized, _cpu_util, memory_util, contention) do
    # Favor memory allocation
    cpu_f = if Decimal.gt?(contention, Decimal.new("0.5")), do: Decimal.new("0.9"), else: Decimal.new("1.0")
    mem_f = if Decimal.gt?(memory_util, Decimal.new("0.7")), do: Decimal.new("1.2"), else: Decimal.new("1.0")
    {cpu_f, mem_f}
  end

  defp apply_strategy(:network_optimized, _cpu_util, _memory_util, _contention) do
    # Balance CPU/memory, prioritize network headroom
    {Decimal.new("1.0"), Decimal.new("1.0")}
  end

  defp apply_strategy(:balanced, cpu_util, memory_util, _contention) do
    # Equal weight to all resources
    avg_util = Decimal.div(Decimal.add(cpu_util, memory_util), Decimal.new("2"))
    factor = if Decimal.gt?(avg_util, Decimal.new("0.7")), do: Decimal.new("1.1"), else: Decimal.new("1.0")
    {factor, factor}
  end

  defp apply_strategy(_unknown, _cpu_util, _memory_util, _contention) do
    # Default to balanced
    {Decimal.new("1.0"), Decimal.new("1.0")}
  end

  defp calculate_efficiency(cpu_util, memory_util, contention) do
    # Efficiency = (avg utilization) * (1 - contention penalty)
    avg_util = Decimal.div(Decimal.add(cpu_util, memory_util), Decimal.new("2"))
    contention_penalty = Decimal.mult(contention, Decimal.new("0.3"))
    Decimal.max(Decimal.sub(avg_util, contention_penalty), Decimal.new("0.0"))
  end

  defp apply_rebalancing_changes(_changeset, allocation) do
    # Apply calculated resource changes and broadcast rebalancing event
    event_data = %{
      allocation_id: allocation.id,
      new_cpu: allocation.cpu_allocation_percent,
      new_memory: allocation.memory_allocation_mb,
      efficiency: allocation.allocation_efficiency,
      strategy: allocation.optimization_strategy,
      cluster_node: allocation.cluster_node,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:resources:rebalanced",
      {:rebalancing_applied, event_data}
    )

    # Also publish to the global event stream for cross-domain awareness
    Thunderline.Thunderflow.EventBus.publish_event(%{
      name: "thunderbolt.resources.rebalanced",
      source: :thunderbolt,
      payload: event_data,
      priority: :normal,
      meta: %{pipeline: :general}
    })

    {:ok, allocation}
  end

  defp calculate_scale_up_allocation(changeset) do
    # Calculate new resource allocations for scaling up
    # Respect limits and cluster capacity
    current_cpu = Ash.Changeset.get_attribute(changeset, :cpu_allocation_percent)
    current_memory = Ash.Changeset.get_attribute(changeset, :memory_allocation_mb)
    cpu_limit = Ash.Changeset.get_attribute(changeset, :cpu_limit_percent)
    memory_limit = Ash.Changeset.get_attribute(changeset, :memory_limit_mb)
    scale_factor = Ash.Changeset.get_argument(changeset, :scale_factor) || Decimal.new("1.5")

    # Scale up by factor but respect limits
    new_cpu = Decimal.min(Decimal.mult(current_cpu, scale_factor), cpu_limit)
    new_memory = min(round(Decimal.to_float(Decimal.mult(Decimal.new(current_memory), scale_factor))), memory_limit)

    changeset
    |> Ash.Changeset.change_attribute(:cpu_allocation_percent, new_cpu)
    |> Ash.Changeset.change_attribute(:memory_allocation_mb, new_memory)
  end

  defp calculate_scale_down_allocation(changeset) do
    # Calculate new resource allocations for scaling down
    # Respect minimum allocations
    current_cpu = Ash.Changeset.get_attribute(changeset, :cpu_allocation_percent)
    current_memory = Ash.Changeset.get_attribute(changeset, :memory_allocation_mb)
    min_percent = Ash.Changeset.get_attribute(changeset, :min_allocation_percent)
    scale_factor = Ash.Changeset.get_argument(changeset, :scale_factor) || Decimal.new("0.7")

    # Scale down by factor but respect minimums
    new_cpu = Decimal.max(Decimal.mult(current_cpu, scale_factor), min_percent)
    # Min 128MB
    new_memory = max(round(Decimal.to_float(Decimal.mult(Decimal.new(current_memory), scale_factor))), 128)

    changeset
    |> Ash.Changeset.change_attribute(:cpu_allocation_percent, new_cpu)
    |> Ash.Changeset.change_attribute(:memory_allocation_mb, new_memory)
  end

  defp broadcast_scaling_event(_changeset, allocation) do
    event_data = %{
      allocation_id: allocation.id,
      cpu_percent: allocation.cpu_allocation_percent,
      memory_mb: allocation.memory_allocation_mb,
      cluster_node: allocation.cluster_node,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "thunderbolt:resources:scaling",
      {:scaling_completed, event_data}
    )

    # Publish to event bus for observability
    Thunderline.Thunderflow.EventBus.publish_event(%{
      name: "thunderbolt.resources.scaled",
      source: :thunderbolt,
      payload: event_data,
      priority: :normal,
      meta: %{pipeline: :general}
    })

    {:ok, allocation}
  end

  defp evaluate_scaling_needs(_changeset, allocation) do
    # Check if resource usage indicates need for scaling
    cpu_util = if Decimal.gt?(allocation.cpu_allocation_percent, Decimal.new("0")),
      do: Decimal.div(allocation.cpu_usage_percent, allocation.cpu_allocation_percent),
      else: Decimal.new("0")

    mem_util = if allocation.memory_allocation_mb > 0,
      do: Decimal.new(allocation.memory_usage_mb / allocation.memory_allocation_mb),
      else: Decimal.new("0")

    overall_util = Decimal.div(Decimal.add(cpu_util, mem_util), Decimal.new("2"))

    cond do
      Decimal.gt?(overall_util, allocation.scale_up_threshold_percent) ->
        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "thunderbolt:resources:scale_needed",
          {:scale_up_needed, %{allocation_id: allocation.id, utilization: overall_util}}
        )

      Decimal.lt?(overall_util, allocation.scale_down_threshold_percent) and allocation.auto_scaling_enabled ->
        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "thunderbolt:resources:scale_needed",
          {:scale_down_needed, %{allocation_id: allocation.id, utilization: overall_util}}
        )

      true ->
        :ok
    end

    {:ok, allocation}
  end

  defp create_orchestration_event(_changeset, allocation) do
    # Create orchestration event for audit trail
    event_attrs = %{
      event_type: :resource_allocated,
      event_category: :scaling,
      severity: :info,
      title: "Resource allocation updated",
      description: "Resource allocation for chunk modified with #{allocation.optimization_strategy} strategy",
      event_data: %{
        allocation_id: allocation.id,
        cpu_allocated: allocation.cpu_allocation_percent,
        memory_allocated: allocation.memory_allocation_mb,
        network_allocated: allocation.network_bandwidth_kbps,
        priority_class: allocation.priority_class
      },
      context_data: %{
        cluster_node: allocation.cluster_node,
        auto_scaling: allocation.auto_scaling_enabled,
        efficiency: allocation.allocation_efficiency
      },
      resource_allocation_id: allocation.id,
      chunk_id: allocation.chunk_id,
      triggered_by: "resource_allocation_action",
      status: :completed
    }

    # Publish to event bus for cross-domain visibility
    case Thunderline.Thunderflow.EventBus.publish_event(%{
           name: "thunderbolt.orchestration.resource_allocated",
           source: :thunderbolt,
           payload: event_attrs,
           priority: :normal,
           meta: %{pipeline: :general, correlation_id: allocation.id}
         }) do
      {:ok, _event} ->
        {:ok, allocation}

      {:error, reason} ->
        # Log but don't fail the allocation operation
        require Logger
        Logger.warning("Failed to publish orchestration event: #{inspect(reason)}")
        {:ok, allocation}
    end
  end
end
