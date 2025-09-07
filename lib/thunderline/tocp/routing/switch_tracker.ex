defmodule Thunderline.TOCP.Routing.SwitchTracker do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Routing.SwitchTracker`.
  Shim that delegates to the Thunderlink namespace.
  """
  defdelegate start_link(opts), to: Thunderline.Thunderlink.Transport.Routing.SwitchTracker
  defdelegate record_switch(zone, prev, new, total_nodes, opts \\ []), to: Thunderline.Thunderlink.Transport.Routing.SwitchTracker
end
