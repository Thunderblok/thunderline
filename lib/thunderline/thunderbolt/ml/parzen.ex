defmodule Thunderline.Thunderbolt.ML.Parzen do
  @moduledoc """
  Non-parametric density estimator using histogram approximation over PCA-reduced dimensions.

  Parzen windows (Parzen, 1962) provide a kernel-based method for estimating probability
  density functions without assuming a parametric form. This module implements a **histogram-based
  approximation** (MVP approach) that:

  1. Maintains a sliding window of recent samples (default: 300)
  2. Reduces dimensionality via PCA (default: 2 dims)
  3. Constructs histogram bins over the projected space
  4. Normalizes to produce a probability density estimate

  ## Theory

  Full Parzen window density estimation:

      p̂(x) = (1/Nh) Σᵢ K((x - xᵢ)/h)

  where:
  - N = number of samples
  - h = bandwidth (kernel width)
  - K = kernel function (typically Gaussian)
  - xᵢ = training samples

  **This MVP uses histogram approximation** for speed and simplicity:

      p̂(x) ≈ count(bin(x)) / (total_samples × bin_width)

  Future enhancement: Full kernel density with bandwidth selection (e.g., Silverman's rule).

  ## Usage

  ```elixir
  # Initialize
  parzen = Parzen.init(window_size: 300, bins: 20, dims: 2)

  # Fit with new batch (Nx tensor)
  parzen = Parzen.fit(parzen, batch)

  # Get current density estimate
  histogram = Parzen.histogram(parzen)  # %{bins: [...], density: [...]}

  # Query density at specific point
  density = Parzen.density_at(parzen, point)  # float

  # Snapshot for embedding in voxel
  snapshot = Parzen.snapshot(parzen)

  # Restore from snapshot
  parzen = Parzen.from_snapshot(snapshot)
  ```

  ## Architecture

  Parzen instances are used by `Thunderline.Thunderbolt.ML.Controller` to maintain the empirical
  distribution of real data. The Controller compares this "ground truth" density with
  the density produced by candidate ONNX models, using the distance to train the
  SLA selector (see `Thunderline.Thunderbolt.ML.SLASelector`).

  ## References

  - Parzen, E. (1962). "On Estimation of a Probability Density Function and Mode"
  - Silverman, B. W. (1986). "Density Estimation for Statistics and Data Analysis"
  - Li et al. (2007). "An Improved Adaptive Parzen Window Approach Based on SLA"
  """

  @typedoc """
  Parzen window density estimator state.

  Fields:
  - `window`: Sliding FIFO window of recent samples (list of Nx tensors)
  - `window_size`: Maximum number of samples to retain
  - `bins`: Number of histogram bins per dimension
  - `dims`: Dimensionality after PCA reduction
  - `pca_basis`: PCA basis vectors (Nx tensor, shape: {original_dims, dims})
  - `histogram`: Current density estimate (Nx tensor, normalized to sum=1.0)
  - `bin_edges`: Edges for each dimension [{min, max, step}, ...]
  - `total_samples`: Total samples processed (for statistics)
  """
  @type t :: %__MODULE__{
          pac_id: term(),
          feature_family: atom() | String.t(),
          window_size: pos_integer(),
          dims: 1 | 2,
          bins: pos_integer(),
          samples: Nx.Tensor.t() | nil,
          proj_samples: Nx.Tensor.t() | nil,
          pca_basis: Nx.Tensor.t() | nil,
          pca_mean: Nx.Tensor.t() | nil,
          bin_edges: Nx.Tensor.t() | nil,
          bin_probs: Nx.Tensor.t() | nil,
          last_updated_at: integer() | nil
        }

  defstruct pac_id: nil,
            feature_family: nil,
            window_size: 300,
            dims: 1,
            bins: 20,
            samples: nil,
            proj_samples: nil,
            pca_basis: nil,
            pca_mean: nil,
            bin_edges: nil,
            bin_probs: nil,
            last_updated_at: nil

  @doc """
  Initialize a new Parzen density estimator.

  ## Options

  - `:pac_id` - PAC identifier (required)
  - `:feature_family` - Feature family atom or string (required)
  - `:window_size` - Number of recent samples to keep (default: 300)
  - `:bins` - Number of histogram bins (default: 20)
  - `:dims` - Number of PCA dimensions to reduce to (default: 1)

  ## Examples

      iex> parzen = Parzen.init(pac_id: "pac_123", feature_family: :text)
      iex> parzen.window_size
      300

  """
  @spec init(keyword()) :: t()
  def init(opts) do
    pac_id = Keyword.fetch!(opts, :pac_id)
    feature_family = Keyword.fetch!(opts, :feature_family)
    window_size = Keyword.get(opts, :window_size, 300)
    bins = Keyword.get(opts, :bins, 20)
    dims = Keyword.get(opts, :dims, 1)

    unless dims in [1, 2] do
      raise ArgumentError, "dims must be 1 or 2, got: #{inspect(dims)}"
    end

    %__MODULE__{
      pac_id: pac_id,
      feature_family: feature_family,
      window_size: window_size,
      bins: bins,
      dims: dims,
      samples: nil,
      proj_samples: nil,
      pca_basis: nil,
      pca_mean: nil,
      bin_edges: nil,
      bin_probs: nil,
      last_updated_at: nil
    }
  end

  @doc """
  Fit the Parzen estimator with a new batch of samples.

  Updates the sliding window, recomputes PCA projection if needed,
  and rebuilds the histogram PDF approximation.

  ## Parameters

  - `parzen` - Current Parzen state
  - `batch` - Tensor of shape `{batch_size, feature_dim}` containing new samples

  ## Returns

  Updated Parzen state with new histogram.

  ## Examples

      iex> batch = Nx.tensor([[1.0, 2.0], [3.0, 4.0]])
      iex> parzen = Parzen.init(pac_id: "pac_1", feature_family: :test) |> Parzen.fit(batch)
      iex> parzen.bin_probs != nil
      true

  """
  @spec fit(t(), Nx.Tensor.t()) :: t()
  def fit(parzen, batch) do
    start_time = System.monotonic_time()
    batch_size = Nx.axis_size(batch, 0)

    # Emit telemetry start
    :telemetry.execute(
      [:thunderline, :ml, :parzen, :fit, :start],
      %{batch_size: batch_size},
      %{
        pac_id: parzen.pac_id,
        feature_family: parzen.feature_family,
        window_size: parzen.window_size,
        dims: parzen.dims,
        bins: parzen.bins
      }
    )

    # Update samples with sliding window
    all_samples =
      if parzen.samples == nil do
        batch
      else
        concatenated = Nx.concatenate([parzen.samples, batch], axis: 0)
        n = Nx.axis_size(concatenated, 0)

        if n > parzen.window_size do
          # Keep last window_size rows
          start_idx = n - parzen.window_size
          Nx.slice_along_axis(concatenated, start_idx, parzen.window_size, axis: 0)
        else
          concatenated
        end
      end

    # PCA projection
    {pca_mean, pca_basis, proj_samples} = compute_pca(all_samples, parzen.dims)

    # Build histogram PDF
    {bin_edges, bin_probs} = build_histogram(proj_samples, parzen.bins)

    updated_state = %{
      parzen
      | samples: all_samples,
        proj_samples: proj_samples,
        pca_mean: pca_mean,
        pca_basis: pca_basis,
        bin_edges: bin_edges,
        bin_probs: bin_probs,
        last_updated_at: System.system_time(:millisecond)
    }

    # Emit telemetry stop
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:thunderline, :ml, :parzen, :fit, :stop],
      %{duration: duration, batch_size: batch_size},
      %{
        pac_id: parzen.pac_id,
        feature_family: parzen.feature_family,
        window_size: parzen.window_size,
        dims: parzen.dims,
        bins: parzen.bins
      }
    )

    updated_state
  end

  @doc """
  Get the current histogram representation.

  Returns the bin edges and probability mass for each bin,
  which can be used for distance computations.

  ## Parameters

  - `parzen` - Current Parzen state

  ## Returns

  Map with `:bin_edges` and `:bin_probs` keys, or empty map if not yet fitted.

  ## Examples

      iex> hist = Parzen.histogram(parzen)
      iex> Map.has_key?(hist, :bin_edges)
      true

  """
  @spec histogram(t()) :: map()
  def histogram(parzen) do
    if parzen.bin_probs == nil do
      %{}
    else
      %{
        bin_edges: parzen.bin_edges,
        bin_probs: parzen.bin_probs,
        dims: parzen.dims
      }
    end
  end

  @doc """
  Compute the estimated density at a given point.

  Projects the point using the learned PCA basis and returns
  the probability density at that location.

  ## Parameters

  - `parzen` - Current Parzen state
  - `point` - Tensor of shape `{feature_dim}` or `{1, feature_dim}`

  ## Returns

  Estimated probability density (float).

  ## Examples

      iex> point = Nx.tensor([1.5, 2.5])
      iex> density = Parzen.density_at(parzen, point)
      iex> is_float(density)
      true

  """
  @spec density_at(t(), Nx.Tensor.t()) :: float()
  def density_at(parzen, point) do
    # Return 0 if not fitted
    if parzen.bin_probs == nil or parzen.pca_basis == nil do
      0.0
    else
      # Ensure point is 1D vector
      point_vec = if Nx.rank(point) == 2, do: Nx.squeeze(point, axes: [0]), else: point

      # Project to PCA space: (point - mean) · basis
      centered = Nx.subtract(point_vec, parzen.pca_mean)
      coord = Nx.dot(centered, parzen.pca_basis)
      coord_scalar = Nx.to_number(coord)

      # Find which bin this falls into
      bin_edges_list = Nx.to_flat_list(parzen.bin_edges)
      bin_probs_list = Nx.to_flat_list(parzen.bin_probs)

      # Binary search for bin index
      bin_idx = find_bin_index(coord_scalar, bin_edges_list)

      if bin_idx >= 0 and bin_idx < length(bin_probs_list) do
        # Return density: prob / bin_width
        prob = Enum.at(bin_probs_list, bin_idx)
        bin_width = Enum.at(bin_edges_list, bin_idx + 1) - Enum.at(bin_edges_list, bin_idx)
        prob / bin_width
      else
        0.0
      end
    end
  end

  @doc """
  Create a serializable snapshot of the Parzen state.

  Useful for persisting state to database or voxel metadata.

  ## Parameters

  - `parzen` - Current Parzen state

  ## Returns

  Map with all state fields in serializable format.

  ## Examples

      iex> snapshot = Parzen.snapshot(parzen)
      iex> is_map(snapshot)
      true

  """
  @spec snapshot(t()) :: map()
  def snapshot(parzen) do
    %{
      pac_id: parzen.pac_id,
      feature_family: parzen.feature_family,
      window_size: parzen.window_size,
      dims: parzen.dims,
      bins: parzen.bins,
      sample_shape: if(parzen.samples, do: Nx.shape(parzen.samples), else: nil),
      pca_basis: if(parzen.pca_basis, do: Nx.to_binary(parzen.pca_basis), else: nil),
      pca_mean: if(parzen.pca_mean, do: Nx.to_binary(parzen.pca_mean), else: nil),
      bin_edges: if(parzen.bin_edges, do: Nx.to_binary(parzen.bin_edges), else: nil),
      bin_probs: if(parzen.bin_probs, do: Nx.to_binary(parzen.bin_probs), else: nil),
      last_updated_at: parzen.last_updated_at
    }
  end

  @doc """
  Restore a Parzen state from a snapshot.

  ## Parameters

  - `snapshot` - Map created by `snapshot/1`

  ## Returns

  Reconstructed Parzen state.

  ## Examples

      iex> restored = Parzen.from_snapshot(snapshot)
      iex> restored.window_size == parzen.window_size
      true

  """
  @spec from_snapshot(map()) :: t()
  def from_snapshot(snapshot) do
    %__MODULE__{
      pac_id: snapshot.pac_id,
      feature_family: snapshot.feature_family,
      window_size: snapshot.window_size,
      dims: snapshot.dims,
      bins: snapshot.bins,
      # Don't restore full samples to keep snapshots light
      samples: nil,
      proj_samples: nil,
      pca_basis: if(snapshot.pca_basis, do: Nx.from_binary(snapshot.pca_basis, :f32), else: nil),
      pca_mean: if(snapshot.pca_mean, do: Nx.from_binary(snapshot.pca_mean, :f32), else: nil),
      bin_edges: if(snapshot.bin_edges, do: Nx.from_binary(snapshot.bin_edges, :f32), else: nil),
      bin_probs: if(snapshot.bin_probs, do: Nx.from_binary(snapshot.bin_probs, :f32), else: nil),
      last_updated_at: snapshot.last_updated_at
    }
  end

  # Private helper functions

  defp compute_pca(samples, dims) do
    n = Nx.axis_size(samples, 0)

    # Center the data
    mean = Nx.mean(samples, axes: [0])
    centered = Nx.subtract(samples, mean)

    # Compute covariance matrix: C = (X^T X) / (n-1)
    cov = Nx.dot(Nx.transpose(centered), centered)
    cov = Nx.divide(cov, n - 1)

    # SVD to get principal components
    {_u, s, v} = Nx.LinAlg.svd(cov, full_matrices?: false)

    # Take top 'dims' components (columns of V)
    # V shape is [D, D], we want [D, dims]
    basis =
      if dims == 1 do
        # Extract first column as 1D vector
        Nx.slice_along_axis(v, 0, 1, axis: 1) |> Nx.squeeze(axes: [1])
      else
        # Take first 'dims' columns
        Nx.slice_along_axis(v, 0, dims, axis: 1)
      end

    # Project samples onto principal components
    proj =
      if dims == 1 do
        # Result is [N] vector
        Nx.dot(centered, basis)
      else
        # Result is [N, dims] matrix
        Nx.dot(centered, basis)
      end

    {mean, basis, proj}
  end

  defp build_histogram(proj_samples, bins) do
    # For 1D case, proj_samples is [N] vector
    # For 2D case, would be [N, 2] matrix (future work)

    # Find min/max
    min_val = Nx.reduce_min(proj_samples) |> Nx.to_number()
    max_val = Nx.reduce_max(proj_samples) |> Nx.to_number()

    # Handle degenerate case
    {min_val, max_val} =
      if abs(max_val - min_val) < 1.0e-6 do
        {min_val - 1.0e-6, max_val + 1.0e-6}
      else
        {min_val, max_val}
      end

    # Create bin edges: linspace from min to max with bins+1 points
    bin_edges = Nx.linspace(min_val, max_val, n: bins + 1)
    bin_edges_list = Nx.to_flat_list(bin_edges)

    # Count samples in each bin
    proj_list = Nx.to_flat_list(proj_samples)
    counts = count_bins(proj_list, bin_edges_list, bins)

    # Normalize to probabilities
    total = Enum.sum(counts)
    probs = Enum.map(counts, fn c -> c / total end)

    {bin_edges, Nx.tensor(probs)}
  end

  defp count_bins(samples, bin_edges, bins) do
    # Initialize counts
    counts = List.duplicate(0, bins)

    # Bin each sample
    Enum.reduce(samples, counts, fn sample, acc ->
      bin_idx = find_bin_index(sample, bin_edges)

      if bin_idx >= 0 and bin_idx < bins do
        List.update_at(acc, bin_idx, &(&1 + 1))
      else
        acc
      end
    end)
  end

  defp find_bin_index(value, bin_edges) do
    # Find which bin this value falls into
    # bin_edges is a list of length bins+1
    # Return index i where bin_edges[i] <= value < bin_edges[i+1]

    bins = length(bin_edges) - 1

    cond do
      value < Enum.at(bin_edges, 0) ->
        -1

      # Last edge is inclusive
      value >= Enum.at(bin_edges, bins) ->
        bins

      true ->
        # Binary search
        Enum.reduce_while(0..(bins - 1), -1, fn i, _acc ->
          if value >= Enum.at(bin_edges, i) and value < Enum.at(bin_edges, i + 1) do
            {:halt, i}
          else
            {:cont, -1}
          end
        end)
    end
  end
end
