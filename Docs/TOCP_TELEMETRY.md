# TOCP Telemetry Taxonomy (Draft / DIP-TOCP-002)

Sampling: Heartbeat events sampled 1/20. Critical reliability events unsampled.

## Event Prefix
All events under `[:tocp, *]`.

## Proposed Events
| Event | Measurements | Metadata | Notes |
|-------|--------------|----------|-------|
| membership.tick | %{duration_ms: int} | %{node: id} | Gossip cycle duration |
| membership.change | %{incarnation: int} | %{node: id, prev: state, new: state} | State transition |
| routing.relay_selected | %{score: float} | %{dest: zone, via: relay_id} | Hysteresis decisions |
| delivery.packet_tx | %{bytes: int} | %{kind: kind, dest: node} | Raw UDP send |
| delivery.packet_rx | %{bytes: int} | %{kind: kind, from: node} | Raw UDP recv |
| reliability.window | %{inflight: int} | %{peer: node} | Sliding window gauge |
| reliability.ack_batch | %{count: int} | %{peer: node} | Batched ACK flush |
| reliability.retry | %{attempt: int} | %{peer: node, mid: mid} | Retry emission |
| reliability.timeout | %{inflight: int} | %{peer: node, mid: mid} | Declared lost (should be zero in tests) |
| fragments.assemble | %{fragments: int, bytes: int} | %{fid: fid} | Completed assembly |
| store.offer | %{bytes: int} | %{ref: ref} | Message stored |
| store.gc | %{evicted: int, freed_bytes: int} | %{} | Retention sweep |
| flowcontrol.debit | %{remaining: int} | %{peer: node} | Token debit |
| churn.relay_switch | %{interval_ms: int} | %{from: relay_id, to: relay_id} | Relay churn metric |
| sim.metric | %{value: number} | %{name: atom} | Simulation aggregate |
| security.sig_fail | %{count: 1} | %{peer: node} | Signature verification failure |
| security.replay_drop | %{count: 1} | %{peer: node, mid: mid} | Replay/reused mid dropped |
| security.quarantine | %{reason: atom} | %{peer: node} | Peer moved to quarantine |
| rate.drop | %{dropped: int} | %{peer: node, zone: zone} | Credits/rate limiter discard |
| fragments.evicted | %{evicted: int} | %{peer?: node} | Fragment assembly eviction |

## Dashboards (Initial)
1. Membership Health: alive/suspect/dead counts, tick p95, hb sample ratio.
2. Latency/Reliability: retry rates, ack p95, window gauges.
3. Traffic Mix: tx/rx bytes by kind, reliable %, chunked %.
4. Store: offers, hit ratio (TBD), gc_evicted trend.
5. Churn: relay-switch rate (<5%/min steady).

## SLO Targets
- Convergence <30s @ 1000 nodes.
- Reliable miss rate 0 under 1% artificial loss.
- Zone-cast latency: p95 <250ms (LAN), <800ms (2-relay path) for 1KB.

---
Ownership: Sibyl-Eyes
