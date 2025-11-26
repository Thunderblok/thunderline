# TAK Persistence Architecture

**Status:** ✅ ACTIVE  
**Implementation Date:** November 21, 2025  
**Owner:** Thundervine Domain  
**Version:** 1.0

---

## Overview

The TAK (Totalistic Automata Kernel) persistence layer provides event-sourced recording and replay capabilities for cellular automaton evolution. It captures fine-grained voxel state changes during CA execution, enabling:

- **Historical Analysis**: Query past CA states at any tick
- **Replay & Debugging**: Reconstruct evolution sequences from events
- **Performance Metrics**: Track rule effectiveness and evolution patterns
- **Scientific Reproducibility**: Ensure exact replay of CA experiments

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         TAK.Runner                               │
│  (Cellular Automaton Execution)                                 │
└──────────────────────┬──────────────────────────────────────────┘
                       │ broadcast
                       │ topic: "ca:#{run_id}"
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Phoenix.PubSub                                │
└──────────────────────┬──────────────────────────────────────────┘
                       │ subscribe
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│              Thundervine.TAKEventRecorder                        │
│                    (GenServer)                                   │
│                                                                  │
│  1. Receive {:ca_delta, msg}                                    │
│  2. Normalize cells → diffs (coord → voxel_id)                  │
│  3. Build TAKChunkEvolved event                                 │
│  4. Persist via Ash                                             │
│  5. Track stats (received, persisted, failed)                   │
└──────────────────────┬──────────────────────────────────────────┘
                       │ persist
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│            Thundervine.TAKChunkEvent (Ash Resource)              │
│                  → PostgreSQL (tak_chunk_events)                 │
│                                                                  │
│  Fields: zone_id, chunk_coords, tick_id, diffs (JSONB),         │
│          rule_hash, meta, inserted_at                           │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **CA Evolution**: TAK.Runner executes cellular automaton tick
2. **Delta Broadcast**: Runner emits `{:ca_delta, msg}` to PubSub topic `"ca:#{run_id}"`
3. **Event Reception**: TAKEventRecorder receives message via PubSub subscription
4. **Normalization**: Convert PubSub format to TAKChunkEvolved struct
   - `cells: [%{coord: {x,y}, old: val, new: val}]` 
   - → `diffs: [%{voxel_id: {x,y,z}, old: val, new: val}]`
5. **Persistence**: Create TAKChunkEvent record via Ash
6. **Stats Tracking**: Increment events_received/persisted/failed counters

---

## Core Components

### 1. TAKEventRecorder (GenServer)

**Location:** `lib/thundervine/consumers/tak_event_recorder.ex`

**Responsibilities:**
- Subscribe to TAK PubSub stream for specific run_id
- Convert PubSub messages to TAKChunkEvolved events
- Persist events to database via Ash
- Track operational statistics

**Key Functions:**
```elixir
# Start recorder for a TAK run
{:ok, pid} = Thundervine.TAKEventRecorder.start_link(run_id: "my_run", zone_id: "zone_1")

# Get recorder statistics
stats = Thundervine.TAKEventRecorder.get_stats(pid)
# => %{
#      events_received: 1000,
#      events_persisted: 998,
#      events_failed: 2,
#      last_tick: 1000,
#      started_at: ~U[2025-11-21 00:00:00Z]
#    }
```

**State:**
```elixir
%{
  run_id: String.t(),      # TAK run identifier
  zone_id: String.t(),     # Zone for event metadata
  stats: %{
    events_received: non_neg_integer(),
    events_persisted: non_neg_integer(),
    events_failed: non_neg_integer(),
    last_tick: integer() | nil,
    started_at: DateTime.t()
  }
}
```

### 2. TAKChunkEvent (Ash Resource)

**Location:** `lib/thundervine/resources/tak_chunk_event.ex`

**Schema:**
```elixir
defmodule Thundervine.TAKChunkEvent do
  attributes do
    uuid_primary_key :id
    attribute :zone_id, :string, allow_nil?: false
    attribute :chunk_coords, {:array, :integer}, allow_nil?: false
    attribute :tick_id, :integer, allow_nil?: false
    attribute :diffs, {:array, :map}, allow_nil?: false
    attribute :rule_hash, :string, allow_nil?: false
    attribute :meta, :map
    create_timestamp :inserted_at
  end

  identities do
    identity :by_zone_tick, [:zone_id, :chunk_coords, :tick_id]
  end
end
```

