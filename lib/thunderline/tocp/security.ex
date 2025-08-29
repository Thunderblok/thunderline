defmodule Thunderline.TOCP.Security do
  @moduledoc """
  Security roadmap placeholder.

  MVP: Only signature placeholders on control frames (no full Noise yet).
  DIP-TOCP-004 will evolve this into a Noise-XK handshake stage & key rotation.
  Replay protection: LRU (src, mid, ts) within replay_skew_ms (config default 30s).
  """

  @typedoc "Opaque key id"
  @type key_id :: binary()

  @callback sign(key_id(), binary()) :: {:ok, binary()} | {:error, term()}
  @callback verify(key_id(), binary(), binary()) :: :ok | {:error, term()}
  @callback replay_seen?(key_id(), binary(), non_neg_integer()) :: boolean()
end
