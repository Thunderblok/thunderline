defmodule Thunderline.Thunderbolt.Signal.PLL do
  @moduledoc "Discrete PLL tracking latent clause/recurrence pulses. (migrated from Thunderline.Current.PLL)"
  defstruct phi: 0.0, omega: 0.25, eps: 0.1, kappa: 0.05
  def step(%__MODULE__{} = pll, pulse) do
    e = saw(pll.phi) - if(pulse, do: 1.0, else: 0.0)
    omega1 = pll.omega + pll.kappa * e
    %__MODULE__{pll | omega: omega1, phi: rem(pll.phi + omega1, 1.0)}
  end
  def gate?(%__MODULE__{phi: phi}, g), do: (phi >= 1.0 - 0.1 or phi <= 0.1) and g > 0.5
  def prewindow?(%__MODULE__{phi: phi}), do: phi >= 1.0 - 0.2 and phi < 1.0 - 0.1
  defp saw(x), do: x - :math.floor(x)
end
