defmodule Thunderline.Current.Hilbert do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Signal.Hilbert"
  @deprecated "Use Thunderline.Thunderbolt.Signal.Hilbert"
  require Logger
  def new(l \\ 63) do emit(); Thunderline.Thunderbolt.Signal.Hilbert.new(l) end
  def step(h, x) do emit(); Thunderline.Thunderbolt.Signal.Hilbert.step(h, x) end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderbolt.Signal.Hilbert")
  end
  def __deprecated_test_emit__, do: emit()
end
