defmodule Thunderline.Thundergate.RateLimiting.Policy do
  @moduledoc """
  Ash policy integration for rate limiting.

  Provides reusable policy checks that can be used in Ash resources
  to enforce rate limits declaratively.

  ## Usage in Ash Resources

      policies do
        policy action_type(:create) do
          authorize_if RateLimiting.Policy.within_rate_limit(:api_calls)
        end

        policy action(:expensive_operation) do
          authorize_if RateLimiting.Policy.within_rate_limit(:heavy_operations)
        end
      end
  """

  use Ash.Policy.SimpleCheck

  alias Thunderline.Thundergate.RateLimiting.RateLimiter

  @impl true
  def describe(opts) do
    bucket = Keyword.get(opts, :bucket, :api_calls)
    "actor must be within rate limit for #{bucket}"
  end

  @impl true
  def match?(actor, _context, opts) do
    bucket = Keyword.get(opts, :bucket, :api_calls)
    identifier = get_identifier(actor, opts)

    case RateLimiter.check_rate_limit(identifier, bucket,
           metadata: %{actor_id: get_actor_id(actor)}
         ) do
      {:ok, _remaining} -> true
      {:error, :rate_limited} -> false
    end
  end

  @doc """
  Helper to create a rate limit check for a specific bucket.

  ## Examples

      authorize_if RateLimiting.Policy.within_rate_limit(:api_calls)
      authorize_if RateLimiting.Policy.within_rate_limit(:heavy_operations)
  """
  def within_rate_limit(bucket) when is_atom(bucket) do
    {__MODULE__, bucket: bucket}
  end

  # Private functions

  defp get_identifier(actor, opts) do
    case Keyword.get(opts, :identifier_key) do
      nil ->
        # Default: use actor ID or IP
        get_actor_id(actor) || "anonymous"

      key when is_atom(key) ->
        Map.get(actor || %{}, key) || "anonymous"
    end
  end

  defp get_actor_id(nil), do: nil

  defp get_actor_id(actor) when is_map(actor) do
    Map.get(actor, :id) || Map.get(actor, "id")
  end

  defp get_actor_id(actor), do: to_string(actor)
end
