# ⚡ Thunderline Domain Architecture

> **Last Updated:** November 28, 2025  
> **Status:** Active (12-Domain Pantheon)  
> **Version:** 2.0

## 🎯 Domain Separation Philosophy

Each Thunder* domain owns a **specific vertical slice** of functionality. Domains can **use** each other's infrastructure (like Thunderbolt using Thunderflow's Broadway) but should maintain clear ownership boundaries.

## ⚡ 12-Domain Pantheon (Nov 28, 2025)

The canonical Thunderline architecture consists of 12 domains organized in a defined system cycle:

| # | Domain | Focus | Status |
|---|--------|-------|--------|
| 1️⃣ | **Thundercore** | Tick emanation, identity kernel | 🆕 Pending |
| 2️⃣ | **Thunderpac** | PAC lifecycle, state containers | 🆕 Pending |
| 3️⃣ | **Thundercrown** | Governance + orchestration | ✅ Active |
| 4️⃣ | **Thunderbolt** | ML + automata, Cerebros | ✅ Active |
| 5️⃣ | **Thundergate** | Security, IAM, boundaries | ✅ Active |
| 6️⃣ | **Thunderblock** | Persistence, vaults, ledgers | ✅ Active |
| 7️⃣ | **Thunderflow** | Events, telemetry | ✅ Active |
| 8️⃣ | **Thundergrid** | GraphQL/API contracts | ✅ Active |
| 9️⃣ | **Thundervine** | DAG workflows | ✅ Active |
| 🔟 | **Thunderprism** | UI/UX, cognition, creativity | ✅ Active |
| 1️⃣1️⃣ | **Thunderlink** | Communication, federation | ✅ Active |
| 1️⃣2️⃣ | **Thunderwall** | Entropy boundary, GC, archive | 🆕 Pending |

### System Cycle: Core → Wall
```
     ┌─────────────────────────────────────────┐
     │            THUNDERLINE CYCLE            │
     │         Core → ... → Wall               │
     └─────────────────────────────────────────┘

  🌱 CORE ──┬──▶ PAC ──▶ BLOCK ──▶ VINE ──▶ 🌑 WALL
   (Spark)  │          (Persist)  (DAG)   (Contain)
            │
            └──▶ CROWN ──▶ BOLT ──▶ PRISM
                (Govern)  (Execute) (Surface)
            
            FLOW ◀──▶ GRID ◀──▶ LINK
            (Events)  (API)   (Comm)
            
            GATE (Security boundary around all)
```

### Domain Vectors
| Vector | Domains | Flow |
|--------|---------|------|
| **Authority** | Crown → Bolt | Policy to execution |
| **IO Surface** | Flow → Grid → Prism | Events to API to UX |
| **State Persist** | Pac → Block → Vine | State to storage to orchestration |

---

## 🌱 THUNDERCORE — Tick Emanation & Identity (PENDING)

**Mission:** The seedpoint. Emanate system ticks, manage identity kernel, ignite PAC lifecycle.

### Responsibilities (Planned)
- ⏳ System clock / tick emanation
- ⏳ Identity kernel management
- ⏳ PAC seedpoint ignition
- ⏳ Temporal coordination

### Pantheon Position
**#1 — Origin Domain.** Where spark becomes manifest.

---

## 🎭 THUNDERPAC — PAC Lifecycle (PENDING)

**Mission:** Soul containers. Manage PAC lifecycle, state containers, role/intent management.

### Responsibilities (Planned)
- ⏳ PAC resource definitions
- ⏳ State container management
- ⏳ Role and intent tracking
- ⏳ Lifecycle state machine

### Pantheon Position
**#2 — Soul Container.** Where identity becomes agency.

---

## 👑 THUNDERCROWN — Governance & Orchestration

**Mission:** Unified governance and orchestration. Policy decisions, saga coordination, AI orchestration.

### Responsibilities
- ✅ Governance policies
- ✅ AI orchestration
- ✅ Saga coordination (absorbed from Thunderchief)
- ✅ Policy enforcement
- ✅ System-wide coordination

