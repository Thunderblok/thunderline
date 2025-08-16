# 🛡️ WARDEN BACKLOG & EXECUTION BRIEF

> Date: 2025-08-16  
> Source Inputs: High Command Diff (Event processing standardization), OKO Handbook (Systems Ecology & DIP), Domain Catalog (Interaction Matrix), Master Playbook (Phase Overlay)  
> Audience: Domain Stewards, Warden Execution Team, Architecture Leads

---
## 🧭 PURPOSE
Provide a single, prioritized, dependency-aware task map so Wardens can execute with zero ambiguity while preserving domain ecology (no predation, no mutation drift). Every task declares: Domain, Steward Role, Priority, Type, Dependencies, Definition of Done (DoD), Balance Signals Impact.

Priority Scale:
- P0 = Immediate (gate for next milestone)
- P1 = High (affects stability or first milestone success)
- P2 = Normal (enables future phases)
- P3 = Opportunistic / Tech Debt

---
## 🔑 CRITICAL PATH (P0, UPDATED AFTER PHASE-0) — ACTIVE REMAINING
| ID | Title | Domain | Type | Owner Role | Dependencies | DoD | Status |
|----|-------|--------|------|------------|--------------|-----|--------|
| CP-04 | README + Docs: Event Processing canonical snippet | Root | Docs | Steward Council | CP-01, CP-02 | Section added (Ash.run!/3 + gating), links to DIP; passes review | OPEN |
| CP-05 | Remove legacy domain list (15 domains) & align to 7 | Root | Docs | Catalog Steward | CP-04 | README & docs free of obsolete domains | PARTIAL (README still old) |
| CP-07 | BRG Checklist Script (stub mix task) | Root | Tooling | Flow + Catalog | CP-06 | `mix thunderline.brg.check` prints current metrics placeholders | OPEN |
| CP-08 | DIP Issue Template | Root | Governance | Security (Gate) | None | `.github/ISSUE_TEMPLATE/dip.yml` added & rendered correctly | OPEN |
| CP-09 | Catalog Edge Validation (static stub) | Root | Tooling | Catalog Steward | Interaction Matrix final | `mix thunderline.catalog.validate` exits 0 & warns for unknown edges | OPEN |
| CP-N1 | Domain Name Alignment (replace legacy Thunderchief/Thundercore/Thundervault in code) | Root | Refactor | Catalog Steward | None | All modules & pipelines use 7-domain names; tests updated | NEW |
| CP-N2 | CrossDomainPipeline normalization to canonical `%Thunderline.Event{}` | ThunderFlow | Refactor | Flow Steward | CP-N1 | Pipeline emits normalized struct; property test for shape | NEW |
| CP-N3 | Job Module Namespace Refactor (`Thunderchief.Jobs.*` → domain-scoped) | ThunderFlow | Hygiene | Flow Steward | CP-N1 | New modules created, old removed, references updated | NEW |
| CP-N4 | Circuit Breaker Test Suite | ThunderFlow | Quality | Flow Steward | Existing breaker | Tests: state transitions, half-open recovery, telemetry assertions | NEW |
| CP-N5 | Event Fanout Metric Aggregator | ThunderFlow | Observability | Flow Steward | CP-06 | Aggregates distribution & exposes P95 fanout | NEW |

### Completed (Phase-0 Delivered)
| ID | Delivered Artifact | Notes |
|----|--------------------|-------|
| CP-01 | `Thunderline.Thunderflow.Jobs.ProcessEvent` worker | Namespace differs from original spec (adjusted) |
| CP-02 | `Thunderline.Integrations.EventOps` Ash generic action | Gated via `TL_ENABLE_REACTOR` env var |
| CP-06 | Baseline metrics (jobs, events, circuit breaker, emit latency) | Add fanout & queue depth derivatives next |

### Conditional (Reclassified from Critical → Conditional Due to Gate)
| CID | Title | Condition to Activate |
|-----|-------|----------------------|
| CON-03 | Implement `RealtimeReactor` + diagram | When a flow meets Reactor gate criteria (≥3 dependent side-effects + undo need + failing inconsistency test) |
| CON-10 | Reactor Retry/Undo Telemetry Hook | After CON-03 implemented |

