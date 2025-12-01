defmodule Thunderline.Thundercrown.Constraint do
  @moduledoc """
  Composable constraint primitives for the PolicyEngine.

  Constraints are atomic boolean predicates that evaluate against a context.
  They can be composed using logical operators to build complex rules.

  ## Built-in Constraints

  ### Resource Limits
      Constraint.resource_limit(:api_calls, 1000)
      Constraint.resource_limit(:memory_mb, 512)

  ### Time Windows
      Constraint.time_window(9, 17)  # 9 AM to 5 PM
      Constraint.weekday_only()

  ### Actor Checks
      Constraint.has_role(:admin)
      Constraint.has_scope("thunderpac:read:*")

  ### Context Checks
      Constraint.has_key(:tenant_id)
      Constraint.matches(:env, ~r/prod|staging/)

  ## Composition

      # AND composition
      c = Constraint.all_of([
        Constraint.has_role(:admin),
        Constraint.time_window(9, 17)
      ])

      # OR composition
      c = Constraint.any_of([
        Constraint.has_role(:admin),
        Constraint.has_scope("override:*")
      ])

      # NOT
      c = Constraint.not_c(Constraint.weekday_only())

  ## Custom Constraints

      Constraint.custom(fn ctx ->
        Map.get(ctx, :request_count, 0) < 100
      end)
  """

  @type t :: %__MODULE__{
          type: atom(),
          params: map(),
          combinator: nil | {:all_of | :any_of | :not_c, [t()]}
        }

  defstruct [:type, :params, :combinator]

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Creates a resource limit constraint.

  Checks if `context[resource]` is under the specified limit.
  """
  @spec resource_limit(atom(), number()) :: t()
  def resource_limit(resource, limit) when is_atom(resource) and is_number(limit) do
    %__MODULE__{
      type: :resource_limit,
      params: %{resource: resource, limit: limit}
    }
  end

  @doc """
  Creates a time window constraint.

  Checks if current hour is between start_hour and end_hour (inclusive).
  Uses UTC time.
  """
  @spec time_window(non_neg_integer(), non_neg_integer()) :: t()
  def time_window(start_hour, end_hour)
      when is_integer(start_hour) and is_integer(end_hour) and
             start_hour >= 0 and start_hour <= 23 and
             end_hour >= 0 and end_hour <= 23 do
    %__MODULE__{
      type: :time_window,
      params: %{start_hour: start_hour, end_hour: end_hour}
    }
  end

  @doc """
  Creates a weekday-only constraint.

  Returns true if current day is Monday-Friday (UTC).
  """
  @spec weekday_only() :: t()
  def weekday_only do
    %__MODULE__{
      type: :weekday_only,
      params: %{}
    }
  end

  @doc """
  Creates a role check constraint.

  Checks if context has an actor with the specified role.
  """
  @spec has_role(atom()) :: t()
  def has_role(role) when is_atom(role) do
    %__MODULE__{
      type: :has_role,
      params: %{role: role}
    }
  end

  @doc """
  Creates a scope check constraint.

  Checks if context actor has a scope matching the pattern.
  Supports wildcard matching: "domain:resource:*"
  """
  @spec has_scope(String.t()) :: t()
  def has_scope(scope_pattern) when is_binary(scope_pattern) do
    %__MODULE__{
      type: :has_scope,
      params: %{pattern: scope_pattern}
    }
  end

  @doc """
  Creates a context key existence check.
  """
  @spec has_key(atom()) :: t()
  def has_key(key) when is_atom(key) do
    %__MODULE__{
      type: :has_key,
      params: %{key: key}
    }
  end

  @doc """
  Creates a regex match constraint against a context field.
  """
  @spec matches(atom(), Regex.t()) :: t()
  def matches(key, %Regex{} = pattern) when is_atom(key) do
    %__MODULE__{
      type: :matches,
      params: %{key: key, pattern: pattern}
    }
  end

  @doc """
  Creates an equality check constraint.
  """
  @spec equals(atom(), term()) :: t()
  def equals(key, value) when is_atom(key) do
    %__MODULE__{
      type: :equals,
      params: %{key: key, value: value}
    }
  end

  @doc """
  Creates a custom constraint with a function.

  The function receives the context and should return a boolean.
  """
  @spec custom((map() -> boolean())) :: t()
  def custom(fun) when is_function(fun, 1) do
    %__MODULE__{
      type: :custom,
      params: %{fun: fun}
    }
  end

  @doc """
  Always passes.
  """
  @spec always() :: t()
  def always do
    %__MODULE__{
      type: :always,
      params: %{}
    }
  end

  @doc """
  Always fails.
  """
  @spec never() :: t()
  def never do
    %__MODULE__{
      type: :never,
      params: %{}
    }
  end

  # ============================================================================
  # Combinators
  # ============================================================================

  @doc """
  Combines constraints with AND logic (all must pass).
  """
  @spec all_of([t()]) :: t()
  def all_of(constraints) when is_list(constraints) do
    %__MODULE__{
      type: :combinator,
      params: %{},
      combinator: {:all_of, constraints}
    }
  end

  @doc """
  Combines constraints with OR logic (any must pass).
  """
  @spec any_of([t()]) :: t()
  def any_of(constraints) when is_list(constraints) do
    %__MODULE__{
      type: :combinator,
      params: %{},
      combinator: {:any_of, constraints}
    }
  end

  @doc """
  Negates a constraint.
  """
  @spec not_c(t()) :: t()
  def not_c(%__MODULE__{} = constraint) do
    %__MODULE__{
      type: :combinator,
      params: %{},
      combinator: {:not_c, [constraint]}
    }
  end

  # ============================================================================
  # Evaluation
  # ============================================================================

  @doc """
  Evaluates a constraint against the given context.

  Returns `true` if the constraint passes, `false` otherwise.
  """
  @spec evaluate(t(), map()) :: boolean()
  def evaluate(%__MODULE__{type: :combinator, combinator: {:all_of, constraints}}, ctx) do
    Enum.all?(constraints, &evaluate(&1, ctx))
  end

  def evaluate(%__MODULE__{type: :combinator, combinator: {:any_of, constraints}}, ctx) do
    Enum.any?(constraints, &evaluate(&1, ctx))
  end

  def evaluate(%__MODULE__{type: :combinator, combinator: {:not_c, [constraint]}}, ctx) do
    not evaluate(constraint, ctx)
  end

  def evaluate(%__MODULE__{type: :always}, _ctx), do: true
  def evaluate(%__MODULE__{type: :never}, _ctx), do: false

  def evaluate(%__MODULE__{type: :resource_limit, params: %{resource: res, limit: limit}}, ctx) do
    current = Map.get(ctx, res, 0)
    current < limit
  end

  def evaluate(%__MODULE__{type: :time_window, params: %{start_hour: sh, end_hour: eh}}, _ctx) do
    hour = DateTime.utc_now().hour

    if sh <= eh do
      hour >= sh and hour <= eh
    else
      # Wraps around midnight
      hour >= sh or hour <= eh
    end
  end

  def evaluate(%__MODULE__{type: :weekday_only}, _ctx) do
    day = Date.utc_today() |> Date.day_of_week()
    # 1 = Monday, 5 = Friday
    day >= 1 and day <= 5
  end

  def evaluate(%__MODULE__{type: :has_role, params: %{role: expected}}, ctx) do
    actor_role = get_in(ctx, [:actor, :role]) || ctx[:role]
    actor_role == expected
  end

  def evaluate(%__MODULE__{type: :has_scope, params: %{pattern: pattern}}, ctx) do
    scopes = get_in(ctx, [:actor, :scopes]) || ctx[:scopes] || []
    Enum.any?(scopes, &scope_matches?(&1, pattern))
  end

  def evaluate(%__MODULE__{type: :has_key, params: %{key: key}}, ctx) do
    Map.has_key?(ctx, key)
  end

  def evaluate(%__MODULE__{type: :matches, params: %{key: key, pattern: pattern}}, ctx) do
    value = Map.get(ctx, key)
    is_binary(value) and Regex.match?(pattern, value)
  end

  def evaluate(%__MODULE__{type: :equals, params: %{key: key, value: expected}}, ctx) do
    Map.get(ctx, key) == expected
  end

  def evaluate(%__MODULE__{type: :custom, params: %{fun: fun}}, ctx) do
    fun.(ctx)
  end

  # Scope matching with wildcards
  defp scope_matches?(have, required) do
    have_parts = String.split(have, ":")
    required_parts = String.split(required, ":")

    match_parts(have_parts, required_parts)
  end

  defp match_parts([], []), do: true
  defp match_parts(["*" | _], _), do: true
  defp match_parts(_, ["*" | _]), do: true
  defp match_parts([h | ht], [r | rt]) when h == r, do: match_parts(ht, rt)
  defp match_parts(_, _), do: false
end
