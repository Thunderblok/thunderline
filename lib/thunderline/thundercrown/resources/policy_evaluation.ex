defmodule Thunderline.Thundercrown.Resources.PolicyEvaluation do
  @moduledoc """
  PolicyEvaluation - Audit trail for policy decisions.

  Records every policy evaluation for compliance, debugging, and analytics.

  ## Recorded Information

  - Which policies were evaluated
  - The context at evaluation time
  - Individual rule outcomes
  - Final verdict
  - Timing information
  """
  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  postgres do
    table "policy_evaluations"
    repo Thunderline.Repo
  end

  graphql do
    type :policy_evaluation
  end

  actions do
    defaults [:read]

    read :recent do
      prepare fn query, _ctx ->
        query
        |> Ash.Query.sort(evaluated_at: :desc)
        |> Ash.Query.limit(100)
      end
    end

    read :by_actor do
      argument :actor_id, :string, allow_nil?: false
      filter expr(actor_id == ^arg(:actor_id))
    end

    read :by_policy do
      argument :policy_id, :uuid, allow_nil?: false
      filter expr(policy_id == ^arg(:policy_id))
    end

    read :denied do
      filter expr(verdict == :deny)
    end

    create :record do
      accept [
        :policy_id,
        :policy_name,
        :actor_id,
        :tenant_id,
        :action_descriptor,
        :context_snapshot,
        :rule_results,
        :verdict,
        :verdict_reason,
        :duration_us,
        :metadata
      ]

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :evaluated_at, DateTime.utc_now())
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

    # Only admins and system can create evaluations
    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :system)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # Read access for authenticated users (their own evaluations)
    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :policy_id, :uuid do
      allow_nil? true
      description "Reference to PolicyDefinition (may be nil for inline policies)"
    end

    attribute :policy_name, :string do
      allow_nil? false
      description "Policy name at evaluation time"
    end

    attribute :actor_id, :string do
      allow_nil? true
      description "Actor who triggered the evaluation"
    end

    attribute :tenant_id, :string do
      allow_nil? true
      description "Tenant context"
    end

    attribute :action_descriptor, :map do
      allow_nil? false
      default %{}
      description "The action being authorized (domain, resource, action)"
    end

    attribute :context_snapshot, :map do
      allow_nil? false
      default %{}
      description "Sanitized snapshot of evaluation context"
    end

    attribute :rule_results, :map do
      allow_nil? false
      default %{}
      description "Map of rule_name -> pass/fail"
    end

    attribute :verdict, :atom do
      allow_nil? false
      constraints one_of: [:allow, :deny, :allow_with]
    end

    attribute :verdict_reason, :string do
      allow_nil? true
      description "Human-readable reason for verdict"
    end

    attribute :duration_us, :integer do
      allow_nil? true
      description "Evaluation duration in microseconds"
    end

    attribute :evaluated_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
  end

  calculations do
    calculate :rule_pass_rate, :float do
      calculation fn records, _ctx ->
        Enum.map(records, fn record ->
          results = record.rule_results || %{}
          total = map_size(results)

          if total > 0 do
            passed = Enum.count(results, fn {_k, v} -> v == true end)
            passed / total
          else
            nil
          end
        end)
      end
    end
  end
end
