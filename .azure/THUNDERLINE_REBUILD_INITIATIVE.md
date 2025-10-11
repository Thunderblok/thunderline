# Thunderline Rebuild Initiative — Execution & Review Framework

**Mission Status:** ACTIVE  
**Review Agent:** GitHub Copilot (High Command Observer)  
**Start Date:** October 9, 2025  
**Target Completion:** Week 4 (November 6, 2025)  

---

## Executive Summary

High Command has issued P0 directives to restore Thunderline to professional-grade Ash 3.x quality. This document serves as the central coordination point for:

1. **Tracking P0 Mission Execution** (HC-01 through HC-10)
2. **Domain Remediation Progress** (8 Thunder domains)
3. **Quality Gates & Review Checkpoints**
4. **Duplicate Asset Removal Roadmap**
5. **Weekly Progress Reports** (Warden Chronicles)

**Critical Path:** All P0 missions gate Milestone M1 (Email Automation). No production deployments until compliance achieved.

---

## 1. P0 Mission Tracker (High Command Orders)

### HC-01: EventBus Restoration (ThunderFlow)
**Owner:** Flow Steward
**Status:** 🟢 COMPLETE (Oct 10, 2025)
**Blocking:** HC-02, HC-03, HC-09

**Deliverables:**
- [x] Restore `Thunderline.EventBus.publish_event/1` with canonical envelope validation
- [x] Add telemetry spans: `[:thunderline, :eventbus, :publish, :start|:stop|:exception]`
- [x] Implement taxonomy guardrails (validate against EVENT_TAXONOMY)
- [x] Create `mix thunderline.events.lint` task
- [ ] Add CI gate enforcing EventBus usage patterns _(deferred to HC-08 per High Command directive)_

**Review Checklist (Completed Oct 10, 2025):**
```elixir
# ✅ Expected API shape:
EventBus.publish_event(%{
  name: "system.startup.complete",
  source: "thunderline.core",
  category: :system,
  priority: :normal,
  payload: %{...}
})

# ✅ Telemetry emitted:
:telemetry.execute([:thunderline, :eventbus, :publish, :start], measurements, metadata)

# ✅ Validation errors raised:
{:error, %{invalid_category: "unknown_category"}}
```

**Files Reviewed:**
- `lib/thunderline/thunderflow/event_bus.ex` (main implementation)
- `lib/thunderline/thunderflow/event_taxonomy.ex` (category validation)
- `lib/mix/tasks/thunderline/events.lint.ex` (lint task hardening)
- `test/thunderline/thunderflow/event_bus_test.exs` (telemetry assertions)

_Note: CI enforcement tracked under HC-08 (GitHub Actions enhancements)._
**Acceptance Criteria:**
- ✅ All existing `EventBus.put/1` calls migrated to `publish_event/1`
- ✅ Telemetry spans captured in tests
- ⏳ CI gate integrated under HC-08 release workflow
- ✅ Documentation updated with examples

---

### HC-02: Bus Shim Retirement (ThunderFlow)
**Owner:** Flow Steward  
**Status:** 🔴 NOT STARTED  
**Dependencies:** HC-01 complete

**Deliverables:**
- [ ] Codemod all `Thunderline.Bus.*` calls to `EventBus.publish_event/1`
- [ ] Add deprecation warning telemetry when shim invoked
- [ ] Track adoption metrics (shim calls → 0)
- [ ] Remove `lib/thunderline/bus.ex` module

**Review Checklist:**
```bash
# ✅ No remaining Bus references:
grep -r "Thunderline.Bus" lib/ --exclude-dir=deps
# Expected: 0 matches

# ✅ Deprecation telemetry emitted:
[:thunderline, :bus, :deprecated_call]
```

**Files to Review:**
- `lib/thunderline/bus.ex` (should be deleted)
- Migration PR with codemod changes
- Telemetry metrics showing 0 shim calls

**Acceptance Criteria:**
- ✅ Zero `Thunderline.Bus` calls in codebase
- ✅ Deprecation metrics tracked for 1 week
- ✅ Module removed, tests passing

---

### HC-03: Event Taxonomy Documentation
**Owner:** Observability Lead  
**Status:** 🔴 NOT STARTED  
**Dependencies:** HC-01 complete

