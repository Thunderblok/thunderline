# ⚔️ TOCP Presence Security — Battle Plan (v0.1)
**Codename:** Operation Iron Veil  
**Audience:** Warden & Prometheus Lines  
**Status:** Ratified (Scaffold Integrated)  
**Scope:** Presence security posture for the Thunderline Open Circuit Protocol (TOCP).

---

## 🎯 Objectives
1. **Don’t leak identity or topology** through presence.
2. **Make abuse expensive** (rate, credit, admission, proof).
3. **Contain blast radius** (zones, supervisors, kill-switch).
4. **Add crypto where it matters first** (control frames), then scale to full session crypto.

---

## ✅ MVP Controls (Ship Now)
### Identity & Minimization
- **Pseudonymous NodeID** = `Ed25519 pubkey → BLAKE3 (truncated)`; never include raw public key in clear payloads.
- **Zone privacy**: advertise `ZoneID = blake3(slug)` only; never the human slug.
- Presence beacons carry **no PII, no software versions, no capability lists** beyond a tiny bitmask.

### Integrity & Replay
- **Sign control frames** (ANNOUNCE/ADVERTISE/ACK) with Ed25519; data frames may be unsigned initially.
- **Replay window**: `(src, mid, ts)` LRU with **30s skew**; drop stale or duplicates.
- **Versioned header** with reserved **ENCRYPT** and **SOFT-ENC** flags (wire forward-compat).

### Admission & Sybil Friction
- **Join tokens (short-lived bearer)** issued by Gate or seed relay per zone; **no token → no gossip acceptance**.
- Optional **proof-of-work** on ANNOUNCE (~50–150ms) under abuse.
- **One-node-many-zones ban**: cap zones per node; require separate token per zone.

### Abuse Controls & DoS
- **Credits + token buckets**: per-peer & per-zone rate guards.
- **Heartbeat sampling** 1/20 (auto-raise to 1/5 under churn) and piggyback budget ≤ **512B**.
- **Fragment caps**: `8 assemblies/peer`, `256 global`; drop oldest on pressure.
- **Relay hysteresis** **15%** to stop route flaps.
- **Backoff ladder** for retry storms; hard cutoff after **5** retries.

### Topology Containment
- **Zones = blast domains**. Presence, credits, and store limits are per-zone.
- **Feature flag**: `:tocp` and **per-zone kill-switch** — drop a zone with one config flip.
- **Quarantine state** in Membership: misbehaving nodes only receive minimal control traffic.

### Telemetry & Tripwires
Emit counters & events:
- `tocp.security.sig_fail`, `tocp.security.replay_drop`, `tocp.rate.drop`,
  `tocp.fragments.evicted`, `tocp.routing.relay_switch_rate`, `tocp.delivery.dup_rx`.

Default alert actions (telemetry hooks in-progress):
- `sig_fail > 3/s` → auto-quarantine sender **60s** (counter via Aggregator).
- `rate.drop > 5%` on a zone → halve zone credits **30s**.
- `relay_switch_rate > 5%/min` (steady) → raise hysteresis to **25%** for **5m** (driven by `routing.relay_switch_rate`).

---

## 🔒 Next Hardening (v1.1 — Fast Follow)
### Transport Security
- **Noise-XK** sessions for relays/peers (control+data) with key pinned to NodeID.
- **Batch verify** control-frame cohorts to amortize Ed25519 cost.

### Privacy & Unlinkability
- **Ephemeral NodeIDs per zone** (rotate daily or on rekey), bound to a long-term DID via **blinded tokens**.
- **Store-and-forward sealing**: payload AEAD with per-zone session key (relays see headers only).

### Anti-Enumeration
- **Gossip cover**: fake heartbeat timing jitter + random no-op piggybacks at low traffic.
- **Sparse answers** to membership queries; never return full maps.

### Admission Evolution
- Swap bearer join tokens for **caveated macaroons** (zone, TTL, rate caps).
- Optional **stake/attest** path for privileged relays (KMS or Web5 DID doc check).

---

