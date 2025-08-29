defmodule Thunderline.TOCP.Router do
  @moduledoc """
  Router behaviour – ingestion point for Transport -> membership/routing decisions -> egress.

  Will own backpressure hooks once FlowControl lands.
  """

  @typedoc "Packet classification"
  @type kind :: :reliable | :unreliable | :control

  @callback inbound(binary(), kind(), map()) :: :ok | {:error, atom()}
  @callback outbound(map(), keyword()) :: :ok | {:error, term()}
end
