defmodule Thunderline.TOCP.Routing.HysteresisManager do
  @moduledoc """
  Deprecated: Use `Thunderline.Thunderlink.Transport.Routing.HysteresisManager`.
  Shim that delegates to the Thunderlink namespace.
  """
  defdelegate start_link(opts), to: Thunderline.Thunderlink.Transport.Routing.HysteresisManager
  defdelegate current(), to: Thunderline.Thunderlink.Transport.Routing.HysteresisManager
end
