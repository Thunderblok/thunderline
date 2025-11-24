# Domain Activation Flow Architecture

**Created**: November 24, 2025  
**Purpose**: Visual representation of tick-based domain activation system

---

## Current State (Before Implementation)

```
Application Start
       ↓
  [Supervisor]
       ↓
  ┌────┴────────────────────────────────────┐
  ↓         ↓         ↓         ↓          ↓
Core    Database  Domains  Infrastructure  Web
  ↓         ↓         ↓         ↓          ↓
PubSub    Repo    Thunderbolt EventBuffer Endpoint
Vault           Thunderflow  Blackboard
              Thundergate  Registry
              (ALL START IMMEDIATELY - NO GATING)
```

**Problem**: No coordination, no activation lifecycle, no tick system

---

## Target State (After Implementation)

```
Application Start
       ↓
  [Supervisor]
       ↓
       1. Core Infrastructure
       ↓
  ┌────────────────────────┐
  │  Phoenix.PubSub        │
  │  Task.Supervisor       │
  │  Vault (if enabled)    │
  └────────┬───────────────┘
       ↓
       2. Database Layer
       ↓
  ┌────────────────────────┐
  │  Thunderline.Repo      │
  └────────┬───────────────┘
       ↓
       3. Tick System (NEW!)
       ↓
  ┌─────────────────────────────────────────┐
  │  Thunderblock.DomainRegistry (FIRST)    │ ← Listens for activations
  │  ↓                                       │
  │  Thunderlink.TickGenerator (SECOND)     │ ← Generates ticks
  └────────┬────────────────────────────────┘
       ↓ (subscribes to "system:domain_tick")
       ↓
       4. Domain Supervisors (WAITING STATE)
       ↓
  ┌──────────────────────────────────────────┐
  │  Thunderflow.DomainSupervisor            │
  │  Thunderbolt.DomainSupervisor            │  All domains start in
  │  Cerebros.DomainSupervisor               │  WAITING state,
  │  Thundercrown.DomainSupervisor           │  subscribed to tick
  │  Thundergrid.DomainSupervisor            │  events
  │  Thundergate.DomainSupervisor            │
  │  (all waiting for first tick)            │
  └────────┬─────────────────────────────────┘
       ↓
       ... WAITING ...
       ↓
       🎯 TICK #1 arrives at T+1000ms
       ↓
  ┌──────────────────────────────────────────┐
  │  {:domain_tick, 1, timestamp, metadata}  │
  └────────┬─────────────────────────────────┘
       ↓ (broadcast to all waiting domains)
       ↓
  ┌──────────┬────────────┬──────────┬────────┐
  ↓          ↓            ↓          ↓        ↓
Thunderflow Thunderbolt Cerebros  Thundercrown ...
  ↓          ↓            ↓          ↓        ↓
ACTIVATE!  ACTIVATE!   ACTIVATE!  ACTIVATE!  ACTIVATE!
  ↓          ↓            ↓          ↓        ↓
  │          │            │          │        │
  │ Each domain:                              │
  │ 1. Starts domain-specific children        │
  │ 2. Broadcasts {:domain_activated, name}   │
  │ 3. DomainRegistry records activation      │
  │ 4. Changes state from :waiting → :active  │
  └──────────┴────────────┴──────────┴────────┘
       ↓
       🎯 TICK #2 arrives at T+2000ms
       ↓
  ┌──────────────────────────────────────────┐
  │  {:domain_tick, 2, timestamp, metadata}  │
  └────────┬─────────────────────────────────┘
       ↓
  All domains already :active - just update tick count
  (no re-activation)
```

---

## Tick Event Flow

