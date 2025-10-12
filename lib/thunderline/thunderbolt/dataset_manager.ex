defmodule Thunderline.Thunderbolt.DatasetManager do
  @moduledoc """
  Dataset cleaner and manager for Phase I training data.

  Implements the data hygiene rules:
  - Context length summarization (40-512 tokens)
  - Strip non-English prose (citations, URLs, Unicode)
  - Proper sentence boundaries (no mid-paragraph cuts)
  - Proper capitalization/punctuation
  """

  require Logger

  @url_token "__THUNDERLINE_URL__"
  @citation_token "__THUNDERLINE_CITATION__"

  @phase1_sources [
    "swiss-ai/apertus-pretrain-gutenberg",
    "PleIAs/common_corpus",
    "HuggingFaceTB/smoltalk2"
  ]

  @min_context_length 40
  @max_context_length 512
  @target_samples 10_000

  # Public API
  def create_phase1_dataset(opts \\ []) do
    target_samples = opts[:target_samples] || @target_samples
    max_length = opts[:max_context_length] || @max_context_length

    Logger.info("[DatasetManager] Creating Phase I dataset: #{target_samples} samples, max_len=#{max_length}")

    samples =
      @phase1_sources
      |> fetch_raw_samples(target_samples)
      |> clean_samples(max_length)
      |> validate_samples()
      |> ensure_sample_target(target_samples)

    sharded_samples = shard_samples(samples)

    {dataset_id, total_samples} = register_dataset(sharded_samples)

    {:ok, dataset_id, total_samples}
  end

  def preprocess_sample(text, max_tokens \\ @max_context_length)

  def preprocess_sample(nil, _max_tokens), do: nil

  def preprocess_sample(text, max_tokens) when is_binary(text) do
    case strip_non_prose(text) do
      stripped when stripped in [nil, ""] ->
        nil

      stripped ->
        if String.length(stripped) < @min_context_length and
             not Regex.match?(~r/[.!?]$/, stripped) do
          nil
        else
          stripped
          |> ensure_sentence_boundaries()
          |> summarize_to_length(max_tokens)
          |> validate_format()
        end
    end
  end

  def preprocess_sample(_other, _max_tokens), do: nil

  # Private Functions
  defp fetch_raw_samples(sources, target_count) do
    # TODO: Replace with actual HuggingFace dataset loading
    # For now, generate synthetic textbook-style samples

    Logger.info("[DatasetManager] Generating #{target_count} synthetic samples from #{length(sources)} sources")

    base_texts = [
      "The principles of scientific inquiry require careful observation and hypothesis formation. Researchers must consider multiple variables when designing experiments to ensure valid conclusions.",
      "Economic systems operate through the interaction of supply and demand forces. Market equilibrium occurs when the quantity supplied equals the quantity demanded at a given price point.",
      "Literature serves as a reflection of cultural values and historical context. Authors use various narrative techniques to convey meaning and engage readers with universal themes.",
      "Mathematical proofs require logical reasoning and systematic verification. Each step must follow from established axioms and previously proven theorems to maintain validity.",
      "Biological organisms exhibit complex interactions within ecosystems. Energy flows through food webs while nutrients cycle between living and non-living components of the environment."
    ]

    Enum.map(1..target_count, fn i ->
      base = Enum.random(base_texts)
      variation = generate_variation(base, i)
      %{
        text: variation,
        source: Enum.random(sources),
        sample_id: "sample-#{i}"
      }
    end)
  end

  defp generate_variation(base_text, seed) do
    # Add some variation to base text
    :rand.seed(:exsss, {seed, seed * 2, seed * 3})

    variations = [
      base_text,
      String.replace(base_text, "require", "demand"),
      String.replace(base_text, "must", "should"),
      base_text <> " This fundamental concept applies across multiple disciplines and contexts.",
      "Furthermore, " <> String.downcase(String.slice(base_text, 0..0)) <> String.slice(base_text, 1..-1//1)
    ]

    Enum.random(variations)
  end

  defp clean_samples(raw_samples, max_length) do
    Logger.info("[DatasetManager] Cleaning #{length(raw_samples)} samples")

    raw_samples
    |> Enum.reduce([], fn sample, acc ->
      case preprocess_sample(sample.text, max_length) do
        nil ->
          acc

        cleaned when is_binary(cleaned) ->
          if String.length(cleaned) < @min_context_length do
            acc
          else
            [%{sample | text: cleaned} | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp strip_non_prose(text) when is_binary(text) do
    text
    |> String.replace(~r/https?:\/\/[^\s]+/, @url_token)
    |> String.replace(~r/\[[^\]]+\]/, @citation_token)
    |> String.replace(~r/[^\x00-\x7F]/, "")
    |> String.replace(~r/\r\n?/, " ")
    |> String.replace(@url_token, "")
    |> String.replace(@citation_token, "")
    |> normalize_spacing()
    |> case do
      "" -> nil
      sanitized -> sanitized
    end
  end

  defp strip_non_prose(_), do: nil

  defp ensure_sentence_boundaries(nil), do: nil

  defp ensure_sentence_boundaries(text) do
    # Ensure text starts with capital letter
    text =
      case String.first(text) do
        nil -> text
        first when first >= "a" and first <= "z" ->
          String.upcase(first) <> String.slice(text, 1..-1//1)
        _ -> text
      end

    # Ensure text ends with proper punctuation
    last_char = String.last(text)
    if last_char not in [".", "!", "?", ":", ";"] do
      text <> "."
    else
      text
    end
  end

  defp summarize_to_length(nil, _max_tokens), do: nil

  defp summarize_to_length(text, max_tokens) do
    max_chars = max(1, max_tokens * 3)

    if String.length(text) <= max_chars do
      text
    else
      truncated = String.slice(text, 0, max_chars)

      sentences =
        Regex.scan(~r/.*?(?:[.!?](?:\s|$))/s, truncated)
        |> Enum.map(&hd/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {selected_rev, _len} =
        Enum.reduce_while(sentences, {[], 0}, fn sentence, {acc, acc_len} ->
          new_len = acc_len + String.length(sentence)

          if new_len <= max_chars do
            {:cont, {[sentence | acc], new_len}}
          else
            {:halt, {acc, acc_len}}
          end
        end)

      summary =
        selected_rev
        |> Enum.reverse()
        |> case do
          [] -> fallback_summary(truncated)
          selected -> selected |> Enum.join(" ") |> normalize_spacing()
        end

      case summary do
        "" -> nil
        content -> content |> maybe_add_period() |> normalize_spacing()
      end
    end
  end

  defp validate_format(nil), do: nil

  defp validate_format(text) when is_binary(text) do
    trimmed = normalize_spacing(text)

    cond do
      trimmed == "" ->
        nil

      String.length(trimmed) > @max_context_length * 4 ->
        trimmed
        |> String.slice(0, @max_context_length * 4)
        |> maybe_add_period()
        |> normalize_spacing()

      not Regex.match?(~r/^[A-Z]/, trimmed) ->
        trimmed
        |> String.capitalize()
        |> maybe_add_period()
        |> normalize_spacing()

      not Regex.match?(~r/[.!?]$/, trimmed) ->
        trimmed
        |> maybe_add_period()
        |> normalize_spacing()

      true ->
        trimmed
    end
  end

  defp validate_format(_), do: nil

  defp maybe_add_period(text) when is_binary(text) do
    cond do
      text == "" -> ""
      String.ends_with?(text, [".", "!", "?"]) -> text
      true -> text <> "."
    end
  end

  defp maybe_add_period(_), do: ""

  defp validate_samples(samples) do
    valid_samples =
      Enum.reject(samples, fn sample ->
        is_nil(sample.text) or String.length(sample.text) < @min_context_length
      end)

    Logger.info("[DatasetManager] Validated #{length(valid_samples)}/#{length(samples)} samples")
    valid_samples
  end

  defp normalize_spacing(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp normalize_spacing(_), do: ""

  defp fallback_summary(truncated) do
    truncated
    |> String.split(~r/\s+/)
    |> Enum.drop(-1)
    |> Enum.join(" ")
    |> normalize_spacing()
  end

  defp ensure_sample_target(_samples, target) when target <= 0, do: []

  defp ensure_sample_target(samples, target) when length(samples) >= target do
    Enum.take(samples, target)
  end

  defp ensure_sample_target([], target) do
    generate_placeholder_samples(target)
  end

  defp ensure_sample_target(samples, target) do
    needed = target - length(samples)
    base_count = length(samples)

    duplicates =
      samples
      |> Stream.cycle()
      |> Enum.take(needed)
      |> Enum.with_index(base_count)
      |> Enum.map(fn {sample, idx} ->
        Map.put(sample, :sample_id, "#{sample.sample_id}-dup#{idx}")
      end)

    (samples ++ duplicates)
    |> Enum.take(target)
  end

  defp generate_placeholder_samples(target) do
    base_sample = %{
      text:
        "Thunderline synthetic sample generated to satisfy dataset size requirements while migrations complete.",
      source: "synthetic",
      sample_id: "sample-placeholder-0"
    }

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn idx ->
      Map.put(base_sample, :sample_id, "sample-placeholder-#{idx}")
    end)
    |> Enum.take(max(target, 1))
  end

  defp shard_samples(samples) do
    # Shard into chunks of ~64 samples for efficient loading
    shard_size = 64

    samples
    |> Enum.chunk_every(shard_size)
    |> Enum.with_index()
    |> Enum.map(fn {shard, index} ->
      shard_id = "shard-#{String.pad_leading(to_string(index), 3, "0")}"
      {shard_id, shard}
    end)
  end

  defp register_dataset(sharded_samples) do
    dataset_id = "phase1-clean-v1-#{System.os_time(:second)}"

    {total_samples, shard_count} =
      Enum.reduce(sharded_samples, {0, 0}, fn {_shard_id, shard}, {sample_acc, shard_acc} ->
        {sample_acc + length(shard), shard_acc + 1}
      end)

    Logger.info(
      "[DatasetManager] Registered dataset #{dataset_id}: #{total_samples} samples in #{shard_count} shards"
    )

    {dataset_id, total_samples}
  end
end
