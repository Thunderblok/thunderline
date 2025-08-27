# Thunderline Domain Top‑Down Architecture (Aug 2025)

This document provides a top‑down (C4 Container + enriched flow) view across all active domains, key bridging modules, event pipelines, and representative resource groupings. It complements `system_architecture_webrtc.md` (voice/media focus) by emphasizing inter‑domain contractual flows and boundary ownership.

## 1. C4 Container View (Domains as Containers)

```mermaid
%% C4 style container diagram (simplified using Mermaid flowchart primitives)
flowchart TB
  %% Personas / External Systems
  user([User / Operator]):::actor
  agent([PAC / Autonomous Agent]):::actor
  extApis[(External APIs\nSaaS / LLM / Email / ActivityPub)]:::ext
  extFed[(Federated Peers)]:::ext

  %% Styling
  classDef domain fill:#121722,stroke:#4a5b78,stroke-width:1px,color:#e8eef7,rx:8,ry:8;
  classDef pipe fill:#0e1633,stroke:#6aa0ff,color:#ebf3ff,rx:6,ry:6;
  classDef actor fill:#1e2d18,stroke:#6ac46f,color:#defade,rx:30,ry:30;
  classDef ext fill:#2b150e,stroke:#ffb28a,color:#fff7f2,rx:10,ry:10;
  classDef bridge fill:#20201f,stroke:#d4b14a,color:#fff7d5,rx:6,ry:6,stroke-dasharray:3 2;
  classDef store fill:#0f1f1f,stroke:#4fd,color:#d9ffff,rx:6,ry:6;
  classDef svc fill:#171717,stroke:#666,color:#f2f2f2,rx:6,ry:6;

  subgraph GATE[ThunderGate – Security / Ingest / Audit]
    gateAuth[Auth / Tokens / Policy Rules]:::svc
    gateBridge[Ingest ThunderBridge\nExternal Normalization]:::bridge
    gateWatch[Thunderwatch (File Monitor)]:::svc
    gateAudit[Audit / Error / Metrics Resources]:::svc
  end
  class GATE domain

  subgraph LINK[ThunderLink – Realtime UX / Federation]
    linkUI[LiveView UI / Channels]:::svc
    linkVoice[VoiceChannel & RoomPipeline (signaling)]:::svc
    linkBridge[Dashboard ThunderBridge]:::bridge
    linkWS[WebSocket Client (federation)]:::svc
  end
  class LINK domain

  subgraph FLOW[ThunderFlow – Event Bus & Pipelines]
    flowBus[EventBus / Mnesia Store]:::pipe
    flowEP[EventPipeline (Broadway)]:::pipe
    flowRT[RealtimePipeline]:::pipe
    flowX[CrossDomainPipeline]:::pipe
    flowDLQ[Dead Letter / Retry]:::pipe
  end
  class FLOW domain

  subgraph BOLT[ThunderBolt – Compute / ML / Automata]
    boltCell[ThunderCell Cluster / CA Engine]:::svc
    boltErl[ErlangBridge]:::bridge
    boltNeuro[NeuralBridge / Cerebros]:::svc
    boltLane[Lane & DAG Orchestrators]:::svc
  end
  class BOLT domain

  subgraph CROWN[ThunderCrown – Governance / AI Orchestration]
    crownBus[MCP Bus]:::svc
    crownAI[Daisy / Policy / Workflow Orchestrator]:::svc
  end
  class CROWN domain

  subgraph BLOCK[ThunderBlock – Persistence / Provision]
    blkVault[(Vault: Knowledge / Memory / Embeddings)]:::store
    blkProv[Provisioning / Cluster Nodes]:::svc
    blkChk[Checkpoint & Query Opt]:::svc
  end
  class BLOCK domain

  subgraph GRID[ThunderGrid – Spatial / ECS]
    gridZones[Zones / Spatial Coord / Boundaries]:::svc
    gridECS[ECS Runtime Placement]:::svc
  end
  class GRID domain

  subgraph CHIEF[ThunderChief – Batch / Domain Processors]
    chiefDP[Domain Processor Workers / Jobs]:::svc
  end
  class CHIEF domain

  subgraph COM[ThunderCom (Legacy Chat Merge Surface)]
    comMsg[Channels / Messages / Roles]:::svc
    comVoice[Voice Resources (Rooms/Participants/Devices)]:::svc
  end
  class COM domain

  %% Flows
  user -->|Auth| gateAuth
  user -->|UI Interactions| linkUI
  agent --> gridECS
  agent -->|Tool Requests| crownBus
  linkUI -->|Commands / ui.command.*| flowBus
  linkVoice -->|voice.signal.*| flowBus
  comMsg -->|system.presence.*| flowBus
  crownAI -->|ai.intent.*| flowBus
  boltLane -->|compute events| flowBus
  gateBridge -->|normalized ingest| flowBus
  flowBus --> flowEP --> flowRT --> linkUI
  flowEP --> flowX --> boltLane
  flowEP --> flowDLQ
  flowX --> blkVault
  blkProv --> blkVault
  blkVault --> flowBus
  flowEP --> gridECS
  gridECS --> flowBus
  crownAI --> boltLane
  boltCell --> boltErl --> linkBridge
  linkBridge --> linkUI
  gateWatch --> flowBus
  gateAudit --> blkVault
  linkWS -->|federated events| flowBus
  extApis --> gateBridge
  extFed --> linkWS

  %% Observability global (not a domain node) could be implicit via flowBus instrumentation
```

