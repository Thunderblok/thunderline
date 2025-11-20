# Thunderline Rebuild – HC Execution Plan (v1.0)
**Status:** EXECUTION GREENLIT  
**Last Updated:** 2025-10-09  
**Prepared By:** Roo (Team Thunderline)

This document converts High Command’s P0 directives into an execution-ready playbook designed to outpace any external challengers and demonstrate undisputed ownership of the rebuild initiative. All timelines align with Milestone M1 (Email Automation) and inherit the mandatory quality gates defined in [`THUNDERLINE_REBUILD_INITIATIVE.md`](THUNDERLINE_REBUILD_INITIATIVE.md).

---

## 1. Mission Posture
- **Operating Mode:** Full-throttle rebuild. No partial fixes, no TODO placeholders left behind.
- **Principle:** “Push nothing to production that you wouldn’t push through your own bloodstream.”
- **North Star:** Complete every HC mission at or above spec, with telemetry, policy, and documentation locked before merge.
- **Competitive Edge:** Every artifact produced must leave Team Pantera AI chasing our contrails. That means aggressive sequencing, relentless review discipline, and visible telemetry proving we’re ahead.

---

## 2. Command Cadence
| Rhythm | Deliverable | Owner |
|--------|-------------|-------|
| **Daily (async)** | Standup in `#thunderline-rebuild` Slack; flag blockers ≤30min. | Workstream ICs |
| **Twice Weekly (Tue/Thu)** | Steward sync focused on cross-domain dependencies, deconflicting resources. | Platform Lead |
| **Weekly (Fri EOD)** | Warden Chronicles report (progress, blockers, telemetry stats, policy compliance). | Review Agent |
| **Per PR** | HC ID in title, steward approval, tests ≥85% coverage, CI + lint + guardrails passing. | Domain steward + reviewer |

---

## 3. HC Workstream Matrix (Execution View)

