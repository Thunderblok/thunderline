defmodule Thunderline.Thunderbolt.Resources.MagTaskExecution do
  @moduledoc """
  Ash resource for tracking task execution progress and results.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "thundermag_task_executions"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :start_execution do
      accept [
        :execution_id,
        :macro_command_id,
        :total_tasks,
        :execution_plan,
        :session_id,
        :zone_assignments
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :executing)
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
      end
    end

    update :update_progress do
      accept [:completed_tasks, :failed_tasks, :results, :errors]
    end

    update :complete_execution do
      accept [:status, :completed_at]
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end

    update :cancel_execution do
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :cancelled)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end
  end

  preparations do
    prepare build(load: [:completion_percentage, :duration_ms])
  end

  attributes do
    uuid_primary_key :id

    attribute :execution_id, :uuid do
      allow_nil? false
    end

    attribute :macro_command_id, :uuid do
      allow_nil? false
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
    end

    attribute :total_tasks, :integer do
      allow_nil? false
      default 0
    end

    attribute :completed_tasks, :integer do
      default 0
    end

    attribute :failed_tasks, :integer do
      default 0
    end

    attribute :execution_plan, :map do
      default %{}
    end

    attribute :results, {:array, :map} do
      default []
    end

    attribute :errors, {:array, :map} do
      default []
    end

    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    attribute :session_id, :uuid
    attribute :zone_assignments, {:array, :string}, default: []

    timestamps()
  end

  relationships do
    belongs_to :macro_command, Thunderline.Thunderbolt.Resources.MagMacroCommand

    has_many :task_assignments, Thunderline.Thunderbolt.Resources.MagTaskAssignment do
      destination_attribute :task_execution_id
    end
  end

  calculations do
    calculate :completion_percentage,
              :decimal,
              expr(
                if total_tasks > 0 do
                  completed_tasks / total_tasks * 100
                else
                  0
                end
              )

    calculate :duration_ms,
              :integer,
              expr(
                if not is_nil(started_at) and not is_nil(completed_at) do
                  datetime_diff(completed_at, started_at, :millisecond)
                else
                  nil
                end
              )
  end
end