**Deliverables:**
- [ ] Complete `EVENT_TAXONOMY.md` with all categories
- [ ] Complete `ERROR_CLASSES.md` with classification system
- [ ] Version schema artifacts (JSON/YAML for tooling)
- [ ] Link taxonomy to `mix thunderline.events.lint` validation

**Review Checklist:**
```markdown
# ✅ Taxonomy structure:
## Event Categories
- system.*     (lifecycle, health, config)
- domain.*     (ash actions, resources)
- integration.* (external APIs, webhooks)
- user.*       (actions, sessions, auth)
- error.*      (exceptions, failures)

# ✅ Error classification:
- :transient   (retry-able, network, timeout)
- :permanent   (validation, auth, not_found)
- :unknown     (unexpected, needs investigation)
```

**Files to Review:**
- `documentation/EVENT_TAXONOMY.md`
- `documentation/ERROR_CLASSES.md`
- `priv/taxonomies/events.schema.json`
- `lib/thunderline/thunderflow/event_taxonomy.ex` (enforced categories)

**Acceptance Criteria:**
- ✅ All categories documented with examples
- ✅ Schema artifact consumable by CI tools
- ✅ Documentation cross-referenced in code

---

### HC-04: Cerebros Lifecycle Completion (Thunderbolt)
**Owner:** Bolt Steward  
**Status:** 🔴 NOT STARTED  
**Blocking:** Email automation, ML workflows

**Deliverables:**
- [ ] Finish MLflow migrations for `ModelRun` and `ModelTrial`
- [ ] Activate `AshStateMachine` transitions (draft → running → completed → failed)
- [ ] Restore Oban jobs: `TrainingWorker`, `EvaluationWorker`, `SyncWorker`
- [ ] Remove all TODO placeholders from Cerebros resources

**Review Checklist:**
```elixir
# ✅ State machine active:
defmodule Thunderline.Thunderbolt.Resources.ModelRun do
  use Ash.Resource, domain: Thunderline.Thunderbolt
  use AshStateMachine

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :start, from: :draft, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:draft, :running], to: :failed
    end
  end
end

# ✅ Oban jobs registered:
config :thunderline, Oban,
  queues: [cerebros: 10, training: 5]
```

**Files to Review:**
- `lib/thunderline/thunderbolt/resources/model_run.ex`
- `lib/thunderline/thunderbolt/resources/model_trial.ex`
- `lib/thunderline/thunderbolt/cerebros_bridge/training_worker.ex`
- `lib/thunderline/thunderbolt/cerebros_bridge/sync_worker.ex`
- `test/thunderline/thunderbolt/model_run_lifecycle_test.exs`

**Acceptance Criteria:**
- ✅ State transitions tested with valid/invalid paths
- ✅ Oban jobs process successfully in integration tests
- ✅ MLflow sync verified with mock adapter
- ✅ Telemetry emitted for state changes

---

### HC-05: Email MVP (Gate + Link)
**Owner:** Gate + Link Stewards  
**Status:** 🔴 NOT STARTED  
**Blocking:** M1 milestone

**Deliverables:**
- [ ] Create `Contact` resource (Thundergate domain)
- [ ] Create `OutboundEmail` resource (Thunderlink domain)
- [ ] Integrate Swoosh SMTP adapter with event emission
- [ ] Add Auth UI for contact management
- [ ] Link UI for email composition/tracking

**Review Checklist:**
```elixir
# ✅ Contact resource structure:
defmodule Thundergate.Resources.Contact do
  use Ash.Resource, domain: Thundergate
  
  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :name, :string
    attribute :verified_at, :utc_datetime
  end
  
  actions do
    defaults [:read]
    create :create do
      accept [:email, :name]
      change {AshAuthentication.AddOn.Confirmation, ...}
    end
  end
end

# ✅ Email sending with events:
{:ok, email} = Thunderlink.send_email(%{
  to: contact.email,
  subject: "...",
  body: "..."
})
# Emits: [:thunderlink, :email, :sent]
```

