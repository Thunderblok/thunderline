defmodule Thunderline.Thundervine.WorkflowCompactorWorker do
  @moduledoc """
  Oban worker alternative to the in-memory `WorkflowCompactor` GenServer.

  Schedule via Oban.Cron (e.g., every 5m) to seal inactive workflows without relying
  on a continuously running process (useful in multi-node or serverless topologies).
  """
  use Oban.Worker, queue: :scheduled_workflows, max_attempts: 1
  require Logger
  alias Thunderline.Thundervine.Resources.Workflow
  require Ash.Query
  import Ash.Expr

  @default_idle_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    idle_minutes = Map.get(args, "idle_minutes", @default_idle_minutes)
    idle_cutoff = DateTime.utc_now() |> DateTime.add(-idle_minutes * 60, :second)

    wf_query =
      Workflow
      |> Ash.Query.filter(expr(status == :building and inserted_at < ^idle_cutoff))
      |> Ash.Query.limit(500)

    case Ash.read(wf_query) do
      {:ok, wfs} -> Enum.each(wfs, &seal/1)
      {:error, err} -> Logger.warning("[WorkflowCompactorWorker] read_failed=#{inspect(err)}")
    end

    :ok
  end

  defp seal(wf) do
    case Ash.Changeset.for_update(wf, :seal, %{}) |> Ash.update() do
      {:ok, _} ->
        Logger.info("[WorkflowCompactorWorker] sealed workflow=#{wf.id}")

      {:error, err} ->
        Logger.warning("[WorkflowCompactorWorker] seal_failed=#{inspect(err)} wf=#{wf.id}")
    end
  end
end
