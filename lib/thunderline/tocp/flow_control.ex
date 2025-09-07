defmodule Thunderline.TOCP.FlowControl do
  @moduledoc """
  Deprecated: Flow control (credits / token buckets) contract.
  Prefer `Thunderline.Thunderlink.Transport.FlowControl`.

  Later sprint: Implement per-peer & per-zone token buckets; expose credit snapshot.
  """

  @callback allowed?(map()) :: boolean()
  @callback debit(map()) :: :ok | {:error, :insufficient}
end