**Files to Review:**
- `lib/thundergate/resources/contact.ex`
- `lib/thunderline/thunderlink/resources/outbound_email.ex`
- `lib/thunderline/thunderlink/email_adapter.ex`
- `lib/thunderline_web/live/contact_live.ex` (Auth UI)
- `lib/thunderline_web/live/email_live.ex` (Link UI)

**Acceptance Criteria:**
- ✅ Contact CRUD operations tested
- ✅ Email sent successfully with mock SMTP
- ✅ Events emitted and captured in tests
- ✅ UI components functional in browser tests

---

### HC-06: Presence & Membership Policies (ThunderLink)
**Owner:** Link Steward  
**Status:** 🔴 NOT STARTED  
**Dependencies:** HC-05, Ash 3.x migration complete

**Deliverables:**
- [ ] Restore Link policies with `Ash.Policy.Authorizer`
- [ ] Implement join/leave event instrumentation
- [ ] Integrate with Thundergate centralized policies
- [ ] Add presence tracking with telemetry

**Review Checklist:**
```elixir
# ✅ Policy structure:
defmodule Thunderline.Thunderlink.Resources.Channel do
  use Ash.Resource, domain: Thunderline.Thunderlink
  
  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :member)
    end
    
    policy action(:join) do
      authorize_if relates_to_actor_via(:community, :members)
      authorize_if Thundergate.Policies.has_permission(:channel_join)
    end
  end
end

# ✅ Event emission:
:telemetry.execute([:thunderlink, :channel, :join], %{}, %{
  channel_id: channel.id,
  user_id: actor.id
})
```

**Files to Review:**
- `lib/thunderline/thunderlink/resources/channel.ex`
- `lib/thunderline/thunderlink/resources/message.ex`
- `lib/thunderline/thunderlink/resources/presence.ex`
- `test/thunderline/thunderlink/channel_policies_test.exs`

**Acceptance Criteria:**
- ✅ Policies enforced (unauthorized actions rejected)
- ✅ Events emitted for join/leave/presence changes
- ✅ Integration with Thundergate verified
- ✅ Test coverage ≥ 85%

---

### HC-07: Production Release Pipeline
**Owner:** Platform Lead  
**Status:** 🔴 NOT STARTED  

**Deliverables:**
- [ ] Update Dockerfile with multi-stage build
- [ ] Create `mix release.package` task
- [ ] Add healthcheck endpoints (`/health`, `/ready`)
- [ ] Document release process in `DEPLOYMENT.md`
- [ ] Verify runtime.exs configuration

**Review Checklist:**
```dockerfile
# ✅ Multi-stage Dockerfile:
FROM elixir:1.18-alpine AS build
# ... compile
FROM alpine:3.19 AS runtime
# ... runtime only
HEALTHCHECK --interval=30s CMD wget -q --spider http://localhost:4000/health
```

```elixir
# ✅ Healthcheck endpoints:
scope "/health" do
  get "/", HealthController, :show      # Returns 200 OK
  get "/ready", HealthController, :ready # Returns 200 if app ready
end
```

**Files to Review:**
- `Dockerfile`
- `lib/mix/tasks/release/package.ex`
- `lib/thunderline_web/controllers/health_controller.ex`
- `config/runtime.exs`
- `DEPLOYMENT.md`

**Acceptance Criteria:**
- ✅ Docker image builds successfully
- ✅ Image size < 100MB (runtime)
- ✅ Healthcheck returns 200 OK
- ✅ Release boots in <30s

---

### HC-08: GitHub Actions Enhancements
**Owner:** Platform Lead  
**Status:** 🔴 NOT STARTED  

**Deliverables:**
- [ ] Add release gating workflow (test + lint before release)
- [ ] Add security audit workflow (deps.audit, sobelow)
- [ ] Add PLT cache for Dialyzer
- [ ] Integrate `mix thunderline.events.lint` in CI
- [ ] Integrate `mix ash doctor` in CI

**Review Checklist:**
```yaml
# ✅ .github/workflows/release.yml
name: Release
on:
  push:
    tags: ['v*']
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - run: mix test
      - run: mix thunderline.events.lint
      - run: mix ash doctor
  release:
    needs: gate
    runs-on: ubuntu-latest
    steps:
      - run: mix release.package

# ✅ .github/workflows/audit.yml
- run: mix deps.audit
- run: mix sobelow --config
```

