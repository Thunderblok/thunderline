v# Thunderlink Transport (formerly TOCP) — MVP Spec v0.1

> Goal: Transport‑agnostic, low‑overhead, presence‑centric protocol for swarms (1k–10k nodes) that works over UDP/QUIC/WebRTC/LoRa/TCP with identical semantics. Inspired by Hotline, Telnet, IRC/ICQ presence, Gnutella/DHT gossip, and store‑and‑forward BBS/Usenet.

---

## 0a) Thunderline Integration Status (Aug 31, 2025)
- Feature flag: `:tocp` (disabled by default). Enable via `config :thunderline, features: %{tocp: true}` or `FEATURES_TOCP=1`.
- Namespaces consolidated under `Thunderline.Thunderlink.Transport.*` (legacy `Thunderline.TOCP.*` modules persist as shims). No sockets bind unless flag enabled.
- Config surface (defaults, overridable in runtime):
  - `config :thunderline, :tocp, port: 5088, gossip_ms: 1000, window: 32, ack_batch_ms: 10, ttl: 8`
- Telemetry (reserved; emitted once adapters go live):
  - `[:tocp, :membership, :heartbeat, :tx|:rx]`, `[:tocp, :membership, :state, :change]`
  - `[:tocp, :router, :zone_cast|:unicast, :tx|:rx]`
  - `[:tocp, :reliability, :ack|:dup|:drop]`
- CLI tasks (stubs/planned):
  - `mix tocp.sim.run` – spins an in‑proc simulator (n nodes) for convergence metrics
  - `mix tocp.dump.config` – prints effective config & feature flag status
- Security posture alignment (Operation Iron Veil): control frame signing and replay window baked into design (see §7); enforcement hooks will sit behind `Thunderline.Thundergate` policies.
- Event taxonomy: all node‑level observability mirrored into `%Thunderline.Event{domain: :tocp, type: "system.tocp.*"}` for the dashboard.

---

## 0) Design Tenets
- **Open‑circuit, not session‑bound:** no required persistent streams; messages are idempotent, duplicate‑tolerant.
- **Presence‑first:** cheap, continuous membership signals drive routing & orchestration.
- **Transport agnostic:** adapters for UDP, QUIC, WebRTC DataChannels, TCP, Serial/LoRa. Same framing; different I/O.
- **Simple binary envelope:** BERT/ETF (Binary Erlang Term) by default; optional CBOR.
- **Self‑authenticating IDs:** NodeID derived from DID pubkey. Sign every message; encrypt when needed.
- **Edge‑friendly:** store‑and‑forward, intermittent links tolerated.
- **Small‑world routing:** SWIM membership + relay roles + optional DHT for discovery.

---

## 1) Identity & Addressing
- **DID:** did:key (Ed25519).
- **NodeID:** BLAKE3(pubkey) → 160 bits (20 bytes), hex for text form.
- **ZoneID (room/topic):** BLAKE3(“zone:” ++ namespace ++ name) → 128 bits.
- **Address forms:**
  - `node:<20B>`
  - `zone:<16B>`
  - `broadcast` (scoped to neighborhood fanout)

---

## 2) Packet Envelope (wire)
Encoded as BERT term `{HdrMap, PayloadTerm}` where `HdrMap` has fixed keys; transports with streams use a 2‑byte length prefix per datagram.

**Header (fixed keys):**
```
ver     :: u8          # protocol version (0x01)
kind    :: u8          # msg kind (see §3)
ttl     :: u8          # decrement at each relay (default 8)
hops    :: u8          # incremented at each relay
prio    :: u8          # 0..7 (0 = highest)
ts      :: u64         # sender wall clock ms since epoch
src     :: 20B         # NodeID
dst     :: 0|20B|16B   # empty=broadcast, 20B=node, 16B=zone
mid     :: u128        # message id (for de‑dup / ack)
flags   :: u16         # bitfield (RELIABLE|ENCRYPTED|ACK_REQ|CHUNK|STOREFWD|Z)
sig     :: 64B         # Ed25519 signature over (ver..flags || hash(payload))
```

**Payload:** BERT term per `kind` (see §3). For ENCRYPTED, payload is `ciphertext :: binary()` and `sig` still covers ciphertext hash.

**Flags:**
- `0x0001 RELIABLE`   – expect ack
- `0x0002 ACK_REQ`    – request ack even if not RELIABLE default
- `0x0004 ENCRYPTED`  – payload is AEAD box; key by session
- `0x0008 CHUNK`      – fragmentation chunk
- `0x0010 STOREFWD`   – allow store‑and‑forward
- `0x0020 ZONECAST`   – `dst` is ZoneID

