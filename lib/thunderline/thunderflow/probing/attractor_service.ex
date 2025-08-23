defmodule Thunderline.Thunderflow.Probing.AttractorService do
  @moduledoc "Service helpers for recomputing attractor summaries via Ash action."
  alias Thunderline.Thunderflow.Resources.{ProbeRun, ProbeAttractorSummary}
  alias Thunderline.Thunderflow.Probing.Attractor

  @doc "Recompute (in-place) the attractor summary for a run, creating it if missing."
  def recompute(run_id, opts \\ []) do
    with {:ok, run} <- Ash.get(ProbeRun, run_id) do
      summary = run |> Attractor.summarize_run(opts) |> put_canonical()
      case Ash.read_one(ProbeAttractorSummary, [run_id: run.id]) do
        {:ok, nil} -> Ash.create(ProbeAttractorSummary, summary)
        {:ok, rec} ->
          Ash.update(rec, Map.take(summary, [:points,:delay_rows,:m,:tau,:corr_dim,:lyap,:lyap_r2,:lyap_window,:lyap_canonical,:reliable,:note]))
        other -> other
      end
    end
  end

  defp put_canonical(summary) do
    Map.put(summary, :lyap_canonical, canonical_lyap(summary))
  end

  defp canonical_lyap(%{lyap_r2: r2, lyap: simple} = s) when is_number(r2) do
    ro = Map.get(s, :lyap_rosenstein) || Map.get(s, :lyap)
    if r2 >= 0.6 and is_number(ro), do: ro, else: simple
  end
  defp canonical_lyap(%{lyap: simple}), do: simple
end
