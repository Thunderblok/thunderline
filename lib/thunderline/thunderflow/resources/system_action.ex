defmodule Thunderline.Thunderflow.Resources.SystemAction do
  @moduledoc """
  SystemAction Resource - Tracks system-level operations and their results

  Part of the Thunderflow domain for event processing and system coordination.
  This resource captures administrative actions executed through the dashboard,
  providing audit trails and real-time monitoring of system operations.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderflow.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "system_actions"
    repo Thunderline.Repo

    identity_wheres_to_sql unique_pending_action: "status = 'pending'"
  end

  code_interface do
    define :create, action: :create
    define :start_execution, action: :start_execution
    define :complete_success, action: :complete_success
    define :complete_failure, action: :complete_failure
    define :cancel, action: :cancel
    define :recent_actions, action: :recent_actions
    define :by_status, action: :by_status, args: [:status]
    define :by_action_type, action: :by_action_type, args: [:action_type]
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :action_type,
        :action_name,
        :parameters,
        :initiated_by,
        :initiated_at
      ]
    end

    update :start_execution do
      accept []
      change set_attribute(:status, :executing)
      change set_attribute(:completed_at, nil)
    end

    update :complete_success do
      accept [:result, :execution_time_ms]
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :complete_failure do
      accept [:error_message, :execution_time_ms]
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept []
      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :recent_actions do
      pagination offset?: true, default_limit: 50
      filter expr(created_at > ago(1, :day))
    end

    read :by_status do
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
    end

    read :by_action_type do
      argument :action_type, :atom, allow_nil?: false
      filter expr(action_type == ^arg(:action_type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action_type, :atom do
      allow_nil? false

      constraints one_of: [
                    :system_reset,
                    :emergency_stop,
                    :health_check,
                    :system_restart,
                    :safe_mode,
                    :maintenance_mode,
                    :start_streaming,
                    :stop_streaming,
                    :thunderbolt_action,
                    :create_thunderbolt
                  ]
    end

    attribute :action_name, :string do
      allow_nil? false
      constraints max_length: 100
    end

    attribute :parameters, :map do
      allow_nil? true
      default %{}
    end

    attribute :initiated_by, :string do
      allow_nil? false
      default "dashboard"
      constraints max_length: 50
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :executing, :completed, :failed, :cancelled]
    end

    attribute :result, :map do
      allow_nil? true
    end

    attribute :error_message, :string do
      allow_nil? true
      constraints max_length: 500
    end

    attribute :execution_time_ms, :integer do
      allow_nil? true
      constraints min: 0
    end

    attribute :initiated_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  calculations do
    calculate :duration_seconds,
              :decimal,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))", completed_at, initiated_at)) do
      load [:completed_at, :initiated_at]
    end

    calculate :is_completed, :boolean, expr(status in [:completed, :failed, :cancelled])

    calculate :success_rate,
              :decimal,
              expr(
                fragment(
                  "CASE WHEN ? = 'completed' THEN 1.0 WHEN ? IN ('failed', 'cancelled') THEN 0.0 ELSE NULL END",
                  status,
                  status
                )
              )
  end

  identities do
    identity :unique_pending_action, [:action_type, :initiated_by, :status] do
      where expr(status == :pending)
      message "Only one pending action of this type per initiator allowed"
    end
  end

  # Helper functions for dashboard integration

  def track_dashboard_action(
        action_type,
        action_name,
        parameters \\ %{},
        initiated_by \\ "dashboard"
      ) do
    create(%{
      action_type: action_type,
      action_name: action_name,
      parameters: parameters,
      initiated_by: initiated_by,
      initiated_at: DateTime.utc_now()
    })
  end

  def complete_action_success(action_id, result \\ %{}, execution_time_ms \\ nil) do
    case Ash.get(__MODULE__, action_id) do
      {:ok, action} ->
        complete_success(action, %{
          result: result,
          execution_time_ms: execution_time_ms
        })

      error ->
        error
    end
  end

  def complete_action_failure(action_id, error_message, execution_time_ms \\ nil) do
    case Ash.get(__MODULE__, action_id) do
      {:ok, action} ->
        complete_failure(action, %{
          error_message: error_message,
          execution_time_ms: execution_time_ms
        })

      error ->
        error
    end
  end

  def get_dashboard_metrics do
    recent_actions = recent_actions!()

    total_actions = Enum.count(recent_actions)
    completed_actions = Enum.count(recent_actions, &(&1.status == :completed))
    failed_actions = Enum.count(recent_actions, &(&1.status == :failed))

    success_rate =
      if total_actions > 0 do
        (completed_actions / total_actions * 100) |> Float.round(1)
      else
        0.0
      end

    %{
      total_actions_24h: total_actions,
      completed_actions: completed_actions,
      failed_actions: failed_actions,
      pending_actions: Enum.count(recent_actions, &(&1.status == :pending)),
      success_rate: success_rate,
      avg_execution_time: calculate_avg_execution_time(recent_actions),
      recent_actions: Enum.take(recent_actions, 10)
    }
  end

  defp calculate_avg_execution_time(actions) do
    completed_actions = Enum.filter(actions, &(&1.execution_time_ms != nil))

    if Enum.count(completed_actions) > 0 do
      completed_actions
      |> Enum.map(& &1.execution_time_ms)
      |> Enum.sum()
      |> Kernel./(Enum.count(completed_actions))
      |> Float.round(0)
    else
      0
    end
  end
end