---
## 🟡 HIGH PRIORITY (P1) — UPDATED
| ID | Title | Domain | Type | Owner | Dependencies | DoD |
|----|-------|--------|------|-------|-------------|-----|
| P1-11 | Implement Email Flow DIP (Sprint 1) | ThunderLink / Gate | DIP | Gate Steward | CP-08 | DIP issue approved; invariants listed; resources scoped |
| P1-12 | Contact Resource (if needed) | ThunderLink | Resource | Link Steward | P1-11 | Ash resource w/ tests; added to Catalog |
| P1-13 | Event Normalization Helper (`Event.normalize/1`) | ThunderFlow | Lib | Flow Steward | CP-03 | Function added w/ spec; property test for idempotence |
| P1-14 | Fanout Analyzer (Telemetry handler) | ThunderFlow | Observability | Flow Steward | CP-N5 | Aggregates per-event target count; exposed via metrics |
| P1-15 | Reactor Mermaid Generation CI Step | Root | CI | Ops | CP-03 | GitHub Action fails if reactor PR lacks diagram |
| P1-16 | Invariants Annotation Pass (Top 20 resources) | All | Hygiene | Stewards | None | 20 resources updated; issues opened where TBD |
| P1-17 | Bridge Pattern Skeleton (provider_email) | ThunderGate | Bridge | Gate Steward | P1-11 | `bridge/provider_email_bridge.ex` + tests |
| P1-18 | Warning Budget Gate (compile task) | Root | Tooling | Flow Steward | CP-07 | CI fails if warnings > threshold (configurable) |
| P1-19 | Retry Policy DSL for Reactor Steps | ThunderFlow | Enhancement | Flow Steward | CP-03 | DSL macro & 2 example steps using it |
| P1-20 | Resource Churn Diff Tool | Root | Tooling | Catalog | CP-09 | Output: new/removed per domain since last tag |

---
## 🧪 MEDIUM (P2)
| ID | Title | Domain | Type | DoD |
|----|-------|--------|------|-----|
| P2-21 | Queue Depth Adaptive Concurrency | ThunderFlow | Performance | Broadway concurrency auto-tunes & test sim |
| P2-22 | Reactor Backoff Strategy Library | ThunderFlow | Lib | Backoff modules w/ test matrix |
| P2-23 | Email Send Reactor (if complexity > simple) | ThunderFlow | Reactor | DAG + compensation (draft/unmark) |
| P2-24 | Event Replay Tool | ThunderFlow | Maintenance | `mix thunderline.events.replay --from <id>` prototype |
| P2-25 | Ash Policy Hardening (Gate resources) | ThunderGate | Security | Resources with explicit policies + tests |
| P2-26 | Catalog Visual Graph Export | Root | Tooling | Generates Mermaid from Interaction Matrix |
| P2-27 | Spatial Metrics Integration | ThunderGrid | Observability | Emits zone heatmap metric |
| P2-28 | Reactor Step Property Tests | ThunderFlow | Quality | StreamData based invariants |
| P2-29 | Bridge Conformance Tests Framework | ThunderGate | Tooling | Shared test macro for bridges |
| P2-30 | Multi-LLM Routing Skeleton | ThunderCrown | Feature | Routing module + config map |

---
## 🧊 LOW (P3 / Opportunistic)
| ID | Title | Domain | DoD |
|----|-------|--------|-----|
| P3-31 | Remove legacy telemetry files | ThunderFlow | Deleted & no references |
| P3-32 | README Latin Motto Footnote | Root | Added context footnote |
| P3-33 | Codeowners Steward Mapping | Root | CODEOWNERS file listing domains |
| P3-34 | Dialyzer Strict Mode | Root | No new warnings; plt cached |
| P3-35 | Mermaid Diagrams for Top 5 Reactors | ThunderFlow | Stored in priv/diagrams |
| P3-36 | RFC Template | Root | `.github/ISSUE_TEMPLATE/rfc.yml` present |

---
## 🧵 DEPENDENCY GRAPH (UPDATED)
```
CP-N1 → CP-N3, CP-N2
CP-N2 → (enables richer analytics for P1-14)
CP-N5 → P1-14
CP-06 → CP-07, CP-N5
CP-08 → P1-11
CP-09 → P1-20
CON-03 → CON-10, P1-19
```

