defmodule Thunderline.Thunderblock.Timing.DelayedExecution do
  @moduledoc """
  Deferred task execution with retry logic and backoff strategies.

  Provides utilities for executing tasks with delays, automatic retries,
  and exponential backoff. Suitable for resilient background operations.

  ## Usage

      # Execute a task after a delay
      DelayedExecution.execute_later(fn ->
        send_email(user)
      end, delay_ms: 5_000)

      # Execute with retry and exponential backoff
      DelayedExecution.retry_with_backoff(fn ->
        HTTPClient.post("/api/endpoint", data)
      end, max_retries: 3, initial_backoff_ms: 1_000)
  """

  require Logger
  alias Thunderline.Thunderblock.Timing.Timer

  @default_max_retries 3
  @default_initial_backoff_ms 1_000
  @default_max_backoff_ms 30_000
  @default_jitter_factor 0.1

  @doc """
  Executes a function after a specified delay.

  ## Options

    * `:delay_ms` - Delay before execution (required)
    * `:metadata` - Arbitrary metadata map
    * `:name` - Optional name for the delayed execution

  ## Returns

    * `{:ok, timer_ref}` - Task scheduled successfully
    * `{:error, reason}` - Failed to schedule
  """
  def execute_later(fun, opts \\ []) when is_function(fun, 0) do
    delay_ms = Keyword.fetch!(opts, :delay_ms)
    metadata = Keyword.get(opts, :metadata, %{})
    name = Keyword.get(opts, :name)

    Timer.create(delay_ms, fun, metadata: metadata, name: name)
  end

  @doc """
  Executes a function with retry logic and exponential backoff.

  ## Options

    * `:max_retries` - Maximum number of retry attempts (default: 3)
    * `:initial_backoff_ms` - Initial backoff duration (default: 1000ms)
    * `:max_backoff_ms` - Maximum backoff duration (default: 30000ms)
    * `:jitter_factor` - Randomization factor for backoff (default: 0.1)
    * `:on_retry` - Callback function called on each retry: `fn attempt, error -> ... end`
    * `:retryable?` - Function to determine if error is retryable: `fn error -> boolean end`

  ## Returns

    * `{:ok, result}` - Task succeeded
    * `{:error, reason}` - Task failed after all retries
  """
  def retry_with_backoff(fun, opts \\ []) when is_function(fun, 0) do
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    initial_backoff = Keyword.get(opts, :initial_backoff_ms, @default_initial_backoff_ms)
    max_backoff = Keyword.get(opts, :max_backoff_ms, @default_max_backoff_ms)
    jitter_factor = Keyword.get(opts, :jitter_factor, @default_jitter_factor)
    on_retry = Keyword.get(opts, :on_retry)
    retryable_fn = Keyword.get(opts, :retryable?, &default_retryable?/1)

    do_retry(
      fun,
      attempt: 0,
      max_retries: max_retries,
      current_backoff: initial_backoff,
      max_backoff: max_backoff,
      jitter_factor: jitter_factor,
      on_retry: on_retry,
      retryable?: retryable_fn
    )
  end

  @doc """
  Executes a function with a deadline timeout.

  If the function doesn't complete within the deadline, it's terminated
  and an error is returned.

  ## Options

    * `:timeout_ms` - Timeout duration in milliseconds (required)

  ## Returns

    * `{:ok, result}` - Task completed within timeout
    * `{:error, :timeout}` - Task exceeded timeout
  """
  def execute_with_deadline(fun, opts \\ []) when is_function(fun, 0) do
    timeout_ms = Keyword.fetch!(opts, :timeout_ms)

    task = Task.async(fun)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        # Task didn't complete in time
        Task.shutdown(task, :brutal_kill)

        Logger.warning("Task deadline exceeded",
          timeout_ms: timeout_ms
        )

        :telemetry.execute(
          [:thunderline, :timing, :deadline_exceeded],
          %{count: 1, timeout_ms: timeout_ms},
          %{}
        )

        {:error, :timeout}
    end
  end

  # Private functions

  defp do_retry(fun, opts) do
    attempt = Keyword.fetch!(opts, :attempt)
    max_retries = Keyword.fetch!(opts, :max_retries)

    try do
      result = fun.()

      if attempt > 0 do
        Logger.info("Task succeeded after retries", attempt: attempt)

        :telemetry.execute(
          [:thunderline, :timing, :retry_success],
          %{count: 1, attempts: attempt + 1},
          %{}
        )
      end

      {:ok, result}
    rescue
      error ->
        retryable_fn = Keyword.fetch!(opts, :retryable?)

        if attempt < max_retries && retryable_fn.(error) do
          # Calculate backoff with jitter
          current_backoff = Keyword.fetch!(opts, :current_backoff)
          max_backoff = Keyword.fetch!(opts, :max_backoff)
          jitter_factor = Keyword.fetch!(opts, :jitter_factor)

          backoff_with_jitter = calculate_backoff(
            current_backoff,
            max_backoff,
            jitter_factor
          )

          Logger.warning("Task failed, retrying",
            attempt: attempt + 1,
            max_retries: max_retries,
            backoff_ms: backoff_with_jitter,
            error: Exception.message(error)
          )

          # Call retry callback if provided
          if on_retry = Keyword.get(opts, :on_retry) do
            on_retry.(attempt + 1, error)
          end

          :telemetry.execute(
            [:thunderline, :timing, :retry_attempt],
            %{count: 1, attempt: attempt + 1, backoff_ms: backoff_with_jitter},
            %{error_type: error.__struct__}
          )

          # Sleep and retry
          Process.sleep(backoff_with_jitter)

          do_retry(
            fun,
            Keyword.merge(opts, [
              attempt: attempt + 1,
              current_backoff: min(current_backoff * 2, max_backoff)
            ])
          )
        else
          # Not retryable or max retries exceeded
          Logger.error("Task failed permanently",
            attempt: attempt + 1,
            max_retries: max_retries,
            error: Exception.format(:error, error, __STACKTRACE__)
          )

          :telemetry.execute(
            [:thunderline, :timing, :retry_exhausted],
            %{count: 1, attempts: attempt + 1},
            %{error_type: error.__struct__}
          )

          {:error, error}
        end
    end
  end

  defp calculate_backoff(current_backoff, max_backoff, jitter_factor) do
    # Add jitter: backoff ± (backoff * jitter_factor)
    jitter_range = trunc(current_backoff * jitter_factor)
    jitter = :rand.uniform(jitter_range * 2) - jitter_range

    min(current_backoff + jitter, max_backoff)
  end

  defp default_retryable?(error) do
    # By default, retry on network/timeout errors
    case error do
      %HTTPoison.Error{reason: :timeout} -> true
      %HTTPoison.Error{reason: :econnrefused} -> true
      %Mint.TransportError{} -> true
      %DBConnection.ConnectionError{} -> true
      _ -> false
    end
  end
end
