defmodule Thunderchief.ObanHealth do
  @moduledoc "Deprecated: use Thunderline.Thunderflow.Telemetry.ObanHealth"
  @deprecated "Use Thunderline.Thunderflow.Telemetry.ObanHealth"
  require Logger
  def start_link(opts \\ []) do emit(); Thunderline.Thunderflow.Telemetry.ObanHealth.start_link(opts) end
  def subscribe, do: (emit(); Thunderline.Thunderflow.Telemetry.ObanHealth.subscribe())
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderflow.Telemetry.ObanHealth")
  end
end
