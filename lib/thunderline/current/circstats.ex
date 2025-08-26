defmodule Thunderline.Current.CircStats do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Signal.CircStats"
  @deprecated "Use Thunderline.Thunderbolt.Signal.CircStats"
  require Logger
  def rayleigh(phases) do emit(); Thunderline.Thunderbolt.Signal.CircStats.rayleigh(phases) end
  def mean_dir(phases) do emit(); Thunderline.Thunderbolt.Signal.CircStats.mean_dir(phases) end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderbolt.Signal.CircStats")
  end
  def __deprecated_test_emit__, do: emit()
end
