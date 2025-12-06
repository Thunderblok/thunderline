defmodule Thunderline.Forge.Encoder do
  @moduledoc """
  Thunderforge-lite Encoder

  Extracts feature vectors from Thundercell content using Nx.
  Supports multiple encoding strategies from simple bag-of-words to neural embeddings.

  ## Encoding Strategies

  - **:bow** - Bag of words (TF-IDF style, lightweight)
  - **:ngram** - Character n-grams (good for code)
  - **:structural** - Structural features (line count, tokens, etc.)
  - **:combined** - All of the above concatenated
  - **:embedding** - Neural embeddings via Bumblebee (heavy, optional)

  ## Architecture

  ```
  Parser output (cell maps)
       │
       ▼
  Encoder.encode(cells, strategy)
       │
       ▼
  cells with :features populated
       │
       ▼
  Thundercell persistence
  ```

  ## Usage

  ```elixir
  # Encode with default strategy
  encoded = Encoder.encode(cells)

  # Encode with specific strategy
  encoded = Encoder.encode(cells, strategy: :ngram)

  # Batch encode for efficiency
  encoded = Encoder.encode_batch(cells, batch_size: 32)
  ```
  """

  require Nx

  @default_strategy :combined
  @default_vocab_size 256
  @default_ngram_size 3
  @default_feature_dim 64

  @doc """
  Encode a list of cell maps, adding :features to each.

  ## Options

    * `:strategy` - Encoding strategy (default: :combined)
    * `:vocab_size` - Size of vocabulary for BoW (default: 256)
    * `:ngram_size` - N for character n-grams (default: 3)
    * `:feature_dim` - Output feature dimension (default: 64)

  ## Examples

      cells = Parser.parse_content(content, :markdown, "doc.md")
      encoded = Encoder.encode(cells, strategy: :bow)
  """
  @spec encode([map()], keyword()) :: [map()]
  def encode(cells, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)

    Enum.map(cells, fn cell ->
      features = encode_cell(cell, strategy, opts)
      Map.put(cell, :features, features)
    end)
  end

  @doc """
  Encode cells in batches for better performance.

  ## Options

    * `:batch_size` - Number of cells per batch (default: 32)
    * Other options passed to `encode/2`
  """
  @spec encode_batch([map()], keyword()) :: [map()]
  def encode_batch(cells, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 32)

    cells
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      encode(batch, opts)
    end)
  end

  @doc """
  Encode a single cell, returning the feature vector as a list of floats.
  """
  @spec encode_cell(map(), atom(), keyword()) :: [float()]
  def encode_cell(cell, strategy, opts \\ [])

  def encode_cell(cell, :bow, opts) do
    vocab_size = Keyword.get(opts, :vocab_size, @default_vocab_size)
    raw = Map.get(cell, :raw, "")

    raw
    |> tokenize()
    |> bow_features(vocab_size)
  end

  def encode_cell(cell, :ngram, opts) do
    ngram_size = Keyword.get(opts, :ngram_size, @default_ngram_size)
    feature_dim = Keyword.get(opts, :feature_dim, @default_feature_dim)
    raw = Map.get(cell, :raw, "")

    raw
    |> char_ngrams(ngram_size)
    |> ngram_features(feature_dim)
  end

  def encode_cell(cell, :structural, opts) do
    feature_dim = Keyword.get(opts, :feature_dim, @default_feature_dim)
    structural_features(cell, feature_dim)
  end

  def encode_cell(cell, :combined, opts) do
    # Combine all strategies
    bow = encode_cell(cell, :bow, Keyword.put(opts, :vocab_size, 32))
    ngram = encode_cell(cell, :ngram, Keyword.put(opts, :feature_dim, 16))
    structural = encode_cell(cell, :structural, Keyword.put(opts, :feature_dim, 16))

    # Concatenate all features
    bow ++ ngram ++ structural
  end

  def encode_cell(_cell, :embedding, _opts) do
    # Placeholder for Bumblebee embeddings
    # TODO: Implement when we add the embedding model
    List.duplicate(0.0, @default_feature_dim)
  end

  # Private encoding functions

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp bow_features(tokens, vocab_size) do
    # Simple hash-based BoW (no vocabulary needed)
    counts =
      tokens
      |> Enum.frequencies()
      |> Enum.map(fn {token, count} ->
        bucket = :erlang.phash2(token, vocab_size)
        {bucket, count}
      end)
      |> Enum.reduce(List.duplicate(0.0, vocab_size), fn {bucket, count}, acc ->
        List.update_at(acc, bucket, &(&1 + count))
      end)

    # L2 normalize
    normalize_l2(counts)
  end

  defp char_ngrams(text, n) do
    text
    |> String.downcase()
    |> String.graphemes()
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.map(&Enum.join/1)
  end

  defp ngram_features(ngrams, feature_dim) do
    # Hash n-grams into fixed-size feature vector
    counts =
      ngrams
      |> Enum.frequencies()
      |> Enum.map(fn {ngram, count} ->
        bucket = :erlang.phash2(ngram, feature_dim)
        {bucket, count}
      end)
      |> Enum.reduce(List.duplicate(0.0, feature_dim), fn {bucket, count}, acc ->
        List.update_at(acc, bucket, &(&1 + count))
      end)

    # L2 normalize
    normalize_l2(counts)
  end

  defp structural_features(cell, feature_dim) do
    raw = Map.get(cell, :raw, "")
    kind = Map.get(cell, :kind, :unknown)
    structure = Map.get(cell, :structure, %{})

    # Basic statistics
    char_count = String.length(raw)
    line_count = length(String.split(raw, "\n"))
    word_count = length(tokenize(raw))
    avg_line_length = if line_count > 0, do: char_count / line_count, else: 0.0

    # Kind encoding (one-hot style)
    kind_features = kind_to_features(kind)

    # Structure features
    struct_features = structure_to_features(structure)

    # Combine and pad/truncate to feature_dim
    features =
      [
        # Normalized statistics (log scale for count features)
        :math.log(char_count + 1) / 10,
        :math.log(line_count + 1) / 5,
        :math.log(word_count + 1) / 8,
        avg_line_length / 100
      ] ++ kind_features ++ struct_features

    # Pad or truncate to feature_dim
    features
    |> Enum.take(feature_dim)
    |> then(fn f ->
      padding = feature_dim - length(f)

      if padding > 0 do
        f ++ List.duplicate(0.0, padding)
      else
        f
      end
    end)
  end

  defp kind_to_features(kind) do
    kinds = [:text, :markdown, :log, :json, :code, :blob, :embedding, :ca_cell]

    Enum.map(kinds, fn k ->
      if k == kind, do: 1.0, else: 0.0
    end)
  end

  defp structure_to_features(structure) when is_map(structure) do
    # Extract some common structure features
    [
      # Has timestamp (for logs)
      if(Map.get(structure, :timestamp), do: 1.0, else: 0.0),
      # Has level (for logs)
      case Map.get(structure, :level) do
        :error -> 1.0
        :warn -> 0.5
        :info -> 0.25
        _ -> 0.0
      end,
      # Is parse error
      if(Map.get(structure, :parse_error), do: 1.0, else: 0.0),
      # Language encoding for code
      case Map.get(structure, :language) do
        :elixir -> 0.2
        :python -> 0.4
        :javascript -> 0.6
        :typescript -> 0.8
        _ -> 0.0
      end
    ]
  end

  defp structure_to_features(_), do: [0.0, 0.0, 0.0, 0.0]

  defp normalize_l2(vector) do
    tensor = Nx.tensor(vector)
    norm = Nx.LinAlg.norm(tensor) |> Nx.to_number()

    if norm > 0 do
      Enum.map(vector, &(&1 / norm))
    else
      vector
    end
  end

  @doc """
  Compute cosine similarity between two feature vectors.

  ## Examples

      sim = Encoder.cosine_similarity(features1, features2)
      # => 0.85
  """
  @spec cosine_similarity([float()], [float()]) :: float()
  def cosine_similarity(v1, v2) when length(v1) == length(v2) do
    t1 = Nx.tensor(v1)
    t2 = Nx.tensor(v2)

    dot = Nx.dot(t1, t2) |> Nx.to_number()
    norm1 = Nx.LinAlg.norm(t1) |> Nx.to_number()
    norm2 = Nx.LinAlg.norm(t2) |> Nx.to_number()

    if norm1 > 0 and norm2 > 0 do
      dot / (norm1 * norm2)
    else
      0.0
    end
  end

  def cosine_similarity(_, _), do: 0.0

  @doc """
  Find the most similar cells to a query cell.

  ## Examples

      similar = Encoder.find_similar(query_cell, all_cells, top_k: 5)
  """
  @spec find_similar(map(), [map()], keyword()) :: [{map(), float()}]
  def find_similar(query_cell, cells, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, 10)
    query_features = Map.get(query_cell, :features, [])

    if query_features == [] do
      []
    else
      cells
      |> Enum.map(fn cell ->
        cell_features = Map.get(cell, :features, [])
        sim = cosine_similarity(query_features, cell_features)
        {cell, sim}
      end)
      |> Enum.sort_by(fn {_, sim} -> -sim end)
      |> Enum.take(top_k)
    end
  end
end
