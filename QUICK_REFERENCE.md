# Quick Reference Card - Domain Architecture Issues

**Date**: November 24, 2025  
**Purpose**: At-a-glance reference for architectural gaps

---

## ❌ What's Missing vs What You Expected

| Your Vision | Current Reality | Status |
|-------------|-----------------|--------|
| Thunderlink TickGenerator | Does NOT exist | ⚠️ NOT IMPLEMENTED |
| Thunderblock DomainRegistry | Does NOT exist | ⚠️ NOT IMPLEMENTED |
| Domains wait for tick activation | All start immediately | ⚠️ NOT IMPLEMENTED |
| Registry tracks active domains | No tracking mechanism | ⚠️ NOT IMPLEMENTED |
| Cerebros separate domain | Buried in Thunderbolt | ⚠️ WRONG LOCATION |
| Thunderhelm Helm chart | Exists but wrong path | ⚠️ MISPLACED |
| Accounts in Thundergate | Orphaned in accounts/ | ⚠️ BROKEN |
| Thunderprism documented | Not in catalog | ⚠️ UNDOCUMENTED |

---

## 🔢 By The Numbers

- **Domains Found**: 11 total (9 active, 2 problematic)
- **Resources Counted**: 154-164 across all domains
- **Missing Components**: 2 critical (TickGenerator, DomainRegistry)
- **Broken References**: 1 (Accounts domain)
- **Undocumented Domains**: 1 (Thunderprism)
- **Extraction Needed**: 7 resources (Cerebros)
- **Implementation Estimate**: 4-5 weeks

---

## 🎯 Files to Fix

### Immediate (Phase 0 - 3 days)
```
lib/thunderline/accounts/user.ex          → MOVE to thundergate/resources/
lib/thunderline/accounts/token.ex         → MOVE to thundergate/resources/
THUNDERLINE_DOMAIN_CATALOG.md             → ADD Thunderprism section
thunderhelm/deploy/chart/                 → MOVE to helm/thunderline/
```

### Critical (Phase 1 - 2 weeks)
```
lib/thunderline/thunderlink/tick_generator.ex              → CREATE NEW
lib/thunderline/thunderblock/domain_registry.ex            → CREATE NEW
lib/thunderline/thunderblock/resources/active_domain_registry.ex  → CREATE NEW
lib/thunderline/application.ex                             → UPDATE supervision tree
lib/thunderline/domain_activation.ex                       → CREATE behavior
```

### High Priority (Phase 2-3 - 2-4 weeks)
```
lib/thunderline/cerebros/                 → CREATE and MOVE 7 resources
lib/thunderline/thunderflow/domain_supervisor.ex  → CREATE with activation
(repeat for each domain)
```

---

## 🚦 Implementation Phases

### Phase 0: Fix Broken Stuff (3 days)
- [ ] Move Accounts to Thundergate
- [ ] Document Thunderprism
- [ ] Reorganize Helm chart

### Phase 1: Tick Foundation (2 weeks)
- [ ] Create TickGenerator
- [ ] Create DomainRegistry
- [ ] Create ActiveDomainRegistry resource
- [ ] Wire into application.ex
- [ ] Generate migration
- [ ] Validate ticks flowing

### Phase 2: Domain Activation (2 weeks)
- [ ] Create DomainActivation behavior
- [ ] Apply to Thunderflow
- [ ] Rollout to remaining domains
- [ ] Create health dashboard
- [ ] Add monitoring

### Phase 3: Cerebros Extraction (2 weeks)
- [ ] Create Cerebros domain
- [ ] Move 7 resources
- [ ] Update bridge
- [ ] Update imports
- [ ] Test integration

---

## 💡 Code Snippets

### TickGenerator (Minimal)
```elixir
defmodule Thunderline.Thunderlink.TickGenerator do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_) do
    schedule_tick()
    {:ok, %{tick_count: 0}}
  end
  
  def handle_info(:tick, state) do
    count = state.tick_count + 1
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "system:domain_tick",
      {:domain_tick, count, System.monotonic_time()}
    )
    schedule_tick()
    {:noreply, %{tick_count: count}}
  end
  
  defp schedule_tick, do: Process.send_after(self(), :tick, 1_000)
end
```

