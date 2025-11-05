defmodule Thunderline.Thundergate.RateLimiting.RateLimiter do
  @moduledoc """
  Core rate limiting logic for Thunderline.

  Implements token bucket algorithm with distributed support via ETS.
  Uses telemetry for observability and integrates with Ash policies.

  ## Usage

      # Check if request is allowed
      case RateLimiter.check_rate_limit(user_id, :api_calls) do
        {:ok, _remaining} ->
          # Process request
        {:error, :rate_limited} ->
          # Return 429
      end

  ## Configuration

      config :thunderline, Thunderline.Thundergate.RateLimiting,
        buckets: [
          api_calls: [limit: 100, window_ms: 60_000],
          heavy_operations: [limit: 10, window_ms: 60_000]
        ]
  """

  alias Thunderline.Thundergate.RateLimiting.Bucket
  require Logger

  @type bucket_key :: atom()
  @type rate_limit_identifier :: String.t() | integer()
  @type check_result :: {:ok, remaining :: non_neg_integer()} | {:error, :rate_limited}

  @doc """
  Checks if the given identifier is within rate limits for the specified bucket.

  Returns `{:ok, remaining}` if allowed, `{:error, :rate_limited}` if limit exceeded.
  Emits telemetry events for monitoring.
  """
  @spec check_rate_limit(rate_limit_identifier(), bucket_key(), keyword()) :: check_result()
  def check_rate_limit(identifier, bucket_key, opts \\ []) do
    start_time = System.monotonic_time()

    bucket_config = get_bucket_config(bucket_key)
    result = Bucket.consume(identifier, bucket_key, bucket_config)

    duration = System.monotonic_time() - start_time

    emit_telemetry(bucket_key, result, duration, opts)

    case result do
      {:ok, remaining} ->
        {:ok, remaining}
      {:error, :rate_limited} = error ->
        Logger.warning("Rate limit exceeded",
          identifier: identifier,
          bucket: bucket_key,
          metadata: Keyword.get(opts, :metadata, %{})
        )
        error
    end
  end

  @doc """
  Gets rate limit status without consuming tokens.
  Useful for checking limits before expensive operations.
  """
  @spec get_rate_limit_status(rate_limit_identifier(), bucket_key()) ::
    {:ok, %{remaining: non_neg_integer(), limit: non_neg_integer(), reset_at: integer()}}
  def get_rate_limit_status(identifier, bucket_key) do
    bucket_config = get_bucket_config(bucket_key)
    Bucket.status(identifier, bucket_key, bucket_config)
  end

  @doc """
  Returns violations for the given identifier across all buckets.
  Used by monitoring and security systems.
  """
  @spec get_rate_limit_violations(rate_limit_identifier()) :: [%{bucket: bucket_key(), violated_at: DateTime.t()}]
  def get_rate_limit_violations(identifier) do
    # Query ETS tables for violation records
    bucket_keys = get_configured_buckets()

    Enum.flat_map(bucket_keys, fn bucket_key ->
      case Bucket.get_violations(identifier, bucket_key) do
        [] -> []
        violations -> Enum.map(violations, &Map.put(&1, :bucket, bucket_key))
      end
    end)
  end

  @doc """
  Resets rate limits for a specific identifier.
  Should be used sparingly, primarily for administrative purposes.
  """
  @spec reset_rate_limit(rate_limit_identifier(), bucket_key()) :: :ok
  def reset_rate_limit(identifier, bucket_key) do
    Bucket.reset(identifier, bucket_key)

    :telemetry.execute(
      [:thunderline, :rate_limiting, :reset],
      %{count: 1},
      %{identifier: identifier, bucket: bucket_key}
    )

    :ok
  end

  # Private functions

  defp get_bucket_config(bucket_key) do
    buckets = Application.get_env(:thunderline, Thunderline.Thundergate.RateLimiting, [])
    |> Keyword.get(:buckets, default_buckets())

    case Keyword.get(buckets, bucket_key) do
      nil ->
        Logger.warning("Unknown rate limit bucket, using defaults", bucket: bucket_key)
        default_bucket_config()
      config ->
        config
    end
  end

  defp get_configured_buckets do
    Application.get_env(:thunderline, Thunderline.Thundergate.RateLimiting, [])
    |> Keyword.get(:buckets, default_buckets())
    |> Keyword.keys()
  end

  defp default_buckets do
    [
      api_calls: [limit: 100, window_ms: 60_000],
      heavy_operations: [limit: 10, window_ms: 60_000],
      auth_attempts: [limit: 5, window_ms: 300_000]
    ]
  end

  defp default_bucket_config do
    [limit: 60, window_ms: 60_000]
  end

  defp emit_telemetry(bucket_key, result, duration, opts) do
    metadata = %{
      bucket: bucket_key,
      result: elem(result, 0),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    measurements = %{
      duration: duration,
      remaining: case result do
        {:ok, remaining} -> remaining
        {:error, _} -> 0
      end
    }

    :telemetry.execute(
      [:thunderline, :rate_limiting, :check],
      measurements,
      metadata
    )
  end
end
