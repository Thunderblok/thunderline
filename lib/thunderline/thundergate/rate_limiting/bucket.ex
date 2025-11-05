defmodule Thunderline.Thundergate.RateLimiting.Bucket do
  @moduledoc """
  Token bucket implementation for rate limiting.

  Uses ETS for fast, distributed token bucket tracking with automatic cleanup.
  Implements sliding window algorithm for more accurate rate limiting.
  """

  use GenServer
  require Logger

  @table_name :rate_limit_buckets
  @violations_table :rate_limit_violations
  @cleanup_interval_ms 60_000  # Clean up expired buckets every minute

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to consume a token from the bucket.
  Returns {:ok, remaining} if successful, {:error, :rate_limited} if exceeded.
  """
  def consume(identifier, bucket_key, config) do
    limit = Keyword.fetch!(config, :limit)
    window_ms = Keyword.fetch!(config, :window_ms)

    key = bucket_key(identifier, bucket_key)
    now = System.system_time(:millisecond)
    window_start = now - window_ms

    # Get or initialize bucket
    case :ets.lookup(@table_name, key) do
      [] ->
        # First request - create bucket
        tokens = [{now, 1}]
        :ets.insert(@table_name, {key, tokens, now + window_ms})
        {:ok, limit - 1}

      [{^key, tokens, _expires_at}] ->
        # Filter out expired tokens
        valid_tokens = Enum.filter(tokens, fn {timestamp, _} ->
          timestamp > window_start
        end)

        current_count = Enum.sum(Enum.map(valid_tokens, fn {_, count} -> count end))

        if current_count < limit do
          # Allow request
          new_tokens = [{now, 1} | valid_tokens]
          :ets.insert(@table_name, {key, new_tokens, now + window_ms})
          {:ok, limit - current_count - 1}
        else
          # Rate limited
          record_violation(identifier, bucket_key, now)
          {:error, :rate_limited}
        end
    end
  end

  @doc """
  Gets the current status of a bucket without consuming tokens.
  """
  def status(identifier, bucket_key, config) do
    limit = Keyword.fetch!(config, :limit)
    window_ms = Keyword.fetch!(config, :window_ms)

    key = bucket_key(identifier, bucket_key)
    now = System.system_time(:millisecond)
    window_start = now - window_ms

    case :ets.lookup(@table_name, key) do
      [] ->
        {:ok, %{remaining: limit, limit: limit, reset_at: now + window_ms}}

      [{^key, tokens, expires_at}] ->
        valid_tokens = Enum.filter(tokens, fn {timestamp, _} ->
          timestamp > window_start
        end)

        current_count = Enum.sum(Enum.map(valid_tokens, fn {_, count} -> count end))
        remaining = max(0, limit - current_count)

        {:ok, %{remaining: remaining, limit: limit, reset_at: expires_at}}
    end
  end

  @doc """
  Gets recent violations for an identifier.
  """
  def get_violations(identifier, bucket_key) do
    violation_key = bucket_key(identifier, bucket_key)

    case :ets.lookup(@violations_table, violation_key) do
      [] -> []
      [{^violation_key, violations}] ->
        # Return violations from last 5 minutes
        now = System.system_time(:millisecond)
        five_minutes_ago = now - 300_000

        violations
        |> Enum.filter(fn timestamp -> timestamp > five_minutes_ago end)
        |> Enum.map(fn timestamp ->
          %{violated_at: DateTime.from_unix!(timestamp, :millisecond)}
        end)
    end
  end

  @doc """
  Resets a specific bucket.
  """
  def reset(identifier, bucket_key) do
    key = bucket_key(identifier, bucket_key)
    :ets.delete(@table_name, key)
    :ok
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@violations_table, [:named_table, :public, :set, read_concurrency: true])

    # Schedule cleanup
    schedule_cleanup()

    Logger.info("Rate limiting bucket manager started")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_buckets()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private functions

  defp bucket_key(identifier, bucket_key) do
    "#{bucket_key}:#{identifier}"
  end

  defp record_violation(identifier, bucket_key, timestamp) do
    key = bucket_key(identifier, bucket_key)

    violations = case :ets.lookup(@violations_table, key) do
      [] -> [timestamp]
      [{^key, existing}] -> [timestamp | existing]
    end

    # Keep only last 100 violations
    trimmed_violations = Enum.take(violations, 100)
    :ets.insert(@violations_table, {key, trimmed_violations})
  end

  defp cleanup_expired_buckets do
    now = System.system_time(:millisecond)

    # Delete expired buckets
    deleted = :ets.select_delete(@table_name, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}
    ])

    if deleted > 0 do
      Logger.debug("Cleaned up #{deleted} expired rate limit buckets")
    end

    # Clean old violations (older than 5 minutes)
    five_minutes_ago = now - 300_000

    # Update violations table
    :ets.foldl(fn {key, violations}, acc ->
      recent_violations = Enum.filter(violations, fn ts -> ts > five_minutes_ago end)

      if recent_violations == [] do
        :ets.delete(@violations_table, key)
      else
        :ets.insert(@violations_table, {key, recent_violations})
      end

      acc
    end, nil, @violations_table)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
