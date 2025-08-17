defmodule Thunderline.Thunderbolt.Cerebros.Adapter do
  @moduledoc """
  Unified façade for ML search.

  Formerly `Thunderline.ML.Cerebros.Adapter`.
  Delegates to SimpleSearch internally (future: external cerebros app detection).
  """
  alias Thunderline.Thunderbolt.Cerebros.SimpleSearch
  alias Thunderline.Thunderbolt.Cerebros.Artifacts
  alias Thunderline.Thunderbolt.Cerebros.Telemetry
  require Logger

  @doc "Run a search with provided options (see SimpleSearch)."
  def run_search(opts) when is_list(opts) do
    Telemetry.attach_logger()
    if external_available?() do
      Logger.info("[Cerebros.Adapter] External cerebros detected (using internal fallback until delegation implemented)")
      internal(opts)
    else
      internal(opts)
    end
  end

  @doc "Load an artifact (delegates to Artifacts)."
  def load_artifact(path), do: Artifacts.load(path)

  @doc "Predict with an artifact path (stub)."
  def predict_with_artifact(path, samples) do
    with {:ok, art} <- Artifacts.load(path) do
      {:ok, Artifacts.predict_stub(art, samples)}
    end
  end

  defp internal(opts) do
    case SimpleSearch.simple_search(opts) do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  defp external_available?, do: Code.ensure_loaded?(Cerebros.Application)
end
