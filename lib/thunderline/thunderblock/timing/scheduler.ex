defmodule Thunderline.Thunderblock.Timing.Scheduler do
  @moduledoc """
  Job scheduling and execution for Thunderline.

  Integrates with Oban for persistent, fault-tolerant scheduled jobs.
  Provides high-level API for recurring tasks and delayed execution.

  ## Usage

      # Schedule a recurring task
      Scheduler.schedule_recurring(
        :daily_cleanup,
        {MyApp.CleanupWorker, :perform, []},
        schedule: "0 2 * * *"  # Daily at 2 AM
      )

      # Schedule a one-time delayed task
      Scheduler.schedule_once(
        {MyApp.SendEmail, :perform, [user_id]},
        delay_ms: 60_000  # 1 minute from now
      )
  """

  require Logger

  @doc """
  Schedules a recurring job using cron syntax.

  ## Options

    * `:schedule` - Cron expression (e.g., "*/5 * * * *" for every 5 minutes)
    * `:queue` - Oban queue name (default: "scheduled")
    * `:max_attempts` - Number of retry attempts (default: 3)
    * `:timezone` - Timezone for cron schedule (default: "Etc/UTC")
  """
  def schedule_recurring(job_name, {module, function, args}, opts \\ []) do
    schedule = Keyword.fetch!(opts, :schedule)
    queue = Keyword.get(opts, :queue, "scheduled")
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")

    config = %{
      name: job_name,
      schedule: schedule,
      worker: create_worker_module(module, function, args),
      queue: queue,
      max_attempts: max_attempts,
      timezone: timezone
    }

    # Store in application config for Oban to pick up
    update_cron_config(job_name, config)

    Logger.info("Scheduled recurring job",
      name: job_name,
      schedule: schedule,
      module: module,
      function: function
    )

    :telemetry.execute(
      [:thunderline, :timing, :schedule_recurring],
      %{count: 1},
      %{job_name: job_name, schedule: schedule}
    )

    {:ok, job_name}
  end

  @doc """
  Schedules a one-time job with a delay.

  ## Options

    * `:delay_ms` - Delay in milliseconds
    * `:scheduled_at` - Specific DateTime to run (alternative to delay_ms)
    * `:queue` - Oban queue name (default: "scheduled")
    * `:max_attempts` - Number of retry attempts (default: 3)
  """
  def schedule_once({module, function, args}, opts \\ []) do
    queue = Keyword.get(opts, :queue, "scheduled")
    max_attempts = Keyword.get(opts, :max_attempts, 3)

    scheduled_at =
      cond do
        delay_ms = Keyword.get(opts, :delay_ms) ->
          DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)

        scheduled_at = Keyword.get(opts, :scheduled_at) ->
          scheduled_at

        true ->
          DateTime.utc_now()
      end

    job_params = %{
      module: to_string(module),
      function: to_string(function),
      args: args
    }

    worker = create_generic_worker()

    case Oban.insert(
           worker.new(job_params,
             queue: queue,
             max_attempts: max_attempts,
             scheduled_at: scheduled_at
           )
         ) do
      {:ok, job} ->
        Logger.info("Scheduled one-time job",
          module: module,
          function: function,
          scheduled_at: scheduled_at
        )

        :telemetry.execute(
          [:thunderline, :timing, :schedule_once],
          %{count: 1},
          %{module: module, function: function}
        )

        {:ok, job.id}

      {:error, changeset} ->
        Logger.error("Failed to schedule job",
          module: module,
          function: function,
          errors: changeset.errors
        )

        {:error, changeset}
    end
  end

  @doc """
  Cancels a scheduled job.
  """
  def cancel_job(job_id) when is_binary(job_id) or is_integer(job_id) do
    case Oban.cancel_job(job_id) do
      {:ok, job} ->
        :telemetry.execute(
          [:thunderline, :timing, :cancel],
          %{count: 1},
          %{job_id: job_id}
        )

        {:ok, job}

      error ->
        error
    end
  end

  @doc """
  Lists all scheduled jobs.
  """
  def list_scheduled_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    # Query Oban jobs table
    query = """
    SELECT id, worker, queue, scheduled_at, state, args
    FROM oban_jobs
    WHERE state IN ('scheduled', 'available')
    ORDER BY scheduled_at ASC
    LIMIT $1
    """

    case Thunderline.Repo.query(query, [limit]) do
      {:ok, %{rows: rows, columns: columns}} ->
        jobs =
          Enum.map(rows, fn row ->
            Enum.zip(columns, row) |> Map.new()
          end)

        {:ok, jobs}

      error ->
        error
    end
  end

  # Private functions

  defp create_worker_module(_module, _function, _args) do
    # Return generic worker that will execute the MFA
    Thunderline.Thunderblock.Timing.GenericWorker
  end

  defp create_generic_worker do
    Thunderline.Thunderblock.Timing.GenericWorker
  end

  defp update_cron_config(job_name, config) do
    # Store in persistent term for now
    # In production, this would update Oban's cron configuration
    key = {:thunderline_cron, job_name}
    :persistent_term.put(key, config)
  end
end
