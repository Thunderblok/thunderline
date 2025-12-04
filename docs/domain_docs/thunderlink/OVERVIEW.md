# ThunderLink Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thunderlink/domain.ex`  
**Vertex Position**: Data Plane Ring — Transport Layer

## Purpose

ThunderLink is the **communication and networking domain** of Thunderline:
- Protocol bus, broadcast, and federation
- Real-time messaging and presence
- WebRTC voice/video signaling
- Cross-realm federation
- Node registry and cluster topology

**Design Principle**: "Link does delivery, not meaning" — no transformations beyond envelope/serialization.

## Domain Extensions

```elixir
use Ash.Domain,
  extensions: [AshAdmin.Domain, AshOban.Domain, AshGraphql.Domain, AshTypescript.Rpc]
```

- **AshAdmin** — Admin dashboard enabled
- **AshOban** — Background job processing
- **AshGraphql** — GraphQL queries/mutations for Ticket
- **AshTypescript.Rpc** — TypeScript RPC generation

## Directory Structure

```
lib/thunderline/thunderlink/
├── domain.ex                    # Main Ash domain (18 resources)
├── supervisor.ex                # Domain supervisor
├── registry.ex                  # Registry management
├── topics.ex                    # PubSub topics
├── tick_generator.ex            # Tick generation
├── dashboard_metrics.ex         # Dashboard metrics
├── http.ex                      # HTTP utilities
├── thunder_bridge.ex            # Bridge module
├── thunder_websocket_client.ex  # WebSocket client
├── chat/                        # Chat subdomain (separate Ash Domain)
│   ├── chat.ex                  # Chat domain definition
│   ├── conversation.ex          # Conversation resource
│   ├── conversation/changes/    # Ash changes
│   ├── message.ex               # Message resource
│   └── message/changes/         # Ash changes
├── presence/                    # Presence management (2 files)
│   ├── enforcer.ex
│   └── policy.ex
├── resources/                   # Core Ash resources (11 files)
│   ├── channel.ex
│   ├── community.ex
│   ├── federation_socket.ex
│   ├── heartbeat.ex
│   ├── link_session.ex
│   ├── message.ex
│   ├── node.ex
│   ├── node_capability.ex
│   ├── node_group.ex
│   ├── node_group_membership.ex
│   ├── role.ex
│   └── ticket.ex
├── transport/                   # Transport layer (14+ files)
│   ├── admission.ex, config.ex, flow_control.ex
│   ├── fragments.ex, membership.ex, reliability.ex
│   ├── router.ex, store.ex, wire.ex
│   ├── routing/
│   ├── security.ex, security/
│   └── telemetry.ex, telemetry/
└── voice/                       # Voice/WebRTC (5 files)
    ├── room.ex, participant.ex, device.ex
    ├── room_pipeline.ex, supervisor.ex
    └── calculations/
```

## Registered Ash Resources

### Main Domain (18 resources)

#### Support/Communication Resources
| Resource | Module | File |
|----------|--------|------|
| Ticket | `Thunderline.Thunderlink.Resources.Ticket` | resources/ticket.ex |
| Channel | `Thunderline.Thunderlink.Resources.Channel` | resources/channel.ex |
| Community | `Thunderline.Thunderlink.Resources.Community` | resources/community.ex |
| FederationSocket | `Thunderline.Thunderlink.Resources.FederationSocket` | resources/federation_socket.ex |
| Message | `Thunderline.Thunderlink.Resources.Message` | resources/message.ex |
| Role | `Thunderline.Thunderlink.Resources.Role` | resources/role.ex |

#### Voice/WebRTC Resources
| Resource | Module | File |
|----------|--------|------|
| Room | `Thunderline.Thunderlink.Voice.Room` | voice/room.ex |
| Participant | `Thunderline.Thunderlink.Voice.Participant` | voice/participant.ex |
| Device | `Thunderline.Thunderlink.Voice.Device` | voice/device.ex |

#### Node Registry & Cluster Topology
| Resource | Module | File |
|----------|--------|------|
| Node | `Thunderline.Thunderlink.Resources.Node` | resources/node.ex |
| Heartbeat | `Thunderline.Thunderlink.Resources.Heartbeat` | resources/heartbeat.ex |
| LinkSession | `Thunderline.Thunderlink.Resources.LinkSession` | resources/link_session.ex |
| NodeCapability | `Thunderline.Thunderlink.Resources.NodeCapability` | resources/node_capability.ex |
| NodeGroup | `Thunderline.Thunderlink.Resources.NodeGroup` | resources/node_group.ex |
| NodeGroupMembership | `Thunderline.Thunderlink.Resources.NodeGroupMembership` | resources/node_group_membership.ex |

### Chat Subdomain (Separate Ash Domain)

Located at `chat/chat.ex` — `Thunderline.Thunderlink.Chat`:

```elixir
use Ash.Domain, otp_app: :thunderline, extensions: [AshAdmin.Domain, AshPhoenix]
```

| Resource | Module | File |
|----------|--------|------|
| Conversation | `Thunderline.Thunderlink.Chat.Conversation` | chat/conversation.ex |
| Message | `Thunderline.Thunderlink.Chat.Message` | chat/message.ex |

**Note**: Two separate Message resources exist:
- `Thunderline.Thunderlink.Resources.Message` (main domain)
- `Thunderline.Thunderlink.Chat.Message` (chat subdomain)