```
┌─────────────────────────┐
│  TickGenerator          │
│  (every 1000ms)         │
└───────────┬─────────────┘
            ↓
     Generate Tick Event
            ↓
┌───────────────────────────────────────────┐
│ Phoenix.PubSub.broadcast(                 │
│   "system:domain_tick",                   │
│   {:domain_tick, count, timestamp, meta}  │
│ )                                         │
└───────┬───────────────────────────────────┘
        ↓
        │
        ├────────────────┬──────────────┬──────────────┬─────────────┐
        ↓                ↓              ↓              ↓             ↓
┌───────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ DomainRegistry│  │Thunderflow│  │Thunderbolt│  │ Cerebros │  │  Other   │
│  (record tick)│  │(activate?)│  │(activate?)│  │(activate?)│  │ Domains  │
└───────┬───────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘  └─────┬────┘
        ↓                ↓              ↓              ↓             ↓
   Update ETS    If :waiting →   If :waiting →  If :waiting → If :waiting →
   [:last_tick]     activate()      activate()      activate()   activate()
        ↓                ↓              ↓              ↓             ↓
        │                │              │              │             │
        │                └──────┬───────┴──────┬───────┴─────────────┘
        │                       ↓              ↓
        │              ┌────────────────────────────────┐
        │              │ Phoenix.PubSub.broadcast(       │
        │              │   "system:domain_activated",    │
        │              │   {:domain_activated, name}     │
        │              │ )                               │
        │              └────────────┬───────────────────┘
        │                           ↓
        └───────────────────────────┤
                                    ↓
                        ┌─────────────────────────┐
                        │  DomainRegistry         │
                        │  handle_info()          │
                        │  - Add to active set    │
                        │  - Update ETS           │
                        │  - Record in history    │
                        │  - Emit telemetry       │
                        └─────────────────────────┘
```

---

## ETS Data Structure

**Table**: `:thunderblock_domain_registry`

```elixir
# Key-Value Pairs:
{:last_tick, tick_count, timestamp}
{"thunderflow", :active, 1, 1732488000000}
{"thunderbolt", :active, 1, 1732488000000}
{"cerebros", :active, 1, 1732488000100}
{"thundercrown", :active, 2, 1732488001000}
{"thundergrid", :active, 3, 1732488002000}

# Queries:
:ets.lookup(:thunderblock_domain_registry, :last_tick)
# => [{:last_tick, 42, 1732488042000}]

:ets.lookup(:thunderblock_domain_registry, "thunderflow")
# => [{"thunderflow", :active, 1, 1732488000000}]
```

---

## Domain State Machine

```
┌─────────────┐
│   :waiting  │  ← Initial state after GenServer.init()
└──────┬──────┘
       │
       │ Subscribed to "system:domain_tick"
       │
       ↓
  Receive {:domain_tick, 1, ...}
       │
       ↓
┌──────────────────────┐
│  Call activate/2     │
│  (domain-specific)   │
└──────┬───────────────┘
       │
       ├─ :ok ─────────────────────┐
       │                            ↓
       │                    ┌───────────────┐
       │                    │   :active     │
       │                    └───────┬───────┘
       │                            │
       │                            │ Subsequent ticks
       │                            │ just update counter
       │                            ↓
       │                    ┌───────────────┐
       │                    │  Stay :active │
       │                    │  tick += 1    │
       │                    └───────────────┘
       │
       └─ {:error, reason} ───────┐
                                   ↓
                           ┌──────────────┐
                           │   :crashed   │
                           │  (terminate) │
                           └──────────────┘
```

---

## Telemetry Events

### TickGenerator Events
```elixir
:telemetry.execute(
  [:thunderline, :tick_generator, :tick],
  %{
    count: 42,
    latency_ns: 123456,
    active_domains: 6
  },
  %{interval: 1000}
)
```

### DomainRegistry Events
```elixir
:telemetry.execute(
  [:thunderline, :domain_registry, :activation],
  %{active_count: 6},
  %{domain: "thunderflow", tick: 1}
)
```

### Domain Activation Events
```elixir
:telemetry.execute(
  [:thunderline, :domain, :activation],
  %{duration_ms: 45},
  %{domain: "thunderflow", tick: 1, status: :success}
)
```

---

## Health Dashboard Query

```elixir
# Get all active domains
Thunderline.Thunderblock.DomainRegistry.active_domains()
# => ["thunderflow", "thunderbolt", "cerebros", "thundercrown", "thundergrid", "thundergate"]

# Get domain status
Thunderline.Thunderblock.DomainRegistry.domain_status("thunderflow")
# => {:ok, %{status: :active, tick: 42, timestamp: 1732488042000}}

# Get current tick
Thunderline.Thunderlink.TickGenerator.current_tick()
# => 42

# Query ETS directly (fast path)
:ets.lookup(:thunderblock_domain_registry, :last_tick)
# => [{:last_tick, 42, 1732488042000}]
```

