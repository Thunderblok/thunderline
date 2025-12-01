defmodule Thunderline.Thunderbolt.Events.TAKChunkEvolved do
  @moduledoc """
  Event payload emitted by TAK when a chunk evolves for a tick.

  This is intentionally minimal and serializable. It is expected to be
  wrapped in the project's standard event envelope before publishing to
  Thunderflow.
  """

  @enforce_keys [:zone_id, :chunk_id, :tick_id, :diffs, :rule_hash]
  defstruct [
    :zone_id,
    # {cx, cy, cz}
    :chunk_id,
    :tick_id,
    # list of %{voxel_id: {x,y,z}, old: map(), new: map()}
    :diffs,
    :rule_hash,
    # optional map
    :meta
  ]
end