**Database Table:** `tak_chunk_events`
```sql
CREATE TABLE tak_chunk_events (
  id UUID PRIMARY KEY,
  zone_id TEXT NOT NULL,
  chunk_coords INTEGER[] NOT NULL,
  tick_id BIGINT NOT NULL,
  diffs JSONB NOT NULL,  -- Array of {voxel_id, old, new}
  rule_hash TEXT NOT NULL,
  meta JSONB,
  inserted_at TIMESTAMP NOT NULL,
  
  UNIQUE (zone_id, chunk_coords, tick_id)
);

CREATE INDEX ON tak_chunk_events (zone_id);
CREATE INDEX ON tak_chunk_events (tick_id);
CREATE INDEX ON tak_chunk_events (rule_hash);
```

**Diffs Format:**
```elixir
# JSONB array of voxel state transitions
[
  %{voxel_id: {0, 0, 0}, old: 0, new: 1},
  %{voxel_id: {1, 1, 1}, old: 1, new: 0},
  ...
]
```

### 3. TAKChunkState (Ash Resource)

**Location:** `lib/thundervine/resources/tak_chunk_state.ex`

**Purpose:** Store complete chunk state snapshots (future use for checkpointing)

**Schema:**
```elixir
defmodule Thundervine.TAKChunkState do
  attributes do
    uuid_primary_key :id
    attribute :zone_id, :string, allow_nil?: false
    attribute :chunk_coords, {:array, :integer}, allow_nil?: false
    attribute :tick_id, :integer, allow_nil?: false
    attribute :state_snapshot, :map, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :by_zone_chunk, [:zone_id, :chunk_coords]
  end
end
```

### 4. Thundervine.Supervisor

**Location:** `lib/thundervine/supervisor.ex`

**Purpose:** Manage lifecycle of TAKEventRecorder instances

**API:**
```elixir
# Start recorder for a run
{:ok, pid} = Thundervine.Supervisor.start_recorder(run_id: "my_run")

# Stop recorder
:ok = Thundervine.Supervisor.stop_recorder("my_run")

# List active recorders
["run_1", "run_2", "run_3"] = Thundervine.Supervisor.list_recorders()
```

---

## Integration Points

### Auto-start from TAK.Runner

TAK.Runner automatically starts event recording when initialized:

```elixir
# In lib/thunderline/thunderbolt/tak/runner.ex
def init(opts) do
  run_id = Keyword.fetch!(opts, :run_id)
  enable_recording? = Keyword.get(opts, :enable_recording?, true)
  
  if enable_recording? do
    {:ok, _pid} = Thundervine.Supervisor.start_recorder(run_id: run_id)
  end
  
  # ... rest of initialization
end
```

**Disable recording:**
```elixir
{:ok, runner} = TAK.Runner.start_link(
  run_id: "my_run",
  enable_recording?: false
)
```

### PubSub Message Format

TAK.Runner broadcasts CA deltas on topic `"ca:#{run_id}"`:

```elixir
msg = %{
  run_id: "my_run_123",
  seq: 42,                    # Message sequence number
  generation: 100,            # Tick/generation number
  cells: [                    # Cell state changes
    %{coord: {0, 0}, old: 0, new: 1},
    %{coord: {1, 1}, old: 1, new: 0}
  ],
  timestamp: ~U[2025-11-21 12:00:00Z]
}

Phoenix.PubSub.broadcast(Thunderline.PubSub, "ca:#{run_id}", {:ca_delta, msg})
```

---

## Usage Examples

### Basic Recording

```elixir
# 1. Start TAK runner (auto-starts recorder)
{:ok, runner} = Thunderline.Thunderbolt.TAK.Runner.start_link(
  run_id: "experiment_001",
  zone_id: "zone_alpha",
  rule: "B3/S23",  # Conway's Game of Life
  grid_size: {64, 64, 64}
)

# 2. Run simulation
TAK.Runner.step(runner, steps: 1000)

# 3. Check recording stats
{:ok, recorder_pid} = Thundervine.Registry.lookup(
  Thundervine.TAKEventRecorder,
  "experiment_001"
)

stats = Thundervine.TAKEventRecorder.get_stats(recorder_pid)
# => %{events_persisted: 1000, events_failed: 0, ...}

# 4. Stop runner (stops recorder automatically)
TAK.Runner.stop(runner)
```

