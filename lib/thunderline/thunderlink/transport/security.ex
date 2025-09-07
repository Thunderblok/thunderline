defmodule Thunderline.Thunderlink.Transport.Security do
  @moduledoc """
  Security behaviour for Thunderlink Transport (formerly TOCP).

  This abstracts signing, verification, and replay protection. Implementations
  may use real crypto and keystores; the default Impl is a practical scaffold.
  """

  @typedoc "Opaque key id"
  @type key_id :: binary()

  @callback sign(key_id(), binary()) :: {:ok, binary()} | {:error, term()}
  @callback verify(key_id(), binary(), binary()) :: :ok | {:error, term()}
  @callback replay_seen?(key_id(), binary(), non_neg_integer()) :: boolean()
end