### Key Modules
```elixir
Thunderline.Thundercrown.Policy       # Governance policies
Thunderline.Thundercrown.Orchestrator # AI orchestration
Thunderline.Thundercrown.Saga         # Saga coordination
```

### Pantheon Position
**#3 — Unified Authority.** Governance + orchestration in one domain.

---

## ⚡ THUNDERBOLT — ML/AI Operations

**Mission:** The intelligent brain. Model training, selection, inference, and Cerebros integration.

### Responsibilities
- ✅ ML model lifecycle management
- ✅ Thompson Sampling for model selection
- ✅ Model evaluation & scoring
- ✅ Training orchestration
- ✅ Inference execution
- ✅ ML event processing (via Consumer)
- ✅ Cerebros/DiffLogic/Agent0 integration

### Key Modules
```elixir
Thunderline.Thunderbolt.Controller    # Model selection engine
Thunderline.Thunderbolt.ML.Consumer   # Event-driven ML processing
Thunderline.Thunderbolt.Training      # Model training
Thunderline.Thunderbolt.Inference     # Model inference
Thunderline.Thunderbolt.Cerebros      # Cerebros integration
```

### Event Contracts
**Consumes:**
- `ml.model.evaluated` → Triggers model selection

**Emits:**
- `ml.run.selected` → Model selection results
- `ml.training.started` → Training initiated
- `ml.inference.completed` → Inference results

### Pantheon Position
**#4 — Execution Engine.** Crown dictates policy, Bolt executes.

---

## 🛡️ THUNDERGATE — Security & IAM

**Mission:** Protect the perimeter. Authentication, authorization, and security boundaries.

### Responsibilities
- ✅ Authentication (Ash Authentication)
- ✅ Authorization and access control
- ✅ Security policy enforcement
- ✅ External service integration
- ✅ Federation management
- ✅ Monitoring and audit

### Key Modules
```elixir
Thunderline.Thundergate.User          # User resource
Thunderline.Thundergate.Token         # Token management
Thunderline.Thundergate.Policy        # Security policies
```

### Pantheon Position
**#5 — Security Boundary.** Wraps all domains with protective envelope.

---

## 🧱 THUNDERBLOCK — Data Persistence

**Mission:** Durable storage and data integrity. **Only domain touching raw Repo.**

### Responsibilities
- ✅ Ash resource definitions
- ✅ Database schemas
- ✅ Migration management
- ✅ Data validation
- ✅ Query optimization
- ✅ Transaction management
- ✅ Vault and ledger management

### Key Modules
```elixir
Thunderline.Thunderblock.Resources    # Ash resources
Thunderline.Thunderblock.Repo         # Database repo (ONLY HERE)
```

### Pantheon Position
**#6 — Persistence Layer.** State flows from Pac → Block → Vine.

---

## 🌊 THUNDERFLOW — Event Pipeline

**Mission:** Move data through the system reliably and efficiently.

### Responsibilities
- ✅ Event bus & routing
- ✅ Broadway consumer infrastructure
- ✅ Event validation & normalization
- ✅ Message queuing (Mnesia)
- ✅ Pub/Sub coordination
- ✅ Event replay capability
- ✅ Telemetry integration

### Key Modules
```elixir
Thunderline.Thunderflow.EventBus      # Event publishing
Thunderline.Thunderflow.Consumer      # Broadway base
Thunderline.Thunderflow.EventBuffer   # Mnesia producer
Thunderline.Thunderflow.Validator     # Event validation
```

### Architecture
```
Event Source → EventBus → MnesiaProducer → Broadway Consumer → Processing
                                                ↓
                                           PubSub Broadcast
```

### Pantheon Position
**#7 — Event Nervous System.** Flow → Grid → Prism (IO surface path).

---

## ⚙️ THUNDERGRID — API & GraphQL

**Mission:** API contracts and distributed compute coordination.