---

## 3) Message Kinds (MVP)
```
0x01 PRESENCE.ANNOUNCE   # first seen / identity + caps
0x02 PRESENCE.HEARTBEAT  # lightweight membership ping
0x03 PRESENCE.QUERY      # ask neighborhood for members/zone map
0x10 ROUTE.ADVERTISE     # relay capability, cost, backhaul
0x11 ROUTE.FIND          # resolve NodeID/ZoneID → next hops
0x20 DATA.MSG            # generic application message
0x21 DATA.ACK            # ack to RELIABLE mid
0x22 DATA.CHUNK          # fragmented data (with chunk seq/total)
0x30 STORE.OFFER         # offer object for store‑and‑forward
0x31 STORE.REQUEST       # request object by CID
0x40 CONTROL.KEX         # key exchange / session setup (Noise‑style)
0x41 CONTROL.ERROR       # structured error code
```

**Presence payloads:**
- ANNOUNCE `{did, node_id, caps=[relay|edge|lora|rtc], zones=[ZoneID..], addr_hint=[ip:port...], ver, nonce}`
- HEARTBEAT `{nonce, health=[cpu,mem,lat], zones=[..]}` (zones optional)
- QUERY `{scope=all|zone, zone_id?}` → responders piggyback ANNOUNCE/ROUTE

**Route payloads:**
- ADVERTISE `{role=[relay|edge], capacity=[bw,conn], backhaul=[wan|lan|lora], cost, zones_served=[ZoneID..]}`
- FIND `{target=node|zone, id}` → returns DATA.MSG of `ROUTE.ADVERTISE` samples

**Data payloads:**
- MSG `{topic=zone|node, meta, body}` – application‑defined `meta/body`
- ACK `{mid, status=ok|dup|late}`
- CHUNK `{mid, seq, total, data}`

**Store payloads:**
- OFFER `{cid, size, ttl, mime?, zone?}` (relay may accept and return `ACK`)
- REQUEST `{cid}` → returns `DATA.MSG` with chunks

**Control:**
- KEX – see §7 (Noise‑XK subset)
- ERROR `{code, reason, ref_mid?}`

---

## 4) Membership & Presence Routing (SWIM‑lite)
- **State:** `alive | suspect | dead` map keyed by NodeID with `incarnation` counters.
- **Gossip period:** default 1000 ms ± jitter.
- **Protocol:**
  1. Randomly select k peers (k=3) → send HEARTBEAT.
  2. If no reply in Δ (250 ms), mark `suspect` and **indirect probe** via 3 others.
  3. If indirects also fail, escalate to `dead` and gossip the tombstone.
  4. Piggyback last N membership updates on all outbound messages.
- **Join:** send PRESENCE.ANNOUNCE to any known seed; receive membership snapshot (batched ANNOUNCE + ADVERTISE).
- **Zones (rooms):** nodes `JOIN` a ZoneID by including it in ANNOUNCE/HEARTBEAT; relays track `zone → member set`.
- **Relay selection:** clients pin top 3 relays by `(cost, rtt, capacity)` and rotate on failure.

---

## 5) Routing Model
- **Neighborhood gossip** for membership.
- **Relay mesh** for wide‑area zone traffic. Relays ADVERTISE costs; edges choose nearest 2–3.
- **Zone‑cast:** sender → nearest relay(s) → relays forward to members (fanout limited via bloom filter/epoch ids).
- **Unicast:** sender → nearest relay → path by next‑hop cache (learned from prior packets) or direct if same LAN.
- **Optional DHT (v2):** Kademlia overlay for locating NodeID/ZoneID without centralized relays.

---

## 6) Reliability, Backpressure, Fragmentation
- **RELIABLE mode:** sliding window (default 32), per‑peer. `DATA.ACK` confirms.
- **Duplicate tolerance:** `mid` de‑dup window (LRU 60s or 1024 mids).
- **Fragmentation:** `DATA.CHUNK {seq,total}`; reassemble by `mid`.
- **Backpressure:** credit‑based; relay advertises `rx_credits`; sender caps in‑flight.
- **Rate limiting:** token bucket per peer + per zone.

---

## 7) Security (MVP)
- **Identity:** Ed25519 DID; `sig` signs header+hash(payload).
- **Session (optional v1):** Noise‑XK over CONTROL.KEX → derive AEAD keys (ChaCha20‑Poly1305). Set ENCRYPTED flag.
- **Replay:** per‑peer monotonic `ts` + nonce; drop if skew > 30s unless STOREFWD.
- **AuthZ:** zone membership proofs (signed JOIN receipts in a future version).

