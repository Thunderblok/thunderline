defmodule Thundervine.Replay do
  @moduledoc """
  Query and replay capabilities for TAK event history.

  Provides functions to reconstruct CA state from recorded events,
  query event history, and analyze evolution patterns.

  ## Usage

      # Reconstruct state at specific tick
      state = Replay.reconstruct_state("zone_1", [0, 0, 0], 500)

      # Get evolution timeline
      timeline = Replay.evolution_timeline("zone_1", [0, 0, 0])

      # Query events in tick range
      events = Replay.query_tick_range("zone_1", 100, 200)
  """

  require Ash.Query
  alias Thundervine.TAKChunkEvent

  @doc """
  Reconstruct CA state at a specific tick by replaying events.

  Returns a map of voxel_id => state for all voxels that have changed
  up to the target tick.

  ## Parameters
  - `zone_id`: Zone identifier
  - `chunk_coords`: Chunk coordinates as list [x, y, z]
  - `target_tick`: Tick to reconstruct state at

  ## Returns
  Map of voxel_id => current state

  ## Example

      state = Replay.reconstruct_state("zone_alpha", [0, 0, 0], 500)
      # => %{{0, 0, 0} => 1, {1, 1, 1} => 0, ...}
  """
  @spec reconstruct_state(String.t(), [integer()], integer()) :: %{tuple() => integer()}
  def reconstruct_state(zone_id, chunk_coords, target_tick) do
    events =
      TAKChunkEvent
      |> Ash.Query.filter(
        zone_id == ^zone_id and
          chunk_coords == ^chunk_coords and
          tick_id <= ^target_tick
      )
      |> Ash.Query.sort(:tick_id)
      |> Ash.read!()

    apply_events(events, %{})
  end

  @doc """
  Get full evolution timeline for a chunk.

  Returns list of {tick_id, state} tuples showing state at each recorded tick.

  ## Parameters
  - `zone_id`: Zone identifier
  - `chunk_coords`: Chunk coordinates as list [x, y, z]
  - `opts`: Options
    - `:limit` - Maximum number of ticks to return
    - `:start_tick` - Starting tick (default: 0)
    - `:end_tick` - Ending tick (default: all)

  ## Returns
  List of {tick_id, state_map} tuples

  ## Example

      timeline = Replay.evolution_timeline("zone_1", [0, 0, 0], limit: 100)
      # => [{1, %{...}}, {2, %{...}}, ...]
  """
  @spec evolution_timeline(String.t(), [integer()], keyword()) :: [{integer(), map()}]
  def evolution_timeline(zone_id, chunk_coords, opts \\ []) do
    start_tick = Keyword.get(opts, :start_tick, 0)
    end_tick = Keyword.get(opts, :end_tick)
    limit = Keyword.get(opts, :limit)

    query =
      TAKChunkEvent
      |> Ash.Query.filter(zone_id == ^zone_id and chunk_coords == ^chunk_coords)
      |> Ash.Query.sort(:tick_id)

    query =
      if start_tick > 0 do
        Ash.Query.filter(query, tick_id >= ^start_tick)
      else
        query
      end

    query =
      if end_tick do
        Ash.Query.filter(query, tick_id <= ^end_tick)
      else
        query
      end

    query =
      if limit do
        Ash.Query.limit(query, limit)
      else
        query
      end

    events = Ash.read!(query)

    # Build timeline with cumulative state
    {timeline, _} =
      Enum.map_reduce(events, %{}, fn event, state ->
        new_state = apply_diffs(event.diffs, state)
        {{event.tick_id, new_state}, new_state}
      end)

    timeline
  end

  @doc """
  Query events within a tick range.

  ## Parameters
  - `zone_id`: Zone identifier
  - `start_tick`: Starting tick (inclusive)
  - `end_tick`: Ending tick (inclusive)
  - `opts`: Options
    - `:chunk_coords` - Filter by specific chunk
    - `:rule_hash` - Filter by specific rule

  ## Returns
  List of TAKChunkEvent records

  ## Example

      events = Replay.query_tick_range("zone_1", 100, 200, chunk_coords: [0, 0, 0])
  """
  @spec query_tick_range(String.t(), integer(), integer(), keyword()) :: [TAKChunkEvent.t()]
  def query_tick_range(zone_id, start_tick, end_tick, opts \\ []) do
    query =
      TAKChunkEvent
      |> Ash.Query.filter(
        zone_id == ^zone_id and
          tick_id >= ^start_tick and
          tick_id <= ^end_tick
      )
      |> Ash.Query.sort(:tick_id)

    query =
      if chunk_coords = Keyword.get(opts, :chunk_coords) do
        Ash.Query.filter(query, chunk_coords == ^chunk_coords)
      else
        query
      end

    query =
      if rule_hash = Keyword.get(opts, :rule_hash) do
        Ash.Query.filter(query, rule_hash == ^rule_hash)
      else
        query
      end

    Ash.read!(query)
  end

  @doc """
  Get all events for a specific zone.

  ## Parameters
  - `zone_id`: Zone identifier
  - `opts`: Options
    - `:limit` - Maximum events to return
    - `:order` - Sort order (`:asc` or `:desc`, default `:asc`)

  ## Returns
  List of TAKChunkEvent records
  """
  @spec query_zone(String.t(), keyword()) :: [TAKChunkEvent.t()]
  def query_zone(zone_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    order = Keyword.get(opts, :order, :asc)

    query =
      TAKChunkEvent
      |> Ash.Query.filter(zone_id == ^zone_id)
      |> Ash.Query.sort(tick_id: order)

    query =
      if limit do
        Ash.Query.limit(query, limit)
      else
        query
      end

    Ash.read!(query)
  end

  @doc """
  Get events for a specific rule across all zones.

  ## Parameters
  - `rule_hash`: Rule hash to filter by
  - `opts`: Options
    - `:limit` - Maximum events to return
    - `:zone_id` - Filter by specific zone

  ## Returns
  List of TAKChunkEvent records
  """
  @spec query_rule(String.t(), keyword()) :: [TAKChunkEvent.t()]
  def query_rule(rule_hash, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    zone_id = Keyword.get(opts, :zone_id)

    query =
      TAKChunkEvent
      |> Ash.Query.filter(rule_hash == ^rule_hash)
      |> Ash.Query.sort(:tick_id)

    query =
      if zone_id do
        Ash.Query.filter(query, zone_id == ^zone_id)
      else
        query
      end

    query =
      if limit do
        Ash.Query.limit(query, limit)
      else
        query
      end

    Ash.read!(query)
  end

  @doc """
  Calculate activity statistics for a zone.

  Returns metrics about CA evolution including total events, state changes,
  tick range, and average activity per tick.

  ## Parameters
  - `zone_id`: Zone identifier
  - `opts`: Options
    - `:chunk_coords` - Filter by specific chunk
    - `:tick_range` - Limit to {start_tick, end_tick}

  ## Returns
  Map with activity statistics

  ## Example

      stats = Replay.activity_stats("zone_1")
      # => %{
      #      total_events: 1000,
      #      total_state_changes: 15000,
      #      tick_range: {1, 1000},
      #      avg_changes_per_tick: 15.0,
      #      chunks_affected: [[0,0,0], [1,0,0]]
      #    }
  """
  @spec activity_stats(String.t(), keyword()) :: map()
  def activity_stats(zone_id, opts \\ []) do
    chunk_coords = Keyword.get(opts, :chunk_coords)
    tick_range = Keyword.get(opts, :tick_range)

    query = TAKChunkEvent |> Ash.Query.filter(zone_id == ^zone_id)

    query =
      if chunk_coords do
        Ash.Query.filter(query, chunk_coords == ^chunk_coords)
      else
        query
      end

    query =
      if tick_range do
        {start_tick, end_tick} = tick_range
        Ash.Query.filter(query, tick_id >= ^start_tick and tick_id <= ^end_tick)
      else
        query
      end

    events = Ash.read!(query)

    total_changes = Enum.sum(Enum.map(events, &length(&1.diffs)))
    ticks = Enum.map(events, & &1.tick_id)
    chunks = events |> Enum.map(& &1.chunk_coords) |> Enum.uniq()

    %{
      total_events: length(events),
      total_state_changes: total_changes,
      tick_range: if(ticks == [], do: nil, else: {Enum.min(ticks), Enum.max(ticks)}),
      avg_changes_per_tick: if(events == [], do: 0.0, else: total_changes / length(events)),
      chunks_affected: chunks
    }
  end

  @doc """
  Compare activity between two rules.

  ## Parameters
  - `rule_hash_1`: First rule hash
  - `rule_hash_2`: Second rule hash

  ## Returns
  Map comparing the two rules
  """
  @spec compare_rules(String.t(), String.t()) :: map()
  def compare_rules(rule_hash_1, rule_hash_2) do
    stats_1 = rule_stats(rule_hash_1)
    stats_2 = rule_stats(rule_hash_2)

    %{
      rule_1: Map.put(stats_1, :hash, rule_hash_1),
      rule_2: Map.put(stats_2, :hash, rule_hash_2),
      more_active:
        if(stats_1.total_changes > stats_2.total_changes, do: :rule_1, else: :rule_2),
      activity_ratio:
        if(stats_2.total_changes > 0,
          do: stats_1.total_changes / stats_2.total_changes,
          else: nil
        )
    }
  end

  @doc """
  Export evolution history to a format suitable for visualization.

  Returns a list of frames where each frame contains the active voxels
  at that tick.

  ## Parameters
  - `zone_id`: Zone identifier
  - `chunk_coords`: Chunk coordinates
  - `opts`: Options
    - `:limit` - Maximum frames to export
    - `:format` - Export format (`:map` or `:list`, default `:map`)

  ## Returns
  List of {tick_id, voxels} where voxels is either a map or list depending on format

  ## Example

      frames = Replay.export_for_visualization("zone_1", [0, 0, 0], format: :list)
      # => [
      #      {1, [{0, 0, 0}, {1, 1, 1}]},
      #      {2, [{0, 0, 0}, {2, 2, 2}]},
      #      ...
      #    ]
  """
  @spec export_for_visualization(String.t(), [integer()], keyword()) :: [{integer(), any()}]
  def export_for_visualization(zone_id, chunk_coords, opts \\ []) do
    format = Keyword.get(opts, :format, :map)
    timeline = evolution_timeline(zone_id, chunk_coords, opts)

    case format do
      :map ->
        timeline

      :list ->
        Enum.map(timeline, fn {tick, state} ->
          active_voxels =
            state
            |> Enum.filter(fn {_voxel_id, value} -> value == 1 end)
            |> Enum.map(fn {voxel_id, _value} -> voxel_id end)

          {tick, active_voxels}
        end)

      _ ->
        raise ArgumentError, "Invalid format: #{inspect(format)}"
    end
  end

  # Private Helpers

  defp apply_events(events, initial_state) do
    Enum.reduce(events, initial_state, fn event, state ->
      apply_diffs(event.diffs, state)
    end)
  end

  defp apply_diffs(diffs, state) do
    Enum.reduce(diffs, state, fn diff, acc ->
      voxel_id = List.to_tuple(diff["voxel_id"])
      Map.put(acc, voxel_id, diff["new"])
    end)
  end

  defp rule_stats(rule_hash) do
    events =
      TAKChunkEvent
      |> Ash.Query.filter(rule_hash == ^rule_hash)
      |> Ash.read!()

    total_changes = Enum.sum(Enum.map(events, &length(&1.diffs)))

    %{
      total_events: length(events),
      total_changes: total_changes,
      avg_changes_per_event: if(events == [], do: 0.0, else: total_changes / length(events))
    }
  end
end
