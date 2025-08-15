defmodule Thunderblock.Resources.ClusterNode do
  @moduledoc """
  Cluster node tracking and health monitoring
  Replaces in-memory cluster state with persistent Ash resource
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "thunderblock_cluster_nodes"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description "Register a new cluster node"
      primary? true
      accept [:node_name, :node_type, :capabilities, :metadata]
      change set_attribute(:status, :online)
      change set_attribute(:last_heartbeat, &DateTime.utc_now/0)
    end

    update :heartbeat do
      description "Update node heartbeat and status"
      accept [:status, :load_score, :capabilities]
      change set_attribute(:last_heartbeat, &DateTime.utc_now/0)
    end

    update :set_maintenance do
      description "Put node in maintenance mode"
      accept []
      change set_attribute(:status, :maintenance)
    end

    update :bring_online do
      description "Bring node back online"
      accept []
      change set_attribute(:status, :online)
      change set_attribute(:last_heartbeat, &DateTime.utc_now/0)
    end

    read :get_online_nodes do
      description "Get all online cluster nodes"
      filter expr(status == :online)
    end

    read :get_coordinators do
      description "Get all coordinator nodes"
      filter expr(node_type == :coordinator and status == :online)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :node_name, :string do
      description "Unique node identifier"
      allow_nil? false
    end

    attribute :node_type, :atom do
      description "Type of cluster node"
      default :worker
    end

    attribute :status, :atom do
      description "Current node status"
      default :offline
    end

    attribute :load_score, :decimal do
      description "Current load/utilization score (0.0-1.0)"
      default Decimal.new("0.0")
    end

    attribute :capabilities, :map do
      description "Node capabilities and resources"
      default %{}
    end

    attribute :last_heartbeat, :utc_datetime_usec do
      description "Last heartbeat received from node"
      default &DateTime.utc_now/0
    end

    attribute :metadata, :map do
      description "Additional node metadata"
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :is_healthy,
              :boolean,
              expr(
                status == :online and
                  fragment("? > NOW() - INTERVAL '30 seconds'", last_heartbeat)
              )
  end

  identities do
    identity :unique_node_name, [:node_name]
  end
end
