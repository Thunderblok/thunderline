defmodule Thunderline.Thunderbolt.Cerebros.SimpleSearch do
  @moduledoc """
  Thunderbolt Cerebros SimpleSearch (migrated from `Thunderline.ML.Cerebros.SimpleSearch`).
  """
  require Logger
  alias Thunderline.Thunderbolt.Cerebros.Utils.ParamCount
  alias Thunderline.Thunderbolt.Cerebros.Data.{Dataset, TabularDataset}

  @type search_opts :: [dataset: TabularDataset.t() | {:rows, [map()], features: [atom()], target: atom()}, trials: pos_integer(), max_params: pos_integer(), seed: non_neg_integer()]
  @default_trials 3
  @max_trials 100

  def simple_search(opts) when is_list(opts) do
    {dataset, trials, max_params, seed} = normalize_opts(opts)
    if seed, do: :rand.seed(:exsss, {seed, seed * 2 + 1, seed * 3 + 2})
    ds_info = Dataset.info(dataset)

    Logger.info("[Cerebros] Starting simple search: task=#{ds_info.task} shape=#{inspect(ds_info.input_shape)} trials=#{trials}")
    :telemetry.execute([:thunderline, :thunderbolt, :cerebros, :search, :start], %{trials: trials}, %{task: ds_info.task})

    trials_results =
      1..trials
      |> Enum.map(fn idx ->
        spec = random_spec(idx, ds_info)
        model = build_stub_model(ds_info)
        param_info = ParamCount.count(model)
        metric = derive_metric(param_info.total)
        :telemetry.execute([:thunderline, :thunderbolt, :cerebros, :search, :trial, :stop], %{metric: metric}, %{trial: idx})
        %{spec: spec, metric: metric, params: param_info.total, param_info: param_info}
      end)

    best = Enum.min_by(trials_results, & &1.metric)
    artifact_path = persist_artifact(best)

    :telemetry.execute([
      :thunderline,
      :thunderbolt,
      :cerebros,
      :search,
      :complete
    ], %{best_metric: best.metric}, %{trials: length(trials_results)})

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
    trials = opts |> Keyword.get(:trials, @default_trials) |> min(@max_trials)
    max_params = Keyword.get(opts, :max_params, 2_000_000)
    seed = Keyword.get(opts, :seed, nil)
    dataset =
      case Keyword.fetch!(opts, :dataset) do
        %TabularDataset{} = ds -> ds
        {:rows, rows, features: feats, target: tgt} -> TabularDataset.new(rows, feats, tgt)
      end
    {dataset, trials, max_params, seed}
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

  defp build_stub_model(%{input_shape: {in_dim}}) do
    Axon.input("input", shape: {nil, in_dim})
    |> Axon.dense(Enum.random([32, 64, 128]), activation: :relu)
    |> Axon.dense(1)
  end

  defp derive_metric(params) do
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
    spec_hash = :erlang.phash2(best.spec) |> Integer.to_string(36)
    file = Path.join(dir, "trial_#{best.spec.id}_#{spec_hash}.json")
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
      Logger.error("[Cerebros] Failed to persist artifact: #{inspect(e)}")
      :noop
  end
end
