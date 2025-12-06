defmodule Thunderline.Thunderbolt.Rules.HiddenDiffusion do
  @moduledoc """
  HiddenDiffusion — Toy rule demonstrating hidden channel communication.

  This rule implements simple diffusion of hidden state vectors across
  neighboring cells, showing how NCA-style hidden channels can be used
  for inter-bit communication.

  ## Hidden State Structure

  Each Thunderbit has a `hidden_state` field:
  ```elixir
  %{v: [float()], dim: non_neg_integer()}
  ```

  Where `v` is a vector of hidden channel values and `dim` is its dimension.

  ## Algorithm

  For each cell:
  1. Collect hidden vectors from all neighbors
  2. Compute average of neighbor hidden states
  3. Blend own hidden state toward neighbor average (diffusion)
  4. Optionally add small noise for exploration

  ```
  h_new = (1 - α) * h_self + α * mean(h_neighbors) + ε
  ```

  Where:
  - α = diffusion rate (how fast hidden state spreads)
  - ε = small Gaussian noise

  ## Parameters

  - `:dim` - Hidden state dimension (default: 4)
  - `:diffusion_rate` - α, how fast to blend toward neighbors (default: 0.3)
  - `:noise_scale` - ε scale for exploration (default: 0.01)
  - `:init_range` - Range for random initialization (default: {-1.0, 1.0})

  ## Use Cases

  - Testing hidden channel infrastructure
  - Simple emergent pattern formation
  - Basis for more complex NCA rules with learned updates

  ## Reference

  - Mordvintsev et al. "Growing Neural Cellular Automata" (2020)
  - HC Orders: Operation TIGER LATTICE, Doctrine Layer
  """

  @behaviour Thunderline.Thunderbolt.Rule

  alias Thunderline.Thunderbolt.Thunderbit

  @default_dim 4
  @default_diffusion_rate 0.3
  @default_noise_scale 0.01
  @default_init_range {-1.0, 1.0}

  # ═══════════════════════════════════════════════════════════════
  # Rule Behaviour Implementation
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def backend_type, do: :hidden_diffusion

  @impl true
  def init_params(opts \\ []) do
    dim = Keyword.get(opts, :dim, @default_dim)
    diffusion_rate = Keyword.get(opts, :diffusion_rate, @default_diffusion_rate)
    noise_scale = Keyword.get(opts, :noise_scale, @default_noise_scale)
    init_range = Keyword.get(opts, :init_range, @default_init_range)

    %{
      dim: dim,
      diffusion_rate: diffusion_rate,
      noise_scale: noise_scale,
      init_range: init_range
    }
  end

  @impl true
  def update(cell, neighbors, params) do
    dim = Map.get(params, :dim, @default_dim)
    diffusion_rate = Map.get(params, :diffusion_rate, @default_diffusion_rate)
    noise_scale = Map.get(params, :noise_scale, @default_noise_scale)

    # Get or initialize hidden state
    {self_hidden, initialized?} = get_or_init_hidden(cell, dim, params)

    # Get neighbor hidden states
    neighbor_hiddens = extract_neighbor_hiddens(neighbors, dim)

    # Compute diffused hidden state
    new_hidden =
      if Enum.empty?(neighbor_hiddens) do
        # No neighbors - just add noise
        add_noise(self_hidden, noise_scale)
      else
        # Diffuse toward neighbor average
        neighbor_avg = compute_mean_vector(neighbor_hiddens)
        diffused = blend_vectors(self_hidden, neighbor_avg, diffusion_rate)
        add_noise(diffused, noise_scale)
      end

    # Update cell with new hidden state
    new_cell = update_cell_hidden(cell, new_hidden, dim)

    # Compute side-quest metrics
    metrics = compute_metrics(self_hidden, new_hidden, neighbor_hiddens, initialized?)

    {:ok, new_cell, metrics}
  end

  # ═══════════════════════════════════════════════════════════════
  # Hidden State Operations
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Gets the hidden state from a cell, or initializes it if not present.

  Returns {hidden_vector, was_initialized?}.
  """
  def get_or_init_hidden(cell, dim, params) do
    case extract_hidden_state(cell) do
      nil ->
        # Initialize new hidden state
        {init_range_min, init_range_max} = Map.get(params, :init_range, @default_init_range)
        new_hidden = init_hidden_vector(dim, init_range_min, init_range_max)
        {new_hidden, true}

      %{v: v, dim: d} when is_list(v) and length(v) > 0 and d == dim ->
        # Valid hidden state of correct dimension
        {v, false}

      %{v: v} when is_list(v) and length(v) > 0 ->
        # Wrong dimension - resize
        resized = resize_vector(v, dim)
        {resized, true}

      _ ->
        # Invalid or empty - reinitialize
        {init_range_min, init_range_max} = Map.get(params, :init_range, @default_init_range)
        new_hidden = init_hidden_vector(dim, init_range_min, init_range_max)
        {new_hidden, true}
    end
  end

  @doc """
  Extracts hidden state from a cell (handles both Thunderbit struct and maps).
  """
  def extract_hidden_state(%Thunderbit{hidden_state: hs}), do: hs
  def extract_hidden_state(%{hidden_state: hs}), do: hs
  def extract_hidden_state(_), do: nil

  @doc """
  Extracts hidden vectors from neighbor list.
  """
  def extract_neighbor_hiddens(neighbors, dim) do
    neighbors
    |> Enum.map(fn
      {_coord, neighbor} -> extract_hidden_state(neighbor)
      neighbor -> extract_hidden_state(neighbor)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn
      %{v: v} when is_list(v) and length(v) == dim -> v
      %{v: v} when is_list(v) -> resize_vector(v, dim)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Initializes a random hidden vector.
  """
  def init_hidden_vector(dim, min_val \\ -1.0, max_val \\ 1.0) do
    range = max_val - min_val

    for _ <- 1..dim do
      :rand.uniform() * range + min_val
    end
  end

  @doc """
  Resizes a vector to the target dimension (truncate or pad with zeros).
  """
  def resize_vector(v, target_dim) when length(v) == target_dim, do: v

  def resize_vector(v, target_dim) when length(v) > target_dim do
    Enum.take(v, target_dim)
  end

  def resize_vector(v, target_dim) do
    padding = List.duplicate(0.0, target_dim - length(v))
    v ++ padding
  end

  # ═══════════════════════════════════════════════════════════════
  # Vector Operations
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes the element-wise mean of a list of vectors.
  """
  def compute_mean_vector([]), do: []

  def compute_mean_vector(vectors) do
    n = length(vectors)
    dim = length(hd(vectors))

    # Sum element-wise
    sums =
      Enum.reduce(vectors, List.duplicate(0.0, dim), fn vec, acc ->
        Enum.zip_with(acc, vec, &(&1 + &2))
      end)

    # Divide by count
    Enum.map(sums, &(&1 / n))
  end

  @doc """
  Blends two vectors: result = (1 - rate) * v1 + rate * v2
  """
  def blend_vectors(v1, v2, rate) when is_list(v1) and is_list(v2) do
    complement = 1.0 - rate

    Enum.zip_with(v1, v2, fn a, b ->
      complement * a + rate * b
    end)
  end

  @doc """
  Adds small Gaussian noise to a vector.
  """
  def add_noise(v, scale) when scale > 0 do
    Enum.map(v, fn x ->
      # Box-Muller for Gaussian noise
      u1 = :rand.uniform()
      u2 = :rand.uniform()
      noise = :math.sqrt(-2.0 * :math.log(u1)) * :math.cos(2.0 * :math.pi() * u2)
      x + noise * scale
    end)
  end

  def add_noise(v, _scale), do: v

  # ═══════════════════════════════════════════════════════════════
  # Cell Update
  # ═══════════════════════════════════════════════════════════════

  defp update_cell_hidden(%Thunderbit{} = cell, new_hidden, dim) do
    %{cell | hidden_state: %{v: new_hidden, dim: dim}}
  end

  defp update_cell_hidden(cell, new_hidden, dim) when is_map(cell) do
    Map.put(cell, :hidden_state, %{v: new_hidden, dim: dim})
  end

  # ═══════════════════════════════════════════════════════════════
  # Metrics
  # ═══════════════════════════════════════════════════════════════

  defp compute_metrics(old_hidden, new_hidden, neighbor_hiddens, initialized?) do
    # Divergence: how much did our hidden state change?
    divergence =
      if initialized? do
        1.0  # Maximum divergence on initialization
      else
        compute_vector_distance(old_hidden, new_hidden)
      end

    # Clustering: similarity to neighbors (inverse of average distance)
    clustering =
      if Enum.empty?(neighbor_hiddens) do
        0.5
      else
        distances =
          Enum.map(neighbor_hiddens, &compute_vector_distance(new_hidden, &1))

        avg_distance = Enum.sum(distances) / length(distances)
        # Convert distance to similarity (1 / (1 + d))
        1.0 / (1.0 + avg_distance)
      end

    # Entropy: variance of hidden state values
    entropy = compute_vector_variance(new_hidden)

    %{
      divergence: Float.round(divergence, 4),
      clustering: Float.round(clustering, 4),
      entropy: Float.round(entropy, 4)
    }
  end

  defp compute_vector_distance(v1, v2) when length(v1) == length(v2) do
    sum_sq =
      Enum.zip_with(v1, v2, fn a, b -> (a - b) * (a - b) end)
      |> Enum.sum()

    :math.sqrt(sum_sq)
  end

  defp compute_vector_distance(_, _), do: 1.0

  defp compute_vector_variance([]), do: 0.0

  defp compute_vector_variance(v) do
    mean = Enum.sum(v) / length(v)

    variance =
      v
      |> Enum.map(fn x -> (x - mean) * (x - mean) end)
      |> Enum.sum()
      |> Kernel./(length(v))

    # Normalize to [0, 1] range (assuming values in [-1, 1])
    min(1.0, variance)
  end
end
