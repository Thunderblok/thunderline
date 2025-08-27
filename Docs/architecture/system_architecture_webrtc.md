# Thunderline System Architecture (Aug 2025) – With Voice/WebRTC Flow

> This document extends the core architecture diagram to include the emerging Voice/WebRTC (HC-13) pathway: signaling, dynamic room pipelines, participant state, and future media processing surfaces (recording, transcription, VAD, AI intent derivation).

## High-Level Domains
- ThunderBlock: Persistence (Postgres, Mnesia), provisioning, memory services
- ThunderLink: Realtime comms (channels, communities, voice signaling)
- ThunderFlow: Event normalization, pipelines (Broadway), pub/sub fanout, DLQ
- ThunderBolt: Orchestration & compute (ThunderCell, DAG/Lane engines, workers)
- ThunderCrown: Governance, AI orchestration, MCP bus
- ThunderGate: Security, authn/z, policy, rate limiting, external ingress
- ThunderGrid: Spatial/ECS runtime (zones, topology, placement)
- Voice/WebRTC (emerges across Link + Flow): Signaling, room lifecycle, media pipeline (future)

## Voice/WebRTC Current MVP Scope
Implemented today:
- Phoenix Channel: `voice:*` (`ThunderlineWeb.VoiceChannel`) – signaling envelope relay
- Dynamic Supervisor: per-room `RoomPipeline` GenServer (placeholder for Membrane pipeline)
- Resources: `VoiceRoom`, `VoiceParticipant`, `VoiceDevice` (Ash Postgres models)
- Registry: `Thunderline.Thundercom.Voice.Registry`
- Events (new taxonomy entries): signaling (`voice.signal.*`), lifecycle (`voice.room.*`), transcription (`ai.intent.voice.transcription.segment` – future generation site)

Not yet implemented (planned surfaces):
- Actual `Membrane.WebRTC` elements inside pipeline
- Recording & artifact resource (`RecordingSession` / `MediaSegment`)
- Transcription worker + streaming segmentation events
- Voice activity detection (VAD) + speaking metrics -> `voice.room.speaking.*`
- AI co-host agent injection via ThunderCrown
- TURN/STUN infra (integration config placeholders)

## Updated Architecture Diagram (with Voice/WebRTC path)

```mermaid
flowchart LR
  classDef dom fill:#0a0a0a,stroke:#777,stroke-width:1px,color:#eaeaea,rx:8,ry:8;
  classDef svc fill:#171717,stroke:#666,color:#f2f2f2,rx:6,ry:6;
  classDef pipe fill:#0e1633,stroke:#6aa0ff,color:#ebf3ff,stroke-width:1px,rx:6,ry:6;
  classDef sec fill:#1a0e2b,stroke:#b77dff,color:#f6efff,rx:6,ry:6;
  classDef store fill:#0f1f1f,stroke:#4fd,color:#eaffff,rx:6,ry:6;
  classDef ui fill:#122012,stroke:#94f9a3,color:#eaffea,rx:6,ry:6;
  classDef ext fill:#2b150e,stroke:#ffb28a,color:#fff7f2,rx:6,ry:6;
  classDef media fill:#281c0f,stroke:#ffcf66,color:#fff9e8,rx:6,ry:6;

  user([User / Operator]):::ui
  pac([PAC Agent]):::ui
  extAPI[(External APIs\nLLMs / SaaS / Webhooks)]:::ext
  unikernel[(Rust/Firecracker\nUnikernel Pods)]:::ext
  turn[(TURN/STUN Service\n(future))]:::ext

  subgraph BLOCK[ThunderBlock — Infra & Storage]
    direction TB
    blkDash[Dashboard / Provisioner]:::ui
    blkSrv[Server / VM Manager]:::svc
    blkVault[(Thundervault\nPostgres + Mnesia + Files)]:::store
    blkMem[Memory Services / Profiles / Prefs / Secrets]:::svc
    blkCluster[Cluster Nodes & Schedulers]:::svc
  end
  class BLOCK dom

  subgraph LINK[ThunderLink — UX & Federation + Voice]
    direction TB
    lnkUI[Phoenix LiveView\nAutomataLive & Dash]:::ui
    lnkChan[Communities / Channels / Presence]:::svc
    voiceChan[VoiceChannel (signaling)\nvoice:* topics]:::svc
    voiceSup[Voice Supervisor\nDynamic Rooms]:::svc
    voiceRoom[RoomPipeline (GenServer)\nfuture: Membrane.WebRTC]:::media
    lnkOut[Integrations: Email / Chat / ActivityPub]:::svc
  end
  class LINK dom

  subgraph FLOW[ThunderFlow — Events & Telemetry]
    direction TB
    flowBus[EventBus\nEvent Struct]:::pipe
    flowEP[EventPipeline Broadway\nnormalize/batch/route]:::pipe
    flowX[CrossDomainPipeline]:::pipe
    flowRT[RealtimePipeline / PubSub]:::pipe
    flowDLQ[Dead-Letter / Retries]:::pipe
  end
  class FLOW dom

  subgraph BOLT[ThunderBolt — Orchestration & Compute]
    direction TB
    boltPlan[Plans / DAG Orchestrator]:::svc
    boltLane[Lane Engine]:::svc
    boltCell[ThunderCell / Automata Ops]:::svc
    boltJobs[Oban Jobs / Workers]:::svc
  end
  class BOLT dom

  subgraph CROWN[ThunderCrown — Governance & MCP]
    direction TB
    crnMCP[Hermes MCP Bus]:::svc
    crnAI[AshAI Workflows / Policy / Tool Select]:::svc
    crnSched[Task & Goal Scheduler]:::svc
  end
  class CROWN dom

  subgraph GATE[ThunderGate — Security & Integrations]
    direction TB
    gateAuth[Authn/Authz DID/Web5 or Firebase]:::sec
    gatePolicy[Policy Engine / Rate Limits]:::sec
    gateBridge[ThunderBridge Ingest]:::sec
    gateObs[Security Monitoring / Audit Logs]:::sec
    gateHyper[Hypervisor / Unikernel Manager]:::sec
  end
  class GATE dom

  subgraph GRID[ThunderGrid — Spatial & ECS]
    direction TB
    grdCoord[Spatial Coordinates / Zones]:::svc
    grdECS[ECS Runtime / Zone Workers]:::svc
    grdTopo[Grid Topology / Routing]:::svc
  end
  class GRID dom

  obs[Thundereye / Metrics / Traces]:::pipe
  dag[(ThunderDAG / Lineage)]:::store
  recStore[(Recordings + Transcripts\n(future artifacts))]:::store

  user -->|Sign-in| gateAuth
  gateAuth -->|Session + Claims| blkDash
  blkDash --> lnkUI
  lnkUI -->|User joins voice| voiceChan
  voiceChan -->|ensure room| voiceSup
  voiceSup --> voiceRoom

  %% Signaling path (current)
  voiceChan -->|offer/answer/ice| voiceRoom
  voiceRoom -->|broadcast signaling events| voiceChan
  turn -. network assist .-> voiceRoom

  %% Future media pipeline (dashed)
  voiceRoom -. RTP media (future) .-> recStore
  voiceRoom -. VAD events .-> flowBus
  voiceRoom -. transcription segments .-> crnAI

  %% Event flow integration
  voiceChan -->|emit voice.signal.*| flowBus
  voiceRoom -->|emit voice.room.*| flowBus
  flowBus --> flowEP
  flowEP -->|voice events| flowRT
  flowRT -->|UI updates| lnkUI

  %% Core orchestration
  lnkUI -->|Commands / Intents| crnMCP
  crnMCP --> crnAI --> crnSched --> boltPlan --> boltLane --> boltCell
  boltCell --> grdECS --> grdCoord --> grdTopo
  boltLane --> boltJobs -->|emit| flowBus

  %% Storage & observability
  blkSrv --> blkVault
  blkVault --> obs
  flowEP --> obs
  gateObs --> obs
  flowEP --> dag
  flowX --> dag

  %% Security / policy
  crnMCP -->|tool check| gatePolicy
  lnkOut -->|egress| gatePolicy
  gatePolicy -. audit .-> gateObs

  %% External integrations
  gateBridge --> extAPI
  lnkOut --> extAPI

  %% Agents & PAC
  pac -->|acts in zones| grdECS
  pac -->|requests tools| crnMCP
  pac -->|receives UI| lnkUI
```

