defmodule Thunderblock.Resources.ExecutionContainer do
  @moduledoc """
  Execution Container Management Resource

  Manages isolated execution environments for distributed task processing.
  Each container provides secure process isolation, resource limits, and
  execution monitoring capabilities.

  **NOT a blockchain** - This is a distributed execution container system.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer
  import Ash.Resource.Change.Builtins

  postgres do
    table "execution_containers"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :status, :atom, constraints: [one_of: [:idle, :running, :paused, :completed, :failed, :terminated]]
    attribute :container_type, :atom, constraints: [one_of: [:task_executor, :batch_processor, :stream_processor, :federation_bridge]]
    attribute :resource_limits, :map, default: %{
      cpu_limit: 1.0,
      memory_mb: 512,
      disk_mb: 1024,
      max_processes: 100
    }
    attribute :environment, :map, default: %{}
    attribute :security_policy, :map, default: %{
      isolation_level: :standard,
      network_access: :restricted,
      file_access: :sandbox
    }
    attribute :execution_metadata, :map, default: %{}
    attribute :node_assignment, :string
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :provision do
      accept [:name, :container_type, :resource_limits, :environment, :security_policy, :node_assignment]
      change set_attribute(:status, :idle)
    end

    update :start_execution do
      accept [:execution_metadata]
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :pause_execution do
      change set_attribute(:status, :paused)
    end

    update :resume_execution do
      change set_attribute(:status, :running)
    end

    update :complete_execution do
      accept [:execution_metadata]
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail_execution do
      accept [:execution_metadata]
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :terminate do
      change set_attribute(:status, :terminated)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :active_containers do
      filter expr(status in [:running, :paused])
    end

    read :by_node do
      argument :node_name, :string, allow_nil?: false
      filter expr(node_assignment == ^arg(:node_name))
    end

    read :by_type do
      argument :type, :atom, allow_nil?: false
      filter expr(container_type == ^arg(:type))
    end
  end

  calculations do
    calculate :execution_duration_ms, :integer, expr(
      cond do
        not is_nil(completed_at) and not is_nil(started_at) ->
          datetime_diff(completed_at, started_at, :millisecond)
        not is_nil(started_at) ->
          datetime_diff(now(), started_at, :millisecond)
        true -> 0
      end
    )

    calculate :is_long_running, :boolean, expr(
      status == :running and not is_nil(started_at) and
      datetime_diff(now(), started_at, :minute) > 60
    )

    calculate :resource_utilization, :atom, expr(
      cond do
        status in [:idle, :completed, :failed, :terminated] -> :none
        get_path(resource_limits, [:cpu_limit]) > 2.0 -> :high
        get_path(resource_limits, [:cpu_limit]) > 1.0 -> :medium
        true -> :low
      end
    )
  end

  identities do
    identity :unique_container_name, [:name]
  end

  preparations do
    prepare build(sort: [created_at: :desc])
  end
end
