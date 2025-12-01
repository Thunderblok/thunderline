defmodule Thunderline.Thunderbolt.Continuous.Interpolation do
  @moduledoc """
  Interpolation strategies for continuous tensors.

  While the core ContinuousTensor uses piecewise-constant representation
  (value changes only at interval boundaries), this module provides
  optional smooth interpolation for visualization and analysis.

  ## Interpolation Methods

  - **Constant** (default): Piecewise-constant, no interpolation
  - **Linear**: Linear interpolation between interval endpoints
  - **Smooth**: Cubic spline interpolation for smooth curves
  - **Gaussian**: Kernel density estimation with Gaussian kernel

  ## Usage

      alias Thunderline.Thunderbolt.Continuous.{Tensor, Interpolation}

      tensor = Tensor.new(dims: 1)
      |> Tensor.set_interval({0.0, 1.0}, 10.0)
      |> Tensor.set_interval({1.0, 2.0}, 20.0)

      # Constant (default behavior)
      Interpolation.at(tensor, 0.99, :constant)  # => 10.0
      Interpolation.at(tensor, 1.01, :constant)  # => 20.0

      # Linear interpolation (smooth transition)
      Interpolation.at(tensor, 1.0, :linear, bandwidth: 0.1)  # => ~15.0
  """

  alias Thunderline.Thunderbolt.Continuous.Tensor

  @type interpolation_method :: :constant | :linear | :smooth | :gaussian
  @type tensor :: Tensor.t()

  @doc """
  Gets the interpolated value at a continuous coordinate.

  ## Options

  - `:method` - Interpolation method (default: `:constant`)
  - `:bandwidth` - Smoothing bandwidth for `:linear` and `:gaussian`

  ## Examples

      Interpolation.at(tensor, 1.5, :constant)
      Interpolation.at(tensor, 1.5, :linear, bandwidth: 0.5)
      Interpolation.at(tensor, 1.5, :gaussian, bandwidth: 1.0)
  """
  @spec at(tensor(), number() | tuple(), interpolation_method(), keyword()) :: number() | nil
  def at(tensor, coord, method \\ :constant, opts \\ [])

  def at(%Tensor{} = tensor, coord, :constant, _opts) do
    Tensor.get(tensor, coord)
  end

  def at(%Tensor{dims: 1} = tensor, x, :linear, opts) when is_number(x) do
    bandwidth = Keyword.get(opts, :bandwidth, 0.1)
    linear_interpolate_1d(tensor, x, bandwidth)
  end

  def at(%Tensor{dims: 1} = tensor, x, :smooth, opts) when is_number(x) do
    bandwidth = Keyword.get(opts, :bandwidth, 0.5)
    cubic_interpolate_1d(tensor, x, bandwidth)
  end

  def at(%Tensor{dims: 1} = tensor, x, :gaussian, opts) when is_number(x) do
    bandwidth = Keyword.get(opts, :bandwidth, 1.0)
    gaussian_kernel_estimate(tensor, x, bandwidth)
  end

  def at(%Tensor{} = tensor, coord, _method, _opts) do
    # Fall back to constant for multi-dimensional
    Tensor.get(tensor, coord)
  end

  @doc """
  Samples the tensor at regular intervals with interpolation.

  Returns a list of `{coordinate, value}` pairs.

  ## Examples

      samples = Interpolation.sample(tensor, {0.0, 10.0},
        steps: 100,
        method: :linear,
        bandwidth: 0.2
      )
  """
  @spec sample(tensor(), {number(), number()}, keyword()) :: list({number(), number()})
  def sample(%Tensor{dims: 1} = tensor, {start_val, stop_val}, opts \\ []) do
    steps = Keyword.get(opts, :steps, 100)
    method = Keyword.get(opts, :method, :constant)
    interp_opts = Keyword.take(opts, [:bandwidth])

    step_size = (stop_val - start_val) / steps

    Enum.map(0..(steps - 1), fn i ->
      x = start_val + i * step_size
      value = at(tensor, x, method, interp_opts)
      {x, value}
    end)
  end

  @doc """
  Generates a smooth curve from tensor intervals.

  Creates a new tensor with more intervals approximating smooth interpolation.

  ## Options

  - `:resolution` - Number of sub-intervals per original interval
  - `:method` - Interpolation method to use
  """
  @spec smooth(tensor(), keyword()) :: tensor()
  def smooth(%Tensor{dims: 1, intervals: intervals} = tensor, opts \\ []) do
    resolution = Keyword.get(opts, :resolution, 10)
    method = Keyword.get(opts, :method, :linear)
    bandwidth = Keyword.get(opts, :bandwidth, 0.1)

    new_intervals =
      intervals
      |> Enum.flat_map(fn {{start_val, stop_val}, _value} ->
        step = (stop_val - start_val) / resolution

        Enum.map(0..(resolution - 1), fn i ->
          x_start = start_val + i * step
          x_end = x_start + step
          x_mid = (x_start + x_end) / 2

          interpolated_value = at(tensor, x_mid, method, bandwidth: bandwidth)
          {{x_start, x_end}, interpolated_value}
        end)
      end)

    %Tensor{tensor | intervals: new_intervals}
  end

  @doc """
  Finds the transition points (interval boundaries) in a tensor.

  These are the coordinates where the value changes.
  """
  @spec transitions(tensor()) :: list(number())
  def transitions(%Tensor{dims: 1, intervals: intervals}) do
    intervals
    |> Enum.flat_map(fn {{start_val, stop_val}, _value} ->
      [start_val, stop_val]
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Computes the gradient (rate of change) at each transition point.

  Returns a list of `{coordinate, gradient}` pairs.
  """
  @spec gradient_at_transitions(tensor()) :: list({number(), number()})
  def gradient_at_transitions(%Tensor{dims: 1} = tensor) do
    transitions = transitions(tensor)

    Enum.map(transitions, fn x ->
      # Use small epsilon for numerical gradient
      epsilon = 0.0001
      left = Tensor.get(tensor, x - epsilon) || tensor.default || 0
      right = Tensor.get(tensor, x + epsilon) || tensor.default || 0

      gradient = (right - left) / (2 * epsilon)
      {x, gradient}
    end)
  end

  # ============================================================================
  # Private - Linear Interpolation
  # ============================================================================

  defp linear_interpolate_1d(%Tensor{intervals: intervals, default: default}, x, bandwidth) do
    # Find the two nearest intervals
    {left_interval, right_interval} = find_adjacent_intervals(intervals, x)

    case {left_interval, right_interval} do
      {nil, nil} ->
        default

      {{{_ls, left_end}, left_val}, {{right_start, _re}, right_val}}
      when right_start - left_end <= bandwidth * 2 ->
        # Interpolate between intervals
        t = (x - left_end) / (right_start - left_end)
        t = clamp(t, 0.0, 1.0)
        lerp(left_val || 0, right_val || 0, t)

      {nil, {{_rs, _re}, right_val}} ->
        right_val

      {{{_ls, _le}, left_val}, nil} ->
        left_val

      _ ->
        # Within an interval
        case Enum.find(intervals, fn {{s, e}, _v} -> x >= s and x < e end) do
          {_interval, value} -> value
          nil -> default
        end
    end
  end

  defp find_adjacent_intervals(intervals, x) do
    left =
      intervals
      |> Enum.filter(fn {{_s, e}, _v} -> e <= x end)
      |> Enum.max_by(fn {{_s, e}, _v} -> e end, fn -> nil end)

    right =
      intervals
      |> Enum.filter(fn {{s, _e}, _v} -> s >= x end)
      |> Enum.min_by(fn {{s, _e}, _v} -> s end, fn -> nil end)

    {left, right}
  end

  # ============================================================================
  # Private - Cubic Interpolation
  # ============================================================================

  defp cubic_interpolate_1d(%Tensor{intervals: intervals, default: default}, x, bandwidth) do
    # Collect nearby sample points for cubic spline
    points =
      intervals
      |> Enum.flat_map(fn {{start_val, stop_val}, value} ->
        center = (start_val + stop_val) / 2

        if abs(center - x) <= bandwidth * 2 do
          [{center, value}]
        else
          []
        end
      end)
      |> Enum.sort_by(fn {px, _} -> px end)

    case length(points) do
      0 -> default
      1 -> elem(hd(points), 1)
      2 -> linear_from_points(points, x)
      _ -> cubic_from_points(points, x)
    end
  end

  defp linear_from_points([{x1, y1}, {x2, y2}], x) do
    t = (x - x1) / (x2 - x1)
    lerp(y1, y2, t)
  end

  defp cubic_from_points(points, x) do
    # Simplified Catmull-Rom spline interpolation
    # Find the 4 closest points
    sorted = Enum.sort_by(points, fn {px, _} -> abs(px - x) end)
    nearest_4 = Enum.take(sorted, 4)

    # Fall back to quadratic/linear if not enough points
    case length(nearest_4) do
      n when n < 4 ->
        {_, avg} =
          Enum.reduce(nearest_4, {0, 0.0}, fn {_px, py}, {count, sum} ->
            {count + 1, sum + py}
          end)

        avg / length(nearest_4)

      _ ->
        [{_x0, y0}, {x1, y1}, {x2, y2}, {_x3, y3}] =
          Enum.sort_by(nearest_4, fn {px, _} -> px end)

        # Catmull-Rom parameter
        t = if x2 != x1, do: (x - x1) / (x2 - x1), else: 0.5
        t = clamp(t, 0.0, 1.0)

        catmull_rom(y0, y1, y2, y3, t)
    end
  end

  defp catmull_rom(y0, y1, y2, y3, t) do
    # Catmull-Rom spline formula
    t2 = t * t
    t3 = t2 * t

    0.5 *
      (2 * y1 +
         (-y0 + y2) * t +
         (2 * y0 - 5 * y1 + 4 * y2 - y3) * t2 +
         (-y0 + 3 * y1 - 3 * y2 + y3) * t3)
  end

  # ============================================================================
  # Private - Gaussian Kernel Estimation
  # ============================================================================

  defp gaussian_kernel_estimate(%Tensor{intervals: intervals, default: default}, x, bandwidth) do
    # Kernel density estimation with Gaussian kernel
    {weighted_sum, weight_sum} =
      Enum.reduce(intervals, {0.0, 0.0}, fn {{start_val, stop_val}, value}, {ws, w} ->
        center = (start_val + stop_val) / 2
        interval_size = stop_val - start_val

        # Gaussian weight
        dist = (x - center) / bandwidth
        weight = :math.exp(-0.5 * dist * dist) * interval_size

        if value do
          {ws + weight * value, w + weight}
        else
          {ws, w}
        end
      end)

    if weight_sum > 0.0001 do
      weighted_sum / weight_sum
    else
      default
    end
  end

  # ============================================================================
  # Private - Utilities
  # ============================================================================

  defp lerp(a, b, t) when is_number(a) and is_number(b) do
    a + (b - a) * t
  end

  defp lerp(_, b, _), do: b

  defp clamp(x, min_val, max_val) do
    x |> Kernel.max(min_val) |> Kernel.min(max_val)
  end
end
