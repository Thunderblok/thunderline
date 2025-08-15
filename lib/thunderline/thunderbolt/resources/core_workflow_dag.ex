defmodule Thunderline.Thunderbolt.Resources.CoreWorkflowDAG do
  @moduledoc """
  Directed Acyclic Graph for task orchestration
  Replaces in-memory DAG with persistent, queryable structure
  """

  use Ash.Resource,
    domain: Thunderline.Thunderbolt.Domain,
    data_layer: AshPostgres.DataLayer

  import Ash.Resource.Change.Builtins




  postgres do
    table "thundercore_workflow_dags"
    repo Thunderline.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "Workflow DAG identifier"
      allow_nil? false
    end

    attribute :description, :string do
      description "Human-readable workflow description"
    end

    attribute :status, :atom do
      description "Current DAG execution status"
      default :pending
    end

    attribute :priority, :integer do
      description "Execution priority (0-9)"
      default 5
    end

    attribute :metadata, :map do
      description "Workflow metadata and configuration"
      default %{}
    end

    attribute :started_at, :utc_datetime_usec do
      description "When workflow execution began"
    end

    attribute :completed_at, :utc_datetime_usec do
      description "When workflow execution finished"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :define do
      description "Define a new workflow DAG"
      primary? true
      accept [:name, :description, :priority, :metadata]
    end

    update :start_execution do
      description "Begin DAG execution"
      accept []
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :mark_completed do
      description "Mark DAG as completed"
      accept []
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :mark_failed do
      description "Mark DAG as failed"
      accept []
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :active_workflows do
      description "Get all running workflows"
      filter expr(status == :running)
    end

    read :pending_workflows do
      description "Get all pending workflows ordered by priority"
      filter expr(status == :pending)
    end
  end

  relationships do
    has_many :task_nodes, Thunderline.Thunderbolt.Resources.CoreTaskNode do
      destination_attribute :workflow_dag_id
    end
  end

  identities do
    identity :unique_workflow_name, [:name]
  end
end