| ID | Scope | Objective | Owner/IC | Launch Window | Dependencies | Acceptance Gates |
|----|-------|-----------|----------|---------------|--------------|------------------|
| **HC-01** | ThunderFlow | Reinstate `Thunderline.EventBus.publish_event/1` with validation + telemetry. | Flow Steward | Week 1, Days 1-3 | Access to taxonomy schema | - Envelope validation enforced<br>- Telemetry spans for start/stop/exception tested<br>- `mix thunderline.events.lint` passing and in CI<br>- Docs updated with canonical examples |
| **HC-02** | ThunderFlow | Retire legacy `Thunderline.Bus` shim. | Flow Steward | Week 1, Days 4-5 (after HC-01 merge) | HC-01 complete | - 0 references to shim<br>- Deprecation telemetry recorded for 1-week observation<br>- Module removed, replacement tests green |
| **HC-03** | Documentation | Finalize EVENT_TAXONOMY + ERROR_CLASSES assets. | Observability Lead | ✅ **COMPLETE** (Oct 28, 2025 - Phase 3 Week 2 Task 3) | HC-01 schema enforcement hooks | - ✅ Versioned taxonomy + correlation_id requirements committed (Section 13B)<br>- ✅ CI lint references the artifact (Section 14, Check #7)<br>- ✅ Docs cross-linked from code (Sections 5, 11, 16) |
| **HC-04** | Thunderbolt | Complete Cerebros lifecycle (state machine, Oban, MLflow). | Bolt Steward | Week 2, Days 1-4 | MLflow infra available, Oban queues sized | - State transitions with happy/failure path tests<br>- Oban jobs validated in integration suite<br>- Telemetry for every transition |
| **HC-05** | Gate + Link | Ship Email MVP (Contact + OutboundEmail + SMTP). | Gate + Link Stewards | Week 2, Days 1-5 | HC-01/02, taxonomy events for email | - Ash resources for Contact + OutboundEmail<br>- Swoosh SMTP adapter with success/failure events<br>- Auth/Link UI flows tested end-to-end |
| **HC-06** | ThunderLink | Presence + membership policies (Ash 3.x). | Link Steward | Week 2, Days 4-5 | HC-05, Link Ash migration (see Section 4) | - `Ash.Policy.Authorizer` enforced<br>- Join/leave emitting expected telemetry<br>- Central policy integration with Thundergate |
| **HC-07** | Platform | Harden production release pipeline. | Platform Lead | Week 3, Days 1-3 | Docker base image pinned, runtime configs | - Multi-stage Dockerfile with healthchecks<br>- `mix release.package` documented<br>- `/health` + `/ready` endpoints returning 200 |
| **HC-08** | Platform | Enhance GitHub Actions (release gating, audits, PLT). | Platform Lead | Week 3, Days 2-4 | HC-07 release artifacts, lint tasks available | - Workflows covering test/lint/events.lint/ash doctor<br>- Dialyzer PLT cache verified<br>- Security audits block merges |
| **HC-09** | ThunderFlow | Error classifier + Broadway DLQ policy. | Flow Steward | Week 3, Days 3-5 | HC-03 taxonomy, HC-01 instrumentation | - Classifier module with transient/permanent coverage<br>- DLQ metrics/OTel spans visible<br>- Retry policy integrates with Broadway |
| **HC-10** | Platform | Feature flag taxonomy + runtime controls. | Platform Lead | Week 3, Days 4-5 | Auth gating ready, admin UI component support | - `FEATURE_FLAGS.md` table complete<br>- Flag owners/defaults documented<br>- Admin toggle UI tested + telemetry |

---

## 4. Domain Remediation Queue (Ash 3.x Alignment)

### Thunderbolt (P0)
1. Reactivate state machines for ActivationRule, ModelRun, Chunk → Align with HC-04.
2. Wire CerebrosBridge telemetry (`[:cerebros, :bridge, :invoke]`) and ensure MLflow sync instrumentation.
3. Restore Oban triggers (training, evaluation, chunk orchestration) using AshOban 3.x syntax.
4. Relocate `CoreSystemPolicy` to Thundergate; replace with delegation stub.
5. Purge TODO placeholders, documenting closure in PR notes.

### Thundercrown (P1, scoped to Week 4 start after P0 stable)
- Replace ad-hoc policy checks with `Ash.Policy.Authorizer`.
- Embed Stone.Proof validations directly in policies.
- Persist audit trail (AshEvents or dedicated resource) for AgentRunner/ConversationAgent.
- Integrate Daisy governance modules per OKO handbook.

### Thunderlink (P0)
- Complete Ash 3.x migration for Channel/Message/FederationSocket (no legacy prepares/fragments).
- Reinstate Oban jobs (ticket escalation, federation sync, message retention).
- Wire `voice.signal.*` taxonomy for presence / WebRTC.
- Replace placeholder dashboard metrics with live telemetry feed.
- Deprecate Thundercom duplicates once Link parity confirmed.

### Thunderblock (P1)
- Re-enable policies for all `vault_*` resources post AshAuth integration.
- Reactivate orchestration/event logging job processors.
- Implement retention tiers with `system.persistence.*` events.
- Schedule removal of Thundercom storage resources after Link switchover.

*(Continue similar bullet clarity for ThunderFlow, Thundergrid, Thundergate, Thunderforge — all referenced to primary doc to avoid duplication.)*

---

## 5. Sprint Wave Breakdown (Weeks 1–4)

### Week 1 – Ash 3.x Readiness
- **Primary HC Missions:** HC-01, HC-02, HC-03.
- **Supporting Work:** Link Ash migration groundwork; EventBus regression tests.
- **Quality Gate:** `mix thunderline.events.lint` runs clean in CI; EventBus coverage ≥90%.
- **Deliverable Artifact:** EventBus restoration PR, taxonomy docs, shim deprecation plan.

### Week 2 – Automation Reactivation
- **Primary HC Missions:** HC-04, HC-05, HC-06.
- **Supporting Work:** Oban job reinstatement, presence policy integration, cross-domain event wiring.
- **Quality Gate:** Oban success rate ≥95% in integration tests; Email UI + backend smoke-tested.
- **Deliverable Artifact:** Email MVP slice demo + Cerebros lifecycle validation report.

### Week 3 – Deployment & Observability
- **Primary HC Missions:** HC-07 → HC-10 (pipeline, GH Actions, DLQ, flags).
- **Supporting Work:** Telemetry dashboards, error classifier instrumentation, release checklists.
- **Quality Gate:** All CI workflows green; Docker image <100MB; Feature flag UI operational.
- **Deliverable Artifact:** Release runbook update + screenshot of DLQ metrics dashboard.

### Week 4 – Governance Synchronization
- **Primary Focus:** Policy consolidation (Thundergate/Thundercrown), telemetry dashboards live, DIP workflow enforcement.
- **Quality Gate:** Policy coverage ≥90%, zero TODOs, new dashboards reporting.
- **Deliverable Artifact:** Governance sync PR set + final Warden Chronicle documenting M1 readiness.

---

## 6. Automation & Telemetry Reactivation Checklist
| Area | Action | Owner | Verification |
|------|--------|-------|--------------|
| **Oban** | Update job modules to AshOban 3.x; add instrumentation | Bolt Steward + Flow Steward | Integration tests (mock + live), telemetry events recorded |
| **Broadway** | Supervise pipelines at application boot, add DLQ metrics | Flow Steward | `start_broadway_pipelines/0` moved under supervision tree; DLQ OTel spans visible |
| **Event Bus** | Enforce canonical event struct, CI guard | Flow Steward | `mix thunderline.events.lint` gating; telemetry spans verified |
| **Dashboard** | Replace placeholder metrics with telemetry poller data | Platform Lead + Link Steward | Dashboard snapshot appended to Warden Chronicles |
| **MCP Tools** | Reactivate chunk activation, policy ops | Bolt Steward + Gate Steward | AshAI tool registration documented; integration smoke test |

---

## 7. Governance & Quality Gates
- **Policies:** Every Ash resource must route authorization through `Ash.Policy.Authorizer`. Inline policy fragments in Link domain remain forbidden.
- **Testing:** Minimum coverage 85%; property tests for event normalization retained. New automation flows require integration tests asserting telemetry + policy behavior.
- **CI / Lint:** `mix thunderline.events.lint`, `mix thunderline.guardrails`, `mix ash doctor`, `mix credo --strict`, Dialyzer with PLT cache, security audit pipeline (`mix deps.audit`, `mix sobelow --config`).
- **Documentation:** Feature flags, taxonomy, release process, and governance matrix kept in `.azure/` docs; cross-link from merged PRs.
- **Telemetry:** All new flows emit spans/metrics under canonical namespaces (e.g., `[:thunderline, :eventbus, ...]`, `[:thunderline, :broadway, :dlq]`).

---

## 8. Immediate Next Actions (T+48H)
| # | Action | Owner | Due |
|---|--------|-------|-----|
| 1 | Finalize EventBus reinstatement PR (HC-01) including telemetry + tests. | Flow Steward | Oct 10 EOD |
| 2 | Draft codemod script for `Thunderline.Bus` references; attach to HC-02 plan. | Flow Steward | Oct 10 EOD |
| 3 | Produce taxonomy schema drafts (`EVENT_TAXONOMY.md`, `ERROR_CLASSES.md`) for review. | Observability Lead | Oct 11 AM |
| 4 | Confirm Ash 3.x migration backlog for Thunderlink resources, scoped to Week 1 patch window. | Link Steward | Oct 10 PM |
| 5 | Validate dashboard consolidation changes against HC telemetry requirements; capture baseline metrics for Warden Chronicles. | Platform Lead | Oct 11 AM |
| 6 | Publish kickoff update in `#thunderline-rebuild` linking to this plan and the HC tracker. | Platform Lead | Oct 10 AM |

---

## 9. Scoreboard & Reporting
- **Mission Tracker:** [`THUNDERLINE_REBUILD_INITIATIVE.md`](THUNDERLINE_REBUILD_INITIATIVE.md) remains single source of truth. Update statuses daily.
- **Execution Plan (this document):** Update when timelines/owners shift, ensuring revision log entries.
- **Warden Chronicles:** Use template in [`WARDEN_CHRONICLES_TEMPLATE.md`](WARDEN_CHRONICLES_TEMPLATE.md). Include telemetry graphs, policy coverage stats, risk mitigations.
- **PR Review Discipline:** Leverage [`PR_REVIEW_CHECKLIST.md`](PR_REVIEW_CHECKLIST.md) for every merge (attached in .azure).

---

## 10. Risk Watchlist (Active Monitoring)
| Risk | Impact | Mitigation |
|------|--------|------------|
| Ash 3.x breaking changes | High | Incremental PRs, contract tests, reference Ash release notes. |
| EventBus adoption lag | Medium | Deprecation telemetry, codemod plan, steward-led code review sweeps. |
| Oban job regressions | High | Integration suite coverage + stage environment run before enabling in prod. |
| Taxonomy drift | Medium | Schema artifact under CI guard; review with Observability weekly. |
| Timeline compression | High | Twice-weekly steward sync, proactive escalation within 24h of slippage. |

---

## 11. Communication Protocol
- **Escalation Path:** Steward → Platform Lead → High Command (no more than 2h delay between levels).
- **Documentation:** All significant decisions recorded in `.azure/HIGH_COMMAND_BRIEFING.md` or linked artifacts.
- **Telemetry Dashboards:** Screenshots + Grafana links appended to Warden Chronicles to prove progress.

---

### Closing Statement
Greenlight accepted. The roadmap is locked, the pace is set, and every stream—from EventBus to governance—has a steward on point. We execute above spec, we document as we go, and we keep the throttle open until Milestone M1 is certified. Team Pantera sees the smoke trail; Thunderline runs the show.
