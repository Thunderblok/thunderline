defmodule Thunderline.Current.CircStats do
  @moduledoc """Circular statistics: Rayleigh p-value + mean direction."""
  @two_pi 2.0 * :math.pi()

  def rayleigh([]), do: {0.0, 0.0, 1.0}
  def rayleigh(phases) when is_list(phases) do
    n = length(phases)
    {sx, sy} =
      Enum.reduce(phases, {0.0, 0.0}, fn p, {cx, cy} ->
        a = p * @two_pi
        {cx + :math.cos(a), cy + :math.sin(a)}
      end)
    rbar = :math.sqrt(sx * sx + sy * sy) / n
    z = n * rbar * rbar
    p = :math.exp(-z) * (1.0 + (2.0 * z - z * z) / (4.0 * n))
    {rbar, z, clamp01(p)}
  end

  def mean_dir([]), do: nil
  def mean_dir(phases) when is_list(phases) do
    {sx, sy} =
      Enum.reduce(phases, {0.0, 0.0}, fn p, {cx, cy} ->
        a = p * @two_pi
        {cx + :math.cos(a), cy + :math.sin(a)}
      end)
    mu = :math.atan2(sy, sx)
    mu_norm = if mu < 0.0, do: (mu + @two_pi) / @two_pi, else: mu / @two_pi
    mu_norm
  end

  defp clamp01(x) when x < 0.0, do: 0.0
  defp clamp01(x) when x > 1.0, do: 1.0
  defp clamp01(x), do: x
end
