defmodule Thunderline.ThunderIsing.Lattice do
  @moduledoc """
  Stub lattice construction helpers for Ising problems.
  """
  def grid_2d(height, width, _opts), do: {:grid_2d, height, width}
  def max_cut_problem(edge_tuples, num_vertices), do: {:max_cut, num_vertices, edge_tuples}
  def graph(_num_vertices, _edges, _opts), do: {:graph, :placeholder}
end
