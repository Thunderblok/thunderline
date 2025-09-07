defmodule Thunderline.TOCP.Reliability do
  @moduledoc """
  Deprecated: Reliability window & ACK batching contract.
  Prefer `Thunderline.Thunderlink.Transport.Reliability`.

  Week-2: Implement sliding window (32), retries (5), ack batch (10ms), dedup LRU (2048).
  Backoff ladder for retry storms & hard cutoff after max_retries.
  """

  @typedoc "Opaque message id"
  @type mid :: binary()

  @callback track_outbound(mid(), binary()) :: :ok
  @callback ack(mid()) :: :ok
  @callback pending() :: non_neg_integer()
end
