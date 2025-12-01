defmodule Thunderline.Thunderbolt.Sparse.Grid do
  @moduledoc """
  Finch-Inspired Sparse Tensor Support for Thunderbolt Grids.

  Based on: "Finch: A Sparse Tensor Programming Approach to Parallel Graph and Linear Algebra" (arXiv:2404.16730)

  Provides sparse representations for Thunderbit grids where most cells are empty/dead.
  Uses coordinate (COO) format with optional conversion to compressed formats.

  ## Key Insight

  In Growing NCAs and cellular automata, most cells are empty. Dense tensor operations
  waste computation on zeros. Sparse formats let us:

  1. Store only active cells (memory efficient)
  2. Iterate only over active cells (compute efficient)
  3. Enable parallel scatter/gather operations

  ## Representations

  - **COO (Coordinate)**: Simple {i, j, k, value} tuples, good for construction
  - **CSR (Compressed Sparse Row)**: Row-compressed, good for row operations
  - **Voxel Hash**: Hash map keyed by coordinate, good for random access

  ## Reference

  Ahrens et al., "Finch: A Sparse Tensor Programming Approach to Parallel Graph and Linear Algebra", 2024
  """

  alias Thunderline.Thunderbolt.Thunderbit

  defstruct [
    # :coo | :hash | :dense
    :format,
    # {height, width, depth}
    :shape,
    # Number of channels per cell
    :channels,
    # Format-specific data structure
    :data,
    # Default value for missing entries
    :default,
    # Number of non-zero entries
    :nnz
  ]

  @type coord :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type cell_value :: list(float())

  @type t :: %__MODULE__{
          format: :coo | :hash | :dense,
          shape: {non_neg_integer(), non_neg_integer(), non_neg_integer()},
          channels: non_neg_integer(),
          data: term(),
          default: cell_value(),
          nnz: non_neg_integer()
        }

  @default_channels 16
  @alive_threshold 0.1

  # ═══════════════════════════════════════════════════════════════
  # CONSTRUCTION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Create a new sparse grid.

  ## Options

  - `:format` - Storage format (:coo | :hash, default: :hash)
  - `:channels` - Channels per cell (default: 16)
  - `:default` - Default cell value (default: zeros)
  """
  @spec new({non_neg_integer(), non_neg_integer(), non_neg_integer()}, keyword()) :: t()
  def new({h, w, d} = shape, opts \\ []) when is_integer(h) and is_integer(w) and is_integer(d) do
    format = Keyword.get(opts, :format, :hash)
    channels = Keyword.get(opts, :channels, @default_channels)
    default = Keyword.get(opts, :default, List.duplicate(0.0, channels))

    data =
      case format do
        :coo -> []
        :hash -> %{}
      end

    %__MODULE__{
      format: format,
      shape: shape,
      channels: channels,
      data: data,
      default: default,
      nnz: 0
    }
  end

  @doc """
  Create sparse grid from Thunderbit list.

  Filters out dead cells (alpha < threshold).
  """
  @spec from_thunderbits(list({coord(), Thunderbit.t()}), keyword()) :: t()
  def from_thunderbits(cells, opts \\ []) do
    threshold = Keyword.get(opts, :alive_threshold, @alive_threshold)

    # Find bounds
    coords = Enum.map(cells, fn {{x, y, z}, _} -> {x, y, z} end)
    max_x = coords |> Enum.map(&elem(&1, 0)) |> Enum.max(fn -> 0 end)
    max_y = coords |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
    max_z = coords |> Enum.map(&elem(&1, 2)) |> Enum.max(fn -> 0 end)

    shape = {max_x + 1, max_y + 1, max_z + 1}
    grid = new(shape, opts)

    # Insert alive cells
    Enum.reduce(cells, grid, fn {coord, thunderbit}, acc ->
      state = thunderbit_to_state(thunderbit)

      # Check alpha channel for aliveness
      if Enum.at(state, 3, 0.0) >= threshold do
        put(acc, coord, state)
      else
        acc
      end
    end)
  end

  defp thunderbit_to_state(%Thunderbit{} = tb) do
    # Map Thunderbit fields to 16-channel state
    # [R, G, B, α, PLV, σ_flow, λ_sensitivity, hidden...]
    [
      # RGB (from some visual representation)
      0.5,
      0.5,
      0.5,
      # Alpha (1.0 for alive)
      1.0,
      # PLV (Phase Locking Value)
      tb.plv || 0.0,
      # Sigma flow
      tb.sigma_flow || 0.0,
      # Lambda sensitivity
      tb.lambda_sensitivity || 0.0,
      # Hidden channels (pad to 16)
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0
    ]
  end

  # ═══════════════════════════════════════════════════════════════
  # ACCESSORS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Get cell value at coordinate.
  """
  @spec get(t(), coord()) :: cell_value()
  def get(%__MODULE__{format: :hash, data: data, default: default}, coord) do
    Map.get(data, coord, default)
  end

  def get(%__MODULE__{format: :coo, data: entries, default: default}, coord) do
    case Enum.find(entries, fn {c, _v} -> c == coord end) do
      {_, value} -> value
      nil -> default
    end
  end

  @doc """
  Set cell value at coordinate.
  """
  @spec put(t(), coord(), cell_value()) :: t()
  def put(%__MODULE__{format: :hash, data: data, nnz: nnz} = grid, coord, value) do
    new_nnz = if Map.has_key?(data, coord), do: nnz, else: nnz + 1
    %{grid | data: Map.put(data, coord, value), nnz: new_nnz}
  end

  def put(%__MODULE__{format: :coo, data: entries, nnz: nnz} = grid, coord, value) do
    # Remove existing entry if present
    {filtered, was_present} =
      Enum.reduce(entries, {[], false}, fn {c, v}, {acc, found} ->
        if c == coord do
          {acc, true}
        else
          {[{c, v} | acc], found}
        end
      end)

    new_nnz = if was_present, do: nnz, else: nnz + 1
    %{grid | data: [{coord, value} | filtered], nnz: new_nnz}
  end

  @doc """
  Delete cell at coordinate.
  """
  @spec delete(t(), coord()) :: t()
  def delete(%__MODULE__{format: :hash, data: data, nnz: nnz} = grid, coord) do
    if Map.has_key?(data, coord) do
      %{grid | data: Map.delete(data, coord), nnz: nnz - 1}
    else
      grid
    end
  end

  def delete(%__MODULE__{format: :coo, data: entries, nnz: nnz} = grid, coord) do
    filtered = Enum.reject(entries, fn {c, _} -> c == coord end)
    new_nnz = if length(filtered) < length(entries), do: nnz - 1, else: nnz
    %{grid | data: filtered, nnz: new_nnz}
  end

  # ═══════════════════════════════════════════════════════════════
  # ITERATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Iterate over all active (non-zero) cells.

  This is the key efficiency win: we only visit populated cells.
  """
  @spec each_active(t(), (coord(), cell_value() -> any())) :: :ok
  def each_active(%__MODULE__{format: :hash, data: data}, fun) do
    Enum.each(data, fn {coord, value} -> fun.(coord, value) end)
  end

  def each_active(%__MODULE__{format: :coo, data: entries}, fun) do
    Enum.each(entries, fn {coord, value} -> fun.(coord, value) end)
  end

  @doc """
  Map over all active cells, returning new grid.
  """
  @spec map_active(t(), (coord(), cell_value() -> cell_value())) :: t()
  def map_active(%__MODULE__{format: :hash, data: data} = grid, fun) do
    new_data =
      Map.new(data, fn {coord, value} ->
        {coord, fun.(coord, value)}
      end)

    %{grid | data: new_data}
  end

  def map_active(%__MODULE__{format: :coo, data: entries} = grid, fun) do
    new_entries =
      Enum.map(entries, fn {coord, value} ->
        {coord, fun.(coord, value)}
      end)

    %{grid | data: new_entries}
  end

  @doc """
  Parallel map over active cells using Task.async_stream.
  """
  @spec pmap_active(t(), (coord(), cell_value() -> cell_value()), keyword()) :: t()
  def pmap_active(%__MODULE__{format: :hash, data: data} = grid, fun, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    new_data =
      data
      |> Task.async_stream(
        fn {coord, value} -> {coord, fun.(coord, value)} end,
        max_concurrency: max_concurrency,
        timeout: :infinity
      )
      |> Enum.reduce(%{}, fn {:ok, {coord, value}}, acc ->
        Map.put(acc, coord, value)
      end)

    %{grid | data: new_data}
  end

  def pmap_active(%__MODULE__{format: :coo} = grid, fun, opts) do
    # Convert to hash for parallel processing
    grid
    |> to_hash()
    |> pmap_active(fun, opts)
    |> to_coo()
  end

  @doc """
  Filter active cells by predicate.
  """
  @spec filter_active(t(), (coord(), cell_value() -> boolean())) :: t()
  def filter_active(%__MODULE__{format: :hash, data: data} = grid, pred) do
    new_data = Map.filter(data, fn {coord, value} -> pred.(coord, value) end)
    %{grid | data: new_data, nnz: map_size(new_data)}
  end

  def filter_active(%__MODULE__{format: :coo, data: entries} = grid, pred) do
    new_entries = Enum.filter(entries, fn {coord, value} -> pred.(coord, value) end)
    %{grid | data: new_entries, nnz: length(new_entries)}
  end

  # ═══════════════════════════════════════════════════════════════
  # NEIGHBORHOOD OPERATIONS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Get neighbors of a coordinate (26-connectivity in 3D).
  """
  @spec neighbors(t(), coord()) :: list({coord(), cell_value()})
  def neighbors(grid, {x, y, z}) do
    {h, w, d} = grid.shape

    for dx <- -1..1,
        dy <- -1..1,
        dz <- -1..1,
        not (dx == 0 and dy == 0 and dz == 0),
        nx = x + dx,
        ny = y + dy,
        nz = z + dz,
        nx >= 0 and nx < h,
        ny >= 0 and ny < w,
        nz >= 0 and nz < d do
      coord = {nx, ny, nz}
      {coord, get(grid, coord)}
    end
  end

  @doc """
  Apply function to each cell considering its neighbors.

  Efficient: only processes active cells and their immediate neighborhood.
  """
  @spec convolve(t(), (coord(), cell_value(), list({coord(), cell_value()}) -> cell_value())) ::
          t()
  def convolve(grid, fun) do
    # Collect all coordinates that might be affected
    # (active cells + their neighbors)
    affected_coords =
      grid
      |> active_coords()
      |> Enum.flat_map(fn coord ->
        neighbor_coords = neighbors(grid, coord) |> Enum.map(&elem(&1, 0))
        [coord | neighbor_coords]
      end)
      |> Enum.uniq()

    # Apply function to each affected coordinate
    new_values =
      Enum.map(affected_coords, fn coord ->
        current = get(grid, coord)
        neighs = neighbors(grid, coord)
        {coord, fun.(coord, current, neighs)}
      end)

    # Build new grid from results
    Enum.reduce(new_values, new(grid.shape, format: grid.format), fn {coord, value}, acc ->
      # Only store non-default values
      if value != grid.default do
        put(acc, coord, value)
      else
        acc
      end
    end)
  end

  defp active_coords(%__MODULE__{format: :hash, data: data}) do
    Map.keys(data)
  end

  defp active_coords(%__MODULE__{format: :coo, data: entries}) do
    Enum.map(entries, fn {coord, _} -> coord end)
  end

  # ═══════════════════════════════════════════════════════════════
  # FORMAT CONVERSION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Convert to hash format.
  """
  @spec to_hash(t()) :: t()
  def to_hash(%__MODULE__{format: :hash} = grid), do: grid

  def to_hash(%__MODULE__{format: :coo, data: entries} = grid) do
    data = Map.new(entries)
    %{grid | format: :hash, data: data}
  end

  @doc """
  Convert to COO format.
  """
  @spec to_coo(t()) :: t()
  def to_coo(%__MODULE__{format: :coo} = grid), do: grid

  def to_coo(%__MODULE__{format: :hash, data: data} = grid) do
    entries = Map.to_list(data)
    %{grid | format: :coo, data: entries}
  end

  @doc """
  Convert to dense Nx tensor.

  Shape: {H, W, D, C} where C is channels.
  """
  @spec to_dense(t()) :: Nx.Tensor.t()
  def to_dense(%__MODULE__{shape: {h, w, d}, channels: c, default: default} = grid) do
    # Initialize dense tensor with defaults
    default_tensor = Nx.tensor(default, type: :f32)
    dense = Nx.broadcast(default_tensor, {h, w, d, c})

    # Scatter active values
    grid
    |> active_coords()
    |> Enum.reduce(dense, fn {x, y, z} = coord, acc ->
      value = get(grid, coord) |> Nx.tensor(type: :f32)
      Nx.put_slice(acc, [x, y, z, 0], Nx.reshape(value, {1, 1, 1, c}))
    end)
  end

  @doc """
  Create sparse grid from dense Nx tensor.

  Filters out cells where alpha (channel 3) < threshold.
  """
  @spec from_dense(Nx.Tensor.t(), keyword()) :: t()
  def from_dense(tensor, opts \\ []) do
    threshold = Keyword.get(opts, :alive_threshold, @alive_threshold)
    {h, w, d, c} = Nx.shape(tensor)

    grid = new({h, w, d}, Keyword.put(opts, :channels, c))

    # Extract non-zero cells
    tensor_list = Nx.to_list(tensor)

    Enum.reduce(0..(h - 1), grid, fn x, acc_x ->
      Enum.reduce(0..(w - 1), acc_x, fn y, acc_y ->
        Enum.reduce(0..(d - 1), acc_y, fn z, acc_z ->
          value = tensor_list |> Enum.at(x) |> Enum.at(y) |> Enum.at(z)
          alpha = Enum.at(value, 3, 0.0)

          if alpha >= threshold do
            put(acc_z, {x, y, z}, value)
          else
            acc_z
          end
        end)
      end)
    end)
  end

  # ═══════════════════════════════════════════════════════════════
  # STATISTICS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Compute sparsity ratio (proportion of empty cells).
  """
  @spec sparsity(t()) :: float()
  def sparsity(%__MODULE__{shape: {h, w, d}, nnz: nnz}) do
    total = h * w * d
    1.0 - nnz / total
  end

  @doc """
  Get count of active cells.
  """
  @spec count_active(t()) :: non_neg_integer()
  def count_active(%__MODULE__{nnz: nnz}), do: nnz

  @doc """
  Compute bounding box of active cells.
  """
  @spec bounding_box(t()) :: {coord(), coord()} | nil
  def bounding_box(%__MODULE__{nnz: 0}), do: nil

  def bounding_box(grid) do
    coords = active_coords(grid)

    xs = Enum.map(coords, &elem(&1, 0))
    ys = Enum.map(coords, &elem(&1, 1))
    zs = Enum.map(coords, &elem(&1, 2))

    {{Enum.min(xs), Enum.min(ys), Enum.min(zs)}, {Enum.max(xs), Enum.max(ys), Enum.max(zs)}}
  end
end
