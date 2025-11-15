# ThunderLink Domain Overview

**Vertex Position**: Data Plane Ring — Transport Layer

**Purpose**: Real-time transport, presence, and federation layer that delivers messages, voice, and protocol traffic across Thunderline and external networks.

## Charter

ThunderLink provides the communication substrate for Thunderline. It manages WebSocket sessions, voice signaling, community channels, cross-realm federation, and the evolving TOCP transport. The domain guarantees reliable delivery, presence tracking, and telemetry for all user- and agent-facing interactions, while staying agnostic to business meaning (“Link does delivery, not meaning”).

## Core Responsibilities

1. **Realtime Transport** — maintain WebSocket, WebRTC, and custom protocol connections for dashboards, agents, and clients.
2. **Presence & Communities** — manage communities, channels, roles, and presence policies for collaborative features.
3. **Federation Gateway** — broker cross-realm communication through federation sockets and future TOCP transports.
4. **Voice Signaling** — provide signaling flows for voice rooms, participants, and devices (media pipeline emerging with Flow).
5. **Telemetry & Reliability** — capture transport metrics, queue states, and routing decisions for dashboards and anomaly detection.
6. **Protocol Evolution** — host the Thunderline Open Circuit Protocol (TOCP) scaffolding and ensure compatibility with future transports.

## Ash Resources

- [`Thunderline.Thunderlink.Resources.Community`](lib/thunderline/thunderlink/resources/community.ex:28) — defines collaborative spaces and metadata.
- [`Thunderline.Thunderlink.Resources.Channel`](lib/thunderline/thunderlink/resources/channel.ex:25) — channel-level metadata for messaging and broadcast.
- [`Thunderline.Thunderlink.Resources.Message`](lib/thunderline/thunderlink/resources/message.ex:26) — stores messages with references to communities and actors.
- [`Thunderline.Thunderlink.Resources.Role`](lib/thunderline/thunderlink/resources/role.ex:25) — captures roles and permissions for participants.
- [`Thunderline.Thunderlink.Resources.FederationSocket`](lib/thunderline/thunderlink/resources/federation_socket.ex:27) — establishes cross-instance communication channels.
- [`Thunderline.Thunderlink.Voice.Room`](lib/thunderline/thunderlink/voice/room.ex:8) — records voice room configuration and participants.

## Supporting Modules

- [`Thunderline.Thunderlink.Transport`](lib/thunderline/thunderlink/transport.ex:2) — facade bridging new transport implementations with legacy TOCP modules.
- [`Thunderline.Thunderlink.Transport.Router`](lib/thunderline/thunderlink/transport/router.ex:2) — routing behavior for transport traffic.
- [`Thunderline.Thunderlink.Transport.Telemetry.Aggregator`](lib/thunderline/thunderlink/transport/telemetry/aggregator.ex:1) — collects transport metrics.
- [`Thunderline.Thunderlink.Transport.Security`](lib/thunderline/thunderlink/transport/security/impl.ex:10) — pluggable transport security enforcement.
- [`Thunderline.Thunderlink.Chat`](lib/thunderline/thunderlink/chat.ex:1) — high-level messaging API bridging to Ash resources.
- [`Thunderline.Thunderlink.DashboardMetrics`](lib/thunderline/thunderlink/dashboard_metrics.ex:501) — produces metrics for dashboards (currently with several TODO placeholders).

## Integration Points

### Vertical Edges

- **Thundergate → ThunderLink**: capability and authentication decisions feed into Link to authorize transport sessions.
- **ThunderLink → ThunderFlow**: publishes `ui.command.*`, `voice.signal.*`, and other transport events to EventBus for downstream processing.
- **ThunderLink → ThunderBlock**: persists messages and presence state for durable history and compliance.
- **ThunderLink → ThunderCrown**: exposes communication metadata for policy decisions and AI governance.

### Horizontal Edges

- **ThunderLink ↔ ThunderFlow**: real-time pipeline broadcasts updates to connected clients; Flow feeds back telemetry for dashboards.
- **ThunderLink ↔ ThunderGrid**: consults spatial zone data when transport topology or edge placement matters.
- **ThunderLink ↔ ThunderCom**: legacy communication surface being merged—ThunderCom resources should eventually migrate here.
- **ThunderLink ↔ ThunderBolt**: streams execution updates, alerts, and user notifications from ThunderBolt pipelines.

## Telemetry Events

- `[:thunderline, :thunderlink, :transport, :connected|:disconnected]` — connection lifecycle events.
- `[:thunderline, :thunderlink, :message, :sent|:delivered]` — message flow metrics.
- `[:thunderline, :thunderlink, :voice, :signal]` — voice signaling activity.
- `[:thunderline, :thunderlink, :federation, :sync]` — federation socket synchronization.
- `[:thunderline, :tocp, :router, :route]` — TOCP routing telemetry (feature gated).

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| WebSocket message delivery | 15 ms | 80 ms | 10k/s |
| Voice signaling dispatch | 20 ms | 120 ms | 5k/s |
| Federation message relay | 40 ms | 200 ms | 1k/s |
| Presence update propagation | 25 ms | 150 ms | 5k/s |
| Transport telemetry emission | 10 ms | 60 ms | 20k/s |

## Security & Policy Notes

- Presence and messaging policies are under review; many were disabled (see “WARHORSE” TODOs). Reinstate Ash policies and align with Thundergate governance.
- Federation sockets must enforce capability checks before exchanging data with external realms.
- TOCP feature (`:tocp`) remains disabled by default; when enabled ensure the new security hooks (`Thunderline.Thundertgate` integration) are active.
- PII or sensitive payloads routed through ThunderLink should be encrypted at rest via ThunderBlock storage policies.

## Testing Strategy

- Unit tests for transport routing, security modules, and chat message changes.
- Integration tests covering WebSocket connection lifecycle, presence updates, and voice room signaling (`test/thunderline/thunderlink/voice/*.exs`).
- Property tests verifying message ordering and idempotency under retry scenarios.
- Load tests simulating large subscriber counts to validate telemetry and fanout stability.

## Development Roadmap

1. **Phase 1 — Policy Reinforcement**: re-enable Ash policies on communication resources and resolve “WARHORSE” annotations.
2. **Phase 2 — Transport Telemetry**: implement dashboard metrics currently marked as “OFFLINE” and integrate with Thunderwatch.
3. **Phase 3 — Federation Maturation**: finalize TOCP transports, enable feature flag in staging, and document operational playbooks.
4. **Phase 4 — Voice Evolution**: align voice signaling with ThunderFlow real-time pipeline and prepare for membrane/media pipeline integration.

## References

- [`lib/thunderline/thunderlink/domain.ex`](lib/thunderline/thunderlink/domain.ex:2)
- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:390)
- [`docs/documentation/HC_EXECUTION_PLAN.md`](docs/documentation/HC_EXECUTION_PLAN.md:60)
- [`docs/documentation/planning/tocp_thunderline_open_circuit_protocol_mvp_spec_v_0.md`](docs/documentation/planning/tocp_thunderline_open_circuit_protocol_mvp_spec_v_0.md:1)
- [`docs/documentation/docs/flower-power/domain-cleanup-report.md`](docs/documentation/docs/flower-power/domain-cleanup-report.md:142)