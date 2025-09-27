defmodule Thunderline.Thunderflow.Probing.Workers.ProbeAttractorSummaryWorker do
  @moduledoc """
  Oban worker that computes & persists `ProbeAttractorSummary` for a completed run.

  Enqueue this when a run completes (from `ProbeRunProcessor`) if there isn't already
  a summary. Idempotent: checks existing summary by run_id.
  """
  use Oban.Worker, queue: :probe, max_attempts: 1
  require Logger
  alias Thunderline.Thunderflow.Resources.{ProbeRun, ProbeAttractorSummary}
  alias Thunderline.Thunderflow.Probing.Attractor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id} = args}) do
    with {:ok, run} <- Ash.get(ProbeRun, run_id) do
      case Ash.read_one(ProbeAttractorSummary, run_id: run.id) do
        {:ok, %ProbeAttractorSummary{}} ->
          Logger.info("[ProbeAttractorSummaryWorker] summary already exists run=#{run.id}")

        {:ok, nil} ->
          create_summary(run, args)

        {:error, err} ->
          Logger.error(
            "[ProbeAttractorSummaryWorker] read error run=#{run.id} err=#{inspect(err)}"
          )
      end
    else
      {:error, err} ->
        Logger.error("[ProbeAttractorSummaryWorker] run not found #{run_id} err=#{inspect(err)}")
    end

    :ok
  end

  defp create_summary(run, args) do
    opts =
      []
      |> maybe_put(:m, args["m"] || run.attractor_m)
      |> maybe_put(:tau, args["tau"] || run.attractor_tau)
      |> maybe_put(:min_points, args["min_points"] || run.attractor_min_points)

    summary_map = Attractor.summarize_run(run, opts)
    summary_map = Map.put(summary_map, :lyap_canonical, canonical_lyap(summary_map))
    {:ok, _rec} = Ash.create(ProbeAttractorSummary, summary_map)

    :telemetry.execute(
      [:thunderline, :probe, :attractor_summary],
      %{
        corr_dim: summary_map.corr_dim,
        lyap: summary_map.lyap,
        lyap_r2: summary_map.lyap_r2 || 0.0,
        points: summary_map.points,
        delay_rows: summary_map.delay_rows
      },
      %{
        run_id: run.id,
        m: summary_map.m,
        tau: summary_map.tau,
        reliable: summary_map.reliable,
        canonical: summary_map.lyap_canonical
      }
    )

    Logger.info(
      "[ProbeAttractorSummaryWorker] created summary run=#{run.id} cd=#{summary_map.corr_dim} ly=#{summary_map.lyap} ro_r2=#{summary_map.lyap_r2} canonical=#{summary_map.lyap_canonical}"
    )
  rescue
    e ->
      Logger.error(
        "[ProbeAttractorSummaryWorker] failure run=#{run.id} error=#{Exception.message(e)}"
      )
  end

  defp maybe_put(opts, _k, nil), do: opts
  defp maybe_put(opts, k, v), do: Keyword.put(opts, k, v)

  defp canonical_lyap(%{lyap_r2: r2, lyap: simple, lyap_window: _w} = s) when is_number(r2) do
    threshold = 0.6
    # fallback
    ro = Map.get(s, :lyap_rosenstein) || Map.get(s, :lyap)
    if r2 >= threshold and is_number(ro), do: ro, else: simple
  end

  defp canonical_lyap(%{lyap: simple}), do: simple
end
