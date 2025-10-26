# Phase 2 Quick Reference — Code Recon & Saga Inventory

**Mission**: OPERATION SAGA CONCORDIA  
**Phase**: 2 of 4  
**Deadline**: Wed Oct 29, 2025 EOD  
**Agent**: CAPTAIN IRON TIDE  

---

## PRs Awaiting Creation

### PR-A: IRON_TIDE-001 (Phase 1 Documentation)
- **Branch**: `concordia/iron_tide_mvp → main`
- **URL**: https://github.com/Thunderblok/Thunderline/pull/new/concordia/iron_tide_mvp
- **Reviewers**: Crown steward + Bolt steward
- **Merge**: Squash with signed tag `IRON_TIDE-001`

### PR-B: IRON_TIDE-002 (Dependency Fix)
- **Branch**: `deps/ash-version-bump-iron-tide-002 → main`
- **URL**: https://github.com/Thunderblok/Thunderline/pull/new/deps/ash-version-bump-iron-tide-002
- **Reviewers**: Platform lead
- **Merge**: Squash with signed tag `IRON_TIDE-002`
- **Impact**: Unblocks test suite (Ash ~> 3.7)

---

## Task 2.1: Enumerate Saga Entrypoints (3-4 hours)

### Search Commands
```bash
# Find all saga files
fd -e ex thunderbolt | grep -i saga

# Identify run/2 steps
rg -n "def run\(" lib/thunderline/thunderbolt

# Identify rollback/2 compensations
rg -n "rollback" lib/thunderline/thunderbolt

# Count LOC per saga
wc -l lib/thunderline/thunderbolt/**/*.ex
```

### Output: `docs/concordia/saga_inventory.md`

**Table Format**:
```markdown
| Module | File Path | run/2 Steps | rollback/2 Compensations | Gaps | LOC |
|--------|-----------|-------------|--------------------------|------|-----|
| Example | lib/.../example.ex | 3 | 2 | Step 3 no compensation | 87 |
```

**For Each Saga**:
- Document module name and file path
- Count `run/2` steps
- Count `rollback/2` compensations
- **Flag gaps**: Missing rollback, incomplete undo
- Count lines of code

---

## Task 2.2: Event Conformance Audit (3-4 hours)

### Search Commands
```bash
# Find all event emissions in ThunderBolt
rg -n 'PubSub|publish|telemetry|emit|EventBus' lib/thunderline/thunderbolt
```

### Output: `docs/concordia/event_matrix.md`

**Table Format**:
```markdown
| Event Topic | Payload Schema | Taxonomy Category | Conformance Status | Notes |
|-------------|----------------|-------------------|--------------------|-------|
| saga.provision.started | {saga_id, correlation_id} | :system | ✅ COMPLIANT | Matches v0.2 |
| thunderbolt.lane.created | {lane_id, config} | :domain | ⚠️ DRIFT | Missing correlation_id |
```

**For Each Event**:
- Extract event name and payload schema
- Cross-reference with `documentation/EVENT_TAXONOMY.md` v0.2
- Categorize: :system, :domain, :integration, :user, :error
- Check naming: `<domain>.<component>.<action>`
- **Flag drifts**: Add `TODO[CONCORDIA]` comment in code

**Taxonomy Categories**:
- `:system` — `flow.reactor.*`, `saga.*`
- `:domain` — `thunderline:block.*`, `thunderbolt.*`
- `:integration` — Cross-domain events
- `:user` — UI/UX events
- `:error` — Error/failure events

---

## Task 2.3: Correlation ID Audit (2 hours)

### Search Commands
```bash
# Search correlation_id propagation
rg -n "correlation_id" lib/thunderline/thunderbolt/sagas/
```

### Output: `docs/concordia/correlation_audit.md`

**Format**:
```markdown
## Correlation ID Propagation Audit

### ✅ Compliant Sagas
- ProvisionReactor: correlation_id in all steps, all events

### ⚠️ Gaps Identified
- LaneCreationSaga (lib/.../lane_creation.ex:45):
  - Gap: Step 2 → Step 3 missing correlation_id
  - Fix: Add to handle_step_3/2 signature
  - Test: test/thunderbolt/lane_creation_test.exs:78

### 📊 Summary
- Total sagas: 12
- Compliant: 8
- Gaps: 4
- Patches: 4
- Tests: 4
```

