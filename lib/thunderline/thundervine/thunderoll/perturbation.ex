defmodule Thunderline.Thundervine.Thunderoll.Perturbation do
  @moduledoc """
  Low-rank perturbation generation for EGGROLL.

  Instead of sampling full-rank noise E ∈ R^(m×n), we sample:
    A ∈ R^(m×r)
    B ∈ R^(n×r)
  And form the perturbation as A·Bᵀ.

  ## Memory Efficiency

  - Full-rank ES: O(mn) storage per perturbation
  - Low-rank ES: O(r(m+n)) storage per perturbation

  For a 1B parameter model with m=n=32768 and r=1:
  - Full-rank: 1B floats = 4GB per perturbation
  - Low-rank: 65536 floats = 256KB per perturbation

  ## Forward Pass Efficiency

  Instead of:
    y = x @ (W + E)ᵀ = x @ Wᵀ + x @ Eᵀ  # O(mn) for x @ Eᵀ

  We compute:
    y = x @ Wᵀ + (x @ B) @ Aᵀ  # O(r(m+n)) total

  ## Full-Rank Updates via Aggregation

  Key insight from EGGROLL: while individual perturbations are low-rank,
  the aggregated update Σ(fᵢ * Aᵢ * Bᵢᵀ) is full-rank when
  population_size >= hidden_dim.
  """

  require Logger

  defstruct [:a, :b, :seed, :sigma, :shape]

  @type t :: %__MODULE__{
          a: Nx.Tensor.t(),
          b: Nx.Tensor.t(),
          seed: integer(),
          sigma: float(),
          shape: {pos_integer(), pos_integer()}
        }

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Sample perturbations for entire population.

  Uses deterministic key derivation so perturbations can be
  reconstructed from seeds without storing full matrices.
  This is critical for communication with remote backends.

  ## Parameters

  - `param_shape` - Shape of the parameter matrix {m, n}
  - `population_size` - Number of perturbations to sample
  - `rank` - Low-rank dimension r
  - `sigma` - Standard deviation of noise
  - `base_key` - Base RNG key
  - `generation` - Current generation (for key derivation)

  ## Returns

  List of `%Perturbation{}` structs, one per population member.
  """
  @spec sample_population(
          {pos_integer(), pos_integer()},
          pos_integer(),
          pos_integer(),
          float(),
          integer(),
          non_neg_integer()
        ) :: [t()]
  def sample_population(param_shape, population_size, rank, sigma, base_key, generation) do
    # Fold generation into base key for reproducibility
    gen_key = fold_key(base_key, generation)

    for member_idx <- 0..(population_size - 1) do
      # Deterministic key folding (matches JAX pattern from EGGROLL)
      member_key = fold_key(gen_key, member_idx)
      sample_one(param_shape, rank, sigma, member_key)
    end
  end

  @doc """
  Sample a single perturbation.
  """
  @spec sample_one({pos_integer(), pos_integer()}, pos_integer(), float(), integer()) :: t()
  def sample_one({m, n} = shape, rank, sigma, key) do
    # Split key for A and B
    {key_a, key_b} = split_key(key)

    # Sample A and B from N(0, 1)
    a = random_normal({m, rank}, key_a)
    b = random_normal({n, rank}, key_b)

    %__MODULE__{
      a: a,
      b: b,
      seed: key,
      sigma: sigma,
      shape: shape
    }
  end

  @doc """
  Apply perturbation to base parameters for forward pass.

  perturbed_output = base_output + sigma * (x @ B) @ Aᵀ

  This is computed efficiently as:
    x @ perturbed.T = x @ base.T + sigma * (x @ B) @ A.T

  The trick is that we never materialize the full (m×n) perturbation.
  """
  @spec apply(t(), Nx.Tensor.t(), Nx.Tensor.t()) :: Nx.Tensor.t()
  def apply(%__MODULE__{} = pert, base_params, input) do
    # Base forward pass (standard)
    base_output = Nx.dot(input, Nx.transpose(base_params))

    # Low-rank correction: O(r(m+n)) instead of O(mn)
    x_b = Nx.dot(input, pert.b)
    correction = Nx.dot(x_b, Nx.transpose(pert.a))

    # Combined output
    Nx.add(base_output, Nx.multiply(correction, pert.sigma))
  end

  @doc """
  Compute the outer product A @ Bᵀ (materializes full perturbation).

  This is used during the update aggregation step, not during forward passes.
  """
  @spec outer_product(t()) :: Nx.Tensor.t()
  def outer_product(%__MODULE__{a: a, b: b}) do
    Nx.dot(a, Nx.transpose(b))
  end

  @doc """
  Reconstruct perturbation from seed (for communication with remote backends).

  This allows us to send just the seed and reconstruct the full perturbation
  on the remote side, dramatically reducing communication overhead.
  """
  @spec from_seed({pos_integer(), pos_integer()}, pos_integer(), float(), integer()) :: t()
  def from_seed(shape, rank, sigma, seed) do
    sample_one(shape, rank, sigma, seed)
  end

  @doc """
  Get seeds from a list of perturbations for remote transmission.
  """
  @spec extract_seeds([t()]) :: [integer()]
  def extract_seeds(perturbations) do
    Enum.map(perturbations, & &1.seed)
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  # Key folding - deterministic key derivation
  # This matches the JAX pattern: jax.random.fold_in(key, data)
  defp fold_key(key, data) when is_integer(key) and is_integer(data) do
    # Simple but effective: XOR with rotated data
    # In production, use a proper hash like MurmurHash3
    rotated = Integer.mod(data * 2654435761, 2 ** 32)
    Bitwise.bxor(key, rotated)
  end

  # Split key into two independent keys
  defp split_key(key) do
    key1 = fold_key(key, 0)
    key2 = fold_key(key, 1)
    {key1, key2}
  end

  # Generate random normal tensor using Nx
  defp random_normal(shape, key) do
    # Seed the RNG
    :rand.seed(:exsss, {key, key + 1, key + 2})

    # Generate standard normal samples
    flat_size = Tuple.product(shape)

    values =
      for _ <- 1..flat_size do
        # Box-Muller transform for normal distribution
        u1 = :rand.uniform()
        u2 = :rand.uniform()
        :math.sqrt(-2.0 * :math.log(u1)) * :math.cos(2.0 * :math.pi() * u2)
      end

    values
    |> Nx.tensor(type: :f32)
    |> Nx.reshape(shape)
  end
end