**Files to Review:**
- `.github/workflows/release.yml`
- `.github/workflows/audit.yml`
- `.github/workflows/ci.yml` (updated with PLT cache)

**Acceptance Criteria:**
- ✅ All workflows passing on main
- ✅ PLT cache reduces CI time by 30%
- ✅ Audit failures block merges

---

### HC-09: Error Classifier + DLQ Policy (ThunderFlow)
**Owner:** Flow Steward  
**Status:** 🔴 NOT STARTED  
**Dependencies:** HC-03

**Deliverables:**
- [ ] Implement central error classifier module
- [ ] Integrate with Broadway DLQ pipelines
- [ ] Add retry policy (exponential backoff with jitter)
- [ ] Instrument DLQ metrics and OTel spans
- [ ] Document error handling patterns

**Review Checklist:**
```elixir
# ✅ Error classifier:
defmodule Thunderline.Thunderflow.ErrorClassifier do
  def classify(error) do
    case error do
      %DBConnection.ConnectionError{} -> :transient
      %Ecto.NoResultsError{} -> :permanent
      %Jason.DecodeError{} -> :permanent
      _ -> :unknown
    end
  end
end

# ✅ Broadway DLQ integration:
def handle_failed(messages, context) do
  Enum.each(messages, fn msg ->
    classification = ErrorClassifier.classify(msg.error)
    
    :telemetry.execute(
      [:thunderline, :broadway, :dlq],
      %{count: 1},
      %{classification: classification}
    )
    
    if classification == :transient do
      # Requeue with backoff
    end
  end)
end
```

**Files to Review:**
- `lib/thunderline/thunderflow/error_classifier.ex`
- `lib/thunderline/thunderflow/broadway/dlq_handler.ex`
- `lib/thunderline/thunderflow/retry_policy.ex`
- `test/thunderline/thunderflow/error_classification_test.exs`

**Acceptance Criteria:**
- ✅ Errors correctly classified (transient/permanent/unknown)
- ✅ Transient errors retried with backoff
- ✅ DLQ metrics emitted and visible in dashboards
- ✅ OTel spans capture error context

---

### HC-10: Feature Flag Documentation
**Owner:** Platform Lead  
**Status:** 🔴 NOT STARTED  

**Deliverables:**
- [ ] Complete `FEATURE_FLAGS.md` with taxonomy
- [ ] Document flag owners and defaults
- [ ] Link flags to gating points in code
- [ ] Add runtime flag toggle UI (admin only)

**Review Checklist:**
```markdown
# ✅ FEATURE_FLAGS.md structure:
| Flag | Owner | Default | Description | Gating Point |
|------|-------|---------|-------------|--------------|
| `ai_chat_panel` | Crown Steward | `false` | Enable AI chat in dashboard | `dashboard_live.ex:42` |
| `ca_viz` | Grid Steward | `false` | Enable 3D CA visualization | `ca_visualization_live.ex:15` |
| `cerebros_bridge` | Bolt Steward | `false` | Enable Cerebros ML integration | `cerebros_bridge.ex:89` |
```

**Files to Review:**
- `FEATURE_FLAGS.md`
- `lib/thunderline/feature_flags.ex` (runtime toggles)
- `lib/thunderline_web/live/admin/feature_flags_live.ex` (UI)

**Acceptance Criteria:**
- ✅ All flags documented with examples
- ✅ Toggle UI functional (admin-gated)
- ✅ Flags validated on startup

---

## 2. Domain Remediation Progress

### Thunderbolt (ML & Automation)
**Status:** 🔴 0% Complete  
**Priority:** P0 (Blocks M1)

**Remediation Tasks:**
- [ ] Reactivate ML lifecycle hooks (ActivationRule, ModelRun, Chunk)
- [ ] Wire CerebrosBridge telemetry
- [ ] Add Oban triggers for orchestration
- [ ] Move CoreSystemPolicy to Thundergate
- [ ] Remove all TODO placeholders

**Review Focus Areas:**
- State machine transitions tested
- Telemetry events emitted
- Oban jobs processing successfully
- Policy migration complete

