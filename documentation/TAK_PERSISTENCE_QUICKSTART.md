# TAK Persistence Quick Start Guide

**Purpose:** Fast reference for developers working with TAK event recording and replay.

---

## 🚀 Quick Start (3 steps)

### 1. Start TAK Runner with Recording
```elixir
{:ok, runner} = Thunderline.Thunderbolt.TAK.Runner.start_link(
  run_id: "my_experiment",
  zone_id: "zone_1",
  rule: "B3/S23",  # Conway's Game of Life
  grid_size: {64, 64, 64}
)
```
✅ Event recording starts automatically!

### 2. Run Simulation
```elixir
TAK.Runner.step(runner, steps: 1000)
```
✅ Events are being persisted to PostgreSQL in real-time

### 3. Query Events
```elixir
events = Thundervine.TAKChunkEvent
|> Ash.Query.filter(zone_id == "zone_1")
|> Ash.read!()

IO.inspect(length(events))  # => 1000
```

---

## 📊 Common Queries

### Get Events for Specific Tick
```elixir
tick_events = Thundervine.TAKChunkEvent
|> Ash.Query.filter(zone_id == ^zone_id and tick_id == ^tick)
|> Ash.read!()
```

### Get Chunk Evolution History
```elixir
history = Thundervine.TAKChunkEvent
|> Ash.Query.filter(
    zone_id == ^zone_id and 
    chunk_coords == ^[0, 0, 0]
  )
|> Ash.Query.sort(:tick_id)
|> Ash.read!()
```

### Get Events by Rule
```elixir
rule_events = Thundervine.TAKChunkEvent
|> Ash.Query.filter(rule_hash == ^rule_hash)
|> Ash.read!()
```

### Get Events in Time Range
```elixir
range_events = Thundervine.TAKChunkEvent
|> Ash.Query.filter(
    zone_id == ^zone_id and
    tick_id >= ^start_tick and
    tick_id <= ^end_tick
  )
|> Ash.read!()
```

---

## 🔄 Replay CA State

### Reconstruct State at Tick
```elixir
defmodule MyApp.TAKReplay do
  def state_at_tick(zone_id, chunk_coords, target_tick) do
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(
        zone_id == ^zone_id and 
        chunk_coords == ^chunk_coords and 
        tick_id <= ^target_tick
      )
    |> Ash.Query.sort(:tick_id)
    |> Ash.read!()
    
    # Apply diffs sequentially
    Enum.reduce(events, %{}, fn event, state ->
      Enum.reduce(event.diffs, state, fn diff, acc ->
        Map.put(acc, diff.voxel_id, diff.new)
      end)
    end)
  end
end

# Usage
state = MyApp.TAKReplay.state_at_tick("zone_1", [0,0,0], 500)
```

### Replay Full Evolution
```elixir
defmodule MyApp.TAKReplay do
  def replay_evolution(zone_id, chunk_coords) do
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(zone_id == ^zone_id and chunk_coords == ^chunk_coords)
    |> Ash.Query.sort(:tick_id)
    |> Ash.read!()
    
    # Build state for each tick
    {states, _} = Enum.map_reduce(events, %{}, fn event, state ->
      new_state = Enum.reduce(event.diffs, state, fn diff, acc ->
        Map.put(acc, diff.voxel_id, diff.new)
      end)
      
      {{event.tick_id, new_state}, new_state}
    end)
    
    states
  end
end

# Returns: [{tick_1, state_1}, {tick_2, state_2}, ...]
evolution = MyApp.TAKReplay.replay_evolution("zone_1", [0,0,0])
```

---

## 🎛️ Manual Recorder Control

### Start Recorder Manually
```elixir
{:ok, pid} = Thundervine.Supervisor.start_recorder(
  run_id: "manual_test",
  zone_id: "test_zone"
)
```

### Stop Recorder
```elixir
:ok = Thundervine.Supervisor.stop_recorder("manual_test")
```

### List Active Recorders
```elixir
recorders = Thundervine.Supervisor.list_recorders()
# => ["run_1", "run_2", "manual_test"]
```

### Get Recorder Stats
```elixir
{:ok, pid} = Thundervine.Registry.lookup(
  Thundervine.TAKEventRecorder,
  "manual_test"
)

stats = Thundervine.TAKEventRecorder.get_stats(pid)
# => %{
#      events_received: 1000,
#      events_persisted: 998,
#      events_failed: 2,
#      last_tick: 1000,
#      started_at: ~U[2025-11-21 12:00:00Z]
#    }
```

---

## 🔧 Configuration

### Disable Auto-Recording
```elixir
{:ok, runner} = TAK.Runner.start_link(
  run_id: "no_recording",
  enable_recording?: false  # ⬅️ Disable recording
)
```

### Custom Zone ID
```elixir
# Zone ID defaults to run_id, but can be customized
{:ok, pid} = Thundervine.Supervisor.start_recorder(
  run_id: "my_run",
  zone_id: "custom_zone"  # ⬅️ Different zone_id
)
```

---

