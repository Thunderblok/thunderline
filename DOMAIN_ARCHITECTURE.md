# ⚡ Thunderline Domain Architecture

> **Last Updated:** November 14, 2025  
> **Status:** Active  
> **Version:** 1.0

## 🎯 Domain Separation Philosophy

Each Thunder* domain owns a **specific vertical slice** of functionality. Domains can **use** each other's infrastructure (like ThunderBolt using ThunderFlow's Broadway) but should maintain clear ownership boundaries.

## 📊 THUNDERPRISM - Observability & Analytics

**Mission:** Make the invisible visible. Monitor, measure, and understand system behavior.

### Responsibilities
- ✅ Metrics collection & aggregation
- ✅ Telemetry pipeline management
- ✅ Performance monitoring
- ✅ Alert generation & routing
- ✅ Distributed tracing
- ✅ Anomaly detection
- ✅ Dashboard generation

### Key Modules
```elixir
Thunderline.Thunderprism.Metrics      # Metric collection
Thunderline.Thunderprism.Telemetry    # Telemetry handlers
Thunderline.Thunderprism.Alerts       # Alert management
Thunderline.Thunderprism.Trace        # Distributed tracing
```

### Integrations
- Hooks into ThunderFlow events for pipeline metrics
- Monitors ThunderBolt ML model performance
- Tracks ThunderGrid resource utilization
- Observes ThunderVine workflow execution

---

## ⚡ THUNDERBOLT - ML/AI Operations

**Mission:** The intelligent brain. Model training, selection, and inference.

### Responsibilities
- ✅ ML model lifecycle management
- ✅ Thompson Sampling for model selection
- ✅ Model evaluation & scoring
- ✅ Training orchestration
- ✅ Inference execution
- ✅ ML event processing (via Consumer)

### Key Modules
```elixir
Thunderline.Thunderbolt.Controller    # Model selection engine
Thunderline.Thunderbolt.ML.Consumer   # Event-driven ML processing
Thunderline.Thunderbolt.Training      # Model training
Thunderline.Thunderbolt.Inference     # Model inference
```

### Event Contracts
**Consumes:**
- `ml.model.evaluated` → Triggers model selection

**Emits:**
- `ml.run.selected` → Model selection results
- `ml.training.started` → Training initiated
- `ml.inference.completed` → Inference results

### Infrastructure Usage
- **Uses ThunderFlow:** Broadway consumer for event processing
- **Uses ThunderVine:** Workflow orchestration for training pipelines
- **Uses ThunderGrid:** Distributed training across nodes

---

## 🌿 THUNDERVINE - Workflow Orchestration

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

---

## ⚙️ THUNDERGRID - Distributed Compute

**Mission:** Harness distributed resources for parallel computation.

### Responsibilities
- ✅ Node discovery & management
- ✅ Resource allocation
- ✅ Task distribution
- ✅ Load balancing
- ✅ Fault tolerance
- ✅ Cluster coordination

### Key Modules
```elixir
Thunderline.Thundergrid.Cluster       # Cluster management
Thunderline.Thundergrid.Scheduler     # Task scheduling
Thunderline.Thundergrid.Resources     # Resource tracking
```

### Integration Points
- Distributes ThunderBolt training jobs
- Executes ThunderVine workflows across nodes
- Provides compute resources to all domains

---

## 🌊 THUNDERFLOW - Event Pipeline

**Mission:** Move data through the system reliably and efficiently.

### Responsibilities
- ✅ Event bus & routing
- ✅ Broadway consumer infrastructure
- ✅ Event validation & normalization
- ✅ Message queuing (Mnesia)
- ✅ Pub/Sub coordination
- ✅ Event replay capability

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

---

## 🧱 THUNDERBLOCK - Data Persistence

**Mission:** Durable storage and data integrity.

### Responsibilities
- ✅ Ash resource definitions
- ✅ Database schemas
- ✅ Migration management
- ✅ Data validation
- ✅ Query optimization
- ✅ Transaction management

### Key Modules
```elixir
Thunderline.Thunderblock.Resources    # Ash resources
Thunderline.Thunderblock.Repo         # Database repo
```

---

## 🔄 Cross-Domain Patterns

### Event-Driven Communication
Domains communicate primarily through **ThunderFlow events**:

```elixir
# ThunderBolt emits ML results
ThunderBolt → EventBus → "ml.run.selected"

# ThunderPrism monitors everything
ThunderPrism subscribes to "**" (all events)

# ThunderVine orchestrates workflows
ThunderVine → EventBus → "workflow.step.completed"
```

### Resource Sharing
- **ThunderGrid** provides compute to all domains
- **ThunderFlow** provides messaging to all domains
- **ThunderBlock** provides persistence to all domains
- **ThunderPrism** observes all domains

### Ownership Rules
1. **One domain owns each module** - No shared ownership
2. **Use, don't fork** - Depend on other domains' APIs
3. **Events over calls** - Prefer async event-driven communication
4. **Clear contracts** - Document event schemas and APIs

---

## 🚀 Quick Reference

| Domain | Focus | Key Tech | Event Prefix |
|--------|-------|----------|--------------|
| **Prism** | Observability | Telemetry, Metrics | `metric.*`, `alert.*` |
| **Bolt** | ML/AI | Axon, Nx | `ml.*` |
| **Vine** | Workflows | Reactor | `workflow.*` |
| **Grid** | Distributed | libcluster | `cluster.*` |
| **Flow** | Events | Broadway, Mnesia | `event.*` |
| **Block** | Persistence | Ash, Postgres | `data.*` |

---

## 📝 Decision Log

### Why This Structure?

1. **Clear Ownership** - Each domain has distinct responsibilities
2. **Loose Coupling** - Domains interact via events, not direct calls
3. **Scalability** - Can scale domains independently
4. **Maintainability** - Easy to reason about where code lives
5. **Team Alignment** - Teams can own specific domains

### Why ThunderPrism?

Originally considered rolling observability into other domains, but:
- Observability is cross-cutting (monitors ALL domains)
- Deserves first-class treatment
- Prevents metric/telemetry code from polluting business logic
- Enables centralized analytics and alerting

### Why ML Consumer in ThunderBolt?

Even though it uses ThunderFlow's Broadway infrastructure:
- The logic is ML-specific (model selection, Thompson Sampling)
- ThunderFlow provides infrastructure, ThunderBolt provides semantics
- Clear ownership: ThunderBolt owns ML decision-making

---

## 🎯 Future Considerations

### Potential New Domains
- **ThunderForge** - Code generation & metaprogramming
- **ThunderShield** - Security & access control
- **ThunderVault** - Secrets & configuration management

### Domain Evolution
Domains may split/merge as system evolves:
- If a domain becomes too large → Split into focused sub-domains
- If domains have too much overlap → Merge and clarify boundaries
- Always favor **cohesion** over arbitrary separation

---

**Remember:** Domains are organizational tools. They serve the code, not the other way around. Adjust boundaries as needed to maintain clarity and reduce friction.

🤜🤛 *Keep it clean, keep it mean, keep it Thunderline.*
