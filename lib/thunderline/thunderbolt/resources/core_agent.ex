defmodule Thunderline.Thunderbolt.Resources.CoreAgent do
  @moduledoc """
  System agent coordination and lifecycle management
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins

  postgres do
    table "thundercore_agents"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description "Register new system agent"
      primary? true
      accept [:agent_name, :agent_type, :capabilities]
      change set_attribute(:status, :active)
    end

    update :heartbeat do
      description "Update agent heartbeat"
      accept [:status, :current_task]
      change set_attribute(:last_heartbeat, &DateTime.utc_now/0)
    end

    read :active_agents do
      description "Get all active agents"
      filter expr(status == :active)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :agent_name, :string do
      description "Agent identifier"
      allow_nil? false
    end

    attribute :agent_type, :atom do
      description "Type of system agent"
      allow_nil? false
    end

    attribute :status, :atom do
      description "Current agent status"
      default :starting
    end

    attribute :capabilities, :map do
      description "Agent capabilities and configuration"
      default %{}
    end

    attribute :current_task, :string do
      description "Currently executing task"
    end

    attribute :last_heartbeat, :utc_datetime_usec do
      description "Last heartbeat timestamp"
      default &DateTime.utc_now/0
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_agent_name, [:agent_name]
  end
end
