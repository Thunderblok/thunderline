defmodule Thunderline.Current.PLL do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Signal.PLL"
  @deprecated "Use Thunderline.Thunderbolt.Signal.PLL"
  defstruct phi: 0.0, omega: 0.25, eps: 0.1, kappa: 0.05
  require Logger
  def step(pll, pulse) do emit(); Thunderline.Thunderbolt.Signal.PLL.step(pll, pulse) end
  def gate?(pll, g) do emit(); Thunderline.Thunderbolt.Signal.PLL.gate?(pll, g) end
  def prewindow?(pll) do emit(); Thunderline.Thunderbolt.Signal.PLL.prewindow?(pll) end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderbolt.Signal.PLL")
  end
  def __deprecated_test_emit__, do: emit()
end
