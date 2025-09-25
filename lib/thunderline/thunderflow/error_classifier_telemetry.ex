defmodule Thunderline.Thunderflow.ErrorClassifier.Telemetry do
  @moduledoc "Emit telemetry for classified errors."
  alias Thunderline.Thunderflow.ErrorClass
  @spec emit(%ErrorClass{}) :: :ok
  def emit(%ErrorClass{} = e) do
    :telemetry.execute([:thunderline, :error, :classified], %{}, Map.from_struct(e))
    :ok
  end
end
