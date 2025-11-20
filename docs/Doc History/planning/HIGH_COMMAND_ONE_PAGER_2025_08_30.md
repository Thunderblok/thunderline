# ⚡ Thunderline High Command One-Pager (Aug 30, 2025)

Codename: Θ-03 — "From scaffold to signal"

> Sign the control frames. Drop the replays. Quarantine the ghosts. Ship the migrations. Send the email. Build the image. If it isn’t in the sim’s JSON, it doesn’t exist. Festina lente.

---
## Executive Snapshot

✅ UUID v7 adoption → improved ordering/traceability
✅ Thunderlink Transport (formerly TOCP) scaffold extended → first security + routing telemetry live
✅ Feature flags parity → :tocp, :tocp_presence_insecure documented (controls Thunderlink Transport attach & insecure mode)
✅ DIP-TOCP-002 telemetry taxonomy → PARTIAL acceptance (security + churn primitives; telemetry prefix remains `[:tocp, *]`)

⚠️ Remaining REDs: ML persistence (HC-04), Email MVP (HC-05), Presence policies (HC-06), Deployment/CI cluster (HC-07/08/09)

---
## P0 Launch Backlog (HC-01..HC-10) Status

GREEN: HC-01 Unified publish API, HC-10 Feature flags doc
AMBER: HC-02 Bus codemod consolidation, HC-03 Event taxonomy docs, HC-08 CI/CD hardening
RED: HC-04 ML persistence, HC-05 Email MVP, HC-06 Presence/membership policy, HC-07 Deployment automation, HC-09 Error classifier

---
## 48-Hour Targets (Approve & Ship PRs)
1. Thunderlink Transport Security Wiring PR
   - Wire Membership/Router to Security.Impl (verify signatures, replay window check)
   - Increment counters, emit security.quarantine
   - Implement FlowControl.allowed?/1 + :rate.drop telemetry
   - Simulator: Sybil swarm + Replay flood scenarios -> JSON gates
2. Cerebros Migration PR (HC-04)
   - Run migrations & rollback scripts; tag ml.schema.version telemetry
3. Email MVP Scaffold PR (HC-05)
   - Ash resources: Contact, OutboundEmail
   - Actions: :create_contact, :queue_send, :mark_sent, :mark_failed
   - Events: ui.command.email.requested, system.email.sent|failed
4. Ops "First Brick" PR (HC-07/08)
   - Dockerfile, mix release script, /healthz plug
   - CI: Dialyzer PLT cache, mix hex.audit
5. Event Taxonomy Linter PR (HC-03 slice)
   - mix thunderline.events.lint (name format, version presence, registry validation)

---
## 7-Day Tactical Plan
- Finish Transport Week-1 (membership + UDP) behind flag → 1k-node convergence <30s, p95 stabilize <5s
- Quarantine auto-actions (tripwire → timer-based reset)
- Error classifier + DLQ policy skeleton (HC-09) with Broadway hook
- Dashboard: security counters + switch rate panels; insecure mode banner if active
- Presence policy minimal enforcement (admission tokens + join/leave gating)
- Deploy foundations (Dockerfile, release scripts, healthcheck)

---
## Acceptance Gates (Must Hold Green)
- Zero unsigned control frames admitted (sim gate unsigned_control_frames == pass)
- ≥99.9% replay rejection inside 30s allowed skew
- Anomaly reaction < 60s (quarantine/hysteresis bump)
- Email MVP emits system.email.sent|failed with UUID v7 lineage
- Release image builds & /healthz returns 200 in CI container

---
## Simulator JSON Schema (LOCKED v0.2)
```json
{
  "version": "0.2",
  "nodes": 1000,
  "metrics": {
    "membership": {"convergence_ms_p95": 0, "stabilize_ms_p95": 0},
    "routing": {"relay_switch_rate_per_min": 0.0},
    "security": {
      "sig_fail": 0,
      "replay_drop": 0,
      "quarantined_nodes": 0,
      "insecure_mode": false
    },
    "reliability": {"dup_rx_ratio": 0.0, "timeouts": 0}
  },
  "gates": {
    "unsigned_control_frames": "pass",
    "replay_rejection_99_9": "pass",
    "anomaly_reaction_lt_60s": "pass"
  }
}
```
Changes require DIP-TOCP-005 update + steward approval.

---
## Telemetry (Incremental Deltas)
Delivered (PARTIAL per DIP-TOCP-002): membership.*, routing.relay_selected, delivery.*, security.sig_fail, security.replay_drop, delivery.ack.
Planned (P1): security.quarantine, security.insecure_mode (one-shot), reliability.window.*, error.classified, error.dlq, zone.presence.*

---
## Feature Flags Governance
- :tocp (enables Thunderlink Transport supervisor tree)
- :tocp_presence_insecure (ALLOWED only with boot WARN + emit [:tocp,:security,:insecure_mode])
Policy: In CI, insecure presence requires ALLOW_INSECURE_TESTS=true or test fails.

---
## Immediate Engineering Tasks (Ordered)
1. Migration Tiger Team: apply Cerebros migrations (HC-04)
2. Email MVP scaffold (HC-05) → unblock “send an email” proof
3. Security wiring → Membership/Router (Iron Veil slice)
4. Linter task (HC-03) small slice (1–2h)
5. Ops baseline (Dockerfile + /healthz + release script)
6. FlowControl.allowed?/1 + :rate.drop event
7. Simulator scenarios & gates (Sybil swarm, Replay flood)

---
## Risk Register
| Risk | Color | Mitigation |
|------|-------|------------|
| HC-04 + HC-05 compression | 🔴 | Parallel pods + strict scope guard |
| Presence policy absence | 🔴 | Implement minimal admission gating this sprint |
| Deployment automation lag | 🟡 | Ship Ops baseline PR (48h target) |
| Telemetry taxonomy drift | 🟡 | Implement linter now (HC-03 slice) |

---
## Decision Confirmations
- Parallelize HC-04 & HC-05: APPROVED
- DIP-TOCP-002 PARTIAL accepted; backlog follow-ons enumerated
- Insecure presence flag allowed (WARN + telemetry one-shot)
- Taxonomy linter prioritized immediately

---
## Implementation Nits (Must Address in Slice)
- UUID v7 monotonic sequence fallback; WARN on clock drift
- Replay ETS: shard by (src mod X), prune by time buckets, cap by buckets
- Signature cache: short TTL to reduce hot-loop overhead
- Hysteresis: add cooldown window after churn spikes (dampen reselection thrash)
- Config guardrails: centralize normalization & clamping (Thunderline.Thunderlink.Transport.Config; legacy TOCP.Config delegates)
- Simulator gate: force FAIL when presence insecure unless ALLOW_INSECURE_TESTS=true

---
## Quarantine & Flow Control (Upcoming)
Telemetry Additions:
- [:tocp,:security,:quarantine] measurements: %{count: 1} metadata: %{node: id, reason: r}
- [:tocp,:flow,:rate,:drop] measurements: %{count: 1} metadata: %{kind: k}
Action: Implement within security wiring PR.

---
## Ownership & Stewardship
- Security (Iron Veil slice): Security steward + Routing steward
- Migrations: Data steward (Cerebros) + Repo maintainer
- Email MVP: Application steward (ThunderGate/Link integration) + Ash steward
- Linter: Observability steward

---
## Exit Criteria for Current Sprint (Θ-03)
All 48-hour targets merged + simulator gates green + quarantine & rate drop telemetry emitting in dev environment.

---
"Structa, Tuta, Certa" – build it structured, secure, certain.
