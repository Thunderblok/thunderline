defmodule Thunderline.Thunderbolt.Continuous do
  @moduledoc """
  Continuous Tensor Abstraction for Thunderline.

  This module provides the main API for working with continuous tensors,
  implementing the research from Won et al. "The Continuous Tensor Abstraction:
  Where Indices are Real" (OOPSLA 2025).

  ## Overview

  Traditional tensors use integer indices. Continuous tensors extend this to
  real-valued indices using piecewise-constant representation, enabling:

  - **Sub-tick precision**: Events between discrete timesteps
  - **Smooth state transitions**: PAC states as continuous manifolds
  - **Real-valued spatial queries**: Location-based search at any coordinate
  - **Efficient sparse storage**: Store only where values change

  ## Quick Start

      alias Thunderline.Thunderbolt.Continuous

      # Create a 1D tensor
      tensor = Continuous.new(dims: 1, default: 0.0)

      # Set values for intervals
      tensor = tensor
      |> Continuous.set({0.0, 10.0}, 1.0)   # Value 1.0 for [0, 10)
      |> Continuous.set({10.0, 20.0}, 2.0)  # Value 2.0 for [10, 20)

      # Query at any real coordinate
      Continuous.get(tensor, 5.0)   # => 1.0
      Continuous.get(tensor, 15.5)  # => 2.0
      Continuous.get(tensor, 25.0)  # => 0.0 (default)

  ## Multi-dimensional Tensors

      # 2D spatial tensor
      tensor = Continuous.new(dims: 2)
      |> Continuous.set({{0.0, 100.0}, {0.0, 100.0}}, :region_a)

      Continuous.get(tensor, {50.0, 50.0})  # => :region_a

  ## Algebra Operations

      tensor_sum = Continuous.add(tensor_a, tensor_b)
      tensor_scaled = Continuous.scale(tensor, 2.0)
      integral = Continuous.integrate(tensor, 0.0, 10.0)

  ## Interpolation

      # Smooth interpolation at boundaries
      value = Continuous.interpolate(tensor, 9.99, :linear, bandwidth: 0.5)

  ## Domains Using Continuous Tensors

  - **ThunderGrid**: Continuous spatial indexing (9.2x speedup on radius search)
  - **ThunderPac**: Continuous state manifolds (smooth transitions)
  - **ThunderFlow/Core**: Sub-tick temporal events
  - **ThunderBolt**: Continuous CA field dynamics
  """

  alias Thunderline.Thunderbolt.Continuous.{Tensor, Algebra, Interpolation, Storage}

  # ============================================================================
  # Construction
  # ============================================================================

  @doc """
  Creates a new continuous tensor.

  ## Options

  - `:dims` - Number of dimensions (default: 1)
  - `:default` - Default value for coordinates outside intervals
  - `:metadata` - Additional metadata map

  ## Examples

      Continuous.new(dims: 1)
      Continuous.new(dims: 2, default: 0.0)
      Continuous.new(dims: 3, metadata: %{name: "spatial_field"})
  """
  defdelegate new(opts \\ []), to: Tensor

  @doc """
  Creates a tensor from a list of intervals.

  ## Examples

      Continuous.from_intervals([
        {{0.0, 1.0}, 10},
        {{1.0, 2.0}, 20}
      ])
  """
  @spec from_intervals(list({term(), term()}), keyword()) :: Tensor.t()
  def from_intervals(intervals, opts \\ []) do
    tensor = new(opts)

    Enum.reduce(intervals, tensor, fn {interval, value}, acc ->
      Tensor.set_interval(acc, interval, value)
    end)
  end

  # ============================================================================
  # Access
  # ============================================================================

  @doc """
  Gets the value at a real-valued coordinate.

  ## Examples

      Continuous.get(tensor, 5.0)
      Continuous.get(tensor, {3.14, 2.72})
  """
  defdelegate get(tensor, coord), to: Tensor

  @doc """
  Sets a value for an interval.

  ## Examples

      Continuous.set(tensor, {0.0, 10.0}, 1.0)
      Continuous.set(tensor, {{0.0, 5.0}, {0.0, 5.0}}, "region")
  """
  def set(tensor, interval, value), do: Tensor.set_interval(tensor, interval, value)

  @doc """
  Lists all intervals in the tensor.
  """
  defdelegate intervals(tensor), to: Tensor

  @doc """
  Returns the number of intervals (complexity measure).
  """
  defdelegate interval_count(tensor), to: Tensor

  @doc """
  Queries intervals overlapping a region.

  ## Examples

      Continuous.query(tensor, {2.0, 8.0})  # 1D region
      Continuous.query(tensor, {{0.0, 5.0}, {0.0, 5.0}})  # 2D region
  """
  defdelegate query(tensor, region), to: Tensor, as: :query_region

  # ============================================================================
  # Algebra Operations
  # ============================================================================

  @doc """
  Adds two tensors or a scalar to a tensor.
  """
  defdelegate add(a, b), to: Algebra

  @doc """
  Subtracts tensors or a scalar.
  """
  defdelegate subtract(a, b), to: Algebra

  @doc """
  Element-wise multiplication.
  """
  defdelegate multiply(a, b), to: Algebra

  @doc """
  Scales tensor by a factor.
  """
  defdelegate scale(tensor, factor), to: Algebra

  @doc """
  Sums all interval values.
  """
  defdelegate sum(tensor), to: Algebra

  @doc """
  Mean value across intervals.
  """
  defdelegate mean(tensor), to: Algebra

  @doc """
  Minimum interval value.
  """
  defdelegate min(tensor), to: Algebra

  @doc """
  Maximum interval value.
  """
  defdelegate max(tensor), to: Algebra

  @doc """
  Integrates tensor over a range.

  ## Examples

      Continuous.integrate(tensor, 0.0, 10.0)
  """
  defdelegate integrate(tensor, from, to), to: Algebra

  @doc """
  L2 distance between tensors.
  """
  defdelegate distance(a, b), to: Algebra, as: :l2_distance

  @doc """
  Maps a function over all interval values.
  """
  defdelegate map(tensor, fun), to: Tensor

  @doc """
  Reduces all values to a single result.
  """
  defdelegate reduce(tensor, initial, fun), to: Tensor

  @doc """
  Merges two tensors with optional conflict resolution.
  """
  defdelegate merge(a, b), to: Tensor
  defdelegate merge(a, b, conflict_fn), to: Tensor

  # ============================================================================
  # Interpolation
  # ============================================================================

  @doc """
  Gets interpolated value at a coordinate.

  ## Methods

  - `:constant` - Piecewise constant (default)
  - `:linear` - Linear interpolation
  - `:smooth` - Cubic spline
  - `:gaussian` - Kernel density estimation

  ## Options

  - `:bandwidth` - Smoothing bandwidth (for :linear, :smooth, :gaussian)

  ## Examples

      Continuous.interpolate(tensor, 5.0, :linear, bandwidth: 0.5)
  """
  def interpolate(tensor, coord, method \\ :constant, opts \\ []) do
    Interpolation.at(tensor, coord, method, opts)
  end

  @doc """
  Samples tensor with interpolation.
  """
  def sample(tensor, range, opts \\ []) do
    Interpolation.sample(tensor, range, opts)
  end

  @doc """
  Returns transition points (boundaries).
  """
  defdelegate transitions(tensor), to: Interpolation

  # ============================================================================
  # Storage & Serialization
  # ============================================================================

  @doc """
  Serializes tensor to binary.

  ## Options

  - `:format` - `:etf` (Erlang) or `:json`
  - `:compress` - Whether to compress
  """
  defdelegate serialize(tensor, opts \\ []), to: Storage

  @doc """
  Deserializes binary to tensor.
  """
  defdelegate deserialize(binary, opts \\ []), to: Storage

  @doc """
  Converts to JSON for external systems.
  """
  defdelegate to_json(tensor), to: Storage

  @doc """
  Parses JSON to tensor.
  """
  defdelegate from_json(json), to: Storage

  @doc """
  Exports to Finch.jl format.
  """
  defdelegate to_finch(tensor), to: Storage, as: :to_finch_format

  # ============================================================================
  # Convenience Constructors
  # ============================================================================

  @doc """
  Creates a spatial field tensor (2D).

  ## Options

  - `:bounds` - `{{x_min, x_max}, {y_min, y_max}}`
  - `:default` - Default value

  ## Examples

      field = Continuous.spatial_field(
        bounds: {{0.0, 100.0}, {0.0, 100.0}},
        default: 0.0
      )
  """
  @spec spatial_field(keyword()) :: Tensor.t()
  def spatial_field(opts \\ []) do
    bounds = Keyword.get(opts, :bounds, {{0.0, 100.0}, {0.0, 100.0}})
    default = Keyword.get(opts, :default, nil)
    initial_value = Keyword.get(opts, :initial_value, nil)

    tensor = new(dims: 2, default: default, metadata: %{type: :spatial_field})

    if initial_value do
      set(tensor, bounds, initial_value)
    else
      tensor
    end
  end

  @doc """
  Creates a temporal signal tensor (1D time-indexed).

  ## Options

  - `:start` - Start time (default: 0.0)
  - `:default` - Default value

  ## Examples

      signal = Continuous.temporal_signal(start: 0.0, default: 0.0)
      signal = Continuous.set(signal, {0.0, 1.0}, pulse_value)
  """
  @spec temporal_signal(keyword()) :: Tensor.t()
  def temporal_signal(opts \\ []) do
    default = Keyword.get(opts, :default, nil)
    new(dims: 1, default: default, metadata: %{type: :temporal_signal})
  end

  @doc """
  Creates a state manifold tensor for PAC continuous states.

  ## Examples

      manifold = Continuous.state_manifold(
        states: [:dormant, :active, :explorative],
        default: %{dormant: 1.0, active: 0.0, explorative: 0.0}
      )
  """
  @spec state_manifold(keyword()) :: Tensor.t()
  def state_manifold(opts \\ []) do
    states = Keyword.get(opts, :states, [:dormant, :active])

    default =
      Keyword.get_lazy(opts, :default, fn ->
        # Default: 100% in first state
        Map.new(states, fn state ->
          {state, if(state == hd(states), do: 1.0, else: 0.0)}
        end)
      end)

    new(
      dims: 1,
      default: default,
      metadata: %{type: :state_manifold, states: states}
    )
  end
end
