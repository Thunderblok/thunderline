defmodule Thunderline.TOCP.FlowControl do
  @moduledoc """
  Flow control (credits / token buckets) contract.

  Later sprint: Implement per-peer & per-zone token buckets; expose credit snapshot.
  """

  @callback allowed?(map()) :: boolean()
  @callback debit(map()) :: :ok | {:error, :insufficient}
end
