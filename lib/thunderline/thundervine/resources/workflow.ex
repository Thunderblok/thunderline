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
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "dag_workflows"
    repo Thunderline.Repo
  end

  graphql do
    type :workflow
  end

  actions do
    defaults [:read]

    read :by_correlation_id do
      argument :correlation_id, :string, allow_nil?: false
      filter expr(correlation_id == ^arg(:correlation_id))
    end

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
    # Admin bypass - full access to all operations
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # System actors can perform all operations
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    # Authenticated users can start workflows
    policy action(:start) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Only workflow owners or admins can seal/update workflows
    policy action([:seal, :update_metadata]) do
      authorize_if AshAuthentication.Checks.Authenticated
      # In production, add ownership check:
      # authorize_if expr(created_by_id == ^actor(:id))
    end

    # Read access - authenticated users can read workflows
    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Public read access for sealed workflows (optional)
    policy action_type(:read) do
      authorize_if expr(status == :sealed)
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
