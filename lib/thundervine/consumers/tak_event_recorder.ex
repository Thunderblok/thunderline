defmodule Thundervine.TAKEventRecorder do
  @moduledoc """
  Simple Broadway-style consumer (stub) that persists TAK chunk events into
  Thundervine using the `Thundervine.TAKChunkEvent` resource.

  This module is intentionally minimal: it exposes `handle_event/1` for now
  which accepts a `Thunderline.Events.TAKChunkEvolved` struct or a compatible
  map and creates a `TAKChunkEvent` record.
  """

  alias Thunderline.Events.TAKChunkEvolved
  alias Thundervine.TAKChunkEvent

  def handle_event(%TAKChunkEvolved{} = ev) do
    create_from_event(ev)
  end

  def handle_event(%{} = map) do
    # allow plain maps
    ev = struct(TAKChunkEvolved, Map.new(map))
    create_from_event(ev)
  end

  defp create_from_event(%TAKChunkEvolved{zone_id: zone, chunk_id: coords, tick_id: tick, diffs: diffs, rule_hash: rh, meta: meta}) do
    attrs = %{
      zone_id: zone,
      chunk_coords: Tuple.to_list(coords),
      tick_id: tick,
      diffs: diffs,
      rule_hash: rh,
      meta: meta || %{}
    }

    case TAKChunkEvent.create(attrs, authorize?: false) do
      {:ok, rec} -> {:ok, rec}
      {:error, err} -> {:error, err}
    end
  end
end
