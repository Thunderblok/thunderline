defmodule Thunderline.Thunderbit.Thundercell do
  @moduledoc """
  Raw Substrate Chunk in the Thunderline Data Universe

  Thundercells are the actual payload blocks that Thunderbits reference.
  Think of Thundercells as raw file chunks, dataset batches, embedding blocks,
  or CA grid cells — the substrate upon which symbolic Thunderbits operate.

  ## Core Insight

  > "Thunderbits are not the data. Thunderbits are the semantic tags & roles
  > that sit on top of the data."

  This separation enables:
  - 10k data rows = 10k Thundercells, but only 5-10 Thunderbits (semantic roles)
  - Clean separation between "what the system is thinking" vs "what the data actually is"
  - Many-to-many relationship: one Thunderbit can span multiple Thundercells

  ## Kind Taxonomy

  | Kind              | Description               | Typical Source                    | Use Case           |
  |-------------------|---------------------------|-----------------------------------|--------------------|
  | `:file_chunk`     | Byte range from file      | `"s3://bucket/file.bin"`          | Large file proc    |
  | `:dataset_batch`  | Rows from dataset         | `"postgres://table#offset=1000"`  | Batch ML training  |
  | `:embedding_block`| Pre-computed vectors      | `"vector_store://collection"`     | Similarity search  |
  | `:ca_cell`        | CA lattice cell state     | `"ca://world_id/tick/coord"`      | Cellular automaton |
  | `:audio_window`   | Audio sample window       | `"audio://stream/timestamp"`      | Real-time audio    |
  | `:video_frame`    | Video frame data          | `"video://stream/frame_id"`       | Video processing   |
  | `:token_block`    | Token sequence            | `"tokens://doc_id/range"`         | LLM context        |
  | `:state_snapshot` | Serialized state          | `"snapshot://pac_id/version"`     | PAC checkpoints    |

  ## Usage

      # Create a file chunk cell
      cell = Thundercell.new(:file_chunk, "s3://my-bucket/data.bin", {0, 1024},
        stats: %{size: 1024, hash: "abc123"}
      )

      # Create an embedding block
      embedding = Nx.tensor([0.1, 0.2, 0.3])
      cell = Thundercell.new(:embedding_block, "vector_store://docs", {100, 200},
        embedding: embedding
      )

      # Create a CA cell
      cell = Thundercell.new(:ca_cell, "ca://world-1/tick-42", {0, 0},
        ca_coord: {10, 20, 5},
        payload_ref: {:inline, <<1, 0, 1, 1>>}
      )
  """

  @type kind ::
          :file_chunk
          | :dataset_batch
          | :embedding_block
          | :ca_cell
          | :audio_window
          | :video_frame
          | :token_block
          | :state_snapshot

  @type payload_ref ::
          {:inline, binary()}
          | {:ets, reference()}
          | {:external, String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          source: String.t(),
          range: {non_neg_integer(), non_neg_integer()},
          payload_ref: payload_ref(),
          embedding: Nx.Tensor.t() | nil,
          ca_coord: {integer(), integer(), integer()} | nil,
          stats: map(),
          meta: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :kind, :source, :range]
  defstruct [
    :id,
    :kind,
    :source,
    :range,
    :payload_ref,
    :embedding,
    :ca_coord,
    :inserted_at,
    :updated_at,
    stats: %{},
    meta: %{}
  ]

  @valid_kinds [
    :file_chunk,
    :dataset_batch,
    :embedding_block,
    :ca_cell,
    :audio_window,
    :video_frame,
    :token_block,
    :state_snapshot
  ]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new Thundercell with validated fields.

  ## Parameters

  - `kind` - The cell kind (see Kind Taxonomy)
  - `source` - Origin reference (file path, dataset ID, etc.)
  - `range` - Byte/index range as `{start, end}` tuple
  - `opts` - Optional fields:
    - `:payload_ref` - Where payload is stored (default: `{:inline, <<>>}`)
    - `:embedding` - Optional embedding vector (Nx tensor)
    - `:ca_coord` - CA lattice position as `{x, y, z}` tuple
    - `:stats` - Size, hash, compression ratio, etc.
    - `:meta` - Extensible metadata

  ## Returns

  - `{:ok, %Thundercell{}}` on success
  - `{:error, reason}` on validation failure

  ## Examples

      {:ok, cell} = Thundercell.new(:file_chunk, "s3://bucket/file.bin", {0, 1024})

      {:ok, cell} = Thundercell.new(:ca_cell, "ca://world-1/tick-42", {0, 0},
        ca_coord: {10, 20, 5}
      )
  """
  @spec new(kind(), String.t(), {non_neg_integer(), non_neg_integer()}, keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(kind, source, range, opts \\ [])

  def new(kind, source, {start, finish} = range, opts)
      when kind in @valid_kinds and
             is_binary(source) and
             is_integer(start) and start >= 0 and
             is_integer(finish) and finish >= start do
    now = DateTime.utc_now()

    cell = %__MODULE__{
      id: Thunderline.UUID.v7(),
      kind: kind,
      source: source,
      range: range,
      payload_ref: Keyword.get(opts, :payload_ref, {:inline, <<>>}),
      embedding: validate_embedding(Keyword.get(opts, :embedding)),
      ca_coord: validate_ca_coord(Keyword.get(opts, :ca_coord)),
      stats: Keyword.get(opts, :stats, %{}),
      meta: Keyword.get(opts, :meta, %{}),
      inserted_at: now,
      updated_at: now
    }

    {:ok, cell}
  end

  def new(kind, _source, _range, _opts) when kind not in @valid_kinds do
    {:error, {:invalid_kind, kind, @valid_kinds}}
  end

  def new(_kind, source, _range, _opts) when not is_binary(source) do
    {:error, {:invalid_source, "source must be a string"}}
  end

  def new(_kind, _source, range, _opts) do
    {:error, {:invalid_range, range}}
  end

  @doc """
  Creates a new Thundercell, raising on validation failure.

  See `new/4` for parameters.
  """
  @spec new!(kind(), String.t(), {non_neg_integer(), non_neg_integer()}, keyword()) :: t()
  def new!(kind, source, range, opts \\ []) do
    case new(kind, source, range, opts) do
      {:ok, cell} -> cell
      {:error, reason} -> raise ArgumentError, "Invalid Thundercell: #{inspect(reason)}"
    end
  end

  # ===========================================================================
  # Payload Access
  # ===========================================================================

  @doc """
  Retrieves the payload data from a Thundercell.

  ## Returns

  - `{:ok, binary}` - The payload data
  - `{:error, reason}` - If payload cannot be retrieved

  ## Examples

      {:ok, data} = Thundercell.get_payload(cell)
  """
  @spec get_payload(t()) :: {:ok, binary()} | {:error, term()}
  def get_payload(%__MODULE__{payload_ref: {:inline, data}}) when is_binary(data) do
    {:ok, data}
  end

  def get_payload(%__MODULE__{payload_ref: {:ets, table_ref}}) do
    case :ets.lookup(table_ref, :payload) do
      [{:payload, data}] -> {:ok, data}
      [] -> {:error, :payload_not_found}
    end
  rescue
    ArgumentError -> {:error, :ets_table_not_found}
  end

  def get_payload(%__MODULE__{payload_ref: {:external, uri}}) do
    # External payloads require I/O - return reference for caller to handle
    {:external, uri}
  end

  @doc """
  Sets the payload data for a Thundercell.

  ## Parameters

  - `cell` - The Thundercell to update
  - `data` - Binary payload data
  - `storage` - Storage type: `:inline` (default) or `:ets`

  ## Returns

  Updated Thundercell struct.
  """
  @spec set_payload(t(), binary(), :inline | :ets) :: t()
  def set_payload(%__MODULE__{} = cell, data, storage \\ :inline) when is_binary(data) do
    payload_ref =
      case storage do
        :inline ->
          {:inline, data}

        :ets ->
          table = :ets.new(:thundercell_payload, [:set, :protected])
          :ets.insert(table, {:payload, data})
          {:ets, table}
      end

    %{cell | payload_ref: payload_ref, updated_at: DateTime.utc_now()}
  end

  # ===========================================================================
  # Stats and Metadata
  # ===========================================================================

  @doc """
  Updates the stats map for a Thundercell.
  """
  @spec update_stats(t(), map()) :: t()
  def update_stats(%__MODULE__{} = cell, new_stats) when is_map(new_stats) do
    %{cell | stats: Map.merge(cell.stats, new_stats), updated_at: DateTime.utc_now()}
  end

  @doc """
  Updates the meta map for a Thundercell.
  """
  @spec update_meta(t(), map()) :: t()
  def update_meta(%__MODULE__{} = cell, new_meta) when is_map(new_meta) do
    %{cell | meta: Map.merge(cell.meta, new_meta), updated_at: DateTime.utc_now()}
  end

  @doc """
  Returns the size of the cell's range.
  """
  @spec range_size(t()) :: non_neg_integer()
  def range_size(%__MODULE__{range: {start, finish}}) do
    finish - start
  end

  # ===========================================================================
  # Embedding Operations
  # ===========================================================================

  @doc """
  Sets the embedding vector for a Thundercell.
  """
  @spec set_embedding(t(), Nx.Tensor.t()) :: t()
  def set_embedding(%__MODULE__{} = cell, embedding) do
    %{cell | embedding: embedding, updated_at: DateTime.utc_now()}
  end

  @doc """
  Checks if the cell has an embedding.
  """
  @spec has_embedding?(t()) :: boolean()
  def has_embedding?(%__MODULE__{embedding: nil}), do: false
  def has_embedding?(%__MODULE__{embedding: _}), do: true

  # ===========================================================================
  # CA Coordinate Operations
  # ===========================================================================

  @doc """
  Sets the CA coordinate for a Thundercell.
  """
  @spec set_ca_coord(t(), {integer(), integer(), integer()}) :: t()
  def set_ca_coord(%__MODULE__{} = cell, {x, y, z} = coord)
      when is_integer(x) and is_integer(y) and is_integer(z) do
    %{cell | ca_coord: coord, updated_at: DateTime.utc_now()}
  end

  @doc """
  Checks if the cell is a CA cell type with coordinates.
  """
  @spec ca_cell?(t()) :: boolean()
  def ca_cell?(%__MODULE__{kind: :ca_cell, ca_coord: coord}) when is_tuple(coord), do: true
  def ca_cell?(%__MODULE__{}), do: false

  # ===========================================================================
  # Serialization
  # ===========================================================================

  @doc """
  Converts a Thundercell to a map for serialization.

  Note: Embeddings are converted to lists, ETS refs are converted to :external.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = cell) do
    %{
      id: cell.id,
      kind: cell.kind,
      source: cell.source,
      range: cell.range,
      payload_ref: serialize_payload_ref(cell.payload_ref),
      embedding: serialize_embedding(cell.embedding),
      ca_coord: cell.ca_coord,
      stats: cell.stats,
      meta: cell.meta,
      inserted_at: DateTime.to_iso8601(cell.inserted_at),
      updated_at: DateTime.to_iso8601(cell.updated_at)
    }
  end

  @doc """
  Restores a Thundercell from a map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    kind = parse_kind(map["kind"] || map[:kind])
    source = map["source"] || map[:source]
    range = parse_range(map["range"] || map[:range])

    case {kind, source, range} do
      {{:ok, k}, s, {:ok, r}} when is_binary(s) ->
        {:ok,
         %__MODULE__{
           id: map["id"] || map[:id] || Thunderline.UUID.v7(),
           kind: k,
           source: s,
           range: r,
           payload_ref: deserialize_payload_ref(map["payload_ref"] || map[:payload_ref]),
           embedding: deserialize_embedding(map["embedding"] || map[:embedding]),
           ca_coord: map["ca_coord"] || map[:ca_coord],
           stats: map["stats"] || map[:stats] || %{},
           meta: map["meta"] || map[:meta] || %{},
           inserted_at: parse_datetime(map["inserted_at"] || map[:inserted_at]),
           updated_at: parse_datetime(map["updated_at"] || map[:updated_at])
         }}

      {{:error, reason}, _, _} ->
        {:error, reason}

      {_, _, {:error, reason}} ->
        {:error, reason}

      _ ->
        {:error, :invalid_map}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_embedding(nil), do: nil

  defp validate_embedding(tensor) do
    if is_struct(tensor, Nx.Tensor) do
      tensor
    else
      nil
    end
  end

  defp validate_ca_coord(nil), do: nil

  defp validate_ca_coord({x, y, z} = coord)
       when is_integer(x) and is_integer(y) and is_integer(z) do
    coord
  end

  defp validate_ca_coord(_), do: nil

  defp serialize_payload_ref({:inline, _data}), do: "inline"
  defp serialize_payload_ref({:ets, _ref}), do: "ets"
  defp serialize_payload_ref({:external, uri}), do: uri

  defp deserialize_payload_ref("inline"), do: {:inline, <<>>}
  defp deserialize_payload_ref("ets"), do: {:inline, <<>>}
  defp deserialize_payload_ref(uri) when is_binary(uri), do: {:external, uri}
  defp deserialize_payload_ref(_), do: {:inline, <<>>}

  defp serialize_embedding(nil), do: nil
  defp serialize_embedding(tensor), do: Nx.to_list(tensor)

  defp deserialize_embedding(nil), do: nil
  defp deserialize_embedding(list) when is_list(list), do: Nx.tensor(list)
  defp deserialize_embedding(_), do: nil

  defp parse_kind(kind) when is_atom(kind) and kind in @valid_kinds, do: {:ok, kind}
  defp parse_kind(kind) when is_binary(kind), do: parse_kind(String.to_existing_atom(kind))
  defp parse_kind(kind), do: {:error, {:invalid_kind, kind}}

  defp parse_range({start, finish}) when is_integer(start) and is_integer(finish) do
    {:ok, {start, finish}}
  end

  defp parse_range([start, finish]) when is_integer(start) and is_integer(finish) do
    {:ok, {start, finish}}
  end

  defp parse_range(other), do: {:error, {:invalid_range, other}}

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