### Notes
- Thunderwatch relocated under **ThunderGate** (security/audit boundary) – file events become `:thundergate` domain events feeding observability.
- Voice/WebRTC: signaling now lands in EventBus; future media pipeline (Membrane) will live adjacent to `linkVoice` and produce `voice.room.*` events.
- Dual ThunderBridge: `Thundergate.ThunderBridge` for external ingest; `Thunderline.ThunderBridge` (placed in ThunderLink in code) for dashboard/CA introspection (shown here as `linkBridge`).
- ThunderCom shown as a legacy/merge surface; resources progressively migrate under ThunderLink.

## 2. Enriched Flow Diagram (Expanded Resources Grouped)

```mermaid
flowchart LR
  classDef group fill:#10161f,stroke:#3a4d63,color:#d7e6f3,rx:6,ry:6;
  classDef res fill:#1d2530,stroke:#567,parent:none,color:#e3edf7,rx:4,ry:4;
  classDef pipe fill:#0e1633,stroke:#6aa0ff,color:#ebf3ff,rx:6,ry:6;
  classDef bridge fill:#20201f,stroke:#d4b14a,color:#fff7d5,rx:6,ry:6,stroke-dasharray:3 2;
  classDef store fill:#0f1f1f,stroke:#4fd,color:#d9ffff,rx:6,ry:6;
  classDef accent fill:#2d1f3a,stroke:#b77dff,color:#f6efff;

  subgraph Gate[ThunderGate]
    gPolicy[policy_rule\nalert_rule\nhealth_check]:::res
    gAudit[audit_log\nerror_log\nperformance_trace]:::res
    gExt[external_service\ndata_adapter\nfederated_realm]:::res
    gBridge[ThunderBridge ingest]:::bridge
    gWatch[Thunderwatch]:::res
  end

  subgraph Link[ThunderLink]
    lChan[channel\ncommunity\nrole]:::res
    lMsg[message\nticket]:::res
    lPac[pac_home]:::res
    lBridge[Dashboard ThunderBridge]:::bridge
    lVoice[voice_room\nvoice_participant\nvoice_device]:::res
  end

  subgraph Flow[ThunderFlow]
    fBus[EventBus/Mnesia]:::pipe
    fPipes[event_pipeline\nrealtime_pipeline\ncross_domain_pipeline]:::pipe
    fDLQ[dead_letter]:::pipe
    fLineage[lineage.edge\nconsciousness_flow]:::res
  end

  subgraph Bolt[ThunderBolt]
    bCell[thundercell cluster\nca_engine/bridge]:::res
    bLane[lane_* resources\nworkflow_dag]:::res
    bIsing[ising_* resources]:::res
    bModel[model_run\nmodel_artifact]:::res
    bNeuro[cerebros dataset/artifacts]:::res
  end

  subgraph Crown[ThunderCrown]
    cMCP[mcp_bus]:::res
    cAI[workflow_orchestrator\nai_policy]:::res
    cDaisy[daisy cognitive modules]:::res
  end

  subgraph Block[ThunderBlock]
    blkVault[vault_* (memory, knowledge, embeddings)]:::store
    blkProv[execution_container\nworkflow_tracker\nvault_agent]:::res
    blkUser[vault_user\nvault_user_token]:::res
  end

  subgraph Grid[ThunderGrid]
    grZones[grid_zone\nspatial_coordinate\nzone_boundary]:::res
    grState[chunk_state\nzone_event]:::res
  end

  subgraph Chief[ThunderChief]
    chJobs[domain_processor\nscheduled_workflow_processor]:::res
  end

  subgraph Com[ThunderCom]
    comRes[channel\ncommunity\nmessage]:::res
  end

  %% Flows
  lChan --> fBus
  lMsg --> fBus
  lVoice --> fBus
  gBridge --> fBus
  gWatch --> fBus
  cMCP --> fBus
  cAI --> fBus
  bLane --> fBus
  bCell --> fBus
  grZones --> fBus
  grState --> fBus
  fBus --> fPipes --> lChan
  fPipes --> blkVault
  fPipes --> bLane
  fPipes --> grZones
  fPipes --> cAI
  fPipes --> fDLQ
  blkVault --> fBus
  bModel --> blkVault
  bNeuro --> blkVault
  cAI --> bLane
  bLane --> bCell
  chJobs --> fBus
  lBridge --> lChan
```

