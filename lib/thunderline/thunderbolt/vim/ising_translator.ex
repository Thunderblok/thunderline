defmodule Thunderline.Thunderbolt.VIM.IsingTranslator do
  @moduledoc """
  Translator from Ising parameter maps to lattice representation.

  Input shape:
    %{h: %{spin => field_strength, ...}, j: %{{i,j} => coupling, ...}}

  Output shape:
    %{spins: [{spin, h_value}], couplings: [{i, j, weight}]}
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
