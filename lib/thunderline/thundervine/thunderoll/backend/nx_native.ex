defmodule Thunderline.Thundervine.Thunderoll.Backend.NxNative do
  @moduledoc """
  Pure Elixir/Nx implementation of EGGROLL backend.

  This backend runs entirely within the BEAM, making it suitable for:
  - On-device / embedded deployments (Nerves)
  - Low-latency scenarios
  - Development and testing
  - Smaller population sizes (<10k members)

  For larger populations or GPU acceleration, use `RemoteJax`.

  ## Nx Backend Selection

  The Nx backend used for tensor operations can be configured:

      # Use EXLA for GPU/TPU acceleration (if available)
      Nx.default_backend(EXLA.Backend)

      # Use BinaryBackend for pure CPU (default)
      Nx.default_backend(Nx.BinaryBackend)
  """

  @behaviour Thunderline.Thundervine.Thunderoll.Backend

  alias Thunderline.Thundervine.Thunderoll.Perturbation

  require Logger

  # ═══════════════════════════════════════════════════════════════
  # BEHAVIOUR IMPLEMENTATION
  # ═══════════════════════════════════════════════════════════════

  @impl true
  def compute_update(perturbation_seeds, fitness_vector, config) do
    {m, n} = config.param_shape
    rank = config.rank
    sigma = config.sigma
    n_pop = length(perturbation_seeds)

    Logger.debug("[Thunderoll.NxNative] Computing update for #{n_pop} members")

    start_time = System.monotonic_time(:microsecond)

    # Reconstruct perturbations from seeds and compute weighted sum
    delta =
      perturbation_seeds
      |> Enum.zip(fitness_vector)
      |> Enum.reduce(Nx.broadcast(0.0, {m, n}), fn {seed, fitness}, acc ->
        # Reconstruct perturbation from seed
        pert = Perturbation.from_seed({m, n}, rank, sigma, seed)

        # Compute fitness-weighted outer product
        outer = Perturbation.outer_product(pert)
        weighted = Nx.multiply(outer, fitness)

        Nx.add(acc, weighted)
      end)

    # Scale by 1/(N*σ) - ES gradient estimator
    scale = 1.0 / (n_pop * sigma)
    scaled_delta = Nx.multiply(delta, scale)

    duration_us = System.monotonic_time(:microsecond) - start_time

    Logger.debug("[Thunderoll.NxNative] Update computed in #{duration_us}μs")

    {:ok, %{weights: scaled_delta}}
  end

  @impl true
  def healthy? do
    # Native backend is always available
    true
  end

  @impl true
  def info do
    nx_backend = Nx.default_backend()

    %{
      type: :nx_native,
      nx_backend: nx_backend,
      healthy: true
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # OPTIMIZED IMPLEMENTATIONS
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Vectorized update computation using Nx operations.

  This is more efficient for larger populations as it avoids
  Enum iteration overhead.
  """
  def compute_update_vectorized(perturbation_seeds, fitness_vector, config) do
    {m, n} = config.param_shape
    rank = config.rank
    sigma = config.sigma
    n_pop = length(perturbation_seeds)

    # Pre-generate all A and B matrices
    {all_a, all_b} = generate_all_perturbations(perturbation_seeds, {m, n}, rank)

    # Convert fitness to tensor [N, 1, 1] for broadcasting
    fitness_tensor =
      fitness_vector
      |> Nx.tensor(type: :f32)
      |> Nx.reshape({n_pop, 1, 1})

    # Batch outer product: [N, m, r] @ [N, r, n] -> [N, m, n]
    # This leverages Nx's batched matmul
    all_b_transposed = Nx.transpose(all_b, axes: [0, 2, 1])
    outer_products = Nx.dot(all_a, [2], [0], all_b_transposed, [1], [0])

    # Apply fitness weights
    weighted = Nx.multiply(outer_products, fitness_tensor)

    # Sum across population and scale
    delta = Nx.sum(weighted, axes: [0])
    scale = 1.0 / (n_pop * sigma)
    scaled_delta = Nx.multiply(delta, scale)

    {:ok, %{weights: scaled_delta}}
  end

  defp generate_all_perturbations(seeds, {m, n}, rank) do
    n_pop = length(seeds)

    # Generate all perturbations and stack into batched tensors
    perturbations = Enum.map(seeds, &Perturbation.from_seed({m, n}, rank, 1.0, &1))

    all_a =
      perturbations
      |> Enum.map(& &1.a)
      |> Nx.stack()

    all_b =
      perturbations
      |> Enum.map(& &1.b)
      |> Nx.stack()

    {all_a, all_b}
  end
end
