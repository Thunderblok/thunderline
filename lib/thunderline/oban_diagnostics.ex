defmodule Thunderchief.ObanDiagnostics do
  @moduledoc "Deprecated: use Thunderline.Thunderflow.Telemetry.ObanDiagnostics"
  @deprecated "Use Thunderline.Thunderflow.Telemetry.ObanDiagnostics"
  require Logger
  def start_link(opts \\ []) do
    emit(); Thunderline.Thunderflow.Telemetry.ObanDiagnostics.start_link(opts)
  end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderflow.Telemetry.ObanDiagnostics")
  end
end
