defmodule Thunderline.Thunderbolt.IsingMachine.API do
  @moduledoc """
  Stub Ising machine algorithm API.

  Each function accepts opts allowing `:force_error` to broaden return types so
  downstream pattern matches that handle error branches don't trigger
  unreachable clause warnings during compilation.
  """
  def quick_solve(_h, _w, opts \\ []), do: maybe_ok(%{energy: 0.0, steps: Keyword.get(opts, :max_steps, 0)}, opts)
  def solve_grid(opts \\ []), do: maybe_ok(%{result: :grid_solution}, opts)
  def solve_max_cut(_edges, _n, opts \\ []), do: maybe_ok(%{cut: 0.0}, opts)
  def solve_with_parallel_tempering(_lat, opts \\ []), do: maybe_ok(%{energy: 0.0}, opts)
  def solve_distributed(_lattice, opts \\ []), do: maybe_ok(%{status: :distributed}, opts)

  defp maybe_ok(payload, opts) do
    if Keyword.get(opts, :force_error) do
      {:error, :not_implemented}
    else
      {:ok, payload}
    end
  end
end
