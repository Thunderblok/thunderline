# Θ-03 PLAYBOOK — From Scaffold to Signal (Aug 30, 2025)

Companion to: `HIGH_COMMAND_ONE_PAGER_2025_08_30.md` (executive snapshot)  
Scope Window: Next 48h → 7 Days  
Objective: Land security wiring, migrations, email MVP slice, ops baseline, taxonomy linter, and simulator gates while preserving protocol hardening trajectory.

---
## 0. Canonical References
| Area | Doc / DIP | Status |
|------|-----------|--------|
| Telemetry Taxonomy | DIP-TOCP-002 | PARTIAL (follow-ons queued) |
| Security Roadmap | DIP-TOCP-004 | IN PROGRESS (scaffold) |
| Simulator Gates | DIP-TOCP-005 | UPDATED (schema v0.2) |
| Feature Flags | FEATURE_FLAGS.md | Updated w/ insecure governance |
| Decisions Log | TOCP_DECISIONS.md (applies to Thunderlink Transport) | Synced Aug 30 |
| One-Pager | HIGH_COMMAND_ONE_PAGER_2025_08_30.md | Source of sprint directives |

---
## 1. 48h PR Targets (Blocking Set)

### 1.1 Thunderlink Transport Security Wiring PR
Checklist:
- [ ] Integrate `Security.Impl.verify/2` in Membership ANNOUNCE/ADVERTISE/ACK ingest path
- [ ] Invoke replay window check before state mutation
- [ ] Increment `security.sig_fail` / `security.replay_drop` counters via telemetry
- [ ] Implement quarantine trigger (threshold policy configurable; default >3 sig_fail/s per node)
- [ ] Emit `[:tocp,:security,:quarantine]` on quarantine (planned event -> SPEC update once merged)
- [ ] Add signature cache (ETS) with TTL (configurable; default 2s)
- [ ] Add FlowControl.allowed?/1 (stub rate bucket + drop event emission spec) — emit `[:tocp,:flow,:rate,:drop]`
- [ ] Unit tests: signature ok / bad / replay / quarantine threshold trip
- [ ] Integration test: toggling `FEATURE_TOCP_PRESENCE_INSECURE` disables checks + emits one-shot insecure event
- [ ] Update telemetry & decisions docs after merge

### 1.2 Cerebros Migration PR (HC-04)
Checklist:
- [ ] Move pending migrations from backup → `priv/repo/migrations/`
- [ ] Apply & verify idempotent rollback locally
- [ ] Tag `ml.schema.version` in telemetry exporter (counter or gauge)
- [ ] Add test ensuring resources CRUD after migration
- [ ] Update `MIGRATIONS.md` + CHANGELOG (Transport/TOCP section)

### 1.3 Email MVP Scaffold PR (HC-05)
Checklist:
- [ ] Ash Resources: Contact, OutboundEmail
- [ ] Actions: create_contact, queue_send, mark_sent, mark_failed
- [ ] State machine for OutboundEmail (pending → sending → sent | failed)
- [ ] Event emissions: ui.command.email.requested, system.email.sent|failed (UUID v7 lineage preserved)
- [ ] Minimal service module for enqueue/send stub (no external delivery yet)
- [ ] Tests: happy path send, failure marking, lineage assertion
- [ ] Docs: EVENT_TAXONOMY update + Handbook delta

### 1.4 Ops First Brick PR (HC-07/08)
Checklist:
- [ ] Dockerfile (multi-stage: deps → build → runtime) with health probe CMD
- [ ] mix release script (bin wrapper) & doc snippet
- [ ] /healthz Plug route returning 200 + version & git ref
- [ ] CI: Dialyzer PLT cache artifact reuse
- [ ] CI: `mix hex.audit` step (fails on HIGH severity)
- [ ] Optional: Basic `mix release` smoke run in CI container

### 1.5 Event Taxonomy Linter PR (HC-03 slice)
Checklist:
- [ ] Mix task `mix thunderline.events.lint`
- [ ] Validates: name pattern, presence & increment of version field where required, whitelisted categories
- [ ] Fails on unknown or missing version for system/email events
- [ ] JSON output mode for CI parsing
- [ ] Test fixtures for pass/fail scenarios

---
## 2. 7-Day Tactical (Extended) Items
| Item | Goal | Owner | Acceptance |
|------|------|-------|-----------|
| Membership + UDP Week-1 | 1k-node convergence <30s, p95 stabilize <5s | Protocol | Simulator JSON metrics pass gates |
| Quarantine Auto-Reset | Timed release & counter decay | Security | Reset telemetry event & test |
| Error Classifier + DLQ (HC-09) | classify(event)->{class,action} | Reliability | Broadway hook test + DLQ event |
| Dashboard Panels | security counters + relay switch & insecure banner | Observability | LiveView renders real values |
| Presence Policy Enforcement | admission tokens & join gating | Protocol | Unauthorized join rejected test |
| FlowControl Hardening | token buckets per node & zone | Protocol | Rate drop telemetry under synthetic burst |