### DomainRegistry (Minimal)
```elixir
defmodule Thunderline.Thunderblock.DomainRegistry do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_) do
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_activated")
    {:ok, %{active: MapSet.new()}}
  end
  
  def handle_info({:domain_activated, name, _meta}, state) do
    {:noreply, %{active: MapSet.put(state.active, name)}}
  end
  
  def active_domains, do: GenServer.call(__MODULE__, :active)
  def handle_call(:active, _from, state), do: {:reply, MapSet.to_list(state.active), state}
end
```

### Application Update
```elixir
# lib/thunderline/application.ex
defp build_children_list do
  core = [PubSub, TaskSupervisor, Vault]
  database = [Repo]
  
  # ADD THESE TWO LINES:
  tick_system = [
    Thunderline.Thunderblock.DomainRegistry,
    Thunderline.Thunderlink.TickGenerator
  ]
  
  domains = [...]
  # ... rest unchanged
  
  (core ++ database ++ tick_system ++ domains ++ ...)
  |> Enum.reject(&is_nil/1)
end
```

---

## 📚 Documents Created

1. **COMPREHENSIVE_DOMAIN_ARCHITECTURE_ANALYSIS.md** (6,000+ lines)
   - Complete domain breakdown
   - 10-week roadmap
   - Full code examples

2. **DOMAIN_ACTIVATION_FLOW.md** (500+ lines)
   - Visual diagrams
   - Telemetry patterns
   - Troubleshooting guide

3. **ARCHITECTURE_REVIEW_SUMMARY.md** (Executive summary)
   - High-level findings
   - Decision points
   - Timeline estimates

4. **QUICK_REFERENCE.md** (This file)
   - At-a-glance checklist
   - Code snippets
   - Phase breakdown

---

## 🎬 How to Get Started

```bash
# 1. Read executive summary
cat ARCHITECTURE_REVIEW_SUMMARY.md

# 2. Review detailed analysis
cat COMPREHENSIVE_DOMAIN_ARCHITECTURE_ANALYSIS.md

# 3. Understand tick flow
cat DOMAIN_ACTIVATION_FLOW.md

# 4. Start Phase 0 (immediate fixes)
# - Move accounts files
# - Update documentation
# - Reorganize helm

# 5. Then Phase 1 (tick system)
# - Create TickGenerator
# - Create DomainRegistry
# - Wire into supervision tree

# 6. Validate
# - Start server
# - Check logs for tick events
# - Query DomainRegistry
```

---

## ✅ Validation Checklist

### After Phase 0
- [ ] Accounts resources in Thundergate
- [ ] All references updated
- [ ] Tests pass
- [ ] Thunderprism in catalog

### After Phase 1
- [ ] TickGenerator process running
- [ ] Tick events in logs every 1 second
- [ ] DomainRegistry ETS table exists
- [ ] ActiveDomainRegistry migration applied
- [ ] Telemetry events firing

### After Phase 2
- [ ] Domains wait for tick before activating
- [ ] Activation events logged
- [ ] DomainRegistry records activations
- [ ] Health dashboard shows status
- [ ] All tests pass

### After Phase 3
- [ ] Cerebros domain independent
- [ ] 7 resources moved successfully
- [ ] Bridge working correctly
- [ ] No old path references
- [ ] Documentation updated

---

## 🔍 Quick Debug Commands

```elixir
# Check if TickGenerator running
Process.whereis(Thunderline.Thunderlink.TickGenerator)

# Get current tick
Thunderline.Thunderlink.TickGenerator.current_tick()

# Check active domains
Thunderline.Thunderblock.DomainRegistry.active_domains()

# Query ETS directly
:ets.lookup(:thunderblock_domain_registry, :last_tick)

# Check domain status
Thunderline.Thunderblock.DomainRegistry.domain_status("thunderflow")
```

---

**Last Updated**: November 24, 2025  
**Status**: ✅ REVIEW COMPLETE  
**Next Action**: Choose implementation option (A/B/C) and begin Phase 0