### Query Recorded Events

```elixir
# Get all events for a zone at specific tick
events = Thundervine.TAKChunkEvent
|> Ash.Query.filter(zone_id == ^"zone_alpha" and tick_id == ^500)
|> Ash.read!()

# Get event history for a chunk
chunk_history = Thundervine.TAKChunkEvent
|> Ash.Query.filter(
    zone_id == ^"zone_alpha" and 
    chunk_coords == ^[0, 0, 0]
  )
|> Ash.Query.sort(:tick_id)
|> Ash.read!()

# Find all events using specific rule
rule_events = Thundervine.TAKChunkEvent
|> Ash.Query.filter(rule_hash == ^"c4bd91a26d5ba03e")
|> Ash.read!()
```

### Replay CA Evolution

```elixir
defmodule Thundervine.Replay do
  @doc """
  Reconstruct CA state at specific tick by replaying events.
  """
  def reconstruct_state(zone_id, chunk_coords, target_tick) do
    # Get all events up to target tick
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(
        zone_id == ^zone_id and 
        chunk_coords == ^chunk_coords and 
        tick_id <= ^target_tick
      )
    |> Ash.Query.sort(:tick_id)
    |> Ash.read!()
    
    # Apply diffs sequentially
    initial_state = %{}
    
    Enum.reduce(events, initial_state, fn event, state ->
      Enum.reduce(event.diffs, state, fn diff, acc ->
        Map.put(acc, diff.voxel_id, diff.new)
      end)
    end)
  end
end

# Usage
state_at_tick_500 = Thundervine.Replay.reconstruct_state(
  "zone_alpha",
  [0, 0, 0],
  500
)
```

### Manual Recording Control

```elixir
# Start recorder manually (without TAK.Runner)
{:ok, recorder} = Thundervine.Supervisor.start_recorder(
  run_id: "manual_recording",
  zone_id: "test_zone"
)

# Simulate CA deltas (for testing)
Phoenix.PubSub.broadcast(
  Thunderline.PubSub,
  "ca:manual_recording",
  {:ca_delta, %{
    run_id: "manual_recording",
    seq: 1,
    generation: 1,
    cells: [%{coord: {0, 0}, old: 0, new: 1}],
    timestamp: DateTime.utc_now()
  }}
)

# Stop recorder
Thundervine.Supervisor.stop_recorder("manual_recording")
```

### Analyze Rule Performance

```elixir
defmodule Thundervine.Analytics do
  @doc """
  Calculate activity metrics for a rule across all runs.
  """
  def rule_activity_metrics(rule_hash) do
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(rule_hash == ^rule_hash)
    |> Ash.read!()
    
    %{
      total_events: length(events),
      total_state_changes: Enum.sum(Enum.map(events, &length(&1.diffs))),
      tick_range: tick_range(events),
      zones_affected: events |> Enum.map(& &1.zone_id) |> Enum.uniq(),
      avg_changes_per_tick: avg_changes(events)
    }
  end
  
  defp tick_range([]), do: nil
  defp tick_range(events) do
    ticks = Enum.map(events, & &1.tick_id)
    {Enum.min(ticks), Enum.max(ticks)}
  end
  
  defp avg_changes([]), do: 0.0
  defp avg_changes(events) do
    total_changes = Enum.sum(Enum.map(events, &length(&1.diffs)))
    total_changes / length(events)
  end
end
```

---

## Performance Considerations

### Event Volume

TAK simulations can generate high event volumes:
- **64³ grid**: ~260k voxels
- **Active cells**: 5-20% (13k-52k active voxels)
- **Change rate**: 1-10% per tick (130-5,200 changes/tick)
- **1000 ticks**: 130k-5.2M total events

### Optimization Strategies

1. **Batch Inserts**: Group events before persisting (future enhancement)
2. **Partitioning**: Partition `tak_chunk_events` by `zone_id` or time range
3. **Compression**: JSONB automatically compresses repeated structures
4. **Async Workers**: Use Oban for background persistence (future)
5. **Sampling**: Record every Nth tick for long runs

