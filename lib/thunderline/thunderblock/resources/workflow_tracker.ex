defmodule Thunderline.Thunderblock.Resources.WorkflowTracker do
  @moduledoc """
  Workflow Completion Tracking Resource - ThunderChief Integration

  Tracks workflow completion targets and current counts for orchestration.
  Implements the pattern from "Orchestrating Background Jobs in Elixir with Oban and Broadway"
  integrated into ThunderBlock domain architecture.
  """

  use Ash.Resource,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshOban]

  postgres do
    table "workflow_trackers"
    repo Thunderline.Repo
  end

  code_interface do
    domain Thunderline.Thunderblock.Domain

    define :create
    define :increment_count
    define :for_workflow, args: [:workflow_id, :step_name]
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    update :increment_count do
      argument :job_completion_event, :map, allow_nil?: false

      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :current_count) || 0
        target = Ash.Changeset.get_attribute(changeset, :target_count)

        new_count = current + 1

        changeset
        |> Ash.Changeset.change_attribute(:current_count, new_count)
        |> Ash.Changeset.change_attribute(
          :status,
          if(new_count >= target, do: :completed, else: :in_progress)
        )
      end
    end

    read :for_workflow do
      argument :workflow_id, :string, allow_nil?: false
      argument :step_name, :atom

      filter expr(
               workflow_id == ^arg(:workflow_id) and
                 (is_nil(^arg(:step_name)) or step_name == ^arg(:step_name))
             )
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workflow_id, :string, allow_nil?: false
    attribute :step_name, :atom, allow_nil?: false
    attribute :target_count, :integer, allow_nil?: false
    attribute :current_count, :integer, default: 0

    attribute :status, :atom,
      default: :pending,
      constraints: [one_of: [:pending, :in_progress, :completed, :failed]]

    attribute :domain_context, :atom, allow_nil?: false
    attribute :next_step_config, :map, default: %{}

    timestamps()
  end

  # AshOban configuration for orchestration automation
  oban do
    triggers do
      # Auto-cleanup completed workflow trackers
      trigger :cleanup_completed_trackers do
        action :destroy
        scheduler_cron "0 2 * * *"
        where expr(status == :completed and updated_at < ago(7, :day))
      end
    end
  end
end
