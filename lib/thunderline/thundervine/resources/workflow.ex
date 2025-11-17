defmodule Thunderline.Thundervine.Resources.Workflow do
  @moduledoc """
  Workflow - Root workflow instance anchored on correlation_id.

  Represents an event-driven execution graph that tracks:
  - Originating domain and root event
  - Correlation ID for distributed tracing
  - Workflow status (building vs sealed)
  - Associated nodes, edges, and snapshots

  Each workflow tracks a complete execution lineage, enabling replay,
  analysis, and distributed system observability.
  """
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "dag_workflows"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read]

    create :start do
      accept [:source_domain, :root_event_name, :correlation_id, :causation_id, :metadata]
    end

    update :seal do
      accept []

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :status, :sealed)
      end
    end

    update :update_metadata do
      accept [:metadata]
    end
  end

  policies do
    policy action([:start, :seal]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action_type(:read) do
      authorize_if expr(true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source_domain, :atom do
      allow_nil? false
      description "Originating domain of root action"
    end

    attribute :root_event_name, :string, allow_nil?: false
    attribute :correlation_id, :string, allow_nil?: false
    attribute :causation_id, :string, allow_nil?: true

    attribute :status, :atom do
      allow_nil? false
      default :building
      constraints [one_of: [:building, :sealed]]
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :nodes, Thunderline.Thundervine.Resources.WorkflowNode do
      destination_attribute :workflow_id
    end

    has_many :edges, Thunderline.Thundervine.Resources.WorkflowEdge do
      destination_attribute :workflow_id
    end

    has_many :snapshots, Thunderline.Thundervine.Resources.WorkflowSnapshot do
      destination_attribute :workflow_id
    end
  end

  identities do
    identity :unique_correlation, [:correlation_id]
  end
end
