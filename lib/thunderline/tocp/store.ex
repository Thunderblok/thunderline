defmodule Thunderline.TOCP.Store do
  @moduledoc """
  Store-and-forward retention policy contract.

  Week-2: Offer/Request; retention 24h / 512MB (DIP-TOCP-003) with TTL & byte GC.
  """

  @typedoc "Stored message reference"
  @type ref :: binary()

  @callback offer(ref(), binary(), map()) :: :ok | {:error, term()}
  @callback request(ref()) :: {:ok, binary()} | {:error, :not_found}
end
