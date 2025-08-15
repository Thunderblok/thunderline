defmodule Thunderline.Thunderbolt.Resources.CoreTaskNode do
  @moduledoc """
  Individual task nodes within workflow DAGs
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "thundercore_task_nodes"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :node_name, :string do
      description "Task node identifier"
      allow_nil? false
    end
    
    attribute :task_type, :string do
      description "Type of task to execute"
      allow_nil? false
    end
    
    attribute :task_config, :map do
      description "Task configuration and parameters"
      default %{}
    end
    
    attribute :status, :atom do
      description "Task execution status"
      default :pending
    end
    
    attribute :dependencies, {:array, :string} do
      description "Array of task node IDs this task depends on"
      default []
    end
    
    attribute :position_x, :integer do
      description "X coordinate for DAG visualization"
      default 0
    end
    
    attribute :position_y, :integer do
      description "Y coordinate for DAG visualization"
      default 0
    end
    
    attribute :started_at, :utc_datetime_usec do
      description "When task execution began"
    end
    
    attribute :completed_at, :utc_datetime_usec do
      description "When task execution finished"
    end
    
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]
    
    create :add_to_dag do
      description "Add task node to workflow DAG"
      primary? true
      accept [:node_name, :task_type, :task_config, :dependencies, :position_x, :position_y, :workflow_dag_id]
    end
    
    update :start_execution do
      description "Begin task execution"
      accept []
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end
    
    update :mark_completed do
      description "Mark task as completed"
      accept []
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
    
    update :mark_failed do
      description "Mark task as failed"
      accept []
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
    
    read :ready_tasks do
      description "Get tasks ready for execution (dependencies met)"
      # This would need custom logic to check dependencies
      filter expr(status == :pending)
    end
  end

  relationships do
    belongs_to :workflow_dag, Thunderline.Thunderbolt.Resources.CoreWorkflowDAG
  end
end
