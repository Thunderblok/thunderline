defmodule Thunderline.Thundervine.Resources.WorkflowNode do
  @moduledoc """
  WorkflowNode - Atomic step inside a workflow.

  Links to events and optional actions, tracking:
  - Event name and resource reference
  - Execution status (pending → success/error)
  - Correlation/causation IDs for tracing
  - Timing metrics (started_at, completed_at, duration_ms)
  - Arbitrary payload data

  Nodes represent individual execution steps in the workflow DAG,
  with edges defining dependencies between them.
  """
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "dag_nodes"
    repo Thunderline.Repo
  end

  graphql do
    type :workflow_node
  end

  policies do
    # Admin and system bypass
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    # Authenticated users can create and update workflow nodes
    policy action_type([:create, :update]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    # Read access for authenticated users
    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  actions do
    defaults [:read]

    create :record_start do
      accept [
        :workflow_id,
        :event_name,
        :resource_ref,
        :action_name,
        :correlation_id,
        :causation_id,
        :payload
      ]

      change fn cs, _ -> Ash.Changeset.change_attribute(cs, :started_at, DateTime.utc_now()) end
    end

    update :mark_success do
      accept [:payload]
      change fn cs, ctx -> mark_done(:success).(cs, ctx) end
    end

    update :mark_error do
      accept [:payload]
      change fn cs, ctx -> mark_done(:error).(cs, ctx) end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :workflow_id, :uuid, allow_nil?: false
    attribute :event_name, :string, allow_nil?: false

    attribute :resource_ref, :string,
      allow_nil?: true,
      description: "Serialized reference (domain:resource:id)"

    attribute :action_name, :string, allow_nil?: true

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      constraints: [one_of: [:pending, :success, :error]]

    attribute :correlation_id, :string, allow_nil?: false
    attribute :causation_id, :string, allow_nil?: true
    attribute :payload, :map, allow_nil?: false, default: %{}
    attribute :started_at, :utc_datetime_usec, allow_nil?: true
    attribute :completed_at, :utc_datetime_usec, allow_nil?: true
    attribute :duration_ms, :integer, allow_nil?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :workflow, Thunderline.Thundervine.Resources.Workflow do
      source_attribute :workflow_id
      destination_attribute :id
    end
  end

  defp mark_done(status) do
    fn cs, _ ->
      started = Ash.Changeset.get_attribute(cs, :started_at)
      now = DateTime.utc_now()

      cs
      |> Ash.Changeset.change_attribute(:status, status)
      |> Ash.Changeset.change_attribute(:completed_at, now)
      |> case do
        c when started ->
          Ash.Changeset.change_attribute(
            c,
            :duration_ms,
            DateTime.diff(now, started, :millisecond)
          )

        c ->
          c
      end
    end
  end
end