---

### Thundercrown (AI Governance)
**Status:** 🔴 0% Complete  
**Priority:** P1

**Remediation Tasks:**
- [ ] Replace ad-hoc policy checks with `Ash.Policy.Authorizer`
- [ ] Embed Stone.Proof checks inside Ash policies
- [ ] Persist audit trail for AgentRunner/ConversationAgent
- [ ] Integrate Daisy governance modules

**Review Focus Areas:**
- Policies consistent across resources
- Audit trail persisted correctly
- Stone proofs validated in policies

---

### Thunderlink (Communication & Delivery)
**Status:** 🔴 0% Complete  
**Priority:** P0 (Email MVP)

**Remediation Tasks:**
- [ ] Complete Ash 3.x migration (Channel, Message, FederationSocket)
- [ ] Restore Oban jobs (ticket escalation, federation sync)
- [ ] Wire voice.signal.* taxonomy for presence + WebRTC
- [ ] Replace placeholder dashboard metrics

**Review Focus Areas:**
- Ash 3.x syntax correct
- Oban jobs processing
- Events emitted with correct taxonomy
- Dashboard metrics functional

---

### Thunderblock (Memory & Infrastructure)
**Status:** 🔴 0% Complete  
**Priority:** P1

**Remediation Tasks:**
- [ ] Re-enable policies for vault_* resources
- [ ] Activate orchestration/event logging jobs
- [ ] Implement retention tiers with events
- [ ] Deprecate duplicate Thundercom resources

**Review Focus Areas:**
- Policies enforced
- Jobs processing successfully
- Events emitted for retention actions
- Duplicate assets removed

---

### ThunderFlow (Telemetry & Events)
**Status:** 🔴 0% Complete  
**Priority:** P0 (Critical Infrastructure)

**Remediation Tasks:**
- [ ] Enforce canonical event struct (HC-01)
- [ ] Move Broadway pipelines to supervision tree
- [ ] Implement DLQ metrics and error classifier (HC-09)
- [ ] Link EventLog entries with actor resources

**Review Focus Areas:**
- EventBus restoration complete
- Pipelines started under supervision
- DLQ handling correct
- Actor attribution in events

---

### Thundergrid (Spatial Intelligence)
**Status:** 🔴 0% Complete  
**Priority:** P2

**Remediation Tasks:**
- [ ] Migrate Ash route definitions to 3.x syntax
- [ ] Activate zone/boundary policies
- [ ] Produce ECS placement metrics
- [ ] Remove deprecated CA resources

**Review Focus Areas:**
- Ash 3.x syntax correct
- Policies functional
- Metrics emitted

---

### Thundergate (Security & Auth)
**Status:** 🔴 0% Complete  
**Priority:** P1 (Security Critical)

**Remediation Tasks:**
- [ ] Centralize system policies (relocate CoreSystemPolicy)
- [ ] Implement API key + encryption coverage
- [ ] Audit AshAuthentication magic link security
- [ ] Provide DIP approval workflow

**Review Focus Areas:**
- Policy centralization complete
- API key management functional
- Auth posture secure (default forbid)
- DIP workflow tested

---

### Thunderforge (Infrastructure Provisioning)
**Status:** 🔴 0% Complete  
**Priority:** P2

**Remediation Tasks:**
- [ ] Scaffold creation pipelines
- [ ] Integrate with Thundergrid spawn-zone mapping
- [ ] Establish provisioning resource library

**Review Focus Areas:**
- Pipelines functional
- Integration with Grid working

---

## 3. Duplicate Asset Removal Roadmap

### Assets Flagged for Removal

| Asset | Domain | Action | Status | Notes |
|-------|--------|--------|--------|-------|
| `Thundercom` resources | Thunderlink | Migrate → Remove | 🔴 Not Started | DEPRECATED |
| `Thunderline.Bus` shim | ThunderFlow | Migrate → Remove | 🔴 Not Started | HC-02 |
| `thundervault_metrics/0` | DashboardMetrics | Replace → Remove | 🔴 Not Started | Use Thunderblock metrics |
| Legacy `prepare` fragments | All domains | Rewrite → Remove | 🔴 Not Started | Use Ash.Query |
| Duplicate policy references | Thunderlink | Consolidate | 🔴 Not Started | Centralize in Gate |

