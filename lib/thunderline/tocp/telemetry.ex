defmodule Thunderline.TOCP.Telemetry do
  @moduledoc """
  Telemetry event taxonomy placeholder (see docs/TOCP_TELEMETRY.md & DIP-TOCP-002).

  Provides helper emit functions once implemented. Scaffold only.
  """

  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements, meta) when is_atom(event) and is_map(measurements) and is_map(meta) do
    :telemetry.execute([:tocp, event], measurements, meta)
    :ok
  end
end