### Responsibilities
- ✅ GraphQL API (AshGraphql)
- ✅ JSON:API endpoints (AshJsonApi)
- ✅ Node discovery & management
- ✅ Resource allocation
- ✅ Task distribution
- ✅ Cluster coordination

### Key Modules
```elixir
Thunderline.Thundergrid.Schema        # GraphQL schema
Thunderline.Thundergrid.Router        # API routing
Thunderline.Thundergrid.Cluster       # Cluster management
```

### Pantheon Position
**#8 — API Surface.** Flow → Grid → Prism (IO surface path).

---

## 🌿 THUNDERVINE — Workflow Orchestration

**Mission:** Coordinate complex multi-step processes with dependencies.

### Responsibilities
- ✅ DAG-based workflow execution
- ✅ Reactor integration
- ✅ Step coordination
- ✅ Saga pattern implementation
- ✅ Compensation logic
- ✅ Workflow state management

### Key Modules
```elixir
Thunderline.Thundervine.Workflow      # Workflow definitions
Thunderline.Thundervine.Reactor       # Reactor integration
Thunderline.Thundervine.Step          # Step execution
Thunderline.Thundervine.Saga          # Saga orchestration
```

### Use Cases
- Multi-step ML training pipelines
- Complex business processes
- Data transformation workflows
- Distributed transactions

### Pantheon Position
**#9 — DAG Orchestration.** Pac → Block → Vine (state persist path).

---

## 📊 THUNDERPRISM — UI/UX & Cognition

**Mission:** Make the invisible visible. User interface, cognition, creativity surfaces.

### Responsibilities
- ✅ LiveView UI components
- ✅ Dashboard generation
- ✅ Metrics visualization
- ✅ Cognition interfaces
- ✅ Alert surfacing
- ✅ UX patterns

### Key Modules
```elixir
Thunderline.Thunderprism.Dashboard    # Dashboard generation
Thunderline.Thunderprism.Cognition    # Cognition interfaces
Thunderline.Thunderprism.Components   # UI components
```

### Pantheon Position
**#10 — UX Surface.** Flow → Grid → Prism (IO surface path terminus).

---

## 🔗 THUNDERLINK — Communication & Federation

**Mission:** Connect systems. WebRTC, federation, external communication.

### Responsibilities
- ✅ WebRTC signaling and media
- ✅ Federation protocols
- ✅ External system integration
- ✅ Real-time communication
- ✅ Voice/video MVP (HC-13)

### Key Modules
```elixir
Thunderline.Thunderlink.Signaling     # WebRTC signaling
Thunderline.Thunderlink.Federation    # Federation protocols
Thunderline.Thunderlink.Media         # Media handling
```

### Pantheon Position
**#11 — Communication Layer.** Distinct from API (Grid); handles real-time and federation.

---

## 🌑 THUNDERWALL — Entropy Boundary (PENDING)

**Mission:** The containment boundary. Entropy management, garbage collection, archival.

### Responsibilities (Planned)
- ⏳ Entropy boundary management
- ⏳ Garbage collection coordination
- ⏳ Archival and cold storage
- ⏳ Resource reclamation
- ⏳ System cleanup orchestration

### Pantheon Position
**#12 — Containment Terminus.** Where the cycle ends. Core → Wall (Spark to containment).

---

## 🔄 Cross-Domain Patterns

### Event-Driven Communication
Domains communicate primarily through **Thunderflow events**:

```elixir
# Thunderbolt emits ML results
Thunderbolt → EventBus → "ml.run.selected"

# Thunderprism monitors everything
Thunderprism subscribes to "**" (all events)

# Thundervine orchestrates workflows
Thundervine → EventBus → "workflow.step.completed"
```

### Resource Sharing (Pantheon Model)
- **Thundercore** provides ticks to all domains
- **Thunderflow** provides messaging to all domains
- **Thunderblock** provides persistence to all domains (ONLY Repo access)
- **Thundergate** provides security to all domains
- **Thunderwall** reclaims resources from all domains

