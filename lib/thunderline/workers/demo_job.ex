defmodule Thunderline.Workers.DemoJob do
  @moduledoc """
  Demo Oban worker for testing (legacy namespace).

  This is a thin wrapper delegating to `Thunderline.Thunderflow.Jobs.DemoJob`.
  Kept for backwards compatibility with existing code references.

  See `Thunderline.Thunderflow.Jobs.DemoJob` for full documentation.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Thunderline.Thunderflow.Jobs.DemoJob, as: ActualDemoJob

  @impl Oban.Worker
  def perform(job) do
    ActualDemoJob.perform(job)
  end
end
