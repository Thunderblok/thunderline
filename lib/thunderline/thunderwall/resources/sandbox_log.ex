defmodule Thunderline.Thunderwall.Resources.SandboxLog do
  @moduledoc """
  Sandbox operation log for Thunderwall containment actions.

  HC-Ω-10: Records all sandbox operations including freezes, replays,
  decay overrides, and quarantines for audit and rollback capability.

  ## Operation Types

  - `:freeze` - Chunk frozen for N ticks
  - `:replay` - Mirror replay of historical tick range
  - `:decay_override` - PAC decay factor modified
  - `:quarantine` - Segment isolated from normal processing

  ## State Lifecycle

  Operations can be in states:
  - `:pending` - Scheduled but not yet active
  - `:active` - Currently in effect
  - `:completed` - Finished normally
  - `:cancelled` - Terminated early
  - `:failed` - Error during execution

  ## Audit Trail

  Each log entry captures:
  - Who/what triggered the operation
  - Target (chunk, PAC, segment)
  - Duration and parameters
  - Start/end timestamps
  - Outcome and any errors
  """

  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderwall.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  require Logger

  alias Thunderline.Thunderflow.EventBus

  postgres do
    table "thunderwall_sandbox_logs"
    repo Thunderline.Repo

    custom_indexes do
      index [:operation_type], name: "sandbox_logs_type_idx"
      index [:status], name: "sandbox_logs_status_idx"
      index [:target_type, :target_id], name: "sandbox_logs_target_idx"
      index [:started_at], name: "sandbox_logs_started_idx"
      index [:expires_at], name: "sandbox_logs_expires_idx"
      index "USING GIN (params)", name: "sandbox_logs_params_idx"
      index "USING GIN (result)", name: "sandbox_logs_result_idx"
    end
  end

  admin do
    form do
      field :operation_type
      field :target_type
      field :target_id
      field :status
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CODE INTERFACE
  # ═══════════════════════════════════════════════════════════════

  code_interface do
    define :log_freeze
    define :log_replay
    define :log_decay_override
    define :log_quarantine
    define :complete
    define :cancel
    define :fail
    define :active_operations
    define :for_target, args: [:target_type, :target_id]
    define :recent
  end

  # ═══════════════════════════════════════════════════════════════
  # ACTIONS
  # ═══════════════════════════════════════════════════════════════

  actions do
    defaults [:read, :destroy]

    create :log_freeze do
      description "Log a chunk freeze operation"

      accept [:target_id, :triggered_by, :reason]

      argument :ticks, :integer do
        allow_nil? false
        description "Number of ticks to freeze"
      end

      change set_attribute(:operation_type, :freeze)
      change set_attribute(:target_type, :chunk)
      change set_attribute(:status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        ticks = Ash.Changeset.get_argument(changeset, :ticks)

        # Estimate expiration (assuming 50ms per tick)
        expires_ms = ticks * 50
        expires_at = DateTime.add(DateTime.utc_now(), expires_ms, :millisecond)

        changeset
        |> Ash.Changeset.force_change_attribute(:params, %{ticks: ticks})
        |> Ash.Changeset.force_change_attribute(:expires_at, expires_at)
      end

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :freeze_started)
               {:ok, record}
             end)
    end

    create :log_replay do
      description "Log a mirror replay operation"

      accept [:target_id, :triggered_by, :reason]

      argument :start_tick, :integer do
        allow_nil? false
      end

      argument :end_tick, :integer do
        allow_nil? false
      end

      change set_attribute(:operation_type, :replay)
      change set_attribute(:target_type, :chunk)
      change set_attribute(:status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        start_tick = Ash.Changeset.get_argument(changeset, :start_tick)
        end_tick = Ash.Changeset.get_argument(changeset, :end_tick)

        Ash.Changeset.force_change_attribute(changeset, :params, %{
          start_tick: start_tick,
          end_tick: end_tick,
          tick_range: end_tick - start_tick
        })
      end

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :replay_started)
               {:ok, record}
             end)
    end

    create :log_decay_override do
      description "Log a decay factor override"

      accept [:target_id, :triggered_by, :reason]

      argument :factor, :float do
        allow_nil? false
        constraints min: 0.0, max: 10.0
        description "Decay factor multiplier"
      end

      argument :duration_hours, :integer do
        allow_nil? true
        default 24
      end

      change set_attribute(:operation_type, :decay_override)
      change set_attribute(:target_type, :pac)
      change set_attribute(:status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        factor = Ash.Changeset.get_argument(changeset, :factor)
        hours = Ash.Changeset.get_argument(changeset, :duration_hours) || 24
        expires_at = DateTime.add(DateTime.utc_now(), hours, :hour)

        changeset
        |> Ash.Changeset.force_change_attribute(:params, %{factor: factor, duration_hours: hours})
        |> Ash.Changeset.force_change_attribute(:expires_at, expires_at)
      end

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :decay_override_started)
               {:ok, record}
             end)
    end

    create :log_quarantine do
      description "Log a segment quarantine"

      accept [:target_id, :triggered_by, :reason]

      argument :isolation_level, :atom do
        allow_nil? true
        default :partial
        constraints one_of: [:partial, :full]
      end

      change set_attribute(:operation_type, :quarantine)
      change set_attribute(:target_type, :segment)
      change set_attribute(:status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        level = Ash.Changeset.get_argument(changeset, :isolation_level) || :partial

        Ash.Changeset.force_change_attribute(changeset, :params, %{
          isolation_level: level
        })
      end

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :quarantine_started)
               {:ok, record}
             end)
    end

    update :complete do
      description "Mark operation as completed"

      accept [:result]

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :completed)
               {:ok, record}
             end)
    end

    update :cancel do
      description "Cancel an active operation"

      argument :cancel_reason, :string do
        allow_nil? true
      end

      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        reason = Ash.Changeset.get_argument(changeset, :cancel_reason)

        if reason do
          result = Map.put(changeset.data.result || %{}, :cancel_reason, reason)
          Ash.Changeset.force_change_attribute(changeset, :result, result)
        else
          changeset
        end
      end

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :cancelled)
               {:ok, record}
             end)
    end

    update :fail do
      description "Mark operation as failed"

      accept [:error_details]

      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)

      change after_action(fn _changeset, record, _context ->
               emit_sandbox_event(record, :failed)
               {:ok, record}
             end)
    end

    read :active_operations do
      description "List all active sandbox operations"

      prepare fn query, _context ->
        query
        |> Ash.Query.filter(status == :active)
        |> Ash.Query.sort(started_at: :desc)
      end
    end

    read :for_target do
      description "List operations for a specific target"

      argument :target_type, :atom do
        allow_nil? false
      end

      argument :target_id, :string do
        allow_nil? false
      end

      prepare fn query, _context ->
        target_type = Ash.Query.get_argument(query, :target_type)
        target_id = Ash.Query.get_argument(query, :target_id)

        query
        |> Ash.Query.filter(target_type == ^target_type)
        |> Ash.Query.filter(target_id == ^target_id)
        |> Ash.Query.sort(inserted_at: :desc)
      end
    end

    read :recent do
      description "List recent sandbox operations"

      argument :limit, :integer do
        allow_nil? true
        default 50
      end

      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit) || 50

        query
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ATTRIBUTES
  # ═══════════════════════════════════════════════════════════════

  attributes do
    uuid_primary_key :id

    attribute :operation_type, :atom do
      constraints one_of: [:freeze, :replay, :decay_override, :quarantine]
      allow_nil? false
      public? true
      description "Type of sandbox operation"
    end

    attribute :target_type, :atom do
      constraints one_of: [:chunk, :pac, :segment, :bit]
      allow_nil? false
      public? true
      description "Type of target being operated on"
    end

    attribute :target_id, :string do
      allow_nil? false
      public? true
      description "ID of the target (chunk_id, pac_id, segment_id)"
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :active, :completed, :cancelled, :failed]
      allow_nil? false
      default :pending
      public? true
      description "Current status of the operation"
    end

    attribute :params, :map do
      allow_nil? false
      default %{}
      public? true
      description "Operation parameters (ticks, factor, range, etc.)"
    end

    attribute :result, :map do
      allow_nil? false
      default %{}
      public? true
      description "Operation result/outcome data"
    end

    attribute :triggered_by, :string do
      allow_nil? true
      public? true
      description "Source that triggered this operation (handler, user, system)"
    end

    attribute :reason, :string do
      allow_nil? true
      public? true
      description "Human-readable reason for the operation"
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the operation became active"
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the operation completed/terminated"
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When the operation will automatically expire"
    end

    attribute :error_details, :map do
      allow_nil? true
      public? true
      description "Error information if operation failed"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  # ═══════════════════════════════════════════════════════════════
  # CALCULATIONS
  # ═══════════════════════════════════════════════════════════════

  calculations do
    calculate :is_active, :boolean do
      calculation fn records, _context ->
        Enum.map(records, fn record -> record.status == :active end)
      end
    end

    calculate :duration_seconds, :integer do
      calculation fn records, _context ->
        Enum.map(records, fn record ->
          case {record.started_at, record.completed_at} do
            {nil, _} -> 0
            {started, nil} -> DateTime.diff(DateTime.utc_now(), started, :second)
            {started, completed} -> DateTime.diff(completed, started, :second)
          end
        end)
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp emit_sandbox_event(record, event_suffix) do
    event_attrs = %{
      type: :"wall.sandbox.#{record.operation_type}.#{event_suffix}",
      source: :wall,
      payload: %{
        log_id: record.id,
        operation_type: record.operation_type,
        target_type: record.target_type,
        target_id: record.target_id,
        status: record.status,
        params: record.params
      },
      metadata: %{
        resource: __MODULE__,
        triggered_by: record.triggered_by
      }
    }

    with {:ok, ev} <- Thunderline.Event.new(event_attrs) do
      EventBus.publish_event(ev)
    else
      {:error, reason} ->
        Logger.warning("[SandboxLog] Failed to emit #{event_suffix} event: #{inspect(reason)}")
    end
  end
end
