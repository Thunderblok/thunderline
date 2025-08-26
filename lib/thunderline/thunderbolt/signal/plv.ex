defmodule Thunderline.Thunderbolt.Signal.PLV do
  @moduledoc "Phase Locking Value utilities for phases ∈ [0,1). (migrated from Thunderline.Current.PLV)"
  @two_pi 2.0 * :math.pi()
  def plv([]), do: 0.0
  def plv(phases) do
    {cx, cy, n} = Enum.reduce(phases, {0.0, 0.0, 0}, fn p, {sx, sy, n} ->
      a = p * @two_pi
      {sx + :math.cos(a), sy + :math.sin(a), n + 1}
    end)
    :math.sqrt((cx / n) * (cx / n) + (cy / n) * (cy / n))
  end
end
