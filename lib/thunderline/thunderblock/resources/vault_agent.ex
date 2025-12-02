defmodule Thunderline.Thunderblock.Resources.VaultAgent do
  @moduledoc """
  Agent Resource - Migrated from lib/thunderline/pac/resources/agent

  Thunderbit agents in the PAC (Perception-Action-Cognition) system.
  ThunderBlock Vault agent (persistence & federation coordination; legacy Thundervault consolidation).
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events],
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Resource.Change.Builtins

  postgres do
    table "agents"
    repo Thunderline.Repo
  end

  events do
    event_log(Thunderline.Thunderflow.Events.Event)
    current_action_versions(create: 1, update: 1, destroy: 1)
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :spawn_agent do
      accept [:name, :type, :zone_id, :capabilities, :configuration, :created_by_user_id]

      change set_attribute(:status, :idle)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :activate do
      accept []
      change set_attribute(:status, :active)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :suspend do
      accept []
      change set_attribute(:status, :suspended)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :terminate do
      accept []
      change set_attribute(:status, :terminated)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :record_action do
      accept [:state_data]

      change increment(:total_actions)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :update_success_rate do
      argument :success, :boolean, allow_nil?: false
      require_atomic? false

      change fn changeset, context ->
        current_rate = Ash.Changeset.get_attribute(changeset, :success_rate) || Decimal.new("0.0")
        total_actions = Ash.Changeset.get_attribute(changeset, :total_actions) || 0

        if total_actions > 0 do
          success_value = if context.arguments.success, do: 1, else: 0

          new_rate =
            Decimal.div(
              Decimal.add(Decimal.mult(current_rate, total_actions), success_value),
              total_actions + 1
            )

          Ash.Changeset.change_attribute(changeset, :success_rate, new_rate)
        else
          changeset
        end
      end
    end

    read :by_zone do
      argument :zone_id, :string, allow_nil?: false
      filter expr(zone_id == ^arg(:zone_id))
    end

    read :by_type do
      argument :type, :atom, allow_nil?: false
      filter expr(type == ^arg(:type))
    end

    read :active_agents do
      filter expr(status in [:active, :thinking, :acting])
    end
  end

  preparations do
    prepare build(sort: [priority: :desc, inserted_at: :desc])
  end

  validations do
    validate present([:name, :type])
    validate string_length(:name, min: 1, max: 100)
    validate numericality(:priority, greater_than: 0, less_than_or_equal_to: 1000)
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 100
      description "Agent display name"
    end

    attribute :type, :atom do
      allow_nil? false
      description "Agent classification type"
    end

    attribute :status, :atom do
      allow_nil? false
      default :idle
      description "Current agent execution status"
    end

    attribute :zone_id, :string do
      allow_nil? true
      constraints max_length: 50
      description "Zone assignment for distributed agents"
    end

    attribute :capabilities, {:array, :atom} do
      allow_nil? false
      default []
      description "List of agent capabilities/skills"
    end

    attribute :configuration, :map do
      allow_nil? false
      default %{}
      description "Agent configuration parameters"
    end

    attribute :state_data, :map do
      allow_nil? false
      default %{}
      description "Current agent state and memory"
    end

    attribute :last_activity_at, :utc_datetime do
      allow_nil? true
      description "Timestamp of last agent activity"
    end

    attribute :total_actions, :integer do
      allow_nil? false
      default 0
      description "Total number of actions performed"
    end

    attribute :success_rate, :decimal do
      allow_nil? false
      default Decimal.new("0.0")
      description "Agent success rate (0.0 to 1.0)"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 100
      constraints min: 1, max: 1000
      description "Agent execution priority"
    end

    timestamps()
  end

  relationships do
    belongs_to :created_by_user, Thunderline.Thunderblock.Resources.VaultUser do
      allow_nil? true
      attribute_writable? true
    end

    has_many :actions, Thunderline.Thunderblock.Resources.VaultAction do
      destination_attribute :agent_id
    end

    has_many :decisions, Thunderline.Thunderblock.Resources.VaultDecision do
      destination_attribute :agent_id
    end

    has_many :memory_records, Thunderline.Thunderblock.Resources.VaultMemoryRecord do
      destination_attribute :agent_id
    end
  end

  # ===== POLICIES =====
  policies do
    # Bypass for AshAuthentication internal operations
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Read: Allow all authenticated users
    policy action_type(:read) do
      authorize_if actor_present()
    end

    # Create/Update: Require authenticated actor
    policy action_type([:create, :update]) do
      authorize_if actor_present()
    end

    # Destroy: Only creator or admin
    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:created_by_user)
      authorize_if expr(^actor(:role) == :admin)
    end
  end
end