---

## Benefits of This Architecture

### 1. Coordinated Startup
- All domains activate together on first tick
- Prevents race conditions
- Clear startup sequence

### 2. Health Monitoring
- Easy to detect crashed domains (stopped receiving ticks)
- Can implement timeout-based restarts
- Dashboard can show activation timeline

### 3. Graceful Degradation
- Individual domains can fail without affecting tick system
- Registry tracks which domains are operational
- Can skip failed domains in orchestration

### 4. Observability
- Telemetry events for every tick and activation
- ETS table queryable for debugging
- Clear activation timeline in logs

### 5. Testing
- Can disable activation (`wait_for_tick: false`)
- Can mock tick events in tests
- Can test domain activation independently

---

## Example Log Output

```
[info] [TickGenerator] Started with 1000ms interval
[info] [DomainRegistry] Started and subscribed to system events
[info] [Thunderflow] Waiting for first tick to activate...
[info] [Thunderbolt] Waiting for first tick to activate...
[info] [Cerebros] Waiting for first tick to activate...
[info] [Thundercrown] Waiting for first tick to activate...
[info] [Thundergrid] Waiting for first tick to activate...
[info] [Thundergate] Waiting for first tick to activate...

... 1 second later ...

[info] [Thunderflow] Received first tick 1, activating...
[info] [Thunderbolt] Received first tick 1, activating...
[info] [Cerebros] Received first tick 1, activating...
[info] [Thundercrown] Received first tick 1, activating...
[info] [Thundergrid] Received first tick 1, activating...
[info] [Thundergate] Received first tick 1, activating...

[info] [DomainRegistry] Domain activated: thunderflow
[info] [DomainRegistry] Domain activated: thunderbolt
[info] [DomainRegistry] Domain activated: cerebros
[info] [DomainRegistry] Domain activated: thundercrown
[info] [DomainRegistry] Domain activated: thundergrid
[info] [DomainRegistry] Domain activated: thundergate

[info] [Thunderflow] Activating at tick 1
[info] [Thunderbolt] Activating at tick 1
[info] [Cerebros] Activating at tick 1
[info] [Thundercrown] Activating at tick 1
[info] [Thundergrid] Activating at tick 1
[info] [Thundergate] Activating at tick 1

... subsequent ticks every second ...
```

---

## Migration Path

### Week 1: Foundation
- Implement TickGenerator
- Implement DomainRegistry
- Create ActiveDomainRegistry resource
- Add to supervision tree
- Verify ticks flowing

### Week 2: First Domain
- Implement DomainActivation behavior
- Apply to Thunderflow
- Verify activation working
- Monitor logs and telemetry

### Week 3: Rollout
- Apply to remaining domains
- Create health dashboard
- Document activation flow

### Week 4: Validation
- Load testing
- Failure scenario testing
- Performance optimization
- Documentation updates

---

## Troubleshooting

### Domain Not Activating

**Symptom**: Domain stuck in `:waiting` state

**Diagnosis**:
```elixir
# Check if ticks are flowing
:ets.lookup(:thunderblock_domain_registry, :last_tick)

# Check PubSub subscription
Process.info(pid, :dictionary)
# Look for ["$subscribers": ...]
```

**Solutions**:
- Verify TickGenerator started
- Check PubSub subscription successful
- Look for errors in domain's `activate/2` callback

### Tick Not Flowing

**Symptom**: No tick telemetry events

**Diagnosis**:
```elixir
# Check TickGenerator process
Process.whereis(Thunderline.Thunderlink.TickGenerator)

# Check process info
Process.info(pid, :messages)
```

**Solutions**:
- Verify TickGenerator in supervision tree
- Check for crashes in logs
- Verify PubSub started before TickGenerator

### ETS Table Missing

**Symptom**: `:badarg` when querying registry

**Diagnosis**:
```elixir
:ets.info(:thunderblock_domain_registry)
```

**Solutions**:
- Verify DomainRegistry started
- Check for crashes during init
- Ensure table created before first tick

---

**Status**: 📋 DESIGN COMPLETE - READY FOR IMPLEMENTATION
