defmodule Thunderline.Events.TAKChunkEvolved do
  @moduledoc """
  Event payload emitted by TAK when a chunk evolves for a tick.

  This is intentionally minimal and serializable. It is expected to be
  wrapped in the project's standard event envelope before publishing to
  Thunderflow.
  """

  @enforce_keys [:zone_id, :chunk_id, :tick_id, :diffs, :rule_hash]
  defstruct [
    :zone_id,
    :chunk_id,   # {cx, cy, cz}
    :tick_id,
    :diffs,      # list of %{voxel_id: {x,y,z}, old: map(), new: map()}
    :rule_hash,
    :meta        # optional map
  ]
end