---
## 3. Acceptance Gates & Mapping
| Gate | Metric / Event Source | Threshold | Test Harness |
|------|-----------------------|-----------|--------------|
| Unsigned Control | security.sig_fail & internal flag check | 0 unsigned accepted | Sybil/unsigned scenario (sim) |
| Replay Rejection | security.replay_drop / attempted replays | ≥99.9% within 30s skew | Replay flood scenario |
| Anomaly Reaction | quarantine event timestamp delta | < 60s | Churn + malicious pattern scenario |
| Email Lineage | system.email.sent payload lineage chain | present & valid UUID v7 | Email MVP test |
| Release Health | /healthz HTTP 200 | always | CI container run |

---
## 4. Simulator Schema Governance (v0.2)
Location: One-Pager & enforced in sim task.  
Change Process:
1. Propose field => PR updating DIP-TOCP-005 & doc.
2. Bump version (0.3) only if breaking (rename/remove).  
3. Add backward compatibility logic in parser (CI).

---
## 5. Risk Register (Active)
| Risk | Impact | Mitigation | Owner | ETA |
|------|--------|-----------|-------|-----|
| HC-04 + HC-05 schedule clash | Delays email proof | Parallel pods, narrow scope | PM | Daily sync |
| Insecure flag misuse | Weakens test integrity | WARN + one-shot telemetry + CI gate | Security | Done (wiring pending) |
| Telemetry drift | Observability blind spots | Ship linter & doc updates in same PR | Observability | 48h |
| Replay window memory growth | Node memory pressure | Shard + time-bucket prune + cap | Protocol | 72h |

---
## 6. Implementation Guidance Nuggets
- Use UUID v7 monotonic fallback: maintain last_ts & seq; if same ms increment seq nibble + WARN on clock regress.
- Replay ETS Sharding: `:ets.new({:replay, shard}, ...)`; shard = `:erlang.phash2(src, n)`; prune oldest bucket by timestamp.
- Signature Cache: simple ETS set `{pubkey_hash, ts}`; upsert on verify success; skip re-verify if within TTL.
- Hysteresis Cooldown: store last switch ts; disallow switch while `(now - last_ts) < cooldown_ms` unless forced by failure.
- Config Guardrails: `Thunderline.Thunderlink.Transport.Config.normalize/1` (clamp intervals, ensure non-negative, log sanitized keys). Legacy TOCP.Config delegates.

---
## 7. Telemetry Delta Plan
| Event | Status | Source Module | Notes |
|-------|--------|---------------|-------|
| security.sig_fail | Implemented | Security.Impl | Counter increment per failure |
| security.replay_drop | Implemented | Security.Impl | After replay rejection |
| security.quarantine | Planned | Membership/Router | Emit once per state change |
| security.insecure_mode | Planned | Transport.Supervisor boot | One-shot if flag active |
| flow.rate.drop | Planned | FlowControl | Drop decision path |
| routing.relay_selected | Implemented | SwitchTracker | Latency metric derivation |

---
## 8. PR Template Snippet (Include in Each Target PR)
```
### Θ-03 Playbook Alignment
- [ ] References sections: (e.g., 1.1 Security Wiring, 1.2 Migrations)
- [ ] Updated docs (Decisions/Telemetry) if event/config surface changed
- [ ] Added/updated tests (list)
- [ ] Simulator unaffected OR updated (schema v0.2)
- [ ] Acceptance gates remain green (evidence link)

### Telemetry Coverage
- Events added: (list)
- Sampling considerations: (describe)

### Security & Config
- Feature flags modified: (list or N/A)
- Config normalization changes: (Yes/No)
```

---
## 9. CI Enhancements (Planned This Sprint)
| Enhancement | Purpose | Status |
|-------------|---------|--------|
| Dialyzer PLT cache | Speed up type analysis | Pending (Ops PR) |
| hex.audit job | Supply chain scan | Pending (Ops PR) |
| Telemetry doc drift check | Fail if events missing from spec | Planned |
| Simulator gate job | Enforce acceptance gates | Implemented scaffold |
| Event linter job | Enforce taxonomy & version | Pending (Linter PR) |

---
## 10. Exit Criteria (Sprint Θ-03)
All 48h PRs merged, quarantine & rate control telemetry live, simulator gates passing with updated security counters, migrations applied, email events emitting with UUID v7 lineage, Docker image build + /healthz verified in CI.

---
## 11. Post-Sprint Roll-Up (Prep)
- Convert PARTIAL DIP-TOCP-002 → include follow-on acceptance list closure log
- Draft DIP for reliability.window metrics (new) if complexity escalates
- Prepare dashboard panel queries (Grafana or LiveView) for new security metrics

---
"If it isn’t observable, it isn’t shipped."  
"If it isn’t in the simulator JSON, it doesn’t exist."  

---
Maintainers: Security (Iron Veil), Protocol, Observability, Data (Cerebros), Product (Email)