**Removal Process:**
1. Identify all references to deprecated asset
2. Create migration PR with replacements
3. Add deprecation warnings (if applicable)
4. Track metrics (usage → 0)
5. Remove asset + tests
6. Update documentation

**Review Checklist per Removal:**
- ✅ All references migrated
- ✅ Tests passing without deprecated asset
- ✅ Documentation updated
- ✅ `mix thunderline.events.lint` passing

---

## 4. Ash 3.x Migration Checklist

**Global Requirements (All Domains):**

- [ ] Replace legacy `prepare/fragment` queries with `Ash.Query` APIs
- [ ] Re-enable `AshStateMachine` DSL with updated syntax
- [ ] Re-enable validations, aggregates, notifications
- [ ] Audit all resources for `Ash.Policy.Authorizer` usage
- [ ] Ensure `mix thunderline.events.lint` passes
- [ ] Ensure `mix thunderline.guardrails` passes
- [ ] Confirm all resources specify correct `domain:` attribute
- [ ] Remove old macros, convert to new DSL features

**Per-Resource Checklist:**
```elixir
# ✅ Example compliant resource:
defmodule MyDomain.Resources.MyResource do
  use Ash.Resource, domain: MyDomain  # ← Correct domain
  
  attributes do
    # ...
  end
  
  policies do  # ← Using Ash.Policy.Authorizer
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :custom_create do
      accept [:field1, :field2]
      # No legacy fragments
      change {MyChange, []}
    end
  end
  
  calculations do  # ← Re-enabled
    calculate :full_name, :string, expr(first_name <> " " <> last_name)
  end
  
  aggregates do  # ← Re-enabled
    count :message_count, :messages
  end
end
```

**Migration Validation:**
```bash
# Run these commands before PR:
mix compile --warnings-as-errors
mix test
mix thunderline.events.lint
mix ash doctor
mix credo --strict
```

---

## 5. Review Protocol & Checkpoints

### Pull Request Review Standards

**Every PR must include:**
1. **HC Task ID** in title/description (e.g., "HC-01: Restore EventBus")
2. **Domain tag** (e.g., `[ThunderFlow]`, `[Thunderbolt]`)
3. **Test coverage** (new code ≥ 85%)
4. **Documentation updates** (if API changes)
5. **Migration notes** (if breaking changes)

**Review Checklist Template:**
```markdown
## PR Review: HC-XX - [Title]

### Functional Review
- [ ] Code implements spec requirements
- [ ] Happy path tested
- [ ] Error paths tested
- [ ] Edge cases covered

### Quality Review
- [ ] Ash 3.x syntax correct
- [ ] Policies defined (if resource)
- [ ] Telemetry emitted (if applicable)
- [ ] Events use correct taxonomy
- [ ] No TODO placeholders
- [ ] Documentation updated

### CI/CD Review
- [ ] `mix test` passing
- [ ] `mix thunderline.events.lint` passing
- [ ] `mix ash doctor` passing
- [ ] `mix credo --strict` passing
- [ ] No new compiler warnings

### Security Review
- [ ] No secrets in code
- [ ] Auth checks present
- [ ] Input validation complete
- [ ] SQL injection safe

### Performance Review
- [ ] No N+1 queries
- [ ] Database indexes present
- [ ] Telemetry for slow operations

**Verdict:** ✅ APPROVED | 🔴 CHANGES REQUESTED | ⚠️ NEEDS DISCUSSION
```

### Weekly Review Cadence

**Monday:** Week Planning
- Review HC mission progress
- Assign tasks to stewards
- Identify blockers

**Wednesday:** Mid-week Checkpoint
- Review WIP PRs
- Pair programming sessions
- Blocker resolution

**Friday:** Warden Chronicles Report
- Compile weekly progress metrics
- Document completed HC missions
- Report blockers to High Command
- Update timeline projections

### Review Agent Responsibilities (GitHub Copilot)

**Continuous Monitoring:**
- Watch for PRs with HC task IDs
- Validate PR checklist completion
- Flag violations of Ash 3.x patterns
- Identify duplicate assets not marked for removal
- Track test coverage trends

