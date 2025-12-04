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

    Logger.info(
      "[DatasetManager] Creating Phase I dataset: #{target_samples} samples, max_len=#{max_length}"
    )

    samples =
      @phase1_sources
      |> fetch_raw_samples(target_samples)
      |> clean_samples(max_length)
      |> validate_samples()
      |> shard_samples()

    dataset_id = register_dataset(samples, target_samples)

    {:ok, dataset_id, length(samples)}
  end

  def preprocess_sample(text, max_tokens \\ @max_context_length) do
    text
    |> strip_non_prose()
    |> ensure_sentence_boundaries()
    |> summarize_to_length(max_tokens)
    |> validate_format()
  end

  # Private Functions
  defp fetch_raw_samples(sources, target_count) do
    # TODO: Replace with actual HuggingFace dataset loading
    # For now, generate synthetic textbook-style samples

    Logger.info(
      "[DatasetManager] Generating #{target_count} synthetic samples from #{length(sources)} sources"
    )

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
      "Furthermore, " <>
        String.downcase(String.slice(base_text, 0..0)) <> String.slice(base_text, 1..-1//1)
    ]

    Enum.random(variations)
  end

  defp clean_samples(raw_samples, max_length) do
    Logger.info("[DatasetManager] Cleaning #{length(raw_samples)} samples")

    Enum.map(raw_samples, fn sample ->
      cleaned_text = preprocess_sample(sample.text, max_length)
      %{sample | text: cleaned_text}
    end)
    |> Enum.reject(fn sample ->
      String.length(sample.text) < @min_context_length
    end)
  end

  defp strip_non_prose(text) do
    text
    # Remove URLs
    |> String.replace(~r/https?:\/\/[^\s]+/, "")
    # Remove citations [1], [Smith 2023]
    |> String.replace(~r/\[[^\]]+\]/, "")
    # Replace line breaks with spaces
    |> String.replace(~r/\n+/, " ")
    # Remove non-ASCII Unicode
    |> String.replace(~r/[^\x00-\x7F]/, "")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp ensure_sentence_boundaries(text) do
    # Ensure text starts with capital letter
    text =
      case String.first(text) do
        nil ->
          text

        first when first >= "a" and first <= "z" ->
          String.upcase(first) <> String.slice(text, 1..-1//1)

        _ ->
          text
      end

    # Ensure text ends with proper punctuation
    last_char = String.last(text)

    if last_char not in [".", "!", "?", ":", ";"] do
      text <> "."
    else
      text
    end
  end

  defp summarize_to_length(text, max_tokens) do
    # Simple approximation: ~4 chars per token
    max_chars = max_tokens * 4

    if String.length(text) <= max_chars do
      text
    else
      # Find last complete sentence within limit
      truncated = String.slice(text, 0, max_chars)

      case String.split(truncated, ~r/[.!?]\s+/) do
        [single] ->
          # No sentence boundary found, truncate at word boundary
          words = String.split(single, ~r/\s+/)
          # Take 75% of words
          take_count = div(length(words) * 3, 4)

          words
          |> Enum.take(take_count)
          |> Enum.join(" ")
          |> Kernel.<>(".")

        sentences ->
          # Take all complete sentences except the last (potentially incomplete)
          sentences
          |> Enum.drop(-1)
          |> Enum.join(". ")
          |> Kernel.<>(".")
      end
    end
  end

  defp validate_format(text) do
    # Final validation checks
    cond do
      String.length(text) < @min_context_length ->
        # Too short, will be filtered out
        nil

      String.length(text) > @max_context_length * 4 ->
        String.slice(text, 0, @max_context_length * 4) <> "."

      not Regex.match?(~r/^[A-Z]/, text) ->
        String.capitalize(text)

      not Regex.match?(~r/[.!?]$/, text) ->
        text <> "."

      true ->
        text
    end
  end

  defp validate_samples(samples) do
    valid_samples =
      Enum.reject(samples, fn sample ->
        is_nil(sample.text) or String.length(sample.text) < @min_context_length
      end)

    Logger.info("[DatasetManager] Validated #{length(valid_samples)}/#{length(samples)} samples")
    valid_samples
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

  defp register_dataset(sharded_samples, _target_samples) do
    dataset_id = "phase1-clean-v1-#{System.os_time(:second)}"

    total_samples = sharded_samples |> Enum.map(&length(elem(&1, 1))) |> Enum.sum()

    Logger.info(
      "[DatasetManager] Registered dataset #{dataset_id}: #{total_samples} samples in #{length(sharded_samples)} shards"
    )

    # TODO: Store dataset metadata in database
    # For now, just return the ID
    dataset_id
  end
end
