# 🚀 FIRST SPRINT - Week 1 Task Assignments

**Sprint Duration:** October 9-15, 2025 (Week 1)  
**Sprint Goal:** Establish EventBus foundation + Begin domain remediation  
**Review Agent:** GitHub Copilot - ACTIVE

---

## ✅ Documentation Framework Complete

All supporting documentation is ready in `.azure/`:
- ✅ Master execution plan (THUNDERLINE_REBUILD_INITIATIVE.md)
- ✅ Developer quick reference (DEVELOPER_QUICK_REFERENCE.md)
- ✅ PR review checklist (PR_REVIEW_CHECKLIST.md)
- ✅ Weekly reporting template (WARDEN_CHRONICLES_TEMPLATE.md)
- ✅ AI review protocol (COPILOT_REVIEW_PROTOCOL.md)

**All developers should read INDEX.md first!**

---

## 🎯 Priority 1: Foundation (Must Complete This Week)

### TASK-001: EventBus Canonical API Restoration
**HC Mission:** HC-01
**Assignee:** Flow Steward
**Estimated:** 2-3 days
**Priority:** P0 - BLOCKS ALL OTHER WORK
**Status:** 🟢 COMPLETE (Oct 10, 2025)

**Current State:**
- ✅ `Thunderline.EventBus.publish_event/1` already exists and working
- ✅ `publish_event!/1` already exists
- ✅ Delegation wrapper at `lib/thunderline/event_bus.ex`
- ✅ Real implementation at `lib/thunderline/thunderflow/event_bus.ex`
- ✅ Validation via `EventValidator.validate/1`
- ✅ Basic telemetry spans already emitted
- ⚠️ Mix task exists at `lib/mix/tasks/thunderline/events.lint.ex` (needs review)
- ❌ Taxonomy guardrails incomplete
- ❌ Not all telemetry spans present (missing start/stop/exception)
- ❌ CI gate not yet configured

**What Needs Doing:**

1. **Review & Enhance Telemetry** (4 hours)
   ```elixir
   # Add these telemetry spans to event_bus.ex:
   :telemetry.execute(
     [:thunderline, :eventbus, :publish, :start],
     %{system_time: System.system_time()},
     %{event_name: ev.name, category: ev.category, priority: ev.priority}
   )
   
   :telemetry.execute(
     [:thunderline, :eventbus, :publish, :stop],
     %{duration: duration, system_time: System.system_time()},
     %{event_name: ev.name, status: :success}
   )
   
   :telemetry.execute(
     [:thunderline, :eventbus, :publish, :exception],
     %{duration: duration, system_time: System.system_time()},
     %{event_name: ev.name, error: inspect(reason), kind: :validation_failed}
   )
   ```

2. **Complete Event Taxonomy Validation** (6 hours)
   - Review existing `lib/thunderline/thunderflow/event_validator.ex`
   - Ensure all 5 categories validated: `:system`, `:domain`, `:integration`, `:user`, `:error`
   - Add category enum validation
   - Test with invalid categories to ensure {:error, _} returned

3. **Verify Mix Task & Add CI Gate** (4 hours)
   - Test `mix thunderline.events.lint` works correctly
   - Add to `.github/workflows/ci.yml` (or create if missing):
     ```yaml
     - name: Event Taxonomy Lint
       run: mix thunderline.events.lint
     ```
   - Test CI gate locally with intentionally bad event names

4. **Documentation & Examples** (2 hours)
   - Update `lib/thunderline/event_bus.ex` @moduledoc with examples
   - Add telemetry span documentation
   - Document all 5 event categories with examples

**Acceptance Criteria:**
- [ ] Telemetry spans (start/stop/exception) present in tests
- [ ] Category validation rejects invalid categories
- [ ] `mix thunderline.events.lint` runs successfully
- [ ] CI gate added and passing
- [ ] @moduledoc updated with complete API examples
- [ ] Test coverage ≥ 90% for event_bus.ex

**Files to Modify:**
- `lib/thunderline/thunderflow/event_bus.ex`
- `lib/thunderline/thunderflow/event_validator.ex`
- `lib/mix/tasks/thunderline/events.lint.ex`
- `.github/workflows/ci.yml` (or create)
- `test/thunderline/thunderflow/event_bus_test.exs`

