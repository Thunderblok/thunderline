defmodule Thunderline.Current.SafeClose do
  @moduledoc "Deprecated: logic replaced by Thunderbolt.Signal.Sensor boundary_close + Thunderblock.Checkpoint"
  @deprecated "Use Thunderline.Thunderbolt.Signal.Sensor + Thunderline.Thunderblock.Checkpoint"
  require Logger
  def start_link(_), do: (emit(); {:ok, self()})
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; logic now consolidated")
  end
  def __deprecated_test_emit__, do: emit()
end
