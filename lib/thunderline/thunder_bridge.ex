defmodule Thunderline.Legacy.ThunderBridgeStub do
  @moduledoc """
  Temporary stub for the cross-runtime ThunderBridge.

  Referenced widely; provides no-op communication surface. Replace with
  real transport (federated links, protocol negotiation, streaming telemetry)
  after core event pipeline stabilization.
  """

  @deprecated "Use Thunderline.ThunderBridge instead"
  defdelegate connect(opts \\ []), to: Thunderline.ThunderBridge
  @deprecated "Use Thunderline.ThunderBridge instead"
  defdelegate send(payload), to: Thunderline.ThunderBridge
end