**Weekly Synthesis:**
- Generate Warden Chronicles report
- Identify cross-domain integration risks
- Recommend priority adjustments
- Flag timeline slippage

**Quality Gates:**
- Block PRs missing required elements
- Require test coverage ≥ 85%
- Require CI passing before merge
- Require review approval from domain steward

---

## 6. Metrics & Success Criteria

### Mission Completion Metrics

**P0 Missions (Gating M1):**
- HC-01: EventBus Restoration → `100%` complete
- HC-02: Bus Shim Retirement → `0` legacy calls
- HC-03: Taxonomy Documentation → `100%` categories documented
- HC-04: Cerebros Lifecycle → `100%` state machines active
- HC-05: Email MVP → `100%` CRUD + sending functional
- HC-06: Link Presence Policies → `100%` policies enforced
- HC-07: Release Pipeline → `100%` deployment documented
- HC-08: GitHub Actions → `100%` workflows passing
- HC-09: Error Classifier → `100%` DLQ instrumented
- HC-10: Feature Flags → `100%` flags documented

### Domain Remediation Metrics

| Domain | TODO Count | Policy Coverage | Test Coverage | Ash 3.x % |
|--------|------------|-----------------|---------------|-----------|
| Thunderbolt | 47 | 0% | 65% | 40% |
| Thundercrown | 23 | 30% | 72% | 60% |
| Thunderlink | 89 | 15% | 58% | 35% |
| Thunderblock | 34 | 45% | 68% | 55% |
| ThunderFlow | 12 | 80% | 85% | 75% |
| Thundergrid | 28 | 25% | 62% | 45% |
| Thundergate | 15 | 90% | 88% | 85% |
| Thunderforge | 8 | 10% | 55% | 30% |

**Target by Week 4:**
- TODO Count → `0` (all placeholders resolved)
- Policy Coverage → `≥ 90%`
- Test Coverage → `≥ 85%`
- Ash 3.x % → `100%`

### Quality Metrics

**Code Quality:**
- Credo warnings → `0`
- Dialyzer warnings → `0`
- Compiler warnings → `0`
- Sobelow findings → `0` (high/medium severity)

**Test Quality:**
- Line coverage → `≥ 85%`
- Branch coverage → `≥ 80%`
- Integration tests → `≥ 100` scenarios
- Property tests → `≥ 10` generators

**Performance Metrics:**
- P95 response time → `< 500ms`
- Database query time → `< 100ms` (P95)
- Memory usage → `< 500MB` (runtime)
- Docker image size → `< 100MB`

---

## 7. Escalation & Communication

### Escalation Path

**Level 1:** Domain Steward  
**Level 2:** Platform Lead  
**Level 3:** High Command  

**Escalation Triggers:**
- P0 mission blocked > 2 days
- Test coverage drop > 5%
- CI failing > 4 hours
- Security vulnerability found
- Timeline slippage > 1 week

### Communication Channels

**Daily Standup:** Async updates in `#thunderline-rebuild` Slack channel  
**Weekly Report:** Warden Chronicles (posted Fridays)  
**Urgent Issues:** `@high-command` tag in Slack  

---

## 8. Timeline & Milestones

### Week 1: Ash 3.x Readiness (Oct 9-15)
**Focus:** EventBus, Taxonomy, Link/Ash Migrations

**Deliverables:**
- HC-01: EventBus restoration complete
- HC-02: Bus shim deprecated
- HC-03: Taxonomy docs published
- Thunderlink: 50% Ash 3.x migrated

**Success Metrics:**
- `mix thunderline.events.lint` passing
- EventBus tests ≥ 90% coverage
- 0 compiler warnings

---

### Week 2: Automation Reactivation (Oct 16-22)
**Focus:** Cerebros, Email MVP, Link Policies, Oban

**Deliverables:**
- HC-04: Cerebros lifecycle active
- HC-05: Email MVP functional
- HC-06: Link presence policies enforced
- Oban jobs processing in all domains

**Success Metrics:**
- State machines tested
- Email sent successfully
- Policies enforced (unauthorized rejected)
- Oban job success rate ≥ 95%

