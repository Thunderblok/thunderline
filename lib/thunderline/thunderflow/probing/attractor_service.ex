defmodule Thunderline.Thunderflow.Probing.AttractorService do
  @moduledoc "Service helpers for recomputing attractor summaries via Ash action."
  alias Thunderline.Thunderflow.Resources.{ProbeRun, ProbeAttractorSummary}
  alias Thunderline.Thunderflow.Probing.Attractor

  @doc "Recompute (in-place) the attractor summary for a run, creating it if missing."
  def recompute(run_id, opts \\ []) do
    with {:ok, run} <- Ash.get(ProbeRun, run_id) do
      summary = Attractor.summarize_run(run, opts)
      case Ash.read_one(ProbeAttractorSummary, [run_id: run.id]) do
        {:ok, nil} -> Ash.create(ProbeAttractorSummary, summary)
        {:ok, rec} ->
          Ash.update(rec, Map.take(summary, [:points,:delay_rows,:m,:tau,:corr_dim,:lyap,:lyap_r2,:lyap_window,:reliable,:note]))
        other -> other
      end
    end
  end
end
