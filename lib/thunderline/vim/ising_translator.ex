defmodule Thunderline.VIM.IsingTranslator do
  @moduledoc """
  P1 seam (ANVIL) – minimal translator stub from Ising parameter maps to a lattice
  representation suitable for downstream annealing interfaces.

  Input shape:
    %{h: %{spin => field_strength, ...}, j: %{{i,j} => coupling, ...}}

  Output shape:
    %{spins: [{spin, h_value}], couplings: [{i, j, weight}]}

  NOTE: This is a stub – future phases: validation, sparse matrix export, scaling & normalization.
  """
  @type spin :: any()
  @type h_map :: %{required(spin) => number()}
  @type j_map :: %{{spin, spin} => number()}
  @type lattice :: %{spins: list({spin, number()}), couplings: list({spin, spin, number()})}

  @spec to_lattice(%{h: h_map, j: j_map}) :: lattice
  def to_lattice(%{h: h, j: j}) when is_map(h) and is_map(j) do
    %{
      spins: Enum.map(h, fn {s, w} -> {s, w} end),
      couplings: (for {{i, k}, w} <- j, do: {i, k, w})
    }
  end
  def to_lattice(_), do: %{spins: [], couplings: []}
end