### Legend
- Voice signaling currently rides Phoenix Channels + PubSub → normalized into events via ThunderFlow.
- Media plane not yet implemented; diagram shows dashed future edges (RTP ingestion, recording, transcription, VAD).
- TURN/STUN integration is external until we embed config (deployment dependent).

## Implementation Gap Analysis (Voice/WebRTC)
| Capability | Status | File(s) / Ref | Next Step |
|------------|--------|---------------|-----------|
| Room persistence & policy | Implemented | `voice_room.ex` | Add moderation roles / closures events emission |
| Participant tracking | Implemented | `voice_participant.ex` | Emit join/left events to EventBus |
| Device metadata | Implemented | `voice_device.ex` | Enrich w/ codec prefs & last RTT |
| Signaling channel | Implemented (basic) | `voice_channel.ex` | Add validation + size metrics + structured events |
| Dynamic room process | Implemented (stub) | `room_pipeline.ex` | Replace with Membrane pipeline supervision tree |
| WebRTC media negotiation | Not implemented | (N/A) | Introduce `Membrane.WebRTC.Endpoint` per room |
| Recording | Not implemented | (N/A) | Add `RecordingSession` resource + pipeline branch |
| Transcription (stream) | Not implemented | (N/A) | Integrate STT worker → emit `ai.intent.voice.transcription.segment` |
| VAD & speaking metrics | Not implemented | (stub events only) | Use RMS/energy or WebRTC stats → `voice.room.speaking.*` |
| TURN/STUN configuration | Not surfaced | env/deploy | Add config + health check event |
| Taxonomy voice events | Added | `EVENT_TAXONOMY.md` | Implement constructor validations |

## Recommended Near-Term Increment (Sprint Slice)
1. Emit taxonomy-compliant events from `VoiceChannel` + `RoomPipeline`.
2. Add lightweight Membrane pipeline (noop track accept) to validate integration.
3. Add linter rules for `voice.signal.*` and `voice.room.*` categories (extend Section 14 planned Mix task).
4. Append legend + voice focus excerpt to main README for stakeholder visibility.
5. Introduce feature flag `:enable_voice_media` gating Membrane supervision.

## Event Emission Sketch (Signaling Offer)
```elixir
with {:ok, event} <- Thunderline.Event.new(name: "voice.signal.offer", source: :link, payload: %{room_id: room_id, from: principal_id, sdp_type: "offer", size: byte_size(sdp)}) do
  Thunderline.EventBus.emit_realtime("voice.signal.offer", event)
end
```

## KPIs / Telemetry to Add
- Active voice rooms count
- Participants per room (distribution)
- Signaling latency (offer → answer) histogram
- ICE success rate (% of rooms with at least one successful candidate pair)
- Average speaking burst duration & concurrency
- Transcription segment latency (audio capture → text) (future)

---
Prepared for architectural review & resource justification (HC-13 acceleration).
