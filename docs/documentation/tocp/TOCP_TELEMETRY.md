# Thunderlink Transport Telemetry Specification (formerly TOCP)

Prefix: `[:tocp, *]` (unchanged for compatibility)
Version: 0 (scaffold)

## Event Matrix

| Event | Measurements | Metadata | Sampling | Notes |
|-------|--------------|----------|----------|-------|
| membership.join | %{count: 1} | %{node: id, zone: zone} | 1:1 | Node observed first time |
| membership.state_update | %{count: 1} | %{node: id, from: s1, to: s2} | 1:1 | Status transition |
| routing.relay_selected | %{latency_ms: n} | %{node: id, relay: rid, prev: rid2} | 1:1 | Hysteresis applied |
| routing.zone_changed | %{count: 1} | %{node: id, from: z1, to: z2} | 1:1 | Zone reassignment |
| delivery.packet_tx | %{bytes: n} | %{kind: k, reliable?: b} | 1:1 | Pre-send enqueue |
| delivery.packet_rx | %{bytes: n} | %{kind: k, reliable?: b} | 1:1 | Post-receive |
| delivery.retry | %{retry: r} | %{mid: id} | 1:1 | Each retry attempt |
| delivery.ack | %{rtt_ms: n} | %{mid: id} | 1:1 | RTT measurement |
| hb.sample | %{latency_ms: n} | %{node: id} | 1:20 | Gossip/heartbeat sample (hb_sample_ratio) |
| security.sig_fail | %{count: 1} | %{node: id, reason: r?} | 1:1 | Signature verification failure (control frame) |
| security.replay_drop | %{count: 1} | %{node: id} | 1:1 | Dropped replayed control frame |
| security.quarantine | %{count: 1} | %{node: id, reason: r} | 1:1 | (Planned) Node quarantined due to threshold breach |
| security.insecure_mode | %{count: 1} | %{flag: :tocp_presence_insecure} | 1:boot | (Planned) Emitted once when insecure flag active |
| flow.rate.drop | %{count: 1} | %{kind: k} | 1:1 | (Planned) Dropped due to FlowControl.allowed?/1 false |

## Sampling Rules
Heartbeat samples controlled by config `:tocp, :hb_sample_ratio` (default 20 -> 1/20). Note: despite consolidation under `Thunderline.Thunderlink.Transport.*`, the telemetry prefix and config key remain `:tocp`.
All other control & reliability events unsampled for MVP.

## Metrics Derivations (Dashboards)
- Membership Health: alive_count, suspect_rate (suspect / total per interval), dead_rate.
- Latency/Reliability: histogram(rtt_ms), retry_rate, timeout_rate, dup_rx_ratio (planned), reliability.window.* (planned).
- Traffic Mix: sum(bytes) by kind, reliable_ratio.
- Store: store.offered, store.hit, store.gc_evicted.
- Churn: relay_switch_rate (routing.relay_selected count / interval).
- Security: sig_fail_rate, replay_drop_rate, quarantined_nodes (gauge), insecure_mode (boolean banner), quarantine_incidents timeline.
- Flow Control: rate_drop_rate (flow.rate.drop).

## Export
Events forwarded to existing OTel exporter (Flow Telemetry Export bridge). Metric names: `tocp.*` with dot-joined event path.

## Future (Not in Scaffold)
- Exemplar linking (attach mid to distributed trace span)
- Aggregated periodic summaries (reduce cardinality)
- Adaptive sampling for high-volume packet_rx/tx
- Zone-level presence metrics (per DIP-TOCP-002 follow-on)
- DLQ/error-class telemetry (error.classified, error.dlq) post error classifier slice
- reliability.window metrics (dup_rx_ratio, timeouts) once reliability module active

---
Telemetry or it didn’t happen.
