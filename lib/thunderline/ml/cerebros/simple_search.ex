defmodule Thunderline.ML.Cerebros.SimpleSearch do
  @moduledoc """
  Minimal NAS-style search entrypoint bridging Thunderline and Cerebros team work.

  Provides a simple API:
      Thunderline.ML.Cerebros.SimpleSearch.simple_search(dataset: ds, trials: 5)

  Returns:
      {:ok, %{best_metric: float(), best_spec: map(), artifact: String.t(), trials: integer()}}

  This is intentionally lightweight; real search space & training loop will be
  expanded by the Cerebros team. For now, we produce synthetic trial specs and
  a dummy metric derived from parameter count noise.
  """
  require Logger
  alias Thunderline.ML.Cerebros.Utils.ParamCount
  alias Thunderline.ML.Cerebros.Data.{Dataset, TabularDataset}

  @type search_opts :: [dataset: TabularDataset.t() | {:rows, [map()], features: [atom()], target: atom()}, trials: pos_integer(), max_params: pos_integer()]

  @default_trials 3

  def simple_search(opts) when is_list(opts) do
    {dataset, trials, max_params} = normalize_opts(opts)
    ds_info = Dataset.info(dataset)

    Logger.info("[Cerebros] Starting simple search: task=#{ds_info.task} shape=#{inspect ds_info.input_shape} trials=#{trials}")

    trials_results =
      1..trials
      |> Enum.map(fn idx ->
        spec = random_spec(idx, ds_info)
        model = build_stub_model(ds_info)
        param_info = ParamCount.count(model)
        metric = derive_metric(param_info.total)
        %{spec: spec, metric: metric, params: param_info.total, param_info: param_info}
      end)

    best = Enum.min_by(trials_results, & &1.metric)

    artifact_path = persist_artifact(best)

    {:ok,
     %{
       best_metric: best.metric,
       best_spec: best.spec,
       artifact: artifact_path,
       trials: length(trials_results),
       median_metric: median(Enum.map(trials_results, & &1.metric)),
       search_space_version: 1,
       max_params: max_params
     }}
  end

  defp normalize_opts(opts) do
    trials = Keyword.get(opts, :trials, @default_trials)
    max_params = Keyword.get(opts, :max_params, 2_000_000)
    dataset =
      case Keyword.fetch!(opts, :dataset) do
        %TabularDataset{} = ds -> ds
        {:rows, rows, features: feats, target: tgt} -> TabularDataset.new(rows, feats, tgt)
      end

    {dataset, trials, max_params}
  end

  defp random_spec(idx, ds_info) do
    %{
      id: idx,
      hidden_layers: Enum.random(1..4),
      hidden_units: Enum.random([32, 64, 128, 256]),
      activation: Enum.random([:relu, :gelu, :silu]),
      dropout: Enum.random([0.0, 0.1, 0.2, 0.3]),
      seed: :erlang.unique_integer([:positive]),
      input_shape: ds_info.input_shape
    }
  end

  # Build a stub Axon model to enable parameter counting. Replace with real builder later.
  defp build_stub_model(%{input_shape: {in_dim}}) do
    Axon.input("input", shape: {nil, in_dim})
    |> Axon.dense(Enum.random([32, 64, 128]), activation: :relu)
    |> Axon.dense(1)
  end

  defp derive_metric(params) do
    # Synthetic metric: lower is better. Introduce noise so choices vary.
    base = :math.log(params + 1)
    noise = (:rand.uniform() - 0.5) * 0.1
    Float.round(base + noise, 5)
  end

  defp median(list) do
    sorted = Enum.sort(list)
    len = length(sorted)
    if rem(len, 2) == 1 do
      Enum.at(sorted, div(len, 2))
    else
      a = Enum.at(sorted, div(len, 2) - 1)
      b = Enum.at(sorted, div(len, 2))
      (a + b) / 2
    end
  end

  defp persist_artifact(best) do
    dir = Path.join(["priv", "cerebros_artifacts", Date.utc_today() |> Date.to_iso8601()])
    File.mkdir_p!(dir)
    file = Path.join(dir, "trial_#{best.spec.id}_best.json")
    artifact = %{
      spec: best.spec,
      metric: best.metric,
      params: best.params,
      total_parameters: best.param_info.total
    }

    File.write!(file, Jason.encode!(artifact, pretty: true))
    file
  rescue
    e ->
      Logger.error("[Cerebros] Failed to persist artifact: #{inspect e}")
      :noop
  end
end
