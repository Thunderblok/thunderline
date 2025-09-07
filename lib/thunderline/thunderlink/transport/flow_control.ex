defmodule Thunderline.Thunderlink.Transport.FlowControl do
  @moduledoc """
  Flow control (credits / token buckets) behaviour under Thunderlink.
  """
  @callback allowed?(map()) :: boolean()
  @callback debit(map()) :: :ok | {:error, :insufficient}
end
