defmodule Thunderline.EventProcessor do
  @moduledoc "Deprecated: use Thunderline.Thunderflow.Processor.process_event/1"
  @deprecated "Use Thunderline.Thunderflow.Processor"
  require Logger
  def process_event(event) do
    emit(); Thunderline.Thunderflow.Processor.process_event(event)
  end
  defp emit do
    :telemetry.execute([:thunderline, :deprecated_module, :used], %{count: 1}, %{module: __MODULE__})
    Logger.warning("Deprecated module #{inspect(__MODULE__)} used; switch to Thunderline.Thunderflow.Processor")
  end
end
