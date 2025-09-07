defmodule Thunderline.Thunderlink.Transport.Membership do
  @moduledoc """
  Membership directory contract under Thunderlink.
  """
  @typedoc "Node identifier (DID or ephemeral id)"
  @type node_id :: binary()
  @typedoc "Membership state record"
  @type member :: %{
          id: node_id(),
          status: :alive | :suspect | :dead,
          incarnation: non_neg_integer(),
          zone: binary() | nil,
          meta: map(),
          quarantine?: boolean()
        }

  @callback list() :: [member()]
  @callback local_id() :: node_id()
  @callback quarantine(node_id(), atom()) :: :ok
  @callback admit?(binary(), keyword()) :: boolean()
end
