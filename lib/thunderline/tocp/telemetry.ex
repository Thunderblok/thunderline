defmodule Thunderline.TOCP.Telemetry do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Telemetry`.
  Shim that delegates to the Thunderlink namespace.
  """

  @spec emit(atom(), map(), map()) :: :ok
  defdelegate emit(event, measurements, meta), to: Thunderline.Thunderlink.Transport.Telemetry
end
