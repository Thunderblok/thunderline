defmodule Thunderline.Thundercrown.Resources.PolicyDefinition do
  @moduledoc """
  PolicyDefinition - Persistent storage for governance policies.

  Stores declarative policy definitions that can be loaded into the
  PolicyEngine at runtime.

  ## Policy Structure

      %{
        "name" => "api_rate_limit",
        "description" => "Rate limiting for API endpoints",
        "strategy" => "all_of",
        "threshold" => 1.0,
        "rules" => [
          %{
            "name" => "hourly_limit",
            "constraint" => %{
              "type" => "resource_limit",
              "params" => %{"resource" => "api_calls_hour", "limit" => 1000}
            },
            "weight" => 1.0,
            "on_fail" => "deny"
          }
        ],
        "applies_to" => %{
          "domains" => ["thundergrid"],
          "resources" => ["*"],
          "actions" => ["*"]
        }
      }

  ## Versioning

  Policies are versioned. Creating a new version archives the previous one.
  Only `active` policies are evaluated; `archived` policies are kept for audit.
  """
  use Ash.Resource,
    domain: Thunderline.Thundercrown.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource]

  alias Thunderline.Thundercrown.{PolicyEngine, Constraint}

  postgres do
    table "policy_definitions"
    repo Thunderline.Repo
  end

  graphql do
    type :policy_definition
  end

  actions do
    defaults [:read, :destroy]

    read :active do
      filter expr(status == :active)
    end

    read :by_domain do
      argument :domain, :atom, allow_nil?: false

      filter expr(
               fragment(
                 "? @> ?",
                 applies_to["domains"],
                 ^arg(:domain)
               )
             )
    end

    read :applicable do
      argument :domain, :atom, allow_nil?: false
      argument :resource, :atom, allow_nil?: false
      argument :action, :atom, allow_nil?: false

      filter expr(status == :active)
    end

    create :create do
      accept [:name, :description, :policy_data, :applies_to, :priority, :metadata]

      change fn cs, _ctx ->
        cs
        |> Ash.Changeset.change_attribute(:status, :active)
        |> Ash.Changeset.change_attribute(:version, 1)
      end
    end

    update :update do
      accept [:description, :policy_data, :applies_to, :priority, :metadata]

      change fn cs, _ctx ->
        current = Ash.Changeset.get_data(cs, :version) || 0
        Ash.Changeset.change_attribute(cs, :version, current + 1)
      end
    end

    update :activate do
      accept []

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :status, :active)
      end
    end

    update :archive do
      accept []

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :status, :archived)
      end
    end

    update :disable do
      accept []

      change fn cs, _ctx ->
        Ash.Changeset.change_attribute(cs, :status, :disabled)
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

    policy action(:create) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action([:update, :activate, :archive, :disable, :destroy]) do
      authorize_if AshAuthentication.Checks.Authenticated
    end

    policy action_type(:read) do
      authorize_if AshAuthentication.Checks.Authenticated
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      description "Human-readable policy name"
    end

    attribute :description, :string do
      allow_nil? true
    end

    attribute :policy_data, :map do
      allow_nil? false
      default %{}
      description "Serialized policy definition (rules, strategy, threshold)"
    end

    attribute :applies_to, :map do
      allow_nil? false
      default %{"domains" => ["*"], "resources" => ["*"], "actions" => ["*"]}
      description "Scope specifier: which domains/resources/actions this policy applies to"
    end

    attribute :priority, :integer do
      allow_nil? false
      default 100
      description "Evaluation order (lower = evaluated first)"
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :disabled, :archived]
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name_version, [:name, :version]
  end

  @doc """
  Converts a PolicyDefinition record to a PolicyEngine policy struct.

  Note: Uses map access instead of struct pattern matching to avoid
  compile-time cyclic dependency issues with Ash resources.
  """
  @spec to_policy_engine(map()) :: PolicyEngine.policy()
  def to_policy_engine(record) when is_struct(record) do
    data = record.policy_data

    rules =
      (data["rules"] || [])
      |> Enum.map(&parse_rule/1)

    %{
      id: record.id,
      name: record.name,
      description: record.description,
      rules: rules,
      strategy: parse_strategy(data["strategy"]),
      threshold: data["threshold"] || 1.0,
      metadata: record.metadata
    }
  end

  @doc """
  Checks if a policy applies to the given action descriptor.
  """
  @spec applies?(map(), map()) :: boolean()
  def applies?(applies_to, %{domain: domain, resource: resource, action: action}) do
    domain_match?(applies_to, domain) and
      resource_match?(applies_to, resource) and
      action_match?(applies_to, action)
  end

  # Private helpers

  defp parse_rule(rule_map) do
    %{
      name: rule_map["name"],
      constraint: parse_constraint(rule_map["constraint"]),
      weight: rule_map["weight"] || 1.0,
      on_fail: parse_on_fail(rule_map["on_fail"])
    }
  end

  defp parse_constraint(%{"type" => "resource_limit", "params" => params}) do
    resource = String.to_existing_atom(params["resource"])
    Constraint.resource_limit(resource, params["limit"])
  end

  defp parse_constraint(%{"type" => "time_window", "params" => params}) do
    Constraint.time_window(params["start_hour"], params["end_hour"])
  end

  defp parse_constraint(%{"type" => "weekday_only"}) do
    Constraint.weekday_only()
  end

  defp parse_constraint(%{"type" => "has_role", "params" => params}) do
    role = String.to_existing_atom(params["role"])
    Constraint.has_role(role)
  end

  defp parse_constraint(%{"type" => "has_scope", "params" => params}) do
    Constraint.has_scope(params["pattern"])
  end

  defp parse_constraint(%{"type" => "has_key", "params" => params}) do
    key = String.to_existing_atom(params["key"])
    Constraint.has_key(key)
  end

  defp parse_constraint(%{"type" => "equals", "params" => params}) do
    key = String.to_existing_atom(params["key"])
    Constraint.equals(key, params["value"])
  end

  defp parse_constraint(%{"type" => "always"}) do
    Constraint.always()
  end

  defp parse_constraint(%{"type" => "never"}) do
    Constraint.never()
  end

  defp parse_constraint(%{"type" => "all_of", "constraints" => constraints}) do
    Constraint.all_of(Enum.map(constraints, &parse_constraint/1))
  end

  defp parse_constraint(%{"type" => "any_of", "constraints" => constraints}) do
    Constraint.any_of(Enum.map(constraints, &parse_constraint/1))
  end

  defp parse_constraint(%{"type" => "not", "constraint" => constraint}) do
    Constraint.not_c(parse_constraint(constraint))
  end

  defp parse_constraint(_), do: Constraint.always()

  defp parse_strategy("all_of"), do: :all_of
  defp parse_strategy("any_of"), do: :any_of
  defp parse_strategy("first_match"), do: :first_match
  defp parse_strategy("weighted"), do: :weighted
  defp parse_strategy(_), do: :all_of

  defp parse_on_fail("deny"), do: :deny
  defp parse_on_fail("warn"), do: :warn
  defp parse_on_fail("audit"), do: :audit
  defp parse_on_fail(_), do: :deny

  defp domain_match?(%{"domains" => domains}, domain) do
    "*" in domains or to_string(domain) in domains or domain in domains
  end

  defp domain_match?(_, _), do: true

  defp resource_match?(%{"resources" => resources}, resource) do
    "*" in resources or to_string(resource) in resources or resource in resources
  end

  defp resource_match?(_, _), do: true

  defp action_match?(%{"actions" => actions}, action) do
    "*" in actions or to_string(action) in actions or action in actions
  end

  defp action_match?(_, _), do: true
end
