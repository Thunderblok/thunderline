defmodule Thunderline.Current.PLV do
  @moduledoc "Deprecated: use Thunderline.Thunderbolt.Signal.PLV"
  @deprecated "Use Thunderline.Thunderbolt.Signal.PLV"
  require Logger
  def plv(phases) do
    emit()
    Thunderline.Thunderbolt.Signal.PLV.plv(phases)
  end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderbolt.Signal.PLV")
  end
  def __deprecated_test_emit__, do: emit()
end
