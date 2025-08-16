defmodule Thunderline.Support.Backoff do
  @moduledoc """
  Exponential backoff with jitter for Oban job retries.
  
  Provides bounded exponential backoff to prevent thundering herd effects
  and reduce load on failed services during recovery.
  
  ## Usage
  
      defmodule MyWorker do
        use Oban.Worker, max_attempts: 5
        
        @impl Oban.Worker
        def backoff(%Oban.Job{attempt: n}), do: Thunderline.Support.Backoff.exp(n)
      end
  """
  
  @min_ms 1_000      # 1 second minimum
  @max_ms 300_000    # 5 minutes maximum  
  @jitter_pct 0.20   # ±20% jitter to prevent thundering herd
  
  @doc """
  Calculate exponential backoff delay with jitter.
  
  Starts at 1 second, doubles each attempt, capped at 5 minutes.
  Adds ±20% jitter to prevent synchronized retries.
  
  ## Examples
  
      iex> Thunderline.Support.Backoff.exp(1)
      # Returns ~1000ms ±200ms
      
      iex> Thunderline.Support.Backoff.exp(5)  
      # Returns ~16000ms ±3200ms
      
      iex> Thunderline.Support.Backoff.exp(10)
      # Returns 300000ms ±60000ms (capped)
  """
  @spec exp(pos_integer()) :: non_neg_integer()
  def exp(attempt) when attempt <= 1, do: jitter(@min_ms)
  
  def exp(attempt) when is_integer(attempt) and attempt > 1 do
    # 1s * 2^(attempt-1), clamped to max, with jitter
    base_delay = trunc(@min_ms * :math.pow(2, attempt - 1))
    clamped_delay = min(base_delay, @max_ms)
    jitter(clamped_delay)
  end
  
  @doc """
  Calculate linear backoff delay with jitter.
  
  Alternative to exponential for cases where linear growth is preferred.
  """
  @spec linear(pos_integer(), pos_integer()) :: non_neg_integer()
  def linear(attempt, step_ms \\ 5_000) when is_integer(attempt) and is_integer(step_ms) do
    base_delay = max(@min_ms, attempt * step_ms)
    clamped_delay = min(base_delay, @max_ms)
    jitter(clamped_delay)
  end
  
  @doc """
  Apply jitter to a delay value.
  
  Adds random variance to prevent synchronized retry attempts.
  """
  @spec jitter(non_neg_integer()) :: non_neg_integer()
  def jitter(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    jitter_amount = round(delay_ms * @jitter_pct)
    random_offset = :rand.uniform(2 * jitter_amount + 1) - jitter_amount - 1
    max(0, delay_ms + random_offset)
  end
  
  @doc """
  Get backoff configuration for debugging/monitoring.
  """
  def config do
    %{
      min_ms: @min_ms,
      max_ms: @max_ms,
      jitter_pct: @jitter_pct
    }
  end
end