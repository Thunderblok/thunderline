# TOCP Decisions Log (DIPs)

Domain: Thunderline.TOCP.*  
Scope: Scaffold -> Week1 (Presence/Routing) -> Week2 (Reliability/Fragments/Store)

## Active DIPs

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
Status: Draft
Events (initial):
- membership.join, membership.state_update
- routing.relay_selected, routing.zone_changed
- delivery.packet_tx, delivery.packet_rx, delivery.retry
Sampling: Heartbeat sample 1/20 (hb_sample_ratio config). All control frames unsampled.
Decision: Use prefix [:tocp, *] and export via existing OTel exporter.
Open: Histogram buckets for latency & retries.

### DIP-TOCP-003: Store-and-Forward Retention
Status: Draft
Limits: 24h OR 512MB (whichever first). Enforced via periodic GC loop.
Priority: Reliable control frames > data frames.
Decision: TTL enforced on offer; GC scans hourly; size enforcement LRU by last access.
Open: Multi-tenancy considerations (future).

### DIP-TOCP-004: Security Roadmap
Status: Draft
MVP: Sign only control frames (sim only). Phase-in Noise-XK handshake post Week-2.
Decision: Reserve frame fields for key id & signature now.
Open: Key rotation interval & revocation channel.

### DIP-TOCP-005: Simulator Gates (CI)
Status: Draft
Gates:
- Scaffold: report JSON exists.
- Week1: convergence_time_s < 30, stabilization_p95_s < 5.
- Week2: reliable_missed = 0 under loss 1%.
Decision: Mix task writes JSON; CI parses and asserts.
Open: Loss model determinism seed.

## Change Control
All DIPs evolve via PR with CHANGELOG note under "TOCP" heading.

## Ownership
Single-thread leads recorded in High Command brief; each DIP PR tagged with @owner + @sibyl-eyes for telemetry review.

---
"Structa, Tuta, Certa" – build it structured, secure, certain.