---
## ✅ DEFINITIONS OF DONE (GLOBAL)
- Code: Compiles clean + no new warnings (warning budget enforced once CP-18 lands)
- Tests: Unit + minimal integration; property tests where invariants matter
- Docs: Catalog + README + Handbook updated if domain surface or invariants changed
- Telemetry: Emits required metrics & events for new long-lived processes
- Security: Policies or explicit deferred note w/ issue reference
- Governance: DIP / BRG updates included in PR description when applicable

---
## 🔄 SPRINT 1 (POST PHASE-0) PROPOSED ORDER
| Day | Focus | Tasks |
|-----|-------|-------|
| 1 | Naming & Canon | CP-N1, CP-N3 |
| 2 | Event Normalization | CP-N2, CP-N5 seed work |
| 3 | Docs & Governance | CP-04, CP-05, CP-08 |
| 4 | Tooling & Validations | CP-07, CP-09 |
| 5 | Quality & Hardening | CP-N4, prepare DIP for Email Flow (P1-11) |

Exit Criteria Sprint 1: Legacy names removed; pipeline emits canonical events; docs updated with canonical snippet & 7-domain set; BRG & catalog tasks runnable; fanout groundwork in place.

---
## 🧪 TEST COVERAGE TARGETS
| Area | Minimum |
|------|---------|
| Worker (ProcessEvent) | 1 happy path + 1 invalid args (future) |
| Reactor | Step success + retry + compensation scenario |
| Normalization Helper | Property: idempotent + no key loss |
| Bridge Skeleton | Contract tests: success, failure path |
| Metrics Emitters | Telemetry capture test per metric |

---
## 📊 BALANCE METRICS MAPPING
| Metric | Related Tasks | Drift Risk Mitigated |
|--------|---------------|----------------------|
| queue.depth | CP-06, P2-21 | Backpressure blindness |
| reactor.retry.rate | CP-10, P1-19, P2-22 | Hidden instability |
| event.fanout | CP-06, P1-14 | Coupling explosion |
| warning.count | CP-18 | Hygiene decay |
| cross.domain.emit.fanout | P1-14, CP-09 | Dependency sprawl |
| resource.churn | P1-20 | Unbounded resource growth |

---
## 🛠 MIX TASKS (PLANNED STUBS)
| Task | Purpose |
|------|---------|
| `mix thunderline.brg.check` | Outputs current balance readiness & TODOs |
| `mix thunderline.catalog.validate` | Validates Interaction Matrix edges |
| `mix thunderline.events.replay` | Replays events for recovery/testing |
| `mix thunderline.reactors.diagram.verify` | Ensures diagrams exist |

---
## 👥 STEWARD ROLE MAP (REFERENCE)
| Domain | Role Label |
|--------|------------|
| ThunderBlock | Infrastructure Lead |
| ThunderBolt | Orchestration Lead |
| ThunderCrown | AI Governance Lead |
| ThunderFlow | Observability Lead |
| ThunderGate | Security Lead |
| ThunderGrid | Spatial Lead |
| ThunderLink | Interface/Comms Lead |

---
## 🚩 RISKS & MITIGATIONS
| Risk | Impact | Mitigation |
|------|--------|-----------|
| Missing Reactor module | Blocks unified processing | Prioritize CP-03 Day 1 |
| Metrics under-instrumented | Invisible instability | Land CP-06 before new flows |
| Domain leakage via email feature | Boundary erosion | Enforce DIP (P1-11) |
| Fanout growth | Coupling → performance | Analyzer (P1-14) + BRG gate |
| Retry loops w/o compensation | Data inconsistency | Reactor DSL (P1-19) |

---
## 🧪 FUTURE AUTOMATION IDEAS
- Static edge scanner: parse alias/import usage & map to Interaction Matrix
- Telemetry summarizer posting BRG snapshot comment on PRs
- Invariant annotation linter (ensures `Invariants:` present in resource moduledoc)

---
## 🟢 READY FOR EXECUTION
All CP tasks are discrete, low surface-area, and parallelizable for Day 1–5 execution with minimal cross-blocking.

> When opening PRs include: `DIP-CHECKLIST: <x>/10` + `BRG: pending|pass` + related Task IDs.

“Balance first, velocity second. Velocity emerges from a balanced system.”

---

Ping to proceed with implementation sequencing or request generation of stubs (worker, mix tasks) and I will execute immediately.
