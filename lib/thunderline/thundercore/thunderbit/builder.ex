defmodule Thunderline.Thundercore.Thunderbit.Builder do
  @moduledoc """
  Builds Thunderbits from raw text or voice input.

  This module handles the parsing pipeline:
  1. Capture - receive text/voice input
  2. Parse - segment into semantic chunks
  3. Classify - determine kind for each chunk
  4. Extract - pull out tags (PAC names, zones, topics)
  5. Score - assign energy/salience values
  6. Spawn - create Thunderbit structs

  ## Usage

      # From text input
      {:ok, bits} = Builder.from_text("Is the area clear? Provision a PAC for Ezra.")

      # From voice with metadata
      {:ok, bits} = Builder.from_voice(transcript, confidence: 0.92)

      # With explicit source info
      {:ok, bits} = Builder.build("Check status", source: :system, owner: "crown")
  """

  alias Thunderline.Thundercore.Thunderbit

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Builds Thunderbits from text input.

  ## Options
  - `:owner` - Agent responsible for these bits
  - `:context` - Additional context map for tag extraction
  - `:min_energy` - Minimum energy threshold (default: 0.3)

  ## Examples

      iex> Builder.from_text("What is happening in the crash site?")
      {:ok, [%Thunderbit{kind: :question, ...}]}

      iex> Builder.from_text("Navigate to zone 4. Report status.")
      {:ok, [%Thunderbit{kind: :command, ...}, %Thunderbit{kind: :command, ...}]}
  """
  def from_text(text, opts \\ []) do
    build(text, Keyword.put(opts, :source, :text))
  end

  @doc """
  Builds Thunderbits from voice transcript.

  ## Options
  - `:confidence` - ASR confidence score (affects energy)
  - `:owner` - Agent responsible
  - `:context` - Additional context

  ## Examples

      iex> Builder.from_voice("Is Ezra online", confidence: 0.85)
      {:ok, [%Thunderbit{kind: :question, source: :voice, energy: 0.85, ...}]}
  """
  def from_voice(transcript, opts \\ []) do
    confidence = Keyword.get(opts, :confidence, 0.8)
    opts = opts |> Keyword.put(:source, :voice) |> Keyword.put(:base_energy, confidence)
    build(transcript, opts)
  end

  @doc """
  Generic builder with explicit options.

  ## Options
  - `:source` - Origin (:text, :voice, :system, :pac)
  - `:owner` - Responsible agent
  - `:context` - Context map for extraction
  - `:base_energy` - Starting energy value
  - `:min_energy` - Minimum energy threshold
  """
  def build(text, opts \\ []) when is_binary(text) do
    source = Keyword.get(opts, :source, :system)
    owner = Keyword.get(opts, :owner)
    context = Keyword.get(opts, :context, %{})
    base_energy = Keyword.get(opts, :base_energy, 0.7)
    min_energy = Keyword.get(opts, :min_energy, 0.3)

    text
    |> segment()
    |> Enum.map(fn segment ->
      kind = classify(segment)
      tags = extract_tags(segment, context)
      energy = calculate_energy(segment, base_energy)
      salience = calculate_salience(segment, kind, tags)

      if energy >= min_energy do
        Thunderbit.new!(
          kind: kind,
          source: source,
          content: segment,
          tags: tags,
          energy: energy,
          salience: salience,
          owner: owner
        )
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> then(&{:ok, &1})
  end

  @doc """
  Builds a single Thunderbit from explicit parameters.
  Useful for system-generated bits.
  """
  def single(kind, content, opts \\ []) do
    Thunderbit.new(Keyword.merge(opts, kind: kind, content: content))
  end

  # ===========================================================================
  # Segmentation
  # ===========================================================================

  @doc """
  Segments text into semantic chunks.

  Rules:
  1. Split on sentence boundaries (.!?)
  2. Split on conjunctions that introduce new actions (", and then", ", then")
  3. Keep commands together even if they have multiple parts
  """
  def segment(text) when is_binary(text) do
    text
    |> String.trim()
    |> split_sentences()
    |> Enum.flat_map(&split_conjunctions/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_sentences(text) do
    # Split on sentence-ending punctuation, keeping the punctuation
    Regex.split(~r/(?<=[.!?])\s+/, text, trim: true)
  end

  defp split_conjunctions(segment) do
    # Split on conjunction patterns that typically introduce new semantic units
    patterns = [
      ~r/,\s*and\s+then\s+/i,
      ~r/,\s*then\s+/i,
      ~r/;\s+/
    ]

    Enum.reduce(patterns, [segment], fn pattern, segments ->
      Enum.flat_map(segments, fn s ->
        Regex.split(pattern, s, trim: true)
      end)
    end)
  end

  # ===========================================================================
  # Classification
  # ===========================================================================

  @question_patterns [
    ~r/^(what|who|where|when|why|how|is|are|can|could|would|should|do|does|did|will|has|have)\s/i,
    ~r/\?$/
  ]

  @command_patterns [
    ~r/^(provision|create|spawn|deploy|start|stop|navigate|go|move|run|execute|check|verify|report|send|broadcast|update|set|configure)\s/i,
    ~r/^(do|make|build|generate|compute|calculate|find|search|scan|monitor|watch|track)\s/i
  ]

  @goal_patterns [
    ~r/^(ensure|maintain|keep|achieve|reach|complete|finish|maximize|minimize|optimize)\s/i,
    ~r/(should be|must be|needs to be|has to be)/i
  ]

  @memory_patterns [
    ~r/^(remember|recall|note|log|record|save|store)\s/i,
    ~r/(previously|earlier|before|last time|in the past)/i
  ]

  @doc """
  Classifies a text segment into a Thunderbit kind.
  """
  def classify(segment) when is_binary(segment) do
    segment = String.trim(segment)

    cond do
      matches_any?(segment, @question_patterns) -> :question
      matches_any?(segment, @command_patterns) -> :command
      matches_any?(segment, @goal_patterns) -> :goal
      matches_any?(segment, @memory_patterns) -> :memory
      String.contains?(segment, ["error", "failed", "exception"]) -> :error
      true -> :intent
    end
  end

  defp matches_any?(text, patterns) do
    Enum.any?(patterns, fn pattern ->
      Regex.match?(pattern, text)
    end)
  end

  # ===========================================================================
  # Tag Extraction
  # ===========================================================================

  @pac_pattern ~r/\b(PAC[:\s_-]?)(\w+)\b/i
  @zone_pattern ~r/\b(zone[:\s_-]?)(\w+)\b/i
  @topic_keywords ~w(dag telemetry policy memory evolution traits behavior graph orchestration)

  @doc """
  Extracts tags from a text segment.

  Tags are formatted as:
  - "PAC:Name" for PAC references
  - "zone:name" for zone references
  - "topic:keyword" for detected topics
  """
  def extract_tags(segment, context \\ %{}) do
    pac_tags = extract_pac_tags(segment)
    zone_tags = extract_zone_tags(segment)
    topic_tags = extract_topic_tags(segment)
    context_tags = extract_context_tags(context)

    (pac_tags ++ zone_tags ++ topic_tags ++ context_tags)
    |> Enum.uniq()
  end

  defp extract_pac_tags(segment) do
    @pac_pattern
    |> Regex.scan(segment)
    |> Enum.map(fn
      [_, _, name] -> "PAC:#{String.capitalize(name)}"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_zone_tags(segment) do
    @zone_pattern
    |> Regex.scan(segment)
    |> Enum.map(fn
      [_, _, name] -> "zone:#{String.downcase(name)}"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_topic_tags(segment) do
    segment_lower = String.downcase(segment)

    @topic_keywords
    |> Enum.filter(&String.contains?(segment_lower, &1))
    |> Enum.map(&"topic:#{&1}")
  end

  defp extract_context_tags(%{pac: pac}) when is_binary(pac), do: ["PAC:#{pac}"]
  defp extract_context_tags(%{zone: zone}) when is_binary(zone), do: ["zone:#{zone}"]
  defp extract_context_tags(_), do: []

  # ===========================================================================
  # Energy & Salience Calculation
  # ===========================================================================

  @doc """
  Calculates energy score for a segment.

  Factors:
  - Base energy (from source confidence)
  - Length (longer = slightly more energy)
  - Specificity (named entities = more energy)
  - Punctuation emphasis (! = more energy)
  """
  def calculate_energy(segment, base_energy \\ 0.7) do
    length_factor = min(String.length(segment) / 100, 0.15)
    entity_factor = if has_named_entities?(segment), do: 0.1, else: 0.0
    emphasis_factor = if String.contains?(segment, "!"), do: 0.05, else: 0.0

    (base_energy + length_factor + entity_factor + emphasis_factor)
    |> min(1.0)
    |> max(0.0)
    |> Float.round(2)
  end

  @doc """
  Calculates salience (attention priority) for a segment.

  Factors:
  - Kind (questions/commands = higher salience)
  - Tag count (more specific = more salient)
  - Urgency indicators
  """
  def calculate_salience(segment, kind, tags) do
    kind_factor =
      case kind do
        :command -> 0.8
        :question -> 0.7
        :goal -> 0.6
        :error -> 0.9
        _ -> 0.5
      end

    tag_factor = min(length(tags) * 0.05, 0.2)
    urgency_factor = if urgent?(segment), do: 0.15, else: 0.0

    (kind_factor + tag_factor + urgency_factor)
    |> min(1.0)
    |> max(0.0)
    |> Float.round(2)
  end

  defp has_named_entities?(segment) do
    Regex.match?(@pac_pattern, segment) or
      Regex.match?(@zone_pattern, segment) or
      Regex.match?(~r/\b[A-Z][a-z]+\s+[A-Z][a-z]+\b/, segment)
  end

  defp urgent?(segment) do
    segment_lower = String.downcase(segment)

    String.contains?(segment_lower, ["urgent", "immediately", "now", "asap", "critical"]) or
      String.contains?(segment, "!")
  end

  # ===========================================================================
  # Batch Operations
  # ===========================================================================

  @doc """
  Builds multiple Thunderbits from a list of text inputs.
  """
  def batch(texts, opts \\ []) when is_list(texts) do
    results =
      texts
      |> Enum.map(&build(&1, opts))
      |> Enum.map(fn
        {:ok, bits} -> bits
        _ -> []
      end)
      |> List.flatten()

    {:ok, results}
  end

  @doc """
  Merges related Thunderbits by linking them together.
  Bits with overlapping tags get bidirectional links.
  """
  def link_related(bits) when is_list(bits) do
    bits
    |> Enum.with_index()
    |> Enum.map(fn {bit, idx} ->
      related_ids =
        bits
        |> Enum.with_index()
        |> Enum.filter(fn {other, other_idx} ->
          idx != other_idx and tags_overlap?(bit.tags, other.tags)
        end)
        |> Enum.map(fn {other, _} -> other.id end)

      Enum.reduce(related_ids, bit, &Thunderbit.add_link(&2, &1))
    end)
  end

  defp tags_overlap?(tags1, tags2) do
    not Enum.empty?(tags1 -- (tags1 -- tags2))
  end
end