## 📈 Analytics Examples

### Calculate Activity Metrics
```elixir
defmodule MyApp.TAKAnalytics do
  def activity_for_zone(zone_id) do
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(zone_id == ^zone_id)
    |> Ash.read!()
    
    %{
      total_events: length(events),
      total_changes: Enum.sum(Enum.map(events, &length(&1.diffs))),
      tick_range: tick_range(events),
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
    total = Enum.sum(Enum.map(events, &length(&1.diffs)))
    total / length(events)
  end
end

metrics = MyApp.TAKAnalytics.activity_for_zone("zone_1")
```

### Compare Rules
```elixir
defmodule MyApp.TAKAnalytics do
  def compare_rules(rule_hash_1, rule_hash_2) do
    stats_1 = rule_stats(rule_hash_1)
    stats_2 = rule_stats(rule_hash_2)
    
    %{
      rule_1: stats_1,
      rule_2: stats_2,
      more_active: if(stats_1.total_changes > stats_2.total_changes, do: :rule_1, else: :rule_2)
    }
  end
  
  defp rule_stats(rule_hash) do
    events = Thundervine.TAKChunkEvent
    |> Ash.Query.filter(rule_hash == ^rule_hash)
    |> Ash.read!()
    
    %{
      total_events: length(events),
      total_changes: Enum.sum(Enum.map(events, &length(&1.diffs)))
    }
  end
end
```

---

## 🧪 Testing

### Test Recording
```elixir
test "records TAK events" do
  # Start runner
  {:ok, runner} = TAK.Runner.start_link(
    run_id: "test_run",
    zone_id: "test_zone"
  )
  
  # Run simulation
  TAK.Runner.step(runner, steps: 10)
  
  # Verify events
  events = Thundervine.TAKChunkEvent
  |> Ash.Query.filter(zone_id == "test_zone")
  |> Ash.read!()
  
  assert length(events) == 10
end
```

### Test Replay
```elixir
test "replays CA state correctly" do
  # Record some events (setup)
  record_test_events("test_zone", [0,0,0])
  
  # Replay state
  state = MyApp.TAKReplay.state_at_tick("test_zone", [0,0,0], 5)
  
  # Verify state
  assert state[{1, 1, 1}] == 1
  assert state[{0, 0, 0}] == 0
end
```

---

## 🐛 Debugging

### Check Recorder is Running
```elixir
case Thundervine.Registry.lookup(Thundervine.TAKEventRecorder, run_id) do
  {:ok, pid} when is_pid(pid) -> 
    IO.puts("✅ Recorder running: #{inspect(pid)}")
    IO.puts("Alive: #{Process.alive?(pid)}")
  _ -> 
    IO.puts("❌ Recorder not found")
end
```

### Check Persistence Lag
```elixir
stats = Thundervine.TAKEventRecorder.get_stats(pid)
lag = stats.events_received - stats.events_persisted

if lag > 100 do
  IO.warn("⚠️  Persistence lag: #{lag} events")
end
```

### View Recent Events
```elixir
recent = Thundervine.TAKChunkEvent
|> Ash.Query.filter(zone_id == ^zone_id)
|> Ash.Query.sort(inserted_at: :desc)
|> Ash.Query.limit(10)
|> Ash.read!()

Enum.each(recent, fn event ->
  IO.puts("Tick #{event.tick_id}: #{length(event.diffs)} changes")
end)
```

---

## 📚 Event Structure

### TAKChunkEvent Schema
```elixir
%Thundervine.TAKChunkEvent{
  id: "uuid...",
  zone_id: "zone_1",
  chunk_coords: [0, 0, 0],
  tick_id: 100,
  diffs: [
    %{voxel_id: {0, 0, 0}, old: 0, new: 1},
    %{voxel_id: {1, 1, 1}, old: 1, new: 0}
  ],
  rule_hash: "c4bd91a26d5ba03e",
  meta: %{
    run_id: "my_run",
    seq: 42,
    timestamp: ~U[2025-11-21 12:00:00Z]
  },
  inserted_at: ~U[2025-11-21 12:00:01Z]
}
```

### PubSub Message Format
```elixir
# Broadcasted by TAK.Runner on topic "ca:#{run_id}"
{:ca_delta, %{
  run_id: "my_run",
  seq: 42,
  generation: 100,
  cells: [
    %{coord: {0, 0}, old: 0, new: 1},
    %{coord: {1, 1}, old: 1, new: 0}
  ],
  timestamp: ~U[2025-11-21 12:00:00Z]
}}
```

---

## 🔗 Related Documentation

- **Full Architecture:** `documentation/TAK_PERSISTENCE_ARCHITECTURE.md`
- **Domain Catalog:** `THUNDERLINE_DOMAIN_CATALOG.md` (ThunderVine section)
- **Test Suite:** `test/thundervine/tak_event_recorder_test.exs`
- **Migration:** `priv/repo/migrations/20251116120000_create_tak_tables.exs`

---

**Last Updated:** November 21, 2025  
**Status:** Production Ready ✅