**Verify Propagation Across**:
1. **Step to step**: Passed as function argument
2. **External calls**: In API request headers/metadata
3. **Event emissions**: In event metadata/payload

**Actions**:
- Document gaps where correlation_id is NOT propagated
- Patch missing propagation (function signatures, API calls, event metadata)
- Add test assertions (verify correlation_id in events/spans)

---

## Task 2.4: Commit Phase 2 Artifacts

```bash
# Verify all artifacts exist
ls -lh docs/concordia/

# Expected files:
# - saga_inventory.md
# - event_matrix.md
# - correlation_audit.md
# - PHASE_2_QUICK_REF.md (this file)

# Stage and commit
git add docs/concordia/
git commit -m "IRON_TIDE-003: Phase 2 Code Recon & Saga Inventory

- saga_inventory.md: Enumerated X sagas, Y steps, Z compensation gaps
- event_matrix.md: Mapped X events to EVENT_TAXONOMY v0.2, Y drifts
- correlation_audit.md: Audited correlation_id propagation, Z gaps patched

Phase 2 Code Recon complete. For the Line, the Bolt, and the Crown."

# Push for PR creation
git push -u origin concordia/iron_tide_mvp

# Create PR-C with tag IRON_TIDE-003
```

---

## Quality Gates (Every Commit)

```bash
mix compile --warnings-as-errors  # Zero warnings target
mix test                          # All tests green
mix thunderline.events.lint       # Event taxonomy compliance
mix ash.doctor                    # Ash resource correctness (investigate after merge)
mix credo --strict                # Code quality standards
```

**Known Issues**:
- ⚠️ `mix ash.doctor`: Task not found after Ash 3.7 upgrade (non-blocking)
- ⚠️ 4 pre-existing compilation warnings (documented in IRON_TIDE-002 PR)
- ⚠️ 17 pre-existing credo warnings (documented, 5096 mods/funs analyzed)

---

## Acceptance Criteria

- ✅ Complete saga inventory with compensation gap analysis
- ✅ Event taxonomy conformance map (all saga events classified)
- ✅ Correlation ID audit with gaps patched and tested
- ✅ Quality gates pass: compile, events.lint, credo

---

## Risks & Guardrails

### Risk 1: ThunderBolt is PRODUCTION
- **Mitigation**: Phase 2 is documentation-only, NO code changes to active sagas
- **Action**: Inventory and audit only, patch only correlation_id gaps with tests

### Risk 2: Docs vs. Code Drift
- **Mitigation**: Every event change MUST update EVENT_TAXONOMY.md in same PR
- **Action**: Include taxonomy updates in IRON_TIDE-003

### Risk 3: Compensation Gaps
- **Mitigation**: Add negative tests proving compensations fire
- **Action**: Phase 2 Task 2.3 includes test additions

### Risk 4: Event Taxonomy Violations
- **Mitigation**: Flag drifts with TODO[CONCORDIA], escalate critical to High Command
- **Action**: Phase 2 Task 2.2 flags all violations

---

## Standing Principle

*"Cut nothing that runs clean. Flag, isolate, and prove before you remove. We evolve the Line by tightening interfaces, not by heroics."*

---

## Phase 3 Preview (Fri Oct 31 EOD)

**No code yet**, just alignment:

**Module**: `Thunderline.Thunderblock.ProvisionReactor`

**3-Step Saga**:
1. ExecutionContainer.create → compensate: destroy
2. SupervisionTree.start_block/1 → compensate: stop
3. emit_online_event → compensate: emit offline

**Event Wiring**:
- Inbound: `orchestrate.intent.provision_block`
- Progress: `saga.provision_reactor.*`
- Domain: `thunderline:block.online`

**Tests**: Success path, failure at step 2, event conformance, correlation_id, feature flag

---

## For the Line, the Bolt, and the Crown ⚡

**CAPTAIN IRON TIDE** standing by for PR creation confirmation and Phase 2 execution approval. o7