**Branch:** `hc-01-eventbus-telemetry-enhancement`

---

### TASK-002: Critical TODO Audit & Classification
**HC Mission:** Multiple (impacts all domains)  
**Assignee:** Platform Lead or Senior Dev  
**Estimated:** 1 day  
**Priority:** P0 - INFORMS WEEK 2+ WORK

**Current State:**
- ⚠️ **50+ TODOs found in codebase** (grep results show many duplicate entries)
- Major concentration in:
  - `lib/thunderline/thunderlink/dashboard_metrics.ex` (~40 TODOs - metrics stubbed)
  - Ash resource files (fragment syntax issues, validation syntax)
  - Integration points (MLflow, Optuna, HuggingFace)

**What Needs Doing:**

1. **Categorize All TODOs** (4 hours)
   Create `.azure/TODO_AUDIT.md` with classification:
   ```markdown
   # TODO Audit - October 9, 2025
   
   ## Category 1: Ash 3.x Migration (P0 - Blocks HC missions)
   - [ ] `channel.ex:464` - Fix fragment expression for Ash 3.x
   - [ ] `role.ex:579` - Fix validation syntax for Ash 3.x
   - [ ] `message.ex:582` - Fix validation syntax
   ... (list all)
   
   ## Category 2: Dashboard Metrics (P1 - User visible)
   - [ ] `dashboard_metrics.ex:92` - Implement CPU monitoring
   - [ ] `dashboard_metrics.ex:94` - Implement memory monitoring
   ... (list all ~40)
   
   ## Category 3: Integration Stubs (P2 - Feature incomplete)
   - [ ] `auto_ml_driver.ex:149` - Implement Optuna ask() integration
   - [ ] `auto_ml_driver.ex:220` - Implement MLflow logging
   - [ ] `dataset_manager.ex:53` - Replace with actual HuggingFace dataset loading
   
   ## Category 4: Documentation (P3 - Non-blocking)
   - [ ] `action.ex:29` - Follow-up PRs documentation
   ```

2. **Map TODOs to HC Missions** (2 hours)
   - Cross-reference with HC-01 through HC-10
   - Identify which TODOs must be fixed for each HC mission
   - Flag any TODOs that should be converted to HC sub-tasks

3. **Create Tracking Issues** (2 hours)
   - Create GitHub issues for Category 1 (Ash 3.x) TODOs
   - Label with domain tags (thunderlink, thundergrid, etc.)
   - Assign to appropriate domain stewards

**Acceptance Criteria:**
- [ ] Complete TODO_AUDIT.md created
- [ ] All TODOs categorized by priority
- [ ] TODOs mapped to HC missions
- [ ] GitHub issues created for P0 TODOs
- [ ] Stewards notified of their domain TODOs

**Branch:** `todo-audit-classification`

---

## 🎯 Priority 2: Domain Remediation (Parallel Work)

### TASK-003: ThunderLink Dashboard Metrics Implementation
**HC Mission:** Multiple (improves observability for HC-06)  
**Assignee:** Link Steward  
**Estimated:** 2-3 days  
**Priority:** P1 - HIGH VALUE

**Current State:**
- ❌ **40+ metric stubs** in `dashboard_metrics.ex`
- ✅ Dashboard UI already wired up (from previous Phase 1 work)
- ✅ Presence tracking exists
- ❌ Real-time metrics not flowing

**What Needs Doing:**

1. **System Metrics Implementation** (4 hours)
   ```elixir
   # Replace stubs in dashboard_metrics.ex
   def get_system_metrics do
     %{
       cpu: get_cpu_usage(),           # Use :cpu_sup
       memory: get_memory_usage(),     # Use :memsup
       processes: Process.list() |> length(),
       uptime: calculate_real_uptime()
     }
   end
   
   defp get_cpu_usage do
     case :cpu_sup.util() do
       {:ok, usage} -> usage
       _ -> 0
     end
   end
   ```

