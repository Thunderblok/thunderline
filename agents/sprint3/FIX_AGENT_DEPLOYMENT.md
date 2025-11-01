# 🔧 Fix Agent Deployment Plan

**Agent ID:** `fix-agent`  
**Epic:** 3.1 Cerebros Integration Execution  
**Priority:** 🔴 CRITICAL (Priority 1)  
**Duration:** 30 minutes  
**Can Run Parallel With:** config-agent, test-agent  

## Mission
Execute code fixes and dependency management for Cerebros integration.

## Tasks

### Task 1: Fix Broken Import (2 min)
**File:** `lib/thunderline/thunderbolt/cerebros_bridge/run_worker.ex:26`

**Current (BROKEN):**
```elixir
alias CerebrosBridge.Telemetry
```

**Fix To:**
```elixir
alias Cerebros.Telemetry
```

**Verification:** File compiles with no warnings

---

### Task 2: Add Cerebros Dependency (5 min)
**File:** `mix.exs`

**Add to deps function:**
```elixir
{:cerebros, path: "/home/mo/DEV/cerebros"}
```

**Then run:**
```bash
mix deps.get
mix deps.compile
```

**Verification:** `mix compile` succeeds

---

### Task 3: Update Demo Functions (10 min)
**File:** `lib/thunderline_web/live/cerebros_live.ex`

**Update 4 functions to call bridge:**
1. `handle_event("launch_nas_run", ...)`
2. `handle_event("cancel_run", ...)`
3. `handle_event("view_results", ...)`
4. `handle_event("download_report", ...)`

**Pattern:**
```elixir
# Before: Stub implementation
def handle_event("launch_nas_run", params, socket) do
  {:noreply, put_flash(socket, :info, "NAS run launched (demo)")}
end

# After: Call bridge
def handle_event("launch_nas_run", params, socket) do
  case Thunderline.Thunderbolt.CerebrosBridge.RunWorker.run(params) do
    {:ok, result} -> {:noreply, put_flash(socket, :info, "NAS run launched")}
    {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed: #{reason}")}
  end
end
```

**Verification:** LiveView compiles, functions updated

---

### Task 4: Test Compilation (5 min)
```bash
mix compile --warnings-as-errors
mix format --check-formatted
```

**Verification:** 
- Zero compilation warnings
- Code formatted correctly
- All imports resolve

---

## Deliverables

- [ ] `run_worker.ex` import fixed
- [ ] `mix.exs` updated with Cerebros dependency
- [ ] 4 LiveView functions updated
- [ ] Code compiles clean (no warnings)
- [ ] Tests still pass: `mix test`

## Success Criteria
✅ Code compiles with zero warnings  
✅ All imports correct  
✅ LiveView functions call bridge  
✅ Existing tests don't break  

## Blockers
- ❌ Cerebros repo not at `/home/mo/DEV/cerebros` → Update path
- ❌ Cerebros repo has compile errors → Fix upstream first

## Communication
**Report When:**
- Import fixed (2 min mark)
- Dependency added (7 min mark)
- Functions updated (17 min mark)
- Compilation clean (22 min mark)
- All tests pass (30 min mark)

**Estimated Completion:** 30 minutes  
**Status:** 🟢 READY TO DEPLOY
