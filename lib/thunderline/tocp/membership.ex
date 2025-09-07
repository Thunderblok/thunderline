defmodule Thunderline.TOCP.Membership do
  @moduledoc """
  Deprecated: SWIM-lite membership state & gossip tick scaffold.
  Prefer `Thunderline.Thunderlink.Transport.Membership`.

  Week-1 target: Maintain ETS tables for alive/suspect/dead with piggybacked updates.
  This module will supervise its own periodic gossip Task in later implementation.
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
