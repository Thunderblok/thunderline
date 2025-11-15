# ThunderCom Domain Overview

**Vertex Position**: Data Plane Ring — Communication Content Surface

**Purpose**: Legacy communication layer that manages chat content, voice state, notifications, and federation messaging while ThunderLink assumes transport responsibilities.

## Charter

ThunderCom stores and orchestrates the semantic content of Thunderline’s communication features. It manages communities, channels, messages, voice rooms, and notifications. Although transport has moved to ThunderLink, ThunderCom remains the authoritative source of messaging data until migration completes. The domain ensures chat history, voice participation, and notification workflows remain intact during the ongoing consolidation.

## Core Responsibilities

1. **Community & Channel Management** — maintain membership, metadata, and moderation policies for collaborative spaces.
2. **Messaging Storage** — persist message content, attachments, and delivery metadata with audit and retention support.
3. **Voice Session State** — track voice rooms, participants, and devices, coordinating with ThunderLink for signaling.
4. **Federation Content Handling** — store federated messages and reconcile incoming/outgoing content with ThunderGate.
5. **Notification & Mailer Workflows** — manage email and in-app notifications for communication events.
6. **Migration Support** — provide compatibility shims and data access for the ongoing ThunderCom → ThunderLink merge.

## Ash Resources

- [`Thunderline.Thundercom.Resources.Community`](lib/thunderline/thundercom/resources/community.ex:28) — represents collaborative communities.
- [`Thunderline.Thundercom.Resources.Channel`](lib/thunderline/thundercom/resources/channel.ex:25) — channel entity with moderation and metadata.
- [`Thunderline.Thundercom.Resources.Message`](lib/thunderline/thundercom/resources/message.ex:26) — stores chat messages and state transitions.
- [`Thunderline.Thundercom.Resources.Role`](lib/thunderline/thundercom/resources/role.ex:25) — role definitions and permissions inside communities.
- [`Thunderline.Thundercom.Resources.FederationSocket`](lib/thunderline/thundercom/resources/federation_socket.ex:27) — federated communication records.
- [`Thunderline.Thundercom.Resources.VoiceRoom`](lib/thunderline/thundercom/resources/voice_room.ex:20) — tracks voice rooms, participants, and lifecycle events.
- [`Thunderline.Thundercom.Resources.VoiceParticipant`](lib/thunderline/thundercom/resources/voice_participant.ex:10) — participant state inside voice rooms.
- [`Thunderline.Thundercom.Resources.VoiceDevice`](lib/thunderline/thundercom/resources/voice_device.ex:10) — registered devices for voice communications.

## Supporting Modules

- [`Thunderline.Thundercom.Chat`](lib/thunderline/thundercom/notifications.ex:1) — high-level messaging helpers and notification triggers.
- [`Thunderline.Thundercom.Mailer`](lib/thunderline/thundercom/mailer.ex:1) — email delivery for communication events.
- [`Thunderline.Thundercom.Notifications`](lib/thunderline/thundercom/notifications.ex:1) — orchestrates in-app notifications for new messages or invites.
- [`Thunderline.Thundercom.Voice.RoomPipeline`](lib/thunderline/thundercom/voice/room_pipeline.ex:1) — manages voice room lifecycle events.

## Integration Points

### Vertical Edges

- **Thundergate → ThunderCom**: capability checks ensure only authorized actors create or read communication content.
- **ThunderCom → ThunderFlow**: publishes `communication.*` events that drive dashboards, analytics, and downstream automations.
- **ThunderCom → ThunderBlock**: persists chat history and voice transcripts into long-term storage with retention policies.
- **ThunderCom → ThunderLink**: hands off realtime delivery of messages and voice signaling to the transport layer.

### Horizontal Edges

- **ThunderCom ↔ ThunderLink**: ongoing migration—ThunderLink handles transport while ThunderCom continues to manage content.
- **ThunderCom ↔ ThunderBolt**: publishes alerts and status updates consumed by orchestration dashboards.
- **ThunderCom ↔ Thundervine**: contributes message events to the lineage graph to support compliance and replay.

## Telemetry Events

- `[:thunderline, :thundercom, :message, :created|:delivered]`
- `[:thunderline, :thundercom, :voice, :participant_joined|:left]`
- `[:thunderline, :thundercom, :notification, :sent]`
- `[:thunderline, :thundercom, :federation, :synced]`

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Message persistence | 12 ms | 70 ms | 5k/s |
| Notification enqueue | 20 ms | 120 ms | 2k/s |
| Voice participant update | 15 ms | 90 ms | 3k/s |
| Federation sync | 50 ms | 250 ms | 500/min |

## Security & Policy Notes

- Many communication policies were temporarily disabled during WARHORSE (see [`docs/documentation/docs/flower-power/domain-cleanup-report.md`](docs/documentation/docs/flower-power/domain-cleanup-report.md:112)); re-enable Ash policies to enforce tenant isolation.
- Ensure federated messages are sanitized and signed according to Thundergate rules before storage.
- Encryption at rest is handled by ThunderBlock; confirm retention and deletion jobs (ThunderBlock Timing) cover communication data.
- As ownership migrates to ThunderLink, maintain audit trails for the content that remains in ThunderCom to avoid drift.

## Testing Strategy

- Unit tests for message lifecycle, notification generation, and federation socket behavior.
- Integration tests verifying voice room operations, participant updates, and email workflows.
- Property tests ensuring message ordering and idempotency across federation syncs.
- Migration tests to validate ThunderCom-to-ThunderLink data export integrity.

## Development Roadmap

1. **Phase 1 — Policy Reinforcement**: re-enable Ash policies, update tenancy coverage, and align with Thundergate capability checks.
2. **Phase 2 — Migration Tooling**: build scripts and APIs to move content into ThunderLink while preserving history.
3. **Phase 3 — Observability**: add missing telemetry for message queues and voice sessions to assist dashboards.
4. **Phase 4 — Decommission Plan**: document conditions for retiring ThunderCom once all content is migrated.

## References

- [`lib/thunderline/thundercom`](lib/thunderline/thundercom/domain.ex:1)
- [`docs/documentation/docs/flower-power/domain-cleanup-report.md`](docs/documentation/docs/flower-power/domain-cleanup-report.md:93)
- [`THUNDERLINE_DOMAIN_CATALOG.md`](THUNDERLINE_DOMAIN_CATALOG.md:217)
- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:217)