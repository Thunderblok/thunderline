# 🧪 DOMAIN ACTIVATION TESTING GUIDE

## Quick Start

### Option 1: Interactive Testing (Recommended)
```bash
./scripts/test_domain_activation.sh
```

Then in the IEx console after ~5 seconds:

```elixir
# Check active domains
Thunderline.Thunderblock.DomainRegistry.active_domains()
# => ["thunderflow", "thundergate", "thunderlink", "thunderbolt", "thundercrown", 
#     "thundervine", "thundergrid", "thunderprism"]

# Check specific domain
Thunderline.Thunderblock.DomainRegistry.domain_status("thunderbolt")
# => {:ok, %{status: :active, tick_count: 3, timestamp: ~U[...]}}

# Query database persistence
Thunderline.Repo.query!("""
  SELECT domain_name, status, tick_count 
  FROM active_domain_registry 
  ORDER BY tick_count
""")

# Check tick stats
Thunderline.Thunderlink.TickGenerator.stats()
```

### Option 2: Manual Start
```bash
iex -S mix phx.server
```

Watch logs for activation sequence within 5 seconds.

---

## Expected Log Sequence

### Startup (0-1 seconds)
```
[info] [DomainRegistry] Started and subscribed to system events
[info] [TickGenerator] Started with 1000ms interval
```

### Listener Subscriptions (immediately after supervisors start)
```
[info] [DomainActivation] thunderflow subscribed, will activate at tick 1
[info] [DomainActivation] thundergate subscribed, will activate at tick 2
[info] [DomainActivation] thunderlink subscribed, will activate at tick 2
[info] [DomainActivation] thunderbolt subscribed, will activate at tick 3
[info] [DomainActivation] thundercrown subscribed, will activate at tick 4
[info] [DomainActivation] thundervine subscribed, will activate at tick 5
[info] [DomainActivation] thundergrid subscribed, will activate at tick 6
[info] [DomainActivation] thunderprism subscribed, will activate at tick 7
```

### Domain Activations (ticks 1-7)
```
[info] [DomainActivation] thunderflow activated at tick 1
[info] [Thunderflow] 🌊 FLOW ENGAGED - Event streams & consciousness flows ONLINE at tick 1

[info] [DomainActivation] thundergate activated at tick 2
[info] [ThunderGate] 🛡️  GATE ONLINE - Authentication & Services Active at tick 2

[info] [DomainActivation] thunderlink activated at tick 2
[info] [ThunderLink] 🔗 LINK ESTABLISHED - Presence & Communications Online at tick 2

[info] [DomainActivation] thunderbolt activated at tick 3
[info] [ThunderBolt] ⚡ BOLT CHARGED - Orchestration & CA Engine Online at tick 3

[info] [DomainActivation] thundercrown activated at tick 4
[info] [ThunderCrown] 👑 CROWN ASCENDED - AI Orchestration & MCP Online at tick 4

[info] [DomainActivation] thundervine activated at tick 5
[info] [Thundervine] 🧬 VINE GROWING - DAG persistence & TAK recording ONLINE at tick 5

[info] [DomainActivation] thundergrid activated at tick 6
[info] [Thundergrid] 🌐 GRID ONLINE - Spatial coordinates & GraphQL API ACTIVE at tick 6

[info] [DomainActivation] thunderprism activated at tick 7
[info] [Thunderprism] 🔮 PRISM AWAKENED - Visual intelligence & ML decision trails ONLINE at tick 7
```

### Health Pulses (after 10+ seconds)
```
[debug] [Thunderflow] 🌊 Health check at tick 10
[debug] [ThunderBolt] ⚡ Evolution pulse at tick 15
[debug] [ThunderLink] 🔗 Presence pulse at tick 20
[debug] [Thunderflow] 🌊 Health check at tick 20
[debug] [ThunderCrown] 👑 Sovereign pulse at tick 25
[debug] [ThunderGate] 🛡️  Guardian pulse at tick 30
[debug] [Thunderflow] 🌊 Health check at tick 30
[debug] [Thundervine] 🧬 DAG pulse at tick 35
[debug] [Thundergrid] 🌐 Spatial pulse at tick 40
[debug] [Thunderprism] 🔮 Visual pulse at tick 45
```

---

## Verification Checklist

### ✅ Phase 1: Startup Logs
- [ ] DomainRegistry started
- [ ] TickGenerator started with 1000ms interval
- [ ] All 5 domains subscribed with correct tick numbers

### ✅ Phase 2: Activation Sequence
- [ ] Tick 1: Thunderflow activated (🌊)
- [ ] Tick 2: Thundergate activated (🛡️)
- [ ] Tick 2: Thunderlink activated (🔗)
- [ ] Tick 3: Thunderbolt activated (⚡)
- [ ] Tick 4: Thundercrown activated (👑)