2. **ThunderLink Specific Metrics** (6 hours)
   - Community tracking (count from Ash query)
   - Message monitoring (rate calculation from telemetry)
   - Federation tracking (socket count + status)

3. **Hook Up Telemetry Handlers** (4 hours)
   - Attach handlers for metrics collection
   - Store in ETS table for fast reads
   - Update dashboard every 5 seconds

**Acceptance Criteria:**
- [ ] All 40+ TODOs in dashboard_metrics.ex resolved
- [ ] Real CPU/memory/process metrics flowing
- [ ] ThunderLink domain metrics accurate
- [ ] Dashboard shows live data
- [ ] Test coverage ≥ 80%

**Files to Modify:**
- `lib/thunderline/thunderlink/dashboard_metrics.ex`
- `lib/thunderline_web/live/dashboard_live.ex` (if needed)
- `test/thunderline/thunderlink/dashboard_metrics_test.exs`

**Branch:** `hc-link-metrics-implementation`

---

### TASK-004: Ash 3.x Fragment Syntax Fixes (ThunderLink)
**HC Mission:** Global Ash 3.x compliance  
**Assignee:** Link Steward  
**Estimated:** 1-2 days  
**Priority:** P0 - BLOCKING TESTS

**Current State:**
- ❌ Multiple "fragment expression" TODOs in resources:
  - `channel.ex:464` - commented out variable references
  - `role.ex:511, 526, 538, 549` - multiple fragment issues
  - `community.ex:500, 515` - fragment issues
  - `message.ex:477, 498` - fragment issues
  - `federation_socket.ex:524, 539, 554, 569` - fragment issues

**What Needs Doing:**

1. **Convert Fragments to Ash 3.x expr() Syntax** (8 hours)
   ```elixir
   # OLD (deprecated):
   calculate :has_permission, :boolean do
     argument :permission, :string
     calculation fn records, %{permission: perm} ->
       # Fragment with variable reference
       fragment("? @> ?", permissions, ^perm)
     end
   end
   
   # NEW (Ash 3.x):
   calculate :has_permission, :boolean do
     argument :permission, :string
     calculation fn records, %{permission: perm} ->
       expr(contains(permissions, ^perm))
     end
   end
   ```

2. **Test Each Conversion** (6 hours)
   - Add test for each fixed calculation/aggregate
   - Verify query results match previous behavior
   - Ensure no N+1 queries introduced

**Acceptance Criteria:**
- [ ] All fragment TODOs resolved in ThunderLink domain
- [ ] No deprecated fragment() calls remain
- [ ] All tests passing
- [ ] Test coverage maintained or improved
- [ ] Performance unchanged (use `mix test --slowest`)

**Files to Modify:**
- `lib/thunderline/thunderlink/resources/channel.ex`
- `lib/thunderline/thunderlink/resources/role.ex`
- `lib/thunderline/thunderlink/resources/community.ex`
- `lib/thunderline/thunderlink/resources/message.ex`
- `lib/thunderline/thunderlink/resources/federation_socket.ex`
- Corresponding test files

**Branch:** `hc-link-ash3-fragment-fixes`

---

### TASK-005: Ash 3.x Validation Syntax Fixes
**HC Mission:** Global Ash 3.x compliance  
**Assignee:** Available Developer  
**Estimated:** 1 day  
**Priority:** P0 - BLOCKING TESTS

**Current State:**
- ❌ Multiple validation syntax TODOs:
  - `role.ex:579` - Fix validation syntax for Ash 3.x
  - `message.ex:582, 584` - Fix validation syntax (`:edit` not valid)
  - `federation_socket.ex:614` - Fix validation syntax
  - `grid_resource.ex:415` - Fix validation syntax

**What Needs Doing:**

1. **Update Validation Syntax** (4 hours)
   ```elixir
   # OLD (deprecated):
   validations do
     validate compare(:min_value, less_than: :max_value), on: :create
     validate attribute_does_not_equal(:status, :archived), on: :edit  # :edit invalid!
   end
   
   # NEW (Ash 3.x):
   validations do
     validate compare(:min_value, less_than: :max_value), on: [:create]
     validate attribute_does_not_equal(:status, :archived), on: [:update]
   end
   ```

