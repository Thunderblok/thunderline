defmodule Thunderline.Thunderbolt.Continuous.Algebra do
  @moduledoc """
  Continuous algebra operations for ContinuousTensor.

  Implements mathematical operations that respect the piecewise-constant
  representation, producing new tensors with properly merged intervals.

  ## Operations

  ### Element-wise
  - `add/2` - Add two tensors
  - `subtract/2` - Subtract tensors
  - `multiply/2` - Element-wise multiplication
  - `divide/2` - Element-wise division
  - `scale/2` - Scalar multiplication

  ### Reductions
  - `sum/1` - Sum of all interval values
  - `mean/1` - Mean value across intervals
  - `min/1` - Minimum value
  - `max/1` - Maximum value

  ### Advanced
  - `convolve/2` - Convolution with continuous kernel
  - `integrate/3` - Numerical integration over range
  - `differentiate/2` - Numerical differentiation at point

  ## Research Note

  These operations follow the Continuous Tensor Abstraction semantics where
  real-valued indices produce mathematically correct results through
  piecewise-constant interpolation.
  """

  alias Thunderline.Thunderbolt.Continuous.Tensor

  @type tensor :: Tensor.t()
  @type number_or_tensor :: number() | tensor()

  # ============================================================================
  # Element-wise Operations
  # ============================================================================

  @doc """
  Adds two continuous tensors or adds a scalar to a tensor.

  When adding tensors:
  - Intervals are merged
  - Overlapping regions sum their values
  - Non-overlapping regions retain original values

  ## Examples

      # Tensor + scalar
      result = Algebra.add(tensor, 5.0)

      # Tensor + tensor
      result = Algebra.add(tensor_a, tensor_b)
  """
  @spec add(tensor(), number_or_tensor()) :: tensor()
  def add(%Tensor{} = tensor, scalar) when is_number(scalar) do
    Tensor.map(tensor, fn v -> v + scalar end)
  end

  def add(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b) do
    start_time = System.monotonic_time()

    result = binary_op(a, b, &Kernel.+/2)

    emit_telemetry(:algebra, start_time, %{operation: :add, dims: dims})

    result
  end

  @doc """
  Subtracts a scalar or tensor from another tensor.
  """
  @spec subtract(tensor(), number_or_tensor()) :: tensor()
  def subtract(%Tensor{} = tensor, scalar) when is_number(scalar) do
    Tensor.map(tensor, fn v -> v - scalar end)
  end

  def subtract(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b) do
    binary_op(a, b, &Kernel.-/2)
  end

  @doc """
  Element-wise multiplication of tensors or scalar multiplication.
  """
  @spec multiply(tensor(), number_or_tensor()) :: tensor()
  def multiply(%Tensor{} = tensor, scalar) when is_number(scalar) do
    scale(tensor, scalar)
  end

  def multiply(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b) do
    binary_op(a, b, &Kernel.*/2)
  end

  @doc """
  Scales a tensor by a scalar factor.
  """
  @spec scale(tensor(), number()) :: tensor()
  def scale(%Tensor{} = tensor, factor) when is_number(factor) do
    Tensor.map(tensor, fn v -> v * factor end)
  end

  @doc """
  Element-wise division.
  """
  @spec divide(tensor(), number_or_tensor()) :: tensor()
  def divide(%Tensor{} = tensor, scalar) when is_number(scalar) and scalar != 0 do
    Tensor.map(tensor, fn v -> v / scalar end)
  end

  def divide(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b) do
    binary_op(a, b, fn av, bv ->
      if bv != 0, do: av / bv, else: 0.0
    end)
  end

  @doc """
  Applies an arbitrary binary operation element-wise.
  """
  @spec binary_op(tensor(), tensor(), (number(), number() -> number())) :: tensor()
  def binary_op(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b, op)
      when is_function(op, 2) do
    # For each interval in a, find overlapping intervals in b and compute result
    # This is a simplified implementation - full version would handle all edge cases
    merged_intervals = merge_with_op(a.intervals, b.intervals, op, a.default, b.default)

    %Tensor{
      dims: dims,
      intervals: merged_intervals,
      default: compute_default(a.default, b.default, op),
      metadata: Map.merge(a.metadata, b.metadata)
    }
  end

  # ============================================================================
  # Reduction Operations
  # ============================================================================

  @doc """
  Sums all interval values.

  Note: This sums the constant values, not weighted by interval size.
  For integral, use `integrate/3`.
  """
  @spec sum(tensor()) :: number()
  def sum(%Tensor{intervals: intervals}) do
    Enum.reduce(intervals, 0, fn {_interval, value}, acc ->
      if is_number(value), do: acc + value, else: acc
    end)
  end

  @doc """
  Computes the mean value across all intervals.
  """
  @spec mean(tensor()) :: number() | nil
  def mean(%Tensor{intervals: []}) do
    nil
  end

  def mean(%Tensor{intervals: intervals}) do
    {total, count} =
      Enum.reduce(intervals, {0, 0}, fn {_interval, value}, {sum, cnt} ->
        if is_number(value), do: {sum + value, cnt + 1}, else: {sum, cnt}
      end)

    if count > 0, do: total / count, else: nil
  end

  @doc """
  Finds the minimum interval value.
  """
  @spec min(tensor()) :: number() | nil
  def min(%Tensor{intervals: []}) do
    nil
  end

  def min(%Tensor{intervals: intervals}) do
    intervals
    |> Enum.map(fn {_interval, value} -> value end)
    |> Enum.filter(&is_number/1)
    |> Enum.min(fn -> nil end)
  end

  @doc """
  Finds the maximum interval value.
  """
  @spec max(tensor()) :: number() | nil
  def max(%Tensor{intervals: []}) do
    nil
  end

  def max(%Tensor{intervals: intervals}) do
    intervals
    |> Enum.map(fn {_interval, value} -> value end)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> nil end)
  end

  # ============================================================================
  # Advanced Operations
  # ============================================================================

  @doc """
  Integrates the tensor over a range.

  For piecewise-constant tensors, this is the sum of (interval_length × value)
  for all intervals overlapping the integration range.

  ## Examples

      # Integrate over [0, 10]
      result = Algebra.integrate(tensor, 0.0, 10.0)
  """
  @spec integrate(tensor(), number(), number()) :: number()
  def integrate(%Tensor{dims: 1, intervals: intervals, default: default}, from, to)
      when is_number(from) and is_number(to) do
    start_time = System.monotonic_time()

    result =
      Enum.reduce(intervals, 0.0, fn {{int_start, int_stop}, value}, acc ->
        # Find overlap with integration range
        overlap_start = Kernel.max(int_start, from)
        overlap_stop = Kernel.min(int_stop, to)

        if overlap_start < overlap_stop and is_number(value) do
          acc + (overlap_stop - overlap_start) * value
        else
          acc
        end
      end)

    # Add default value contribution for gaps
    gap_contribution = calculate_gap_integral(intervals, from, to, default)

    emit_telemetry(:algebra, start_time, %{operation: :integrate, dims: 1})

    result + gap_contribution
  end

  @doc """
  Computes a weighted integral over all intervals.

  Result = Σ (interval_size × value) for all intervals
  """
  @spec weighted_sum(tensor()) :: number()
  def weighted_sum(%Tensor{dims: 1, intervals: intervals}) do
    Enum.reduce(intervals, 0.0, fn {{start_val, stop_val}, value}, acc ->
      if is_number(value) do
        acc + (stop_val - start_val) * value
      else
        acc
      end
    end)
  end

  @doc """
  Computes the numerical derivative at a point.

  Uses central difference approximation with step size `h`.
  """
  @spec differentiate(tensor(), number(), keyword()) :: number()
  def differentiate(%Tensor{dims: 1} = tensor, x, opts \\ []) do
    h = Keyword.get(opts, :h, 0.001)

    f_plus = Tensor.get(tensor, x + h) || 0
    f_minus = Tensor.get(tensor, x - h) || 0

    (f_plus - f_minus) / (2 * h)
  end

  @doc """
  Convolves a tensor with a kernel function.

  For 1D tensors, this slides the kernel across all intervals.

  ## Examples

      # Gaussian smoothing kernel
      kernel = fn x -> :math.exp(-x * x / 2) end
      smoothed = Algebra.convolve(tensor, kernel, bandwidth: 1.0)
  """
  @spec convolve(tensor(), function(), keyword()) :: tensor()
  def convolve(%Tensor{dims: 1, intervals: intervals} = tensor, kernel_fn, opts \\ [])
      when is_function(kernel_fn, 1) do
    bandwidth = Keyword.get(opts, :bandwidth, 1.0)
    samples = Keyword.get(opts, :samples, 100)

    # Get bounding box
    {min_x, max_x} = get_bounds_1d(intervals)
    step = (max_x - min_x) / samples

    # Sample convolution at regular points
    new_intervals =
      0..(samples - 1)
      |> Enum.map(fn i ->
        x = min_x + i * step
        value = compute_convolution_at(tensor, x, kernel_fn, bandwidth)
        {{x, x + step}, value}
      end)
      |> Enum.filter(fn {_interval, value} -> value != 0.0 end)

    %Tensor{
      dims: 1,
      intervals: new_intervals,
      default: tensor.default,
      metadata: Map.put(tensor.metadata, :convolved, true)
    }
  end

  @doc """
  Computes the L2 norm (Euclidean distance) between two tensors.
  """
  @spec l2_distance(tensor(), tensor()) :: number()
  def l2_distance(%Tensor{dims: dims} = a, %Tensor{dims: dims} = b) do
    diff = subtract(a, b)
    squared = Tensor.map(diff, fn v -> v * v end)

    squared
    |> sum()
    |> :math.sqrt()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp merge_with_op(intervals_a, intervals_b, op, default_a, default_b) do
    # Simplified merge: apply op to all combinations of overlapping intervals
    # A complete implementation would handle interval splitting and merging

    all_intervals =
      for {int_a, val_a} <- intervals_a,
          {int_b, val_b} <- intervals_b,
          overlap = compute_overlap(int_a, int_b),
          overlap != nil do
        {overlap, op.(val_a, val_b)}
      end

    # Add non-overlapping intervals from a with default_b
    non_overlap_a =
      Enum.flat_map(intervals_a, fn {int_a, val_a} ->
        if Enum.any?(intervals_b, fn {int_b, _} -> intervals_overlap?(int_a, int_b) end) do
          []
        else
          [{int_a, op.(val_a, default_b || 0)}]
        end
      end)

    # Add non-overlapping intervals from b with default_a
    non_overlap_b =
      Enum.flat_map(intervals_b, fn {int_b, val_b} ->
        if Enum.any?(intervals_a, fn {int_a, _} -> intervals_overlap?(int_a, int_b) end) do
          []
        else
          [{int_b, op.(default_a || 0, val_b)}]
        end
      end)

    (all_intervals ++ non_overlap_a ++ non_overlap_b)
    |> Enum.sort_by(fn {int, _} -> get_start(int) end)
  end

  defp compute_overlap({a_start, a_stop}, {b_start, b_stop}) do
    overlap_start = Kernel.max(a_start, b_start)
    overlap_stop = Kernel.min(a_stop, b_stop)

    if overlap_start < overlap_stop do
      {overlap_start, overlap_stop}
    else
      nil
    end
  end

  defp intervals_overlap?({a_start, a_stop}, {b_start, b_stop}) do
    a_start < b_stop and b_start < a_stop
  end

  defp get_start({start, _stop}), do: start

  defp compute_default(nil, nil, _op), do: nil
  defp compute_default(a, nil, op), do: op.(a, 0)
  defp compute_default(nil, b, op), do: op.(0, b)
  defp compute_default(a, b, op), do: op.(a, b)

  defp calculate_gap_integral(_intervals, _from, _to, nil), do: 0.0

  defp calculate_gap_integral(intervals, from, to, default) when is_number(default) do
    total_range = to - from

    covered =
      Enum.reduce(intervals, 0.0, fn {{int_start, int_stop}, _value}, acc ->
        overlap_start = Kernel.max(int_start, from)
        overlap_stop = Kernel.min(int_stop, to)

        if overlap_start < overlap_stop do
          acc + (overlap_stop - overlap_start)
        else
          acc
        end
      end)

    gap_size = total_range - covered
    if gap_size > 0, do: gap_size * default, else: 0.0
  end

  defp get_bounds_1d([]), do: {0.0, 1.0}

  defp get_bounds_1d(intervals) do
    {min_val, max_val} =
      Enum.reduce(intervals, {:infinity, :neg_infinity}, fn {{start_val, stop_val}, _},
                                                            {min_acc, max_acc} ->
        {Kernel.min(start_val, min_acc), Kernel.max(stop_val, max_acc)}
      end)

    {min_val, max_val}
  end

  defp compute_convolution_at(%Tensor{} = tensor, x, kernel_fn, bandwidth) do
    # Evaluate kernel-weighted average around point x
    tensor.intervals
    |> Enum.reduce(0.0, fn {{int_start, int_stop}, value}, acc ->
      center = (int_start + int_stop) / 2
      weight = kernel_fn.((x - center) / bandwidth)
      acc + weight * (value || 0)
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
