defmodule Thunderline.Thunderbolt.Evolution.Mutation do
  @moduledoc """
  Mutation and crossover operators for PAC evolution (HC-Δ-4).

  Provides genetic operators for evolving PAC trait vectors and rulesets
  within the MAP-Elites quality-diversity framework.

  ## Mutation Operators

  - **Gaussian**: Add Gaussian noise to trait values
  - **Uniform**: Reset traits to random values
  - **Polynomial**: Non-uniform mutation with configurable distribution
  - **Adaptive**: Mutation strength based on fitness landscape

  ## Crossover Operators

  - **Uniform**: Each gene from random parent
  - **Single-point**: Split at random point
  - **SBX**: Simulated binary crossover

  ## Usage

      # Mutate a PAC
      mutated = Mutation.mutate(pac, rate: 0.1)

      # Crossover two PACs
      child = Mutation.crossover(parent1, parent2)

      # Generate random PAC
      random_pac = Mutation.random_pac()

  ## Trait Vector Format

  Trait vectors are lists of floats in [0.0, 1.0], representing:
  - Gate probabilities for cellular automata
  - Hyperparameters for ML components
  - Behavioral tendencies
  """

  @type pac :: map()
  @type trait_vector :: [float()]

  # Default trait vector length
  @trait_dimensions 64
  @min_value 0.0
  @max_value 1.0

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API - MUTATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Mutates a PAC using the configured strategy.

  ## Options
  - `:rate` - Mutation rate per gene (default: 0.1)
  - `:strategy` - Mutation strategy (default: :gaussian)
    - `:gaussian` - Gaussian noise
    - `:uniform` - Random reset
    - `:polynomial` - Polynomial mutation
  - `:sigma` - Standard deviation for Gaussian (default: 0.1)
  - `:eta` - Distribution index for polynomial (default: 20)
  """
  @spec mutate(pac(), keyword()) :: pac()
  def mutate(pac, opts \\ []) do
    rate = Keyword.get(opts, :rate, 0.1)
    strategy = Keyword.get(opts, :strategy, :gaussian)

    traits = get_traits(pac)
    mutated_traits = mutate_vector(traits, rate, strategy, opts)

    put_traits(pac, mutated_traits)
  end

  @doc """
  Mutates a trait vector.
  """
  @spec mutate_vector(trait_vector(), float(), atom(), keyword()) :: trait_vector()
  def mutate_vector(traits, rate, strategy, opts \\ []) do
    Enum.map(traits, fn value ->
      if :rand.uniform() < rate do
        apply_mutation(value, strategy, opts)
      else
        value
      end
    end)
  end

  @doc """
  Applies Gaussian mutation to a single value.
  """
  @spec gaussian_mutate(float(), float()) :: float()
  def gaussian_mutate(value, sigma \\ 0.1) do
    noise = :rand.normal() * sigma
    clamp(value + noise)
  end

  @doc """
  Applies polynomial mutation to a single value.

  Polynomial mutation is useful for fine-grained local search
  with occasional larger jumps.
  """
  @spec polynomial_mutate(float(), float()) :: float()
  def polynomial_mutate(value, eta \\ 20.0) do
    u = :rand.uniform()

    delta =
      if u < 0.5 do
        :math.pow(2.0 * u, 1.0 / (eta + 1.0)) - 1.0
      else
        1.0 - :math.pow(2.0 * (1.0 - u), 1.0 / (eta + 1.0))
      end

    clamp(value + delta * (@max_value - @min_value))
  end

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API - CROSSOVER
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Performs crossover between two PACs.

  ## Options
  - `:strategy` - Crossover strategy (default: :uniform)
    - `:uniform` - Each gene from random parent
    - `:single_point` - Single crossover point
    - `:two_point` - Two crossover points
    - `:sbx` - Simulated binary crossover
  - `:eta` - Distribution index for SBX (default: 15)
  """
  @spec crossover(pac(), pac(), keyword()) :: pac()
  def crossover(parent1, parent2, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :uniform)

    traits1 = get_traits(parent1)
    traits2 = get_traits(parent2)

    # Ensure same length
    {traits1, traits2} = normalize_lengths(traits1, traits2)

    child_traits =
      case strategy do
        :uniform -> uniform_crossover(traits1, traits2)
        :single_point -> single_point_crossover(traits1, traits2)
        :two_point -> two_point_crossover(traits1, traits2)
        :sbx -> sbx_crossover(traits1, traits2, opts)
      end

    # Inherit structure from first parent, traits from crossover
    put_traits(parent1, child_traits)
  end

  @doc """
  Uniform crossover - each gene from random parent.
  """
  @spec uniform_crossover(trait_vector(), trait_vector()) :: trait_vector()
  def uniform_crossover(traits1, traits2) do
    Enum.zip(traits1, traits2)
    |> Enum.map(fn {v1, v2} ->
      if :rand.uniform() < 0.5, do: v1, else: v2
    end)
  end

  @doc """
  Single-point crossover.
  """
  @spec single_point_crossover(trait_vector(), trait_vector()) :: trait_vector()
  def single_point_crossover(traits1, traits2) do
    point = :rand.uniform(length(traits1))
    {head1, _tail1} = Enum.split(traits1, point)
    {_head2, tail2} = Enum.split(traits2, point)
    head1 ++ tail2
  end

  @doc """
  Two-point crossover.
  """
  @spec two_point_crossover(trait_vector(), trait_vector()) :: trait_vector()
  def two_point_crossover(traits1, traits2) do
    len = length(traits1)
    p1 = :rand.uniform(len)
    p2 = :rand.uniform(len)
    {start, stop} = if p1 < p2, do: {p1, p2}, else: {p2, p1}

    traits1
    |> Enum.with_index()
    |> Enum.map(fn {v1, i} ->
      if i >= start and i < stop do
        Enum.at(traits2, i)
      else
        v1
      end
    end)
  end

  @doc """
  Simulated Binary Crossover (SBX).

  Produces offspring distributed around parents with controllable spread.
  """
  @spec sbx_crossover(trait_vector(), trait_vector(), keyword()) :: trait_vector()
  def sbx_crossover(traits1, traits2, opts \\ []) do
    eta = Keyword.get(opts, :eta, 15.0)

    Enum.zip(traits1, traits2)
    |> Enum.map(fn {v1, v2} ->
      sbx_gene(v1, v2, eta)
    end)
  end

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API - RANDOM GENERATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Generates a random PAC with random traits.

  ## Options
  - `:dimensions` - Trait vector length (default: 64)
  - `:id` - PAC ID (auto-generated if not provided)
  """
  @spec random_pac(keyword()) :: pac()
  def random_pac(opts \\ []) do
    dimensions = Keyword.get(opts, :dimensions, @trait_dimensions)
    id = Keyword.get(opts, :id, Thunderline.UUID.v7())

    traits = random_vector(dimensions)

    %{
      id: id,
      name: "pac_#{String.slice(id, 0..7)}",
      trait_vector: traits,
      ruleset: generate_random_ruleset(traits),
      metadata: %{
        generation: 0,
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Generates a random trait vector.
  """
  @spec random_vector(pos_integer()) :: trait_vector()
  def random_vector(dimensions \\ @trait_dimensions) do
    Enum.map(1..dimensions, fn _ -> :rand.uniform() end)
  end

  @doc """
  Generates a random ruleset from trait vector.

  The first 16 traits encode CA gate probabilities,
  remaining traits encode behavioral parameters.
  """
  @spec generate_random_ruleset(trait_vector()) :: map()
  def generate_random_ruleset(traits) do
    gate_probs = Enum.take(traits, 16)

    %{
      gates:
        Enum.with_index(gate_probs, fn prob, i ->
          {gate_name(i), prob > 0.5}
        end)
        |> Map.new(),
      threshold: Enum.at(traits, 16, 0.5),
      neighborhood: if(Enum.at(traits, 17, 0.5) > 0.5, do: :moore, else: :von_neumann),
      update_rule: if(Enum.at(traits, 18, 0.5) > 0.5, do: :synchronous, else: :asynchronous)
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # PUBLIC API - ADAPTIVE MUTATION
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes adaptive mutation rate based on fitness history.

  Decreases mutation rate when fitness is improving,
  increases when stagnating.
  """
  @spec adaptive_rate(float(), [float()], keyword()) :: float()
  def adaptive_rate(base_rate, fitness_history, opts \\ []) do
    min_rate = Keyword.get(opts, :min_rate, 0.01)
    max_rate = Keyword.get(opts, :max_rate, 0.5)

    if length(fitness_history) < 2 do
      base_rate
    else
      # Check if fitness is improving
      recent = Enum.take(fitness_history, 10)
      improvement = List.first(recent) - List.last(recent)

      adjusted =
        cond do
          improvement > 0.01 ->
            # Improving - decrease exploration
            base_rate * 0.9

          improvement < -0.01 ->
            # Declining - increase exploration
            base_rate * 1.1

          true ->
            # Stagnating - increase exploration
            base_rate * 1.05
        end

      clamp(adjusted, min_rate, max_rate)
    end
  end

  @doc """
  Computes mutation strength based on dimension-specific sensitivity.

  Some traits may be more sensitive to mutation than others.
  """
  @spec dimension_adaptive_sigma(trait_vector(), non_neg_integer(), keyword()) :: float()
  def dimension_adaptive_sigma(traits, dimension, opts \\ []) do
    base_sigma = Keyword.get(opts, :base_sigma, 0.1)
    sensitivity = Keyword.get(opts, :sensitivity, [])

    # Get dimension-specific sensitivity or use default
    dim_sensitivity = Enum.at(sensitivity, dimension, 1.0)

    # Scale sigma by trait value (larger values = smaller mutations)
    value = Enum.at(traits, dimension, 0.5)
    value_factor = 1.0 - 0.5 * value

    base_sigma * dim_sensitivity * value_factor
  end

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE HELPERS
  # ═══════════════════════════════════════════════════════════════

  defp apply_mutation(value, :gaussian, opts) do
    sigma = Keyword.get(opts, :sigma, 0.1)
    gaussian_mutate(value, sigma)
  end

  defp apply_mutation(_value, :uniform, _opts) do
    :rand.uniform()
  end

  defp apply_mutation(value, :polynomial, opts) do
    eta = Keyword.get(opts, :eta, 20.0)
    polynomial_mutate(value, eta)
  end

  defp apply_mutation(value, _unknown, _opts) do
    gaussian_mutate(value, 0.1)
  end

  defp sbx_gene(v1, v2, _eta) when v1 == v2, do: v1

  defp sbx_gene(v1, v2, eta) do
    u = :rand.uniform()

    beta =
      if u <= 0.5 do
        :math.pow(2.0 * u, 1.0 / (eta + 1.0))
      else
        :math.pow(1.0 / (2.0 * (1.0 - u)), 1.0 / (eta + 1.0))
      end

    child = 0.5 * ((1.0 + beta) * v1 + (1.0 - beta) * v2)
    clamp(child)
  end

  defp get_traits(%{trait_vector: traits}) when is_list(traits), do: traits
  defp get_traits(_), do: random_vector()

  defp put_traits(pac, traits) when is_map(pac) do
    pac
    |> Map.put(:trait_vector, traits)
    |> Map.update(:ruleset, %{}, fn ruleset ->
      Map.merge(ruleset, generate_random_ruleset(traits))
    end)
  end

  defp put_traits(_, traits), do: %{trait_vector: traits}

  defp normalize_lengths(traits1, traits2) do
    len1 = length(traits1)
    len2 = length(traits2)

    cond do
      len1 == len2 ->
        {traits1, traits2}

      len1 < len2 ->
        padding = Enum.map(1..(len2 - len1), fn _ -> 0.5 end)
        {traits1 ++ padding, traits2}

      true ->
        padding = Enum.map(1..(len1 - len2), fn _ -> 0.5 end)
        {traits1, traits2 ++ padding}
    end
  end

  defp clamp(value), do: clamp(value, @min_value, @max_value)

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end

  defp gate_name(index) do
    gates = [
      :and,
      :or,
      :xor,
      :nand,
      :nor,
      :xnor,
      :buffer,
      :not,
      :imply,
      :nimply,
      :majority,
      :minority,
      :parity,
      :threshold,
      :random,
      :latch
    ]

    Enum.at(gates, index, :and)
  end
end
