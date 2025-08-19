defmodule Thunderline.Thunderbolt.IsingMachine.API do
  @moduledoc """
  Stub Ising machine algorithm API.

  Provides placeholder functions so resources can compile; replace with real Nx/NIF implementations.
  """
  def quick_solve(_h, _w, _opts), do: {:ok, %{energy: 0.0}}
  def solve_grid(_opts), do: {:ok, %{result: :grid_solution}}
  def solve_max_cut(_edges, _n, _opts), do: {:ok, %{cut: 0.0}}
  def solve_with_parallel_tempering(_lat, _opts), do: {:ok, %{energy: 0.0}}
  def solve_distributed(_lattice, _opts), do: {:ok, %{status: :distributed}}
end
