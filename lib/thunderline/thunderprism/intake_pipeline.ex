defmodule Thunderline.Thunderprism.IntakePipeline do
  @moduledoc """
  Text-to-Thunderbit Intake Pipeline (HC-Δ-5.3)

  Transforms raw text input into Thunderbits with proper categorization,
  edge linking, and geometry assignment for visualization in the Thunderfield.

  ## Pipeline Flow

  1. **Parse** - Split text into meaningful chunks
  2. **Classify** - Assign categories to each chunk
  3. **Link** - Create edges between related chunks
  4. **Position** - Assign geometry for visualization
  5. **Broadcast** - Push to LiveView via PubSub

  ## Usage

      # Single sentence intake
      {:ok, bits} = IntakePipeline.process("The weather is nice today")

      # With context/session
      {:ok, bits} = IntakePipeline.process(text, %{session_id: "abc", pac_id: "pac1"})

      # Stream intake (returns immediately, bits trickle in)
      :ok = IntakePipeline.stream("Long document...", callback_fn)

  ## Design Philosophy

  - **MVP First**: Start with simple sentence splitting and keyword categorization
  - **Extensible**: Hooks for future ML-based classification and embedding
  - **Non-blocking**: Broadcasts results as they're processed
  """

  alias Thunderline.Thunderbit.{Edge, UIContract}
  alias Thunderline.UUID
  require Logger

  # ===========================================================================
  # Types
  # ===========================================================================

  @type intake_opts :: %{
          optional(:session_id) => String.t(),
          optional(:pac_id) => String.t(),
          optional(:broadcast?) => boolean(),
          optional(:link_sequential?) => boolean()
        }

  @type intake_result :: %{
          bits: [map()],
          edges: [Edge.t()],
          stats: %{
            total_chunks: non_neg_integer(),
            processing_time_ms: non_neg_integer()
          }
        }

  # ===========================================================================
  # Main API
  # ===========================================================================

  @doc """
  Process text input into Thunderbits.

  ## Parameters

  - `text` - Raw text input
  - `opts` - Processing options:
    - `:session_id` - Session identifier for grouping bits
    - `:pac_id` - PAC controller ID for attribution
    - `:broadcast?` - Whether to broadcast results (default: true)
    - `:link_sequential?` - Create edges between sequential bits (default: true)

  ## Returns

  `{:ok, result}` with bits, edges, and processing stats.

  ## Examples

      {:ok, result} = IntakePipeline.process("Hello world")
      # => %{bits: [%{id: "...", category: :cognitive, ...}], edges: [], stats: %{...}}
  """
  @spec process(String.t(), intake_opts()) :: {:ok, intake_result()} | {:error, term()}
  def process(text, opts \\ %{}) when is_binary(text) do
    start_time = System.monotonic_time(:millisecond)
    session_id = Map.get(opts, :session_id, UUID.v7())
    broadcast? = Map.get(opts, :broadcast?, true)
    link_sequential? = Map.get(opts, :link_sequential?, true)

    :telemetry.execute(
      [:thunderline, :thunderprism, :intake, :start],
      %{text_length: byte_size(text)},
      %{session_id: session_id}
    )

    try do
      # Step 1: Parse into chunks
      chunks = parse_chunks(text)

      # Step 2: Classify and create bits
      bits =
        chunks
        |> Enum.with_index()
        |> Enum.map(fn {chunk, idx} ->
          create_bit(chunk, idx, session_id, opts)
        end)

      # Step 3: Link sequential bits if requested
      edges =
        if link_sequential? and length(bits) > 1 do
          create_sequential_edges(bits)
        else
          []
        end

      # Step 4: Broadcast if requested
      if broadcast? do
        UIContract.broadcast(bits, edges, :created)
      end

      processing_time = System.monotonic_time(:millisecond) - start_time

      :telemetry.execute(
        [:thunderline, :thunderprism, :intake, :complete],
        %{
          processing_time_ms: processing_time,
          bit_count: length(bits),
          edge_count: length(edges)
        },
        %{session_id: session_id}
      )

      result = %{
        bits: bits,
        edges: edges,
        stats: %{
          total_chunks: length(chunks),
          processing_time_ms: processing_time
        }
      }

      {:ok, result}
    rescue
      error ->
        Logger.error("IntakePipeline processing failed",
          error: Exception.format(:error, error, __STACKTRACE__),
          text_preview: String.slice(text, 0, 100)
        )

        :telemetry.execute(
          [:thunderline, :thunderprism, :intake, :error],
          %{count: 1},
          %{session_id: session_id, error: Exception.message(error)}
        )

        {:error, error}
    end
  end

  @doc """
  Process text as a stream, invoking callback as bits are created.

  Useful for long documents where you want progressive updates.

  ## Parameters

  - `text` - Raw text input
  - `callback` - Function called with each bit: `fn bit -> ... end`
  - `opts` - Processing options

  ## Returns

  `:ok` immediately. Bits are delivered via callback.
  """
  @spec stream(String.t(), (map() -> any()), intake_opts()) :: :ok
  def stream(text, callback, opts \\ %{}) when is_binary(text) and is_function(callback, 1) do
    session_id = Map.get(opts, :session_id, UUID.v7())

    Task.async(fn ->
      chunks = parse_chunks(text)
      prev_bit = nil

      Enum.reduce(chunks, {0, prev_bit}, fn chunk, {idx, prev} ->
        bit = create_bit(chunk, idx, session_id, opts)
        callback.(bit)

        # Create edge to previous if exists
        if prev do
          edge = create_edge(prev, bit)
          UIContract.broadcast_edge(edge)
        end

        # Broadcast the new bit
        UIContract.broadcast_one(bit)

        {idx + 1, bit}
      end)
    end)

    :ok
  end

  # ===========================================================================
  # Parsing
  # ===========================================================================

  @doc """
  Parse text into meaningful chunks.

  MVP implementation: sentence splitting with basic cleanup.
  Future: semantic chunking, NLP-based segmentation.
  """
  @spec parse_chunks(String.t()) :: [String.t()]
  def parse_chunks(text) do
    text
    |> String.trim()
    |> split_sentences()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&empty_chunk?/1)
  end

  defp split_sentences(text) do
    # Split on sentence boundaries: . ! ? followed by space or end
    # Preserve the punctuation with the sentence
    Regex.split(~r/(?<=[.!?])\s+/, text, trim: true)
  end

  defp empty_chunk?(chunk) do
    String.trim(chunk) == ""
  end

  # ===========================================================================
  # Classification
  # ===========================================================================

  @doc """
  Classify a text chunk into a Thunderbit category.

  MVP implementation: keyword-based classification.
  Future: ML-based classification, embedding similarity.
  """
  @spec classify(String.t()) :: atom()
  def classify(text) do
    lowered = String.downcase(text)

    cond do
      # Questions -> cognitive
      String.contains?(lowered, "?") ->
        :cognitive

      # Commands/imperatives -> motor
      Regex.match?(~r/^(please|do|make|create|run|execute|start|stop)/i, lowered) ->
        :motor

      # Memory references -> mnemonic
      Regex.match?(~r/(remember|recall|memory|previous|earlier|before)/i, lowered) ->
        :mnemonic

      # Ethical considerations -> ethical
      Regex.match?(~r/(should|must|ought|right|wrong|fair|ethical|moral)/i, lowered) ->
        :ethical

      # Social/communication -> social
      Regex.match?(~r/(say|tell|ask|communicate|message|respond)/i, lowered) ->
        :social

      # Perception/observation -> perceptual
      Regex.match?(~r/(see|hear|notice|observe|detect|sense)/i, lowered) ->
        :perceptual

      # External world -> sensory
      Regex.match?(~r/(weather|temperature|outside|environment|world)/i, lowered) ->
        :sensory

      # Default -> cognitive
      true ->
        :cognitive
    end
  end

  # ===========================================================================
  # Bit Creation
  # ===========================================================================

  defp create_bit(chunk, index, session_id, opts) do
    category = classify(chunk)
    pac_id = Map.get(opts, :pac_id)

    %{
      id: UUID.v7(),
      content: chunk,
      category: category,
      status: :spawned,
      energy: 1.0,
      salience: compute_salience(chunk, index),
      tags: extract_tags(chunk),
      position: compute_initial_position(index, category),
      session_id: session_id,
      pac_id: pac_id,
      inserted_at: DateTime.utc_now()
    }
  end

  defp compute_salience(chunk, index) do
    # First chunks are more salient, longer chunks are more salient
    length_factor = min(1.0, byte_size(chunk) / 100.0)
    position_factor = max(0.3, 1.0 - index * 0.1)

    Float.round(length_factor * position_factor, 2)
  end

  defp extract_tags(chunk) do
    # Extract capitalized words as potential tags
    Regex.scan(~r/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/, chunk)
    |> List.flatten()
    |> Enum.take(5)
  end

  defp compute_initial_position(index, category) do
    # Layer based on category
    layer = category_to_layer(category)

    # Spread bits in a spiral pattern
    angle = index * 0.5
    radius = 0.1 + index * 0.05

    %{
      x: 0.5 + radius * :math.cos(angle),
      y: 0.5 + radius * :math.sin(angle),
      z: layer * 0.1
    }
  end

  defp category_to_layer(:sensory), do: 0
  defp category_to_layer(:perceptual), do: 1
  defp category_to_layer(:cognitive), do: 2
  defp category_to_layer(:mnemonic), do: 3
  defp category_to_layer(:motor), do: 4
  defp category_to_layer(:social), do: 5
  defp category_to_layer(:ethical), do: 6
  defp category_to_layer(_), do: 2

  # ===========================================================================
  # Edge Creation
  # ===========================================================================

  defp create_sequential_edges(bits) do
    bits
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [bit1, bit2] ->
      create_edge(bit1, bit2)
    end)
  end

  defp create_edge(from_bit, to_bit) do
    %Edge{
      id: UUID.v7(),
      from_id: from_bit.id,
      to_id: to_bit.id,
      relation: :feeds,
      strength: 0.8
    }
  end
end