## GraphQL Endpoints

```elixir
queries do
  get Ticket, :get_ticket, :read
  list Ticket, :list_tickets, :read
end

mutations do
  create Ticket, :create_ticket, :open
  update Ticket, :close_ticket, :close
  update Ticket, :process_ticket, :process
  update Ticket, :escalate_ticket, :escalate
end
```

## TypeScript RPC

```elixir
typescript_rpc do
  resource Ticket do
    rpc_action(:list_tickets, :read)
    rpc_action(:create_ticket, :open)
  end
end
```

## Code Interfaces (Domain-level)

### Node Registry
| Function | Resource | Action |
|----------|----------|--------|
| `register_node` | Node | :register |
| `mark_node_online` | Node | :mark_online |
| `mark_node_offline` | Node | :mark_offline |
| `mark_node_status` | Node | :update_status |
| `online_nodes` | Node | :online_nodes |
| `nodes_by_status` | Node | :read |
| `nodes_by_role` | Node | :read |
| `heartbeat_node` | Node | :heartbeat |

### Heartbeat
| Function | Resource | Action |
|----------|----------|--------|
| `record_heartbeat` | Heartbeat | :record |
| `recent_heartbeats` | Heartbeat | :recent |

### LinkSession
| Function | Resource | Action |
|----------|----------|--------|
| `active_link_sessions` | LinkSession | :active_sessions |
| `establish_link_session` | LinkSession | :mark_established |
| `update_link_session_metrics` | LinkSession | :update_metrics |
| `close_link_session` | LinkSession | :close |

### NodeCapability
| Function | Resource | Action |
|----------|----------|--------|
| `node_capabilities_by_capability` | NodeCapability | :read |

### Chat Subdomain
| Function | Resource | Action |
|----------|----------|--------|
| `create_conversation` | Conversation | :create |
| `get_conversation` | Conversation | :read (get_by: [:id]) |
| `list_conversations` | Conversation | :read |
| `message_history` | Message | :for_conversation |
| `create_message` | Message | :create |

## Authorization

```elixir
authorization do
  authorize :by_default
end
```

Enabled by default — policies must be defined on resources.

## Transport Layer

The transport/ directory implements the TOCP (Thunderline Open Circuit Protocol):

| Module | Purpose |
|--------|---------|
| Router | Transport routing behavior |
| Admission | Connection admission control |
| Config | Transport configuration |
| FlowControl | Flow control mechanisms |
| Fragments | Message fragmentation |
| Membership | Cluster membership |
| Reliability | Reliable delivery |
| Store | Transport storage |
| Wire | Wire protocol |
| Security | Transport security |
| Telemetry | Transport telemetry |

## Voice Signaling

| Module | Purpose |
|--------|---------|
| Room | Voice room configuration |
| Participant | Room participants |
| Device | Participant devices |
| RoomPipeline | Broadway pipeline for voice |
| Supervisor | Voice supervisor |

## Supporting Modules

| Module | Purpose | File |
|--------|---------|------|
| Registry | Node/session registry | registry.ex |
| Topics | PubSub topic management | topics.ex |
| TickGenerator | Tick generation | tick_generator.ex |
| DashboardMetrics | Dashboard metrics | dashboard_metrics.ex |
| ThunderBridge | Bridge module | thunder_bridge.ex |
| ThunderWebsocketClient | WS client | thunder_websocket_client.ex |

## Known Issues & TODOs

### 1. Duplicate Message Resources
Two Message resources exist:
- `Thunderline.Thunderlink.Resources.Message` (main domain - community messaging)
- `Thunderline.Thunderlink.Chat.Message` (chat subdomain - AI conversations)

Verify if this is intentional or should be consolidated.

### 2. Chat as Separate Domain
`Thunderline.Thunderlink.Chat` is a separate Ash Domain with AshPhoenix extension.
Consider whether this should remain separate or merge into main domain.

### 3. WARHORSE TODOs
Multiple TODOs related to policy re-enablement marked as "WARHORSE" throughout the codebase.

### 4. Dashboard Metrics
`dashboard_metrics.ex` has several TODO placeholders for metrics marked as "OFFLINE".

### 5. TOCP Feature Gate
TOCP transport remains feature-gated and disabled by default.

## Telemetry Events

- `[:thunderline, :thunderlink, :transport, :connected|:disconnected]`
- `[:thunderline, :thunderlink, :message, :sent|:delivered]`
- `[:thunderline, :thunderlink, :voice, :signal]`
- `[:thunderline, :thunderlink, :federation, :sync]`
- `[:thunderline, :tocp, :router, :route]`

## Development Priorities

1. **Policy Reinforcement** — Re-enable Ash policies, resolve "WARHORSE" annotations
2. **Transport Telemetry** — Implement dashboard metrics marked "OFFLINE"
3. **Federation Maturation** — Finalize TOCP transports
4. **Voice Evolution** — Integrate with ThunderFlow real-time pipeline

## Related Domains

- **ThunderGate** — Authentication and capability decisions
- **ThunderFlow** — Event publication from transport
- **ThunderBlock** — Message persistence
- **ThunderCrown** — Policy decisions and AI governance
- **ThunderGrid** — Spatial zone data for transport topology
