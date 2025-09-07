defmodule Thunderline.Thunderlink.Transport.Reliability do
  @moduledoc """
  Reliability window & ACK batching behaviour under Thunderlink.
  """
  @typedoc "Opaque message id"
  @type mid :: binary()

  @callback track_outbound(mid(), binary()) :: :ok
  @callback ack(mid()) :: :ok
  @callback pending() :: non_neg_integer()
end