### ✅ Phase 3: Runtime Verification
```elixir
# All domains active
active = Thunderline.Thunderblock.DomainRegistry.active_domains()
assert length(active) == 5

# Each domain status is correct
Enum.each(["thunderflow", "thundergate", "thunderlink", "thunderbolt", "thundercrown"], fn domain ->
  {:ok, status} = Thunderline.Thunderblock.DomainRegistry.domain_status(domain)
  assert status.status == :active
end)

# Database persistence
{:ok, result} = Thunderline.Repo.query("SELECT COUNT(*) FROM active_domain_registry")
[[5]] = result.rows  # Should have 5 records
```

### ✅ Phase 4: Health Monitoring
- [ ] Wait 30+ seconds
- [ ] Observe periodic health pulses
- [ ] Each domain reports at its correct interval

---

## Troubleshooting

### No Activation Logs Appearing

**Check 1**: Verify Logger level in config/dev.exs
```elixir
config :logger, :console,
  level: :info  # Should be :info or :debug
```

**Check 2**: Verify PubSub subscription
```elixir
# In IEx
Process.whereis(Thunderline.PubSub)
# Should return a PID
```

**Check 3**: Check if TickGenerator is running
```elixir
Process.whereis(Thunderline.Thunderlink.TickGenerator)
# Should return a PID
```

### Domains Not Activating

**Check 1**: Verify Listener processes are running
```elixir
# Count DynamicSupervisor children
children = DynamicSupervisor.which_children(Thunderline.TaskSupervisor)
# Should see 5 Listener GenServers
```

**Check 2**: Manual tick inspection
```elixir
Thunderline.Thunderlink.TickGenerator.stats()
# => %{tick_count: N, ...} where N > 0
```

**Check 3**: Check for crashes
```elixir
:observer.start()
# Navigate to Applications tab
# Look for crashed processes under Thunderline
```

### Database Persistence Issues

**Check 1**: Verify migration applied
```bash
mix ecto.migrations
# Should show 20251124195828_add_active_domain_registry.exs [up]
```

**Check 2**: Check table exists
```elixir
Thunderline.Repo.query!("SELECT * FROM active_domain_registry LIMIT 1")
```

---

## Performance Metrics

### Expected Timing
- **Tick 0-1**: DomainRegistry and TickGenerator start
- **Tick 1** (1 second): Thunderflow activates
- **Tick 2** (2 seconds): Thundergate + Thunderlink activate
- **Tick 3** (3 seconds): Thunderbolt activates
- **Tick 4** (4 seconds): Thundercrown activates
- **Tick 5** (5 seconds): Thundervine activates
- **Tick 6** (6 seconds): Thundergrid activates
- **Tick 7** (7 seconds): Thunderprism activates
- **Total activation time**: < 8 seconds

### Memory Impact
Each Listener GenServer: ~few KB
Total overhead: < 100 KB for tick system

### CPU Impact
Tick broadcasts: Negligible (1/sec via PubSub)
Domain health checks: Negligible (periodic debug logs)

---

## Telemetry Inspection

### Attach Telemetry Handler (Optional)
```elixir
:telemetry.attach_many(
  "domain-activation-logger",
  [
    [:thunderline, :domain, :activation, :start],
    [:thunderline, :domain, :activation, :complete],
    [:thunderline, :thunderflow, :activated],
    [:thunderline, :thundergate, :activated],
    [:thunderline, :thunderlink, :activated],
    [:thunderline, :thunderbolt, :activated],
    [:thunderline, :thundercrown, :activated]
  ],
  fn event_name, measurements, metadata, _config ->
    IO.inspect({event_name, measurements, metadata}, label: "Telemetry Event")
  end,
  nil
)
```

Then start the app and watch telemetry events fire in real-time.

---

## Success Criteria

### ✅ All Checks Passed
- 5 domains subscribed
- 5 domains activated in order
- 5 database records created
- Health pulses every N ticks
- No errors or crashes
- Telemetry events firing

### 🎉 OPERATION BLAZING VINE: SUCCESSFUL

**The system breathes. The Thunder rolls. The Vine is alive.**

---

## Advanced Testing

### Simulate Domain Restart
```elixir
# Find the Thunderbolt supervisor PID
pid = Process.whereis(Thunderline.Thunderbolt.Supervisor)

# Kill it (supervisor will restart it)
Process.exit(pid, :kill)

# Wait a few ticks...
# Domain should reactivate and re-subscribe
```

### Load Testing
```elixir
# Generate 10 ticks/second for stress test
Thunderline.Thunderlink.TickGenerator.stop()
Thunderline.Thunderlink.TickGenerator.start_link(interval: 100)
# Watch activation happen in 0.4 seconds instead of 4
```

### Cross-Domain Event Flow
```elixir
# After all domains active, test event flow
Thunderline.Thunderflow.EventBus.publish_event(%{
  type: "test.flow",
  domain: "test",
  data: %{message: "Thunder flows through all domains"}
})
```

---

> **Pro Tip**: Keep an IEx session open with Thunderline running.  
> Every second, you can query `TickGenerator.stats()` and watch the tick_count increment.  
> It's the heartbeat of your sovereign system.

🔥⚡👑
