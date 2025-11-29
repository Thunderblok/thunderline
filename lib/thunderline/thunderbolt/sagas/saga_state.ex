defmodule Thunderline.Thunderbolt.Sagas.SagaState do
  @moduledoc """
  Ash resource for persisting saga execution state.

  Tracks the lifecycle of Reactor saga executions including:
  - Current status (pending, running, completed, failed, halted, retrying)
  - Input/output data
  - Checkpoint data for halted sagas (resume support)
  - Attempt tracking and error history
  - Timestamps for auditing

  ## Saga Lifecycle

      pending → running → completed
                      ↘ failed
                      ↘ halted (can resume)
                      ↘ retrying → running...

  ## Usage

      # Query saga state by correlation_id
      {:ok, state} = Ash.get(SagaState, correlation_id)

      # List failed sagas for a module
      {:ok, failed} = Ash.read(SagaState,
        filter: [saga_module: "Elixir.MyApp.MySaga", status: :failed]
      )
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderbolt,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  @saga_statuses [:pending, :running, :completed, :failed, :halted, :retrying, :cancelled]

  postgres do
    table "saga_states"
    repo Thunderline.Repo

    custom_indexes do
      index [:saga_module, :status]
      index [:status, :last_attempt_at]
      index [:inserted_at]
    end
  end

  json_api do
    type "saga_state"

    routes do
      base "/saga-states"
      get :read
      index :list
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :saga_module, :string do
      allow_nil? false
      description "Fully qualified module name of the Reactor saga"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: @saga_statuses
      description "Current execution status of the saga"
    end

    attribute :inputs, :map do
      default %{}
      description "Input arguments passed to the saga"
    end

    attribute :output, :string do
      description "JSON-serialized output from successful completion"
    end

    attribute :checkpoint, :string do
      description "Serialized Reactor state for halted sagas (resume support)"
    end

    attribute :error, :string do
      description "Error message from failed execution"
    end

    attribute :attempt_count, :integer do
      allow_nil? false
      default 0
      description "Number of execution attempts"
    end

    attribute :max_attempts, :integer do
      default 3
      description "Maximum allowed retry attempts"
    end

    attribute :last_attempt_at, :utc_datetime_usec do
      description "Timestamp of the most recent execution attempt"
    end

    attribute :completed_at, :utc_datetime_usec do
      description "Timestamp when saga completed successfully"
    end

    attribute :timeout_ms, :integer do
      default 60_000
      description "Execution timeout in milliseconds"
    end

    attribute :meta, :map do
      default %{}
      description "Additional metadata (actor, tenant, etc.)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :correlation_id, [:id]
  end

  actions do
    defaults [:read, :destroy]

    read :list do
      pagination keyset?: true, default_limit: 50
    end

    read :list_by_status do
      argument :status, :atom do
        allow_nil? false
        constraints one_of: @saga_statuses
      end

      filter expr(status == ^arg(:status))
      pagination keyset?: true, default_limit: 50
    end

    read :list_by_module do
      argument :saga_module, :string do
        allow_nil? false
      end

      filter expr(saga_module == ^arg(:saga_module))
      pagination keyset?: true, default_limit: 50
    end

    read :stale_sagas do
      description "Find sagas that have been running too long"

      argument :older_than_seconds, :integer do
        allow_nil? false
        default 3600
      end

      filter expr(
               status == :running and
                 last_attempt_at < ago(^arg(:older_than_seconds), :second)
             )
    end

    create :create do
      accept [
        :id,
        :saga_module,
        :status,
        :inputs,
        :attempt_count,
        :max_attempts,
        :timeout_ms,
        :meta,
        :last_attempt_at
      ]
    end

    update :update do
      accept [
        :status,
        :output,
        :checkpoint,
        :error,
        :attempt_count,
        :last_attempt_at,
        :completed_at,
        :meta
      ]
    end

    update :mark_running do
      change set_attribute(:status, :running)
      change set_attribute(:last_attempt_at, &DateTime.utc_now/0)
      change atomic_update(:attempt_count, expr(attempt_count + 1))
    end

    update :mark_completed do
      argument :output, :string

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:output, arg(:output))
    end

    update :mark_failed do
      argument :error, :string

      change set_attribute(:status, :failed)
      change set_attribute(:error, arg(:error))
    end

    update :mark_halted do
      argument :checkpoint, :string

      change set_attribute(:status, :halted)
      change set_attribute(:checkpoint, arg(:checkpoint))
    end

    update :cancel do
      change set_attribute(:status, :cancelled)
    end
  end

  calculations do
    calculate :duration_ms, :integer do
      description "Execution duration in milliseconds (if completed)"

      calculation fn records, _context ->
        Enum.map(records, fn record ->
          case {record.last_attempt_at, record.completed_at} do
            {start, finish} when not is_nil(start) and not is_nil(finish) ->
              DateTime.diff(finish, start, :millisecond)

            _ ->
              nil
          end
        end)
      end
    end

    calculate :is_resumable?, :boolean do
      description "Whether the saga can be resumed"

      calculation fn records, _context ->
        Enum.map(records, fn record ->
          record.status == :halted and not is_nil(record.checkpoint)
        end)
      end
    end

    calculate :attempts_remaining, :integer do
      description "Number of retry attempts remaining"

      calculation fn records, _context ->
        Enum.map(records, fn record ->
          max(0, (record.max_attempts || 3) - (record.attempt_count || 0))
        end)
      end
    end
  end

  code_interface do
    define :get, action: :read, args: [:id]
    define :list_by_status, args: [:status]
    define :list_by_module, args: [:saga_module]
    define :find_stale, action: :stale_sagas, args: [:older_than_seconds]
    define :cancel
  end
end
