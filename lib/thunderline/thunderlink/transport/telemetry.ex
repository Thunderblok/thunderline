defmodule Thunderline.Thunderlink.Transport.Telemetry do
  @moduledoc """
  Thunderlink Transport Telemetry helpers. Emits transport-related telemetry
  events, currently preserving the [:tocp, ...] event prefix to avoid breaking
  downstream consumers. We can dual-emit later if we rename taxonomy.
  """

  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements, meta)
      when is_atom(event) and is_map(measurements) and is_map(meta) do
    :telemetry.execute([:tocp, event], measurements, meta)
    :ok
  end
end
