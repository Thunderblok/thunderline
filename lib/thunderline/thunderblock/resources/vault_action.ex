defmodule Thunderline.Thunderblock.Resources.VaultAction do
  @moduledoc """
  Action Resource - Migrated from lib/thunderline/pac/resources/action

  Agent actions in the PAC (Perception-Action-Cognition) system.
  Records and tracks all agent actions for learning and analysis.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events]

  import Ash.Resource.Change.Builtins




  postgres do
    table "actions"
    repo Thunderline.Repo
  end

  events do
    event_log Thunderline.Thunderflow.Events.Event
    current_action_versions create: 1, update: 1, destroy: 1
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      allow_nil? false
      description "Type of action performed"
    end

    attribute :name, :string do
      allow_nil? false
      constraints max_length: 100
      description "Human-readable action name"
    end

    attribute :parameters, :map do
      allow_nil? false
      default %{}
      description "Action parameters and context"
    end

    attribute :result, :map do
      allow_nil? true
      description "Action execution result data"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      description "Action execution status"
    end

    attribute :started_at, :utc_datetime do
      allow_nil? true
      description "Action execution start timestamp"
    end

    attribute :completed_at, :utc_datetime do
      allow_nil? true
      description "Action completion timestamp"
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      constraints min: 0
      description "Action execution duration in milliseconds"
    end

    attribute :success, :boolean do
      allow_nil? true
      description "Whether action completed successfully"
    end

    attribute :error_message, :string do
      allow_nil? true
      description "Error message if action failed"
    end

    attribute :confidence_score, :decimal do
      allow_nil? true
      constraints min: 0, max: 1
      description "Agent confidence in action (0.0 to 1.0)"
    end

    attribute :cost, :decimal do
      allow_nil? false
      default Decimal.new("0.0")
      description "Computational cost of action"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 100
      constraints min: 1, max: 1000
      description "Action execution priority"
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, Thunderline.Thunderblock.Resources.VaultAgent do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :decision, Thunderline.Thunderblock.Resources.VaultDecision do
      allow_nil? true
      attribute_writable? true
      description "Decision that triggered this action"
    end

    belongs_to :parent_action, __MODULE__ do
      allow_nil? true
      attribute_writable? true
      description "Parent action for sub-actions"
    end

    has_many :child_actions, __MODULE__ do
      destination_attribute :parent_action_id
      description "Sub-actions spawned by this action"
    end
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    create :queue_action do
      accept [:agent_id, :type, :name, :parameters, :priority, :confidence_score, :decision_id, :parent_action_id]

      change set_attribute(:status, :pending)
    end

    update :start_execution do
      accept []

      change set_attribute(:status, :executing)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete_action do
      accept [:result, :success]
      require_atomic? false

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        started_at = Ash.Changeset.get_attribute(changeset, :started_at)
        if started_at do
          duration = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
          Ash.Changeset.change_attribute(changeset, :duration_ms, duration)
        else
          changeset
        end
      end
    end

    update :fail_action do
      accept [:error_message]
      require_atomic? false

      change set_attribute(:status, :failed)
      change set_attribute(:success, false)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        started_at = Ash.Changeset.get_attribute(changeset, :started_at)
        if started_at do
          duration = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
          Ash.Changeset.change_attribute(changeset, :duration_ms, duration)
        else
          changeset
        end
      end
    end

    update :cancel_action do
      accept []

      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :by_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
    end

    read :by_status do
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
    end

    read :pending_actions do
      filter expr(status == :pending)
      prepare build(sort: [priority: :desc, inserted_at: :asc])
    end

    read :recent_actions do
      argument :hours, :integer, default: 24
      filter expr(inserted_at > ago(^arg(:hours), :hour))
      prepare build(sort: [inserted_at: :desc])
    end

    read :successful_actions do
      filter expr(success == true)
    end

    read :failed_actions do
      filter expr(success == false)
    end
  end

  preparations do
    prepare build(load: [:agent])
  end

  aggregates do
    count :child_action_count, :child_actions

    avg :average_child_duration, :child_actions, :duration_ms do
      authorize? false
    end
  end

  validations do
    validate present([:agent_id, :type, :name])
    validate string_length(:name, min: 1, max: 100)
    validate numericality(:priority, greater_than: 0, less_than_or_equal_to: 1000)
    validate numericality(:confidence_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1) do
      where present(:confidence_score)
    end
    validate numericality(:duration_ms, greater_than_or_equal_to: 0) do
      where present(:duration_ms)
    end
  end

  # TODO: Re-enable policies once AshAuthentication is properly configured
  # policies do
  #   policy action_type(:read) do
  #     authorize_if always()
  #   end

  #   policy action_type([:create, :update]) do
  #     authorize_if actor_present()
  #   end

  #   policy action_type(:destroy) do
  #     authorize_if relates_to_actor_via([:agent, :created_by_user])
  #     authorize_if actor_attribute_equals(:role, :admin)
  #   end
  # end
end