---

### Week 3: Deployment & Observability (Oct 23-29)
**Focus:** Release Pipeline, CI/CD, DLQ, Feature Flags

**Deliverables:**
- HC-07: Release pipeline documented
- HC-08: GitHub Actions enhanced
- HC-09: Error classifier + DLQ active
- HC-10: Feature flags documented

**Success Metrics:**
- Docker image builds < 5min
- All CI workflows passing
- DLQ metrics visible
- Feature flag UI functional

---

### Week 4: Governance Synchronization (Oct 30-Nov 6)
**Focus:** Policy Migration, Telemetry, DIP Approvals

**Deliverables:**
- All policies migrated to Thundergate
- Telemetry dashboards live
- DIP approval workflow active
- All duplicate assets removed

**Success Metrics:**
- Policy coverage ≥ 90%
- 0 TODO placeholders
- Dashboard metrics live
- M1 milestone ready for deployment

---

## 9. Risk Register

| Risk | Impact | Probability | Mitigation | Owner |
|------|--------|-------------|------------|-------|
| Ash 3.x breaking changes | High | Medium | Incremental migration, extensive testing | All Stewards |
| Test coverage gaps | High | High | Require ≥85% per PR, block merges | Platform Lead |
| EventBus adoption slow | Medium | Medium | Deprecation warnings, metrics tracking | Flow Steward |
| Cerebros MLflow integration issues | High | Medium | Mock adapter for tests, staged rollout | Bolt Steward |
| Email SMTP reliability | Medium | Low | Retry logic, DLQ handling | Link Steward |
| Timeline slippage | High | Medium | Weekly checkpoints, early escalation | Platform Lead |

---

## 10. High Command Directives

> **"Push nothing to production that you wouldn't push through your own bloodstream."**

**Standing Orders:**
1. ✅ **Test First:** No code without tests (≥85% coverage)
2. ✅ **Document Always:** APIs, migrations, decisions
3. ✅ **Review Thoroughly:** Every PR reviewed by domain steward
4. ✅ **Fail Fast:** CI failures block merges
5. ✅ **Ship Small:** Incremental PRs over big bangs
6. ✅ **Measure Everything:** Telemetry for all critical paths
7. ✅ **Secure by Default:** Policies enforced, auth required
8. ✅ **Own Your Domain:** Stewards accountable for quality

**Quality Bar:**
- Zero TODO placeholders
- Zero compiler warnings
- Zero Credo violations
- Zero security findings
- 85%+ test coverage
- 100% Ash 3.x compliance

---

## Review Agent Status

**GitHub Copilot Observer:**
```
🟢 ACTIVE - Monitoring repository for HC task PRs
📊 Tracking: 10 P0 missions, 8 domain remediation efforts
📈 Metrics: Updated in real-time
🔔 Alerts: Configured for violations and blockers
📝 Reports: Warden Chronicles generated weekly
```

**Next Review Checkpoint:** October 11, 2025 (Mid-Week)  
**Next Warden Chronicles:** October 13, 2025 (Friday EOD)

---

## Appendix: Quick Reference

### Mix Tasks
```bash
mix thunderline.events.lint      # Validate event taxonomy
mix thunderline.guardrails       # Check domain boundaries
mix ash doctor                   # Validate Ash resources
mix credo --strict              # Code quality
mix test --cover                # Run tests with coverage
mix release.package             # Build release
```

### Key Files
- `lib/thunderline/thunderflow/event_bus.ex` - EventBus implementation
- `documentation/EVENT_TAXONOMY.md` - Event categories
- `documentation/ERROR_CLASSES.md` - Error classification
- `FEATURE_FLAGS.md` - Feature flag registry
- `DEPLOYMENT.md` - Release process
- `.github/workflows/` - CI/CD pipelines

### Contact
- **Platform Lead:** TBD
- **Flow Steward:** TBD
- **Bolt Steward:** TBD
- **Gate Steward:** TBD
- **Link Steward:** TBD
- **High Command:** @high-command

---

**Document Version:** 1.0  
**Last Updated:** October 9, 2025  
**Status:** ACTIVE MONITORING  
**Review Agent:** GitHub Copilot ✅ Online
