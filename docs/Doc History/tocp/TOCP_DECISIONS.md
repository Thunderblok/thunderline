# Thunderlink Transport Decisions Log (DIPs) — formerly TOCP

Domain: Thunderline.Thunderlink.Transport.* (TOCP modules remain as shims)  
Scope: Scaffold -> Week1 (Presence/Routing) -> Week2 (Reliability/Fragments/Store)

## Active DIPs (Snapshot: 2025-08-30)

### DIP-TOCP-001: Domain Edges & Anti-Corruption Layer
Status: Draft
Intent: All cross-domain interactions occur via explicit bridge modules. No direct struct sharing.
Bridges:
- Thundercom Bridge (events ingress/egress)
- Flow Telemetry Export (telemetry mapping to OTel)
- Link Mapping (ZoneID<->channel slug)
Decision: Use event-based contracts (Ash actions + events) for ingress/egress. No direct ETS/table reads.
Open: Versioning strategy for bridge events.

### DIP-TOCP-002: Telemetry Taxonomy & Sampling
Status: PARTIAL (accepted Aug 30 2025)
Scope (delivered):
- membership.join, membership.state_update
- routing.relay_selected (feeding relay_switch_rate derived metric)
- delivery.packet_tx, delivery.packet_rx, delivery.retry, delivery.ack
- security.sig_fail, security.replay_drop (counters surfaced in simulator artifact)
Sampling: Heartbeat sample 1/20 (hb_sample_ratio config). All listed control & security events unsampled in MVP.
Decision: Prefix `[:tocp, *]` exported via Flow telemetry exporter -> OTel (`tocp.<event_path>` metric names). Consolidation into `Thunderline.Thunderlink.Transport.*` does not change the telemetry prefix.
Follow-on (P1 backlog):
- zone.presence.* metrics (per-zone membership counts & churn)
- reliability.window metrics (dup_rx_ratio, timeout counters) once reliability slice lands
- DLQ/error-class telemetry (bridge to HC-09 error classifier) -> events: error.classified, error.dlq
- security.quarantine event + quarantine.count gauge (after wiring)
- insecure_mode one-shot event `[:tocp,:security,:insecure_mode]` (emitted at boot if flag true)
Open: Histogram buckets for latency & retries; exemplar/trace linkage; adaptive sampling policy spec.

### DIP-TOCP-003: Store-and-Forward Retention
Status: Draft
Limits: 24h OR 512MB (whichever first). Enforced via periodic GC loop.
Priority: Reliable control frames > data frames.
Decision: TTL enforced on offer; GC scans hourly; size enforcement LRU by last access.
Open: Multi-tenancy considerations (future).

### DIP-TOCP-004: Security Roadmap (Operation Iron Veil)
Status: IN PROGRESS (scaffold merged)
Delivered:
- Ed25519 sign/verify (JOSE) for control frames under feature flag
- Replay window ETS + pruning task
- Telemetry counters: security.sig_fail, security.replay_drop
- Config surface: presence_secured, admission_required, replay_skew_ms, insecure presence override flag (:tocp_presence_insecure)
Next Slice (48h target):
- Wire Membership & Router paths to Security.Impl (verify signatures, invoke replay check)
- Increment counters & emit security.quarantine on threshold breach
- Implement FlowControl.allowed?/1 (rate limiting + :rate.drop telemetry)
- Simulator scenarios: Sybil swarm, Replay flood -> MUST produce pass/fail gates in JSON
Deferred (Week 2+):
- Noise-XK handshake integration
- Key rotation interval & revocation channel
- Admission token verification logic (stub exists)
Open: Signature cache TTL tuning; memory caps on replay buckets; quarantine auto-reset policy.

### DIP-TOCP-005: Simulator Gates (CI)
Status: UPDATED (schema v0.2)
Current JSON schema locked at version 0.2 (see Playbook / Simulator JSON section) including security + routing metrics & gates.
Gates (current enforcement aspirations):
- unsigned_control_frames == pass (zero unsigned control frames admitted)
- replay_rejection_99_9 == pass (≥99.9% rejection within skew window)
- anomaly_reaction_lt_60s == pass (quarantine/hysteresis bump under 60s)
Week1 Targets: convergence_ms_p95 < 30_000; stabilize_ms_p95 < 5_000.
Week2 Targets: reliable_missed = 0 under 1% induced loss.
Decision: Mix task writes JSON; CI parses + fails on gate != pass or metric regressions.
Open: Deterministic loss model seed; gating diff threshold config; admission token scenario.

## Change Control
All DIPs evolve via PR with CHANGELOG note under "TOCP" heading.

## Related External DIPs / Optimization Layer
- DIP-VIM-001 (Virtual Ising Machine Layer) drafted (2025-08-30) – introduces shared optimization layer for routing (relay K-selection) & persona board. Planned telemetry namespaces (vim.router.solve, vim.persona.solve) to be added once flag lands. TOCP will consume RouterAdaptor outputs under feature flag; decisions doc will be updated when active mode enabled.

## Ownership
Single-thread leads recorded in High Command brief; each DIP PR tagged with @owner + @sibyl-eyes for telemetry review.

---
"Structa, Tuta, Certa" – build it structured, secure, certain.
