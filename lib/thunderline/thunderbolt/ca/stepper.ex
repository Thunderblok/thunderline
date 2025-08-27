defmodule Thunderline.CA.Stepper do
  @moduledoc """
  Pure stepping logic for CA grid.

  This is a stubbed reference implementation. Later we can swap in
  accelerated implementations (EAGL, NIF, GPU) by redefining `next/2`.

  Grid representation (placeholder): `%{size: n}` where size is the square grid dimension.
  Ruleset (placeholder): map or atom describing rule parameters.
  """
  @type grid :: %{size: pos_integer()}
  @type ruleset :: map() | atom()
  @type delta :: %{id: String.t(), state: atom(), hex: integer(), energy: non_neg_integer()}

  @doc "Compute next step deltas returning {:ok, deltas, new_grid}."
  @spec next(grid(), ruleset()) :: {:ok, [delta()], grid()}
  def next(%{size: size} = grid, _ruleset) do
    # Produce a small random sample of changed cells to keep payload tight.
    changes = Enum.random(5..18)
    deltas =
      for _ <- 1..changes do
        row = :rand.uniform(size) - 1
        col = :rand.uniform(size) - 1
        id = "#{row}-#{col}"
        energy = :rand.uniform(100) - 1
        state = pick_state(energy)
        %{id: id, state: state, energy: energy, hex: state_color(state)}
      end

    {:ok, deltas, grid}
  end

  defp pick_state(e) when e > 85, do: :critical
  defp pick_state(e) when e > 60, do: :active
  defp pick_state(e) when e > 30, do: :evolving
  defp pick_state(_), do: :inactive

  defp state_color(:critical), do: 0xFF0000
  defp state_color(:active), do: 0x00FF00
  defp state_color(:evolving), do: 0xFFFF00
  defp state_color(:inactive), do: 0x333333
end
