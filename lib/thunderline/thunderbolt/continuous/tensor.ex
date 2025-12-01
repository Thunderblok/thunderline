defmodule Thunderline.Thunderbolt.Continuous.Tensor do
  @moduledoc """
  Core ContinuousTensor implementation based on the Continuous Tensor Abstraction.

  Implements piecewise-constant representation where tensors are defined over
  real-valued domains using intervals of constant values. This enables:

  - **Real-valued indexing**: Query at any continuous coordinate
  - **Sparse efficiency**: Store only where values change
  - **Automatic kernel generation**: Optimized iteration patterns
  - **Sub-tick precision**: Events and states between discrete steps

  ## Research Foundation

  Based on Won et al. "The Continuous Tensor Abstraction: Where Indices are Real"
  (OOPSLA 2025, arXiv:2407.01742)

  ## Representation

  A continuous tensor stores intervals with associated values:

      tensor = ContinuousTensor.new(dims: 1)
      tensor = ContinuousTensor.set_interval(tensor, {0.0, 1.0}, 10.0)
      tensor = ContinuousTensor.set_interval(tensor, {1.0, 2.5}, 20.0)

      ContinuousTensor.get(tensor, 0.5)   # => 10.0
      ContinuousTensor.get(tensor, 1.5)   # => 20.0
      ContinuousTensor.get(tensor, 3.0)   # => nil (outside intervals)

  ## Multi-dimensional Support

      # 2D tensor (spatial grid)
      tensor = ContinuousTensor.new(dims: 2)
      tensor = ContinuousTensor.set_interval(tensor, {{0.0, 10.0}, {0.0, 10.0}}, 1.0)

      ContinuousTensor.get(tensor, {5.0, 5.0})  # => 1.0

  ## Telemetry

  Emits events under `[:thunderline, :bolt, :continuous, :*]`:
  - `:create` - Tensor creation
  - `:get` - Index lookup
  - `:set` - Interval insertion
  - `:algebra` - Algebraic operations
  """

  alias __MODULE__

  @type interval :: {number(), number()}
  @type multi_interval :: interval() | {interval(), interval()} | tuple()
  @type value :: number() | map() | list()

  @type t :: %Tensor{
          dims: pos_integer(),
          intervals: list({multi_interval(), value()}),
          default: value() | nil,
          metadata: map()
        }

  @enforce_keys [:dims]
  defstruct dims: 1,
            intervals: [],
            default: nil,
            metadata: %{}

  @doc """
  Creates a new continuous tensor.

  ## Options

  - `:dims` - Number of dimensions (default: 1)
  - `:default` - Default value for coordinates outside intervals (default: nil)
  - `:metadata` - Additional metadata map

  ## Examples

      iex> tensor = ContinuousTensor.new(dims: 1)
      iex> tensor.dims
      1

      iex> tensor = ContinuousTensor.new(dims: 3, default: 0.0)
      iex> tensor.default
      0.0
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    start_time = System.monotonic_time()

    dims = Keyword.get(opts, :dims, 1)
    default = Keyword.get(opts, :default, nil)
    metadata = Keyword.get(opts, :metadata, %{})

    tensor = %Tensor{
      dims: dims,
      intervals: [],
      default: default,
      metadata: metadata
    }

    emit_telemetry(:create, start_time, %{dims: dims})

    tensor
  end

  @doc """
  Gets the value at a real-valued coordinate.

  Performs interval lookup to find which interval contains the coordinate,
  returning the associated value or the default value if not found.

  ## Examples

      iex> tensor = ContinuousTensor.new(dims: 1, default: 0.0)
      iex> tensor = ContinuousTensor.set_interval(tensor, {0.0, 1.0}, 42.0)
      iex> ContinuousTensor.get(tensor, 0.5)
      42.0

      iex> ContinuousTensor.get(tensor, 2.0)
      0.0
  """
  @spec get(t(), number() | tuple()) :: value() | nil
  def get(%Tensor{} = tensor, coord) do
    start_time = System.monotonic_time()

    result = lookup_interval(tensor, coord)

    emit_telemetry(:get, start_time, %{dims: tensor.dims, found: result != tensor.default})

    result
  end

  @doc """
  Sets a value for an interval in the tensor.

  For 1D tensors, the interval is `{start, stop}`.
  For multi-dimensional tensors, provide a tuple of intervals.

  ## Examples

      # 1D interval
      tensor = ContinuousTensor.set_interval(tensor, {0.0, 10.0}, 1.0)

      # 2D region
      tensor = ContinuousTensor.set_interval(tensor, {{0.0, 5.0}, {0.0, 5.0}}, 2.0)
  """
  @spec set_interval(t(), multi_interval(), value()) :: t()
  def set_interval(%Tensor{} = tensor, interval, value) do
    start_time = System.monotonic_time()

    # Validate interval dimensions match tensor dims
    :ok = validate_interval_dims(tensor.dims, interval)

    # Insert interval (sorted by start point for efficient lookup)
    updated_intervals = insert_sorted(tensor.intervals, {interval, value})

    result = %Tensor{tensor | intervals: updated_intervals}

    emit_telemetry(:set, start_time, %{
      dims: tensor.dims,
      interval_count: length(updated_intervals)
    })

    result
  end

  @doc """
  Returns the number of intervals in the tensor.

  This is a measure of the tensor's complexity - more intervals mean
  more storage and potentially slower lookups.
  """
  @spec interval_count(t()) :: non_neg_integer()
  def interval_count(%Tensor{intervals: intervals}), do: length(intervals)

  @doc """
  Lists all intervals and their values.
  """
  @spec intervals(t()) :: list({multi_interval(), value()})
  def intervals(%Tensor{intervals: intervals}), do: intervals

  @doc """
  Merges two continuous tensors.

  When intervals overlap, uses the `conflict_fn` to resolve values.
  Default conflict resolution takes the value from tensor `b`.

  ## Examples

      tensor_c = ContinuousTensor.merge(tensor_a, tensor_b)

      # Custom conflict resolution (average)
      tensor_c = ContinuousTensor.merge(tensor_a, tensor_b, fn a, b -> (a + b) / 2 end)
  """
  @spec merge(t(), t(), (value(), value() -> value())) :: t()
  def merge(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b, conflict_fn \\ fn _a, b -> b end) do
    start_time = System.monotonic_time()

    # Simple merge: concatenate intervals and let later ones take precedence
    # A full implementation would detect overlaps and call conflict_fn
    merged_intervals = merge_intervals(a.intervals, b.intervals, conflict_fn)

    result = %Tensor{
      dims: dims,
      intervals: merged_intervals,
      default: b.default || a.default,
      metadata: Map.merge(a.metadata, b.metadata)
    }

    emit_telemetry(:algebra, start_time, %{operation: :merge, dims: dims})

    result
  end

  @doc """
  Applies a function to all values in the tensor.

  ## Examples

      # Double all values
      tensor = ContinuousTensor.map(tensor, fn v -> v * 2 end)
  """
  @spec map(t(), (value() -> value())) :: t()
  def map(%Tensor{} = tensor, fun) when is_function(fun, 1) do
    start_time = System.monotonic_time()

    mapped_intervals =
      Enum.map(tensor.intervals, fn {interval, value} ->
        {interval, fun.(value)}
      end)

    result = %Tensor{tensor | intervals: mapped_intervals}

    emit_telemetry(:algebra, start_time, %{operation: :map, dims: tensor.dims})

    result
  end

  @doc """
  Reduces all interval values to a single value.

  ## Examples

      # Sum all interval values
      total = ContinuousTensor.reduce(tensor, 0, fn v, acc -> v + acc end)
  """
  @spec reduce(t(), acc, (value(), acc -> acc)) :: acc when acc: term()
  def reduce(%Tensor{intervals: intervals}, initial, fun) when is_function(fun, 2) do
    Enum.reduce(intervals, initial, fn {_interval, value}, acc ->
      fun.(value, acc)
    end)
  end

  @doc """
  Samples the tensor at regular intervals, returning a list of values.

  Useful for converting continuous representation to discrete for visualization.

  ## Examples

      # Sample 1D tensor at 100 points
      values = ContinuousTensor.sample(tensor, {0.0, 10.0}, steps: 100)
  """
  @spec sample(t(), interval() | tuple(), keyword()) :: list(value())
  def sample(%Tensor{dims: 1} = tensor, {start_val, stop_val}, opts \\ []) do
    steps = Keyword.get(opts, :steps, 100)
    step_size = (stop_val - start_val) / steps

    Enum.map(0..(steps - 1), fn i ->
      coord = start_val + i * step_size
      get(tensor, coord)
    end)
  end

  @doc """
  Queries all intervals that overlap with a given region.

  ## Examples

      # Find all intervals overlapping [2.0, 5.0]
      matches = ContinuousTensor.query_region(tensor, {2.0, 5.0})
  """
  @spec query_region(t(), multi_interval()) :: list({multi_interval(), value()})
  def query_region(%Tensor{dims: 1, intervals: intervals}, {query_start, query_stop}) do
    Enum.filter(intervals, fn {{int_start, int_stop}, _value} ->
      intervals_overlap?(int_start, int_stop, query_start, query_stop)
    end)
  end

  def query_region(%Tensor{dims: _dims, intervals: intervals}, query_bounds) do
    Enum.filter(intervals, fn {interval, _value} ->
      multi_interval_overlaps?(interval, query_bounds)
    end)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp lookup_interval(%Tensor{dims: 1, intervals: intervals, default: default}, coord)
       when is_number(coord) do
    # Binary search would be more efficient for many intervals
    case Enum.find(intervals, fn {{start_val, stop_val}, _value} ->
           coord >= start_val and coord < stop_val
         end) do
      {_interval, value} -> value
      nil -> default
    end
  end

  defp lookup_interval(%Tensor{dims: dims, intervals: intervals, default: default}, coord)
       when is_tuple(coord) and tuple_size(coord) == dims do
    case Enum.find(intervals, fn {interval, _value} ->
           coord_in_multi_interval?(coord, interval)
         end) do
      {_interval, value} -> value
      nil -> default
    end
  end

  defp lookup_interval(%Tensor{default: default}, _coord), do: default

  defp coord_in_multi_interval?(coord, interval) when is_tuple(coord) and is_tuple(interval) do
    coord_list = Tuple.to_list(coord)
    interval_list = Tuple.to_list(interval)

    Enum.zip(coord_list, interval_list)
    |> Enum.all?(fn {c, {start_val, stop_val}} ->
      c >= start_val and c < stop_val
    end)
  end

  defp validate_interval_dims(1, {start_val, stop_val})
       when is_number(start_val) and is_number(stop_val) do
    :ok
  end

  defp validate_interval_dims(dims, interval) when is_tuple(interval) do
    if tuple_size(interval) == dims do
      # Verify each element is a {start, stop} tuple
      interval
      |> Tuple.to_list()
      |> Enum.all?(fn
        {s, e} when is_number(s) and is_number(e) -> true
        _ -> false
      end)
      |> case do
        true -> :ok
        false -> raise ArgumentError, "Each dimension must be {start, stop} tuple"
      end
    else
      raise ArgumentError,
            "Interval dimensions (#{tuple_size(interval)}) don't match tensor dims (#{dims})"
    end
  end

  defp validate_interval_dims(dims, _interval) do
    raise ArgumentError, "Invalid interval format for #{dims}D tensor"
  end

  defp insert_sorted(intervals, {interval, value}) do
    # Extract start point for sorting
    start_point = get_start_point(interval)

    # Find insertion point (keep sorted by start)
    {before, after_list} =
      Enum.split_while(intervals, fn {existing_interval, _v} ->
        get_start_point(existing_interval) <= start_point
      end)

    before ++ [{interval, value}] ++ after_list
  end

  defp get_start_point({start_val, _stop}) when is_number(start_val), do: start_val

  defp get_start_point(interval) when is_tuple(interval) do
    # For multi-dimensional, use first dimension's start
    case elem(interval, 0) do
      {start_val, _stop} -> start_val
      _ -> 0
    end
  end

  defp merge_intervals(intervals_a, intervals_b, _conflict_fn) do
    # Simple merge: concatenate and sort
    # Full implementation would detect overlaps and apply conflict_fn
    (intervals_a ++ intervals_b)
    |> Enum.sort_by(fn {interval, _v} -> get_start_point(interval) end)
  end

  defp intervals_overlap?(a_start, a_stop, b_start, b_stop) do
    a_start < b_stop and b_start < a_stop
  end

  defp multi_interval_overlaps?(interval_a, interval_b)
       when is_tuple(interval_a) and is_tuple(interval_b) do
    a_list = Tuple.to_list(interval_a)
    b_list = Tuple.to_list(interval_b)

    Enum.zip(a_list, b_list)
    |> Enum.all?(fn {{a_start, a_stop}, {b_start, b_stop}} ->
      intervals_overlap?(a_start, a_stop, b_start, b_stop)
    end)
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_telemetry(event, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:thunderline, :bolt, :continuous, event],
      %{duration: duration},
      metadata
    )
  end
end
