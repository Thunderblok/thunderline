defmodule Thunderline.Thunderbolt.Resources.MagTaskAssignment do
  @moduledoc """
  Ash resource for tracking individual task assignments to Thunderbits.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "thundermag_task_assignments"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :assign_task do
      accept [
        :task_execution_id,
        :task_id,
        :thunderbit_id,
        :zone_id,
        :task_type,
        :task_value,
        :sequence,
        :priority,
        :estimated_execution_time_ms,
        :max_retries
      ]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:assigned_at, DateTime.utc_now())
      end
    end

    update :start_execution do
      accept [:status]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :executing)
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
      end
    end

    update :complete_task do
      accept [:status, :result, :actual_execution_time_ms]

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end

    update :fail_task do
      accept [:status, :error, :retry_count]
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end

    update :retry_task do
      accept [:retry_count]
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :retrying)
      end
    end
  end

  preparations do
    prepare build(load: [:can_retry, :execution_duration_ms])
  end

  attributes do
    uuid_primary_key :id

    attribute :task_execution_id, :uuid do
      allow_nil? false
    end

    attribute :task_id, :uuid do
      allow_nil? false
    end

    attribute :thunderbit_id, :uuid
    attribute :zone_id, :string

    attribute :task_type, :atom do
      allow_nil? false
    end

    attribute :task_value, :string
    attribute :sequence, :integer

    attribute :status, :atom do
      allow_nil? false
      default :assigned
    end

    attribute :priority, :atom do
      default :normal
    end

    attribute :estimated_execution_time_ms, :integer
    attribute :actual_execution_time_ms, :integer

    attribute :retry_count, :integer, default: 0
    attribute :max_retries, :integer, default: 3

    attribute :result, :map
    attribute :error, :map

    attribute :assigned_at, :utc_datetime
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :task_execution, Thunderline.Thunderbolt.Resources.MagTaskExecution
  end

  calculations do
    calculate :can_retry, :boolean, expr(retry_count < max_retries and status == :failed)

    calculate :execution_duration_ms,
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
