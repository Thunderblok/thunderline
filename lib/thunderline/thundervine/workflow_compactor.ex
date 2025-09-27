defmodule Thunderline.Thundervine.WorkflowCompactor do
  @moduledoc """
  Periodically seals inactive workflows (status :building) whose latest node is older
  than a configurable inactivity window.

  This prevents unbounded growth of 'building' workflows and signals downstream
  consumers that lineage is complete.
  """
  use GenServer
  require Logger
  alias Thunderline.Thunderblock.Resources.DAGWorkflow
  require Ash.Query
  import Ash.Expr

  @interval_ms :timer.minutes(5)
  @default_idle_minutes 30

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    schedule()
    {:ok, %{idle_minutes: Keyword.get(opts, :idle_minutes, @default_idle_minutes)}}
  end

  defp schedule, do: Process.send_after(self(), :sweep, @interval_ms)

  @impl true
  def handle_info(:sweep, state) do
    idle_cutoff = DateTime.utc_now() |> DateTime.add(-state.idle_minutes * 60, :second)

    wf_query =
      DAGWorkflow
      |> Ash.Query.filter(expr(status == :building and inserted_at < ^idle_cutoff))
      |> Ash.Query.limit(200)

    case Ash.read(wf_query) do
      {:ok, workflows} -> Enum.each(workflows, &seal/1)
      {:error, err} -> Logger.warning("[WorkflowCompactor] read_failed=#{inspect(err)}")
    end

    schedule()
    {:noreply, state}
  end

  defp seal(wf) do
    case Ash.Changeset.for_update(wf, :seal, %{}) |> Ash.update() do
      {:ok, _} ->
        Logger.info("[WorkflowCompactor] sealed workflow=#{wf.id}")

      {:error, err} ->
        Logger.warning("[WorkflowCompactor] seal_failed=#{inspect(err)} wf=#{wf.id}")
    end
  end
end