## ⚙️ Config Defaults (Security-Tilted)
Preferred conceptual map form:
```elixir
config :thunderline, :tocp, %{
  enabled: false,
  presence_secured: true,
  admission_required: true,
  replay_skew_ms: 30_000,
  security_sign_control: true,
  security_soft_encrypt_flag: :reserved,
  gossip: %{interval_ms: 1_000, jitter_ms: 150, k_mode: :auto},
  reliable: %{window: 32, ack_batch_ms: 10, max_retries: 5},
  ttl: %{default: 8},
  credits: %{initial: 64, min: 8},
  rate: %{tokens_per_sec_peer: 200, tokens_per_sec_zone: 1_000, bucket_size_factor: 2},
  fragments: %{max_chunk: :dynamic, max_assemblies_peer: 8, global_cap: 256},
  selector: %{hysteresis_pct: 15}
}
```
Current scaffold (keyword list) equivalent resides in `config/config.exs`; translation maintained until we refactor to the map style.

**Env Overrides:** `FEATURE_TOCP=1` (enable domain), `FEATURE_TOCP_PRESENCE_INSECURE=1` (ALLOWED only for perf tests; emits one-shot telemetry `[:tocp,:security,:insecure_mode]` & boot WARN) – relaxes `security_sign_control` & replay enforcement for benchmark profiles only unless `ALLOW_INSECURE_TESTS=true` gating CI.

---

## 🧪 Simulator Scenarios (Security Suite)
| Scenario | Expectation |
|----------|-------------|
| Sybil Swarm (1k bogus w/out token) | 0 admitted, relay CPU <15% |
| Replay Flood | `replay_drop` increments, quarantine <500ms |
| Fragment Exhaust | Global cap trips, zone stable |
| ACK Abuse | Loss <0.5%, retries bounded |
| Topology Probe | Sparse responses + quarantine |
| Credit Drain | Token buckets throttle; router healthy |

Sim Artifact: `mix tocp.sim.run --out sim_report.json` → includes aggregated `security.sig_fail`, `security.replay_drop`, planned `quarantined_nodes` count & pass/fail flags.

---

## 🛠️ Dev Orders (Actionable)
### Control Frame Crypto (Implemented Scaffold)
- `Security.Impl` provides Ed25519 sign/verify via JOSE; ANNOUNCE/ADVERTISE/ACK integration pending wire path.
- Telemetry emission `security.sig_fail` implemented.

### Replay Window (Implemented Scaffold)
- ETS window + pruning task (`Security.Pruner`) active; ingestion hook TODO.

### Admission Gate
- `Membership.admit?/2` validates zone join token (Gate stub for now).

### Quarantine Path
- `Membership.quarantine/2`; `Router.inbound/3` returns `{:error, :quarantined}`.
- Telemetry (planned): `[:tocp,:security,:quarantine]` with %{count: 1, node: id, reason: r}

### Dynamic Hysteresis (Partial)
- `Routing.SwitchTracker` emits `routing.relay_switch_rate`; `HysteresisManager` scaffold will tune `hysteresis_pct`.

### Rate/Credit Guard (Pending)
- `FlowControl.allowed?/1` planned; `flow.rate.drop` emission not yet wired.

### Docs & CI
- Extend decisions & telemetry docs (done incrementally).
- CI archives `sim_report.json` and fails on red flags.

---

## 📊 Acceptance Gates (Security Edition)
1. Zero unsigned control frames admitted in sim.
2. Replay rejection ≥ 99.9% within skew.
3. Anomaly detection < 60s after simulated flood.
4. Telemetry coverage: 100% of persistent processes emit health metric.
5. SafeStop drains inflight < 2s under active attack.

---

## 🧩 Libraries & Hooks
- Crypto: Ed25519 via JOSE (pure BEAM fallback chosen after enacl build friction); BLAKE3 hashing TBD.
- Reserve Noise/macaroons/blinded tokens; provide stub flags.

---

## 🧭 Doctrine
> *Praesidium ante omnia.* We ship presence that reveals nothing sensitive, admits only the invited, starves abusers, and fails closed per zone. Metrics are our perimeter. If it can’t be simulated, it isn’t secured.

---

## 🗂 Changelog Template
```
Added: (security features, telemetry events)
Changed: (tuning of defaults, hysteresis adjustments)
Fixed: (edge-case replay classification, fragment eviction leak)
Security: (tripwire thresholds, new telemetry counters)
Docs: (DIP refs, decisions updated, Operation Iron Veil brief added)
```

---
Owner: Prometheus-Net  | Security Liaison: Warden-Wire  | Telemetry Steward: Sibyl-Eyes
