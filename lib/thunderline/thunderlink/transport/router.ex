defmodule Thunderline.Thunderlink.Transport.Router do
  @moduledoc """
  Router behaviour under Thunderlink Transport.
  """
  @typedoc "Packet classification"
  @type kind :: :reliable | :unreliable | :control

  @callback inbound(binary(), kind(), map()) :: :ok | {:error, atom()}
  @callback outbound(map(), keyword()) :: :ok | {:error, term()}
end