### Database Sizing

Estimate storage requirements:
```
Event size: ~200 bytes base + (100 bytes × avg_diffs_per_event)
1M events with 10 diffs each: ~1.1 GB
10M events: ~11 GB
```

---

## Monitoring & Observability

### Telemetry Events

TAKEventRecorder emits telemetry for monitoring:

```elixir
# Future enhancement
:telemetry.execute(
  [:thundervine, :event_recorder, :persist],
  %{duration: duration_us, event_count: 1},
  %{run_id: run_id, zone_id: zone_id, result: :ok}
)
```

### Health Checks

```elixir
# Check recorder is running
case Thundervine.Registry.lookup(Thundervine.TAKEventRecorder, run_id) do
  {:ok, pid} when is_pid(pid) -> Process.alive?(pid)
  _ -> false
end

# Check persistence lag
stats = Thundervine.TAKEventRecorder.get_stats(recorder_pid)
lag = stats.events_received - stats.events_persisted
if lag > 100, do: Logger.warning("Persistence lag: #{lag} events")
```

### Failure Recovery

TAKEventRecorder crashes are handled by Thundervine.Supervisor:
- **Restart Strategy**: `:one_for_one` with 3 restarts per 5 seconds
- **Data Loss**: Only in-flight events lost (events already persisted are safe)
- **Recovery**: Recorder restarts and resumes from next PubSub message

---

## Testing

### Test Suite

**Location:** `test/thundervine/tak_event_recorder_test.exs`

**Coverage:**
1. ✅ PubSub subscription and message reception
2. ✅ Event persistence via Ash
3. ✅ Multi-event sequence handling
4. ✅ Supervisor start/stop API
5. ⏸️ TAK.Runner auto-start integration (pending TAK.RuleParser)

**Run tests:**
```bash
mix test test/thundervine/tak_event_recorder_test.exs
```

### Integration Testing

```elixir
# test/integration/tak_persistence_test.exs
defmodule Thundervine.IntegrationTest do
  use Thunderline.DataCase
  
  test "end-to-end TAK recording and replay" do
    # Start runner with recording
    {:ok, runner} = TAK.Runner.start_link(
      run_id: "integration_test",
      zone_id: "test_zone",
      rule: "B3/S23"
    )
    
    # Run simulation
    TAK.Runner.step(runner, steps: 10)
    
    # Verify events recorded
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(zone_id == "test_zone")
    |> Ash.read!()
    
    assert length(events) == 10
    
    # Verify replay
    state = Thundervine.Replay.reconstruct_state("test_zone", [0,0,0], 10)
    assert map_size(state) > 0
  end
end
```

---

## Future Enhancements

### Planned Features

1. **Batch Persistence**: Buffer events and insert in batches for throughput
2. **Compression**: Delta encoding for sequential ticks (store only changes from previous tick)
3. **Snapshots**: Periodic full state snapshots for faster replay
4. **Retention Policies**: Auto-archive old events via ThunderBlock retention policies
5. **Async Workers**: Oban workers for background persistence (decouple from GenServer)
6. **Query API**: High-level Ash queries for common replay patterns
7. **Visualization**: LiveView dashboard for event stream monitoring
8. **Export**: Export events to Parquet/Arrow for offline analysis

### Research Directions

1. **Event Sourcing Patterns**: CQRS with read models for fast queries
2. **Time-travel Debugging**: Step through CA evolution tick-by-tick
3. **Diff Compression**: Use binary diffs or run-length encoding
4. **Distributed Recording**: Shard events across multiple recorders
5. **ML Integration**: Train models to predict CA evolution from event history

---

## References

- **Domain Catalog**: `THUNDERLINE_DOMAIN_CATALOG.md`
- **TAK Architecture**: `documentation/TAK_ARCHITECTURE.md` (if exists)
- **Thunderflow Events**: `lib/thunderline/events/tak_chunk_evolved.ex`
- **Migration**: `priv/repo/migrations/20251116120000_create_tak_tables.exs`

---

**Last Updated:** November 21, 2025  
**Maintainers:** Thundervine Team  
**Status:** Production Ready ✅
