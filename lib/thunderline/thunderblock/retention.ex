defmodule Thunderline.Thunderblock.Retention do
  @moduledoc """
  Retention policy registry and helpers for ThunderBlock surfaces.

  Provides convenience accessors around the `RetentionPolicy` Ash resource,
  bootstraps sensible defaults, and exposes utilities to evaluate effective
  policies for a given resource/scope pair.
  """

  require Logger

  alias Ash
  alias Ash.Changeset
  alias Ash.Query
  alias Thunderline.Thunderblock.Domain
  alias Thunderline.Thunderblock.Resources.RetentionPolicy
  require Ash.Query
  require Ash.Expr

  @defaults [
    %{
      resource: :event_log,
      ttl: {:days, 30},
      action: :delete,
      grace: {:days, 2},
      notes: "Drop persisted events after 30 days; small grace to allow late replays"
    },
    %{
      resource: :telemetry_buffer,
      ttl: {:hours, 48},
      action: :delete,
      notes: "Compact live telemetry buffers after 48h"
    },
    %{
      resource: :job,
      ttl: {:days, 14},
      action: :delete,
      metadata: %{states: %{completed: 7, discarded: 30, cancelled: 7}},
      notes: "Prune Oban history with longer retention for discarded jobs"
    },
    %{
      resource: :artifact,
      ttl: {:days, 90},
      keep_versions: 5,
      action: :archive,
      metadata: %{storage_tier: :warm},
      notes: "Keep latest 5 artifacts hot, archive older ones after 90 days"
    },
    %{
      resource: :vector,
      ttl: {:days, 180},
      action: :compact,
      metadata: %{schedule: :weekly},
      notes: "Weekly compaction; drop orphans older than 180 days"
    },
    %{
      resource: :cache,
      ttl: {:hours, 24},
      action: :delete,
      notes: "Bridge/cache entries expire after 24 hours"
    }
  ]

  @seed_key {:thunderline, :thunderblock_retention_defaults}

  @doc """
  Return the baked-in default retention policy definitions.
  """
  @spec defaults() :: [map()]
  def defaults, do: @defaults

  @doc """
  Ensure default policies exist in the database.

  Called lazily by `get/2` but also usable during migrations or setup tasks.
  """
  @spec ensure_defaults!(keyword()) :: :ok
  def ensure_defaults!(opts \\ []) do
    if Keyword.get(opts, :skip_seed, false) do
      :ok
    else
      seed_defaults()
    end
  end

  @doc """
  Fetch the most specific policy for the given resource and optional scope.

  When a scoped policy is not found, the global default will be returned.
  Returns `{:ok, nil}` when no policy exists and no defaults are defined.
  """
  @spec get(atom(), keyword()) :: {:ok, RetentionPolicy.t() | nil} | {:error, term()}
  def get(resource, opts \\ []) when is_atom(resource) do
    scope = normalize_scope(Keyword.get(opts, :scope, :global))
    ensure_defaults!()

    with {:ok, policy} <- fetch_policy(resource, scope) do
      case policy do
        nil -> fetch_policy(resource, {:global, nil})
        _ -> {:ok, policy}
      end
    end
  end

  @doc """
  Determine the effective policy for the provided resource and scope.

  Accepts shorthand scope tuples like `{:dataset, dataset_id}` or `:global`.
  Returns a `{RetentionPolicy.t(), context}` tuple when found to help callers
  understand whether the result came from an override or the global fallback.
  """
  @spec effective(atom(), :global | tuple(), keyword()) ::
          {:ok, {RetentionPolicy.t(), :exact | :fallback}} | {:error, term()}
  def effective(resource, scope, opts \\ []) do
    scope = normalize_scope(scope)
    ensure_defaults!()

    case fetch_policy(resource, scope, opts) do
      {:ok, %RetentionPolicy{} = policy} ->
        {:ok, {policy, :exact}}

      {:ok, nil} ->
        case fetch_policy(resource, {:global, nil}, opts) do
          {:ok, %RetentionPolicy{} = global} -> {:ok, {global, :fallback}}
          other -> other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_policy(resource, scope, opts \\ [])

  defp fetch_policy(resource, {scope_type, scope_id}, opts) do
    query =
      if is_nil(scope_id) do
        RetentionPolicy
        |> Query.filter(
          Ash.Expr.expr(resource == ^resource and scope_type == ^scope_type and is_nil(scope_id))
        )
      else
        RetentionPolicy
        |> Query.filter(
          Ash.Expr.expr(
            resource == ^resource and scope_type == ^scope_type and scope_id == ^scope_id
          )
        )
      end

    query
    |> Ash.read_one(domain: Keyword.get(opts, :domain, Domain))
  end

  defp fetch_policy(resource, :global, opts), do: fetch_policy(resource, {:global, nil}, opts)

  defp seed_defaults do
    maybe_seed? =
      case :persistent_term.get(@seed_key, :not_seeded) do
        :seeded -> false
        :seeding -> false
        _ -> true
      end

    if maybe_seed? do
      :persistent_term.put(@seed_key, :seeding)

      Enum.each(@defaults, fn attrs ->
        try do
          case upsert_policy(attrs) do
            {:ok, _policy} ->
              :ok

            {:error, reason} ->
              Logger.warning("[Retention] default upsert failed: #{inspect(reason)}")
          end
        rescue
          exception ->
            Logger.warning(
              "[Retention] default upsert crashed for #{inspect(attrs)}: #{Exception.format(:error, exception, __STACKTRACE__)}"
            )
        end
      end)

      :persistent_term.put(@seed_key, :seeded)
    end

    :ok
  rescue
    exception ->
      Logger.warning("[Retention] ensure defaults crashed: #{Exception.message(exception)}")
      :persistent_term.put(@seed_key, :not_seeded)
      :ok
  end

  defp upsert_policy(attrs) do
    {scope_type, scope_id} = normalize_scope(Map.get(attrs, :scope, :global))

    with {:ok, ttl_seconds} <- resolve_interval(attrs, :ttl, required: true),
         {:ok, grace_seconds} <- resolve_interval(attrs, :grace, default: 0) do
      input = %{
        resource: Map.fetch!(attrs, :resource),
        scope_type: scope_type,
        scope_id: scope_id,
        ttl_seconds: ttl_seconds,
        keep_versions: Map.get(attrs, :keep_versions),
        action: Map.get(attrs, :action, :delete),
        grace_seconds: grace_seconds,
        metadata: normalize_metadata(Map.get(attrs, :metadata, %{})),
        notes: Map.get(attrs, :notes),
        is_active: Map.get(attrs, :is_active, true)
      }

      case fetch_policy(input.resource, {scope_type, scope_id}) do
        {:ok, %RetentionPolicy{} = policy} ->
          maybe_update(policy, input)

        {:ok, nil} ->
          RetentionPolicy
          |> Changeset.for_create(:define, input)
          |> Ash.create()

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_update(policy, attrs) do
    updates =
      attrs
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        current = Map.get(policy, key)

        cond do
          is_nil(value) and is_nil(current) -> acc
          value == current -> acc
          true -> Map.put(acc, key, value)
        end
      end)

    if updates == %{} do
      {:ok, policy}
    else
      policy
      |> Changeset.for_update(:configure, updates)
      |> Ash.update()
    end
  end

  defp normalize_scope(:global), do: {:global, nil}
  defp normalize_scope({type, id}), do: build_scope(type, id)
  defp normalize_scope(%{type: type, id: id}), do: build_scope(type, id)
  defp normalize_scope(_), do: {:global, nil}

  defp build_scope(type, id) do
    case normalize_scope_type(type) do
      nil -> {:global, nil}
      normalized -> {normalized, id}
    end
  end

  defp normalize_scope_type(type) when is_atom(type), do: type

  defp normalize_scope_type(type) when is_binary(type) do
    case String.trim(type) |> String.downcase() do
      "global" -> :global
      "tenant" -> :tenant
      "project" -> :project
      "dataset" -> :dataset
      _ -> nil
    end
  end

  defp normalize_scope_type(_), do: nil

  defp resolve_interval(attrs, key, opts \\ []) do
    required? = Keyword.get(opts, :required, false)
    default = Keyword.get(opts, :default)
    raw_value = Map.get(attrs, key, default)

    case interval_to_seconds(raw_value) do
      {:ok, nil} when required? -> {:error, {:missing_interval, key}}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {key, reason}}
    end
  end

  @doc """
  Normalize a retention time unit into its second multiplier.

  Accepts atoms or strings with arbitrary casing/whitespace. Returns
  `{:ok, seconds}` for known units or `{:error, :unknown_unit}` otherwise.

  ## Examples

      iex> #{__MODULE__}.normalize_unit(" HoUrS ")
      {:ok, 3_600}

      iex> #{__MODULE__}.normalize_unit(:days)
      {:ok, 86_400}

      iex> #{__MODULE__}.normalize_unit("parsecs")
      {:error, :unknown_unit}

  """
  @spec normalize_unit(term()) :: {:ok, pos_integer()} | {:error, :unknown_unit}
  def normalize_unit(unit)

  @unit_seconds %{
    "s" => 1,
    "sec" => 1,
    "secs" => 1,
    "second" => 1,
    "seconds" => 1,
    "m" => 60,
    "min" => 60,
    "mins" => 60,
    "minute" => 60,
    "minutes" => 60,
    "h" => 3_600,
    "hr" => 3_600,
    "hrs" => 3_600,
    "hour" => 3_600,
    "hours" => 3_600,
    "d" => 86_400,
    "day" => 86_400,
    "days" => 86_400,
    "w" => 604_800,
    "week" => 604_800,
    "weeks" => 604_800
  }

  def normalize_unit(unit) when is_atom(unit) do
    unit
    |> Atom.to_string()
    |> normalize_unit()
  end

  def normalize_unit(unit) when is_binary(unit) do
    sanitized =
      unit
      |> String.trim()
      |> String.downcase()

    case Map.fetch(@unit_seconds, sanitized) do
      {:ok, seconds} -> {:ok, seconds}
      :error -> {:error, :unknown_unit}
    end
  end

  def normalize_unit(_), do: {:error, :unknown_unit}

  @spec interval_to_seconds(nil | integer() | {term(), term()}) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  defp interval_to_seconds(nil), do: {:ok, nil}

  defp interval_to_seconds(value) when is_integer(value) do
    if value >= 0 do
      {:ok, value}
    else
      {:error, :negative_interval}
    end
  end

  defp interval_to_seconds({unit, value}) when is_integer(value) do
    if value < 0 do
      {:error, :negative_interval}
    else
      with {:ok, seconds_per_unit} <- normalize_unit(unit) do
        {:ok, value * seconds_per_unit}
      end
    end
  end

  defp interval_to_seconds({unit, value}) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> interval_to_seconds({unit, int})
      _ -> {:error, :invalid_interval}
    end
  end

  defp interval_to_seconds(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> interval_to_seconds(int)
      _ -> {:error, :invalid_interval}
    end
  end

  defp interval_to_seconds(_), do: {:error, :invalid_interval}

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(%{} = map), do: map
  defp normalize_metadata(list) when is_list(list), do: Map.new(list)
  defp normalize_metadata(_other), do: %{}
end
