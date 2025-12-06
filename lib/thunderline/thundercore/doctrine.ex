defmodule Thunderline.Thundercore.Doctrine do
  @moduledoc """
  Doctrine — Thunderbit behavioral classification and Ising spin encoding.

  Each Thunderbit can have a "doctrine" that describes its behavioral tendency:
  - `:router` — Focuses on message routing and path optimization
  - `:healer` — Focuses on error recovery and state repair
  - `:compressor` — Focuses on data compression and efficiency
  - `:explorer` — Focuses on novelty seeking and exploration
  - `:guardian` — Focuses on security and boundary protection
  - `:general` — No specific behavioral bias

  ## Ising Spin Model

  For energy calculations, doctrines are encoded as spins:
  - Cooperative doctrines (router, healer) → +1.0
  - Exploratory doctrines (explorer) → -1.0
  - Neutral doctrines (compressor, guardian, general) → 0.0

  The Ising energy measures clustering tendency:
  - Low energy (negative) → like doctrines cluster together
  - High energy (positive) → unlike doctrines are adjacent

  ## Future: Potts Model

  The spin encoding is abstracted through `encode_spin/1` so we can
  upgrade to a multi-dimensional Potts model later without changing
  the rest of the system.

  ## Reference

  - HC Orders: Operation TIGER LATTICE, Doctrine Layer
  - Research: Lex/Friedman "Learning to Be Efficient" (bubble sort algotypes)
  """

  alias Thunderline.Thundercore.Thunderbit

  @type doctrine :: Thunderbit.doctrine()
  @type spin :: float()

  @cooperative_doctrines [:router, :healer]
  @exploratory_doctrines [:explorer]
  @neutral_doctrines [:compressor, :guardian, :general]

  @all_doctrines @cooperative_doctrines ++ @exploratory_doctrines ++ @neutral_doctrines

  # ═══════════════════════════════════════════════════════════════
  # Doctrine Classification
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Returns all valid doctrine values.
  """
  @spec all() :: [doctrine()]
  def all, do: @all_doctrines

  @doc """
  Returns cooperative doctrines (stabilizing behavior).
  """
  @spec cooperative() :: [doctrine()]
  def cooperative, do: @cooperative_doctrines

  @doc """
  Returns exploratory doctrines (disruptive/novel-seeking behavior).
  """
  @spec exploratory() :: [doctrine()]
  def exploratory, do: @exploratory_doctrines

  @doc """
  Returns neutral doctrines (no strong bias).
  """
  @spec neutral() :: [doctrine()]
  def neutral, do: @neutral_doctrines

  @doc """
  Checks if a doctrine is cooperative.
  """
  @spec cooperative?(doctrine()) :: boolean()
  def cooperative?(doctrine), do: doctrine in @cooperative_doctrines

  @doc """
  Checks if a doctrine is exploratory.
  """
  @spec exploratory?(doctrine()) :: boolean()
  def exploratory?(doctrine), do: doctrine in @exploratory_doctrines

  @doc """
  Checks if a doctrine is neutral.
  """
  @spec neutral?(doctrine()) :: boolean()
  def neutral?(doctrine), do: doctrine in @neutral_doctrines

  # ═══════════════════════════════════════════════════════════════
  # Ising Spin Encoding
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Encodes a doctrine as an Ising spin value.

  Returns:
  - `+1.0` for cooperative doctrines (router, healer)
  - `-1.0` for exploratory doctrines (explorer)
  - `0.0` for neutral doctrines (compressor, guardian, general)

  ## Examples

      iex> Doctrine.encode_spin(:router)
      1.0

      iex> Doctrine.encode_spin(:explorer)
      -1.0

      iex> Doctrine.encode_spin(:general)
      0.0
  """
  @spec encode_spin(doctrine()) :: spin()
  def encode_spin(doctrine) when doctrine in @cooperative_doctrines, do: 1.0
  def encode_spin(doctrine) when doctrine in @exploratory_doctrines, do: -1.0
  def encode_spin(doctrine) when doctrine in @neutral_doctrines, do: 0.0
  def encode_spin(_), do: 0.0

  @doc """
  Decodes a spin value back to a doctrine category.

  Returns the category (:cooperative, :exploratory, :neutral) not
  the specific doctrine, since spin→doctrine is not bijective.

  ## Examples

      iex> Doctrine.decode_spin(1.0)
      :cooperative

      iex> Doctrine.decode_spin(-1.0)
      :exploratory

      iex> Doctrine.decode_spin(0.0)
      :neutral
  """
  @spec decode_spin(spin()) :: :cooperative | :exploratory | :neutral
  def decode_spin(spin) when spin > 0.5, do: :cooperative
  def decode_spin(spin) when spin < -0.5, do: :exploratory
  def decode_spin(_), do: :neutral

  # ═══════════════════════════════════════════════════════════════
  # Ising Energy Computation
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes the Ising interaction energy between two doctrines.

  Energy = -J * s_i * s_j (with J = 1)

  Returns:
  - `-1.0` when both are cooperative (favorable clustering)
  - `-1.0` when both are exploratory (favorable clustering)
  - `+1.0` when one is cooperative and one is exploratory (unfavorable)
  - `0.0` when either is neutral

  ## Examples

      iex> Doctrine.interaction_energy(:router, :healer)
      -1.0

      iex> Doctrine.interaction_energy(:router, :explorer)
      1.0

      iex> Doctrine.interaction_energy(:router, :general)
      0.0
  """
  @spec interaction_energy(doctrine(), doctrine()) :: float()
  def interaction_energy(doctrine_i, doctrine_j) do
    s_i = encode_spin(doctrine_i)
    s_j = encode_spin(doctrine_j)
    -s_i * s_j
  end

  @doc """
  Checks if two doctrines are compatible (same or both neutral).

  Compatible doctrines have non-positive interaction energy.
  """
  @spec compatible?(doctrine(), doctrine()) :: boolean()
  def compatible?(doctrine_i, doctrine_j) do
    interaction_energy(doctrine_i, doctrine_j) <= 0.0
  end

  # ═══════════════════════════════════════════════════════════════
  # Distribution Analysis
  # ═══════════════════════════════════════════════════════════════

  @doc """
  Computes the distribution of doctrines in a list of Thunderbits.

  Returns a map of doctrine → count.

  ## Examples

      iex> bits = [%{doctrine: :router}, %{doctrine: :router}, %{doctrine: :explorer}]
      iex> Doctrine.distribution(bits)
      %{router: 2, explorer: 1}
  """
  @spec distribution([map()]) :: %{doctrine() => non_neg_integer()}
  def distribution(bits) when is_list(bits) do
    bits
    |> Enum.map(&extract_doctrine/1)
    |> Enum.frequencies()
  end

  @doc """
  Computes the entropy of doctrine distribution.

  Higher entropy = more diverse doctrines.
  Lower entropy = dominated by one doctrine.

  Returns value in [0, 1] normalized by max entropy (log2 of doctrine count).
  """
  @spec distribution_entropy([map()]) :: float()
  def distribution_entropy(bits) when is_list(bits) do
    dist = distribution(bits)
    total = Enum.sum(Map.values(dist))

    if total == 0 do
      0.0
    else
      entropy =
        dist
        |> Map.values()
        |> Enum.map(fn count ->
          p = count / total
          if p > 0, do: -p * :math.log2(p), else: 0.0
        end)
        |> Enum.sum()

      # Normalize by max entropy
      max_entropy = :math.log2(length(@all_doctrines))
      if max_entropy > 0, do: entropy / max_entropy, else: 0.0
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════

  defp extract_doctrine(%Thunderbit{doctrine: doctrine}), do: doctrine
  defp extract_doctrine(%{doctrine: doctrine}), do: doctrine
  defp extract_doctrine(_), do: :general
end
