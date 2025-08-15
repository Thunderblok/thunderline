defmodule Thunderblock.Resources.TaskOrchestrator do
  @moduledoc """
  Task Orchestration and Workflow Management Resource

  Coordinates complex workflows across multiple execution containers,
  manages task dependencies, and handles distributed task scheduling.

  **NOT blockchain** - This is a distributed task orchestration system.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban.Resource]

  import Ash.Resource.Change.Builtins




  postgres do
    table "task_orchestrators"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :workflow_name, :string, allow_nil?: false
    attribute :workflow_version, :string, default: "1.0.0"
    attribute :tasks, {:array, :map}, allow_nil?: false
    attribute :dependencies, :map, default: %{}
    attribute :status, :atom, constraints: [one_of: [:pending, :running, :paused, :completed, :failed, :cancelled]]
    attribute :execution_strategy, :atom, constraints: [one_of: [:sequential, :parallel, :dag, :priority_queue]]
    attribute :retry_policy, :map, default: %{max_attempts: 3, backoff_ms: 1000}
    attribute :timeout_ms, :integer, default: 300_000  # 5 minutes default
    attribute :execution_log, {:array, :map}, default: []
    attribute :current_step, :integer, default: 0
    attribute :total_steps, :integer
    attribute :progress_percentage, :decimal, default: Decimal.new("0.0")
    attribute :assigned_containers, {:array, :string}, default: []
    attribute :metadata, :map, default: %{}
    attribute :started_at, :utc_datetime
    attribute :completed_at, :utc_datetime
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    create :create_workflow do
      accept [:workflow_name, :workflow_version, :tasks, :dependencies, :execution_strategy, :retry_policy, :timeout_ms, :metadata]
      change fn changeset, _context ->
        tasks = Ash.Changeset.get_attribute(changeset, :tasks) || []
        total_steps = length(tasks)
        Ash.Changeset.change_attribute(changeset, :total_steps, total_steps)
      end
    end

    update :start_workflow do
      accept [:assigned_containers]
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :pause_workflow do
      change set_attribute(:status, :paused)
    end

    update :resume_workflow do
      change set_attribute(:status, :running)
    end

    update :complete_workflow do
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:progress_percentage, Decimal.new("100.0"))
    end

    update :fail_workflow do
      accept [:execution_log]
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel_workflow do
      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :update_progress do
      accept [:current_step, :progress_percentage, :execution_log]
    end

    read :active_workflows do
      filter expr(status in [:running, :paused])
    end

    read :by_status do
      argument :workflow_status, :atom, allow_nil?: false
      filter expr(status == ^arg(:workflow_status))
    end

    read :long_running do
      filter expr(
        status == :running and not is_nil(started_at) and
        datetime_diff(now(), started_at, :minute) > 30
      )
    end

    # ThunderChief Cross-Domain Orchestration Actions
    action :trigger_cross_domain_workflow, :struct do
      description "Trigger workflow across multiple domains"
      argument :source_domain, :atom, allow_nil?: false
      argument :target_domains, {:array, :atom}, allow_nil?: false
      argument :operation_type, :atom, allow_nil?: false
      argument :workflow_config, :map, allow_nil?: false

      run fn input, _context ->
        workflow_id = "cross_domain_#{System.unique_integer([:positive])}"

        # Create workflow tracker for each target domain
        Enum.each(input.arguments.target_domains, fn domain ->
          Thunderline.Thunderblock.Resources.WorkflowTracker.create(%{
            workflow_id: workflow_id,
            step_name: input.arguments.operation_type,
            target_count: 1,
            domain_context: domain,
            next_step_config: input.arguments.workflow_config
          })
        end)

        # Enqueue jobs for each target domain
        jobs = Enum.map(input.arguments.target_domains, fn domain ->
          Thunderline.Thunderblock.Jobs.CrossDomainProcessor.new(%{
            "workflow_id" => workflow_id,
            "source_domain" => input.arguments.source_domain,
            "target_domain" => domain,
            "operation_type" => input.arguments.operation_type,
            "config" => input.arguments.workflow_config
          })
          |> Oban.insert()
        end)

        {:ok, %{workflow_id: workflow_id, jobs_created: length(jobs)}}
      end
    end

    action :orchestrate_domain_sync, :struct do
      description "Orchestrate synchronization across all domains"
      argument :sync_type, :atom, allow_nil?: false
      argument :priority, :atom, default: :normal

      run fn input, _context ->
        workflow_id = "domain_sync_#{System.unique_integer([:positive])}"
        domains = [:thunderbit, :thunderflow, :thunderlink, :thundervault, :thundercrown]

        # Create master workflow tracker
        Thunderline.Thunderblock.Resources.WorkflowTracker.create(%{
          workflow_id: workflow_id,
          step_name: :domain_sync,
          target_count: length(domains),
          domain_context: :thunderblock,
          next_step_config: %{"sync_type" => input.arguments.sync_type}
        })

        # Trigger sync jobs for each domain
        jobs = Enum.map(domains, fn domain ->
          Thunderline.Thunderblock.Jobs.DomainSyncProcessor.new(%{
            "workflow_id" => workflow_id,
            "domain" => domain,
            "sync_type" => input.arguments.sync_type,
            "priority" => input.arguments.priority
          })
          |> Oban.insert()
        end)

        {:ok, %{workflow_id: workflow_id, domains_syncing: domains}}
      end
    end

    action :schedule_workflow_execution, :struct do
      description "Schedule workflow for future execution"
      argument :workflow_id, :string, allow_nil?: false
      argument :scheduled_at, :utc_datetime, allow_nil?: false
      argument :workflow_config, :map, allow_nil?: false

      run fn input, _context ->
        # Schedule using AshOban
        Thunderline.Thunderblock.Jobs.ScheduledWorkflowProcessor.new(%{
          "workflow_id" => input.arguments.workflow_id,
          "config" => input.arguments.workflow_config
        }, scheduled_at: input.arguments.scheduled_at)
        |> Oban.insert()

        {:ok, %{scheduled: true, workflow_id: input.arguments.workflow_id}}
      end
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

    calculate :is_stalled, :boolean, expr(
      status == :running and not is_nil(started_at) and
      datetime_diff(now(), updated_at, :minute) > 5
    )

    calculate :completion_estimate, :utc_datetime, expr(
      cond do
        status in [:completed, :failed, :cancelled] -> completed_at
        progress_percentage > 0 and not is_nil(started_at) ->
          datetime_add(
            started_at,
            round(datetime_diff(now(), started_at, :millisecond) * (100 / progress_percentage)),
            :millisecond
          )
        true -> nil
      end
    )
  end

  identities do
    identity :unique_workflow, [:workflow_name, :workflow_version]
  end

  preparations do
    prepare build(sort: [created_at: :desc])
  end

  # AshOban triggers for orchestration automation
  # TODO: Fix AshOban syntax - commenting out until properly tested
  # oban do
  #   # Monitor long-running workflows
  #   trigger :check_long_running_workflows do
  #     action :long_running
  #     cron "*/10 * * * *"  # Every 10 minutes
  #   end
  #
  #   # Auto-restart failed workflows with retry policy
  #   trigger :restart_failed_workflows do
  #     action :by_status, args: [:failed]
  #     where expr(
  #       fragment("(?->>'auto_restart')::boolean = true", metadata) and
  #       fragment("(?->>'restart_attempts')::integer < 3", metadata)
  #     )
  #     cron "*/5 * * * *"  # Every 5 minutes
  #   end
  #
  #   # Cleanup old completed workflows
  #   trigger :cleanup_old_workflows do
  #     action :destroy
  #     where expr(
  #       status in [:completed, :cancelled] and
  #       completed_at < ago(30, :day)
  #     )
  #     cron "0 3 * * *"  # Daily at 3 AM
  #   end
  #
  #   # Health check for stalled workflows
  #   trigger :health_check_stalled do
  #     action :read
  #     where expr(is_stalled == true)
  #     cron "*/15 * * * *"  # Every 15 minutes
  #   end
  # end
end