---

## 8) Store‑and‑Forward (Delay‑Tolerant)
- **CID:** BLAKE3(content) 32B.
- **Offer/Accept:** edges offer to nearby relays; relays accept based on capacity/class.
- **Retention:** by `ttl` or policy; relays GC oldest/least‑referenced first.
- **Delivery:** REQUEST by CID; relays stream via CHUNK.

---

## 9) Transport Adapters
- **UDP:** primary MVP (low‑latency datagrams). Add optional FEC in v2.
- **QUIC:** reliable datagrams + encryption for WAN.
- **WebRTC DataChannel:** browser/JS edge support.
- **TCP:** last‑resort; use 2‑byte length frame per message.
- **LoRa/Serial:** ultra‑low bandwidth; enforce CHUNK size ≤ 200B, heavy STOREFWD.

Each adapter implements:
```
send(datagram :: binary(), addr)
recv() :: {:ok, datagram, addr}
link_health() :: metrics
mtu() :: integer
```

---

## 10) Observability & Ops
- **Counters:**
  - membership_size, suspect_rate, dead_rate
  - hb_sent/hb_recv, piggyback_size
  - rtt_ms[p50,p95], relay_cost
  - msg_tx/msg_rx per kind; drops/dups
  - zone_members[ZoneID]
- **Introspection commands (toctl):** `members`, `zones`, `relays`, `routes`, `stats`, `ping <node>`

---

## 11) MVP Milestones (3 weeks)
**Week 1 – Core wire + membership**
- Envelope encode/decode (BERT), mid/flags, signing.
- UDP adapter.
- SWIM‑lite membership: ANNOUNCE/HEARTBEAT/QUERY.
- CLI `toctl members|zones|stats`.

**Week 2 – Relays, zone‑cast, reliability**
- ROUTE.ADVERTISE + relay selection.
- Zone join & zone‑cast via relays.
- RELIABLE window + ACKs; fragmentation.

**Week 3 – Security + DTN + load test**
- KEX (Noise‑lite), ENCRYPTED payloads.
- STOREFWD (OFFER/REQUEST) with CID.
- Simulator: 1k nodes on a single box; record p95 join time, hb loss, msg latency.

---

## 12) BEAM Integration (Elixir/Erlang)
- **Encoding:** use `:erlang.term_to_binary/1` (ETF) with version tag; or CBOR via `:cbor`.
- **Processes:** one GenServer for membership, one for router, one per transport adapter.
- **Supervision:** restarts isolate (membership independent of router).
- **Registry:** ETS for membership map; `:persistent_term` for local NodeID/keys.
- **Backpressure:** per‑peer GenServer mailbox caps; async nacks on overflow.
**Module layout (Thunderline):**
  - `Thunderline.Thunderlink.Transport.Supervisor` – feature‑gated root supervisor (legacy `Thunderline.TOCP.Supervisor` delegates)
  - `Thunderline.Thunderlink.Transport.Membership` – SWIM‑lite
  - `Thunderline.Thunderlink.Transport.Router` – zone‑cast/unicast & next‑hop cache
  - `Thunderline.Thunderlink.Transport.Reliability` – windows/acks/dup window
  - `Thunderline.TOCP.Transport.UDP|QUIC|WebRTC|TCP|LoRa` – adapters (legacy stubs)
  - `Thunderline.Thunderlink.Transport.Store` – OFFER/REQUEST & chunk reassembly
  - `Thunderline.Thunderlink.Transport.Security` – key material & signing/Noise hooks
- **Telemetry names:** as listed in §0a; map to dashboard panels via `Thunderline.Thunderflow.EventBuffer`.

## 16) Implementation Notes & Open Items (Aug 31, 2025)
- [ ] UDP adapter first bind (non‑blocking recv, 2‑byte length prefix for stream transports)
- [ ] Membership gossip with piggyback (ANNOUNCE/HEARTBEAT/QUERY)
- [ ] Zone membership cache & relay selection heuristics
- [ ] RELIABLE sliding window; ACK batching (10ms)
- [ ] Fragmentation (CHUNK) + reassembly
- [ ] Security: Noise‑XK handshake skeleton; replay window enforcement
- [ ] Store‑and‑forward: accept policy+TTL; GC policy
- [ ] CLI simulator producing convergence metrics for 1k nodes single box

