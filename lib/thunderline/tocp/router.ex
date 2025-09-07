defmodule Thunderline.TOCP.Router do
  @moduledoc """
  Deprecated: Router behaviour.
  Prefer `Thunderline.Thunderlink.Transport.Router`.

  Will own backpressure hooks once FlowControl lands.
  """

  @typedoc "Packet classification"
  @type kind :: :reliable | :unreliable | :control

  @callback inbound(binary(), kind(), map()) :: :ok | {:error, atom()}
  @callback outbound(map(), keyword()) :: :ok | {:error, term()}
end
