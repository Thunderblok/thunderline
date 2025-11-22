defmodule Thunderline.Thunderflow.Probing.Engine do
  @moduledoc """
  Core synchronous execution loop for a probe run.

  Replaces the Raincatcher Runner GenServer with a pure functional loop usable
  inside an Oban worker or Task. Emits telemetry for each lap and returns the
  accumulated lap maps.
  """
  alias Thunderline.Thunderflow.Probing.{Metrics, Embedding, MonteCarlo}
  alias Thunderline.Thunderflow.Probing.Providers.Mock

  @type run_spec :: %{
          provider: String.t(),
          model: String.t() | nil,
          prompt_path: String.t(),
          laps: pos_integer(),
          samples: pos_integer(),
          embedding_dim: pos_integer(),
          embedding_ngram: pos_integer(),
          condition: String.t()
        }

  def run(%{prompt_path: path} = spec) do
    prompt = File.read!(path)
    do_loop(spec, prompt, nil, nil, 0, [])
  end

  defp do_loop(%{laps: laps} = _spec, _prompt, _prev_emb, _baseline, lap, acc) when lap >= laps,
    do: Enum.reverse(acc)

  defp do_loop(spec, prompt, prev_emb, baseline_dist, lap, acc) do
    provider_mod = resolve_provider(spec.provider)
    t0 = System.monotonic_time(:microsecond)
    {:ok, text} = provider_mod.generate(prompt, %{model: spec.model})

    {emb, _norm} =
      Embedding.hash_embedding(text, dim: spec.embedding_dim, ngram: spec.embedding_ngram)

    cos_prev = if prev_emb, do: Embedding.cosine(prev_emb, emb), else: 0.0

    row = %{
      lap_index: lap,
      provider: spec.provider,
      model: spec.model,
      condition: spec.condition,
      response_preview: String.slice(text, 0, 200),
      char_entropy: Metrics.char_entropy(text),
      lexical_diversity: Metrics.lexical_diversity(text),
      repetition_ratio: Metrics.repetition_ratio(text),
      cosine_to_prev: cos_prev,
      embedding: emb,
      elapsed_ms: div(System.monotonic_time(:microsecond) - t0, 1000)
    }

    {row, baseline_dist} = maybe_mc(row, baseline_dist, prompt, provider_mod, spec)

    :telemetry.execute(
      [
        :thunderline,
        :probe,
        :lap
      ],
      %{
        char_entropy: row.char_entropy,
        lexical_diversity: row.lexical_diversity,
        repetition_ratio: row.repetition_ratio,
        cosine_to_prev: row.cosine_to_prev,
        elapsed_ms: row.elapsed_ms
      },
      %{lap_index: lap, provider: spec.provider, model: spec.model, condition: spec.condition}
    )

    do_loop(spec, prompt, emb, baseline_dist, lap + 1, [row | acc])
  end

  defp maybe_mc(row, baseline_dist, prompt, provider_mod, %{samples: s} = spec) when s > 1 do
    fun = fn p -> provider_mod.generate(p, %{model: spec.model}) end
    dist = MonteCarlo.distribution(fun, prompt, s)

    if baseline_dist == nil do
      {Map.merge(row, %{
         mc_dist: dist,
         js_divergence_vs_baseline: nil,
         topk_overlap_vs_baseline: nil
       }), dist}
    else
      {Map.merge(row, %{
         mc_dist: dist,
         js_divergence_vs_baseline: MonteCarlo.js_divergence(dist, baseline_dist),
         topk_overlap_vs_baseline: MonteCarlo.topk_overlap(dist, baseline_dist, 10)
       }), baseline_dist}
    end
  end

  defp maybe_mc(row, baseline_dist, _prompt, _provider_mod, _spec), do: {row, baseline_dist}

  defp resolve_provider("mock"), do: Mock

  defp resolve_provider(other) do
    raise "Unknown probe provider #{inspect(other)} (extend Thunderline.Thunderflow.Probing.Engine.resolve_provider/1)"
  end
end