2. **Test Validation Behavior** (4 hours)
   - Verify validations still trigger correctly
   - Test both valid and invalid cases
   - Ensure error messages clear

**Acceptance Criteria:**
- [ ] All validation syntax TODOs resolved
- [ ] Tests passing for all modified resources
- [ ] Validation behavior unchanged
- [ ] Error messages remain clear

**Files to Modify:**
- `lib/thunderline/thunderlink/resources/role.ex`
- `lib/thunderline/thunderlink/resources/message.ex`
- `lib/thunderline/thunderlink/resources/federation_socket.ex`
- `lib/thunderline/thundergrid/resources/grid_resource.ex`
- Corresponding test files

**Branch:** `hc-ash3-validation-fixes`

---

## 🎯 Priority 3: Quick Wins (If Time Available)

### TASK-006: AshOban Extension Loading Fixes
**HC Mission:** HC-04 preparation  
**Assignee:** Available Developer  
**Estimated:** 4 hours  
**Priority:** P1 - ENABLES HC-04

**Current State:**
- ❌ Multiple "AshOban extension loading issue" TODOs:
  - `message.ex:564`
  - `federation_socket.ex:865`
  - `grid_resource.ex:617`
  - `role.ex:808, 817` - trigger syntax

**What Needs Doing:**
1. Investigate AshOban loading issue
2. Fix extension configuration
3. Update trigger syntax for AshOban 3.x
4. Test Oban job triggers

**Files to Modify:**
- Resources with AshOban extensions
- `mix.exs` (if dependency version issue)

**Branch:** `hc-ashoban-loading-fixes`

---

## 📊 Sprint Success Metrics

**Must Achieve by Friday Oct 15:**
- ✅ HC-01 EventBus telemetry complete
- ✅ TODO audit classification complete
- ✅ At least 1 domain's Ash 3.x fixes complete (ThunderLink preferred)
- ✅ CI gate for event taxonomy active
- ✅ First PR reviewed by Copilot agent
- ✅ Zero compiler warnings on main branch

**Stretch Goals:**
- Dashboard metrics implementation complete
- All validation syntax fixes complete
- AshOban extension loading resolved

---

## 🚦 Daily Standup Format

Post in `#thunderline-rebuild` channel:

```
**[Your Name] - [Date]**
✅ Yesterday: [what you completed]
🎯 Today: [what you're working on]
🚧 Blockers: [anything blocking you, or "None"]
📊 Progress: TASK-XXX [X]% complete
```

---

## 🆘 Getting Help

**Stuck on Ash 3.x syntax?**
- Read `.azure/DEVELOPER_QUICK_REFERENCE.md` section "Ash 3.x Patterns"
- Check Ash docs: https://hexdocs.pm/ash/

**EventBus questions?**
- Review `.azure/DEVELOPER_QUICK_REFERENCE.md` section "EventBus API"
- Check existing usage in codebase: `grep -r "EventBus.publish_event" lib/`

**PR blocked?**
- Review `.azure/PR_REVIEW_CHECKLIST.md`
- Check CI output for specific failures
- Tag your domain steward

**General questions?**
- Platform Lead
- Review `.azure/INDEX.md` for document navigation

---

## 📝 PR Requirements (Reminder)

Every PR must include:
1. ✅ HC task ID in title (e.g., "[HC-01] Add EventBus telemetry spans")
2. ✅ Domain tag (e.g., "[ThunderFlow]")
3. ✅ Complete PR checklist from `PR_REVIEW_CHECKLIST.md`
4. ✅ Test coverage ≥ 85%
5. ✅ All CI checks passing
6. ✅ Zero new compiler warnings

**Copilot will auto-review within 5 minutes!**

---

## 🎯 Week 2 Preview (Oct 16-22)

If we complete Week 1 goals, Week 2 focuses on:
- HC-04: Cerebros Lifecycle (MLflow migrations, state machines)
- HC-05: Email MVP (Contact/OutboundEmail resources)
- HC-06: Link Presence Policies
- Continued Ash 3.x remediation across other domains

**Let's crush Week 1! 🚀**
