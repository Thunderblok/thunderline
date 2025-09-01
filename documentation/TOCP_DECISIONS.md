# TOCP Domain Decisions (DIP Index)

Status: Scaffold (Week 0)  
Owner: Prometheus-Net  
Motto: Structa, Tuta, Certa.

## Scope
Sovereign protocol domain for membership, routing, transport, reliability & store/forward bridging into existing domains via explicit bridges (no raw struct coupling).

## Decision Records

| DIP | Title | Status | Summary |
|-----|-------|--------|---------|
| DIP-TOCP-001 | Domain Edges & Anti-Corruption Contract | OPEN | Enumerate bridges: Com (federation bus), Flow (telemetry export), Link (zone mapping), Gate (key mgmt future) |
| DIP-TOCP-002 | Telemetry Taxonomy & Sampling | PARTIAL | Event list + HB sample 1/20; switch rate + security counters implemented; dashboards pending |
| DIP-TOCP-003 | Store-and-Forward Retention Policy | OPEN | 24h OR 512MB whichever first; TTL + byte GC sweeper |
| DIP-TOCP-004 | Security Roadmap | OPEN | Phase-in Noise-XK; MVP sign control frames only (flag reserved) |
| DIP-TOCP-005 | Simulator Gates as CI Checks | OPEN | JSON report contract; convergence & reliability SLO assertions |

## Open Questions
1. Zone identity hash function finalization (Link mapping) – deterministic & collision budget?
2. Credit refill granularity (per 100ms vs per second) – impact on burst fairness.
3. Future multi-transport arbitration: QUIC vs WebRTC datachannels priority.
 4. PoW difficulty auto-tuning heuristic (target ms vs failure ratio) – finalize algorithm.
 5. Admission token format evolution (bearer -> macaroons) timeline alignment with Gate.

## Deferred (Post MVP)
- Full cryptographic handshake & key rotation (Noise-XK)
- Multi-transport intelligent path selection
- Advanced congestion control (ECN / dynamic window)
- Adaptive fragmentation reassembly budget
 - Macaroon-based admission tokens & blinded identity binding
 - Batch signature verification scheduling / batching pool

## Invariants (Initial Set / Updated)
- Supervisor attaches only when feature flag `:tocp` true.
- All telemetry events prefixed `[:tocp, *]`.
- No process spawns with open sockets in scaffold phase.
- Control frames MUST be signed when `security_sign_control=true` (sign/verify scaffold implemented).
- Replay window enforced: drops duplicates/stale > replay_skew_ms (ETS + pruning active; wire ingestion pending).
 - Zone kill-switch acts within one gossip interval.

## Implementation Progress (Week 0 Scaffold Delta)
- Added `Routing.SwitchTracker` (relay switch telemetry)
- Added `Telemetry.Aggregator` (security counters)
- Added `Security.Pruner` (replay window maintenance)
- Internal UUID v7 generator (`Thunderline.UUID`) adopted across events
- Config normalization module present (`TOCP.Config`)

---
Signed-Off: (pending High Command)
