defmodule Thunderline.Thunderlink.Transport.Telemetry do
  @moduledoc """
  Thunderlink Transport Telemetry helpers. Emits transport-related telemetry
  events, currently preserving the [:tocp, ...] event prefix to avoid breaking
  downstream consumers. We can dual-emit later if we rename taxonomy.

  Instrumented with OpenTelemetry for T-72h telemetry heartbeat.
  """

  @spec emit(atom(), map(), map()) :: :ok
  def emit(event, measurements, meta)
      when is_atom(event) and is_map(measurements) and is_map(meta) do
    alias Thunderline.Thunderflow.Telemetry.OtelTrace

    OtelTrace.with_span "link.transport_emit", %{
      event: to_string(event),
      transport_type: meta[:transport_type] || "unknown"
    } do
      Process.put(:current_domain, :link)

      OtelTrace.set_attributes(%{
        "thunderline.domain" => "link",
        "thunderline.component" => "transport_telemetry",
        "transport.event" => to_string(event)
      })

      # Continue trace if event originated from upstream
      if Map.has_key?(meta, :trace_id) do
        OtelTrace.continue_trace_from_event(%{meta: meta})
      end

      :telemetry.execute([:tocp, event], measurements, meta)
      OtelTrace.add_event("link.telemetry_emitted")
      :ok
    end
  end
end
