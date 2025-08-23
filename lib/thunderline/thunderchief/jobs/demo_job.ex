defmodule Thunderchief.Jobs.DemoJob do
  @moduledoc """
  Simple Oban worker used to validate that the Oban supervisor is running and jobs execute.

  Moved from `Thunderline.Workers.DemoJob` into the Thunderchief domain (operations & platform schedulers).

  Enqueue with:

      %{} |> new() |> Oban.insert()

  Or rely on `Thunderchief.ObanDiagnostics` which will try to enqueue a probe job if Oban
  isn't yet supervising when diagnostics run.
  """
  use Oban.Worker, queue: :default, max_attempts: 1
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("[DemoJob] Executing demo job args=#{inspect(args)} node=#{inspect(Node.self())}")
    :ok
  end
end

# Backwards compatibility shim (optional). Remove after external callers migrate.
defmodule Thunderline.Workers.DemoJob do
  @moduledoc """
  Deprecated shim. Use `Thunderchief.Jobs.DemoJob` instead.
  """
  @deprecated "Use Thunderchief.Jobs.DemoJob"
  defdelegate new(args \\ %{}), to: Thunderchief.Jobs.DemoJob
end
