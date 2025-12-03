defmodule Thunderline.Thunderflow.Jobs.DemoJob do
  @moduledoc """
  Demo Oban job for testing and introspection.

  This is a simple worker used for:
  - Testing Oban configuration and connectivity
  - Demonstrating job patterns for developers
  - Introspection tooling validation

  ## Usage

      # Create a job changeset
      job = DemoJob.new(%{message: "Hello Oban!"})

      # Insert the job
      Oban.insert(job)

  ## Args

  - `:message` - (optional) Message to log, defaults to "Demo job executed"
  - `:sleep_ms` - (optional) Sleep duration in milliseconds for simulating work
  - `:fail` - (optional) If true, the job will fail for testing retries
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    message = Map.get(args, "message", "Demo job executed")
    sleep_ms = Map.get(args, "sleep_ms", 0)
    should_fail = Map.get(args, "fail", false)

    Logger.info("[DemoJob] Starting: #{message}")

    # Simulate work if requested
    if sleep_ms > 0 do
      Process.sleep(sleep_ms)
    end

    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :oban, :demo_job, :complete],
      %{count: 1, duration_ms: sleep_ms},
      %{message: message}
    )

    if should_fail do
      Logger.warning("[DemoJob] Intentionally failing for test")
      {:error, :intentional_failure}
    else
      Logger.info("[DemoJob] Completed: #{message}")
      :ok
    end
  end
end
