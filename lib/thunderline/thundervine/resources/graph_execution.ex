defmodule Thunderline.Thundervine.Resources.GraphExecution do
  @moduledoc """
  GraphExecution - Tracks a single execution instance of a BehaviorGraph.

  Each execution records:
  - The behavior graph being executed
  - Initial and final context
  - Node-by-node execution results
  - Timing and status information

  This enables:
  - Execution replay and debugging
  - Performance analysis
  - Audit trails
  - Error diagnosis
  """
  use Ash.Resource,
    domain: Thunderline.Thundervine.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "graph_executions"
    repo Thunderline.Repo
  end

  graphql do
    type :graph_execution
  end

  actions do
    defaults [:read]

    read :by_graph do
      argument :behavior_graph_id, :uuid, allow_nil?: false
      filter expr(behavior_graph_id == ^arg(:behavior_graph_id))
    end

    read :by_status do
      argument :status, :atom, allow_nil?: false
      filter expr(status == ^arg(:status))
    end

    read :recent do
      prepare fn query, _ctx ->
        query
        |> Ash.Query.sort(started_at: :desc)
        |> Ash.Query.limit(100)
      end
    end

    create :start do
      accept [:behavior_graph_id, :initial_context, :metadata, :triggered_by]

      change fn cs, _ctx ->
        cs
        |> Ash.Changeset.change_attribute(:status, :running)
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:node_results, %{})
      end
    end

    update :record_node_result do
      argument :node_id, :string, allow_nil?: false
      argument :result, :map, allow_nil?: false

      change fn cs, _ctx ->
        node_id = Ash.Changeset.get_argument(cs, :node_id)
        result = Ash.Changeset.get_argument(cs, :result)

        current_results = Ash.Changeset.get_data(cs, :node_results) || %{}
        updated = Map.put(current_results, node_id, result)

        Ash.Changeset.change_attribute(cs, :node_results, updated)
      end
    end

    update :complete do
      argument :final_context, :map, allow_nil?: true

      change fn cs, _ctx ->
        final_ctx = Ash.Changeset.get_argument(cs, :final_context)

        cs
        |> Ash.Changeset.change_attribute(:status, :completed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> maybe_set_final_context(final_ctx)
      end
    end

    update :fail do
      argument :error, :map, allow_nil?: false

      change fn cs, _ctx ->
        error = Ash.Changeset.get_argument(cs, :error)

        cs
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_details, error)
      end
    end

    update :cancel do
      accept []

      change fn cs, _ctx ->
        cs
        |> Ash.Changeset.change_attribute(:status, :cancelled)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action(:start) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action([:record_node_result, :complete, :fail, :cancel]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :running, :completed, :failed, :cancelled]
    end

    attribute :initial_context, :map do
      allow_nil? false
      default %{}
      description "Context passed to the graph at execution start"
    end

    attribute :final_context, :map do
      allow_nil? true
      description "Context after successful execution"
    end

    attribute :node_results, :map do
      allow_nil? false
      default %{}
      description "Map of node_id -> execution result"
    end

    attribute :error_details, :map do
      allow_nil? true
      description "Error information if execution failed"
    end

    attribute :triggered_by, :string do
      allow_nil? true
      description "What initiated this execution (event, user, schedule, etc)"
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :behavior_graph, Thunderline.Thundervine.Resources.BehaviorGraph do
      attribute_writable? true
      allow_nil? false
    end
  end

  calculations do
    calculate :duration_ms, :integer do
      calculation fn records, _ctx ->
        Enum.map(records, fn record ->
          case {record.started_at, record.completed_at} do
            {start, stop} when not is_nil(start) and not is_nil(stop) ->
              DateTime.diff(stop, start, :millisecond)

            _ ->
              nil
          end
        end)
      end
    end

    calculate :executed_node_count, :integer do
      calculation fn records, _ctx ->
        Enum.map(records, fn record ->
          map_size(record.node_results || %{})
        end)
      end
    end
  end

  defp maybe_set_final_context(cs, nil), do: cs

  defp maybe_set_final_context(cs, ctx) do
    Ash.Changeset.change_attribute(cs, :final_context, ctx)
  end
end
