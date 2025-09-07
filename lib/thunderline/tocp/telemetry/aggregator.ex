defmodule Thunderline.TOCP.Telemetry.Aggregator do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Telemetry.Aggregator`.
  Shim that delegates to the Thunderlink namespace.
  """

  defdelegate start_link(opts), to: Thunderline.Thunderlink.Transport.Telemetry.Aggregator
  defdelegate snapshot, to: Thunderline.Thunderlink.Transport.Telemetry.Aggregator
  defdelegate reset, to: Thunderline.Thunderlink.Transport.Telemetry.Aggregator
end
