# TOCP Telemetry Specification

Prefix: `[:tocp, *]`
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

## Sampling Rules
Heartbeat samples controlled by config `:tocp, :hb_sample_ratio` (default 20 -> 1/20).
All other control & reliability events unsampled for MVP.

## Metrics Derivations (Dashboards)
- Membership Health: alive_count, suspect_rate (suspect / total per interval), dead_rate.
- Latency/Reliability: histogram(rtt_ms), retry_rate, timeout_rate.
- Traffic Mix: sum(bytes) by kind, reliable_ratio.
- Store: store.offered, store.hit, store.gc_evicted.
- Churn: relay_switch_rate (routing.relay_selected count / interval).

## Export
Events forwarded to existing OTel exporter (Flow Telemetry Export bridge). Metric names: `tocp.*` with dot-joined event path.

## Future (Not in Scaffold)
- Exemplar linking (attach mid to distributed trace span)
- Aggregated periodic summaries (reduce cardinality)
- Adaptive sampling for high-volume packet_rx/tx.

---
Telemetry or it didn’t happen.