### Legend / Semantics
- Arrows represent primary event or command flow (logical, not necessarily direct function calls).
- Event normalization occurs at `fBus` (EventBus) → `fPipes` enforce taxonomy & routing.
- Block vault resources supply both long‑term state and ML feature memory to Bolt & Crown.
- Crown orchestrates (policy + intent) → Bolt executes (compute) → Flow publishes outcomes.
- Grid provides spatial & ECS placement context; voice agents (future) may target specific zones.

## 3. Domain Relationship Matrix (Summary)

| From | To | Mechanism | Purpose |
|------|----|----------|---------|
| ThunderLink | ThunderFlow | EventBus publish (`ui.command.*`, `voice.signal.*`) | User intents & signaling |
| ThunderGate | ThunderFlow | Ingest bridge normalization | External events & audit signals |
| Thunderwatch (Gate) | ThunderFlow | File change events | Dev/ops observability |
| ThunderCrown | ThunderFlow | `ai.intent.*` events | AI interpretation / governance |
| ThunderBolt | ThunderFlow | Compute lifecycle events | Progress, telemetry, orchestrated outputs |
| ThunderFlow Pipelines | ThunderLink | RealTimePipeline PubSub | UI updates / push notifications |
| ThunderFlow Pipelines | ThunderBolt | CrossDomainPipeline dispatch | Scheduling compute tasks |
| ThunderFlow Pipelines | ThunderBlock | Persistence writes | Durable event lineage / memory enrichment |
| ThunderBolt | ThunderBlock | Model & run artifacts | Persistence & retrieval |
| ThunderBlock | ThunderFlow | New/updated vault knowledge events | Downstream ML & orchestration triggers |
| ThunderCrown | ThunderBolt | Direct calls + events | Plan → execution orchestration |
| ThunderGrid | ThunderFlow | Spatial events | Topology change, zone lifecycle |
| ThunderChief | ThunderFlow | Batch job events | Periodic orchestration / maintenance |

## 4. Resource Coverage Note
Full resource lists are intentionally grouped to keep diagrams legible. For exhaustive per‑resource references see `lib/thunderline/<domain>/resources/` folders. When a new resource is added:
1. Assign its emitting/consuming domains.
2. Decide if it produces events; update taxonomy if new category.
3. Append it to the appropriate grouping node (or create a new grouping if it becomes crowded (>12 names)).

## 5. Next Suggested Enhancements
| Area | Enhancement | Rationale |
|------|-------------|-----------|
| EventBus | Implement `publish_event/1` helper (HC-01) | Enforce envelope invariants |
| Voice | Add `voice.room.*` emissions & Membrane pipeline | Complete signaling → media path |
| Thunderwatch | Emit `system.audit.file.changed` canonical event | Structured audit correlation |
| Crown ↔ Bolt | Trace IDs propagated in orchestrated runs | End‑to‑end latency attribution |
| DLQ | Surfacing DLQ stats in dashboard | Operational readiness (HC-09) |
| Feature Flags | Implement `Thunderline.Feature.enabled?/1` helper | Governance & toggle clarity |

---
Prepared for stakeholder review & domain boundary validation. Update this document whenever a new domain flow or bridging surface is introduced.