### Ownership Rules
1. **One domain owns each module** - No shared ownership
2. **Use, don't fork** - Depend on other domains' APIs
3. **Events over calls** - Prefer async event-driven communication
4. **Clear contracts** - Document event schemas and APIs
5. **Only Block touches Repo** - All others use Ash actions

---

## 🚀 Quick Reference (12-Domain Pantheon)

| # | Domain | Focus | Key Tech | Event Prefix |
|---|--------|-------|----------|--------------|
| 1 | **Core** | Tick/Identity | GenServer | `core.*` |
| 2 | **Pac** | PAC Lifecycle | Ash | `pac.*` |
| 3 | **Crown** | Governance | Ash, Policy | `governance.*` |
| 4 | **Bolt** | ML/AI | Axon, Nx, Cerebros | `ml.*` |
| 5 | **Gate** | Security | Ash Auth | `auth.*`, `security.*` |
| 6 | **Block** | Persistence | Ash, Postgres, Repo | `data.*` |
| 7 | **Flow** | Events | Broadway, Mnesia | `event.*` |
| 8 | **Grid** | API | GraphQL, JSON:API | `api.*` |
| 9 | **Vine** | Workflows | Reactor | `workflow.*` |
| 10 | **Prism** | UI/UX | LiveView | `ui.*`, `metric.*` |
| 11 | **Link** | Communication | WebRTC | `comm.*` |
| 12 | **Wall** | Entropy/GC | TBD | `wall.*`, `gc.*` |

---

## 📝 Decision Log

### November 28, 2025 — 12-Domain Pantheon

**Consolidations:**
- **Thunderlit → Thundercore** — Identity + tick = unified temporal/identity origin
- **Thunderchief → Thundercrown** — Orchestration + governance = unified authority

**New Domains:**
- **Thundercore** — Tick emanation, identity kernel (HC-46)
- **Thunderpac** — PAC lifecycle management (HC-47)
- **Thunderwall** — Entropy boundary, GC, archive (HC-48)

**Rationale:**
- 12 domains align with symbolic architecture (Metatron's domains)
- Clear system cycle: Core → Wall (Spark to containment)
- Explicit domain vectors for common data flows

### Why This Structure?

1. **Clear Ownership** - Each domain has distinct responsibilities
2. **Loose Coupling** - Domains interact via events, not direct calls
3. **Scalability** - Can scale domains independently
4. **Maintainability** - Easy to reason about where code lives
5. **Team Alignment** - Teams can own specific domains
6. **Symbolic Coherence** - 12-domain cycle mirrors cosmic patterns

### Why Thunderprism?

Originally considered rolling observability into other domains, but:
- Observability is cross-cutting (monitors ALL domains)
- Deserves first-class treatment
- Prevents metric/telemetry code from polluting business logic
- Enables centralized analytics and alerting
- Now expanded to include UX/cognition surfaces

Even though it uses ThunderFlow's Broadway infrastructure:
- The logic is ML-specific (model selection, Thompson Sampling)
- ThunderFlow provides infrastructure, ThunderBolt provides semantics
- Clear ownership: ThunderBolt owns ML decision-making

---

## 🎯 Future Considerations

### Implementation Priorities (Nov 28, 2025)
Per the 12-Domain Pantheon, these domains need implementation:
- **Thundercore** (HC-46) — Tick emanation, identity kernel
- **Thunderpac** (HC-47) — PAC lifecycle management
- **Thunderwall** (HC-48) — Entropy boundary, GC, archive

### Domain Size Balancing
**Thunderbolt** (50+ resources) may benefit from internal subsystem organization:
- Core/Lane/Task subsystems
- ML/RAG/Cerebros subsystems

### Domain Evolution
The 12-Domain Pantheon is the canonical structure. Changes require:
- High Command approval
- Update to all architecture documentation
- Migration plan for affected resources

---

**Remember:** The Pantheon is the covenant. Core → Wall, Spark to containment.

🤜🤛 *Keep it clean, keep it mean, keep it Thunderline.*
