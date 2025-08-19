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
