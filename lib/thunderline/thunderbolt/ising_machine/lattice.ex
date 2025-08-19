defmodule Thunderline.Thunderbolt.IsingMachine.Lattice do
  @moduledoc """
  Stub lattice construction helpers for Ising problems.

  Provides minimal data structures so the higher-level IsingMachine module
  can compile while real Nx implementations are developed.
  """

  def grid_2d(height, width, opts \\ []) do
    coupling = Keyword.get(opts, :coupling, 1.0)
    %{topology: :grid_2d, height: height, width: width, coupling_matrix: coupling}
  end

  def graph(num_vertices, edges, _opts \\ []) do
    %{topology: :graph, vertices: num_vertices, edges: edges}
  end
end
defmodule Thunderline.ThunderIsing.Lattice do
  @moduledoc """
  Stub lattice construction helpers for Ising problems.
  """
  def grid_2d(height, width, _opts), do: {:grid_2d, height, width}
  def max_cut_problem(edge_tuples, num_vertices), do: {:max_cut, num_vertices, edge_tuples}
  def graph(_num_vertices, _edges, _opts), do: {:graph, :placeholder}
end
