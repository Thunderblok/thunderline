defmodule Thunderline.Workers.DemoJob do
  @moduledoc """
  Simple Oban worker used to validate that the Oban supervisor is running and jobs execute.

  Enqueue with:

      %{} |> new() |> Oban.insert()

  Or rely on `Thunderline.ObanDiagnostics` which will try to enqueue a probe job if Oban
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
