# Comprehensive Domain Architecture Analysis
**Date**: November 24, 2025  
**Scope**: Complete domain-by-domain review, tick flow validation, resource boundary verification  
**Reviewer**: AI Architecture Assistant  
**Status**: 🔍 IN PROGRESS

---

## Executive Summary

### Critical Findings

1. **✅ CORRECT**: 8 core active domains with clear boundaries
2. **⚠️ ISSUE**: Thunderlink tick flow system NOT IMPLEMENTED
3. **⚠️ ISSUE**: Thunderblock registry concept exists but tick activation NOT WIRED
4. **⚠️ ISSUE**: Cerebros should be separate domain (currently buried in Thunderbolt)
5. **⚠️ ISSUE**: Helm chart structure missing (Thunderhelm exists but not as Helm)
6. **✅ CORRECT**: Domain separation between ML (Thunderbolt) and automata functions

### Architecture Vision vs Reality

**Your Vision:**
```
Server Start → Thunderlink Ticks Flow → Domains Activate → Thunderblock Registry Tracks Active Domains
              ↓                        ↓
        Heartbeat System        Domain Lifecycle Management
```

**Current Reality:**
```
Server Start → All Domains Start Immediately → No Tick Flow → No Activation Gating
              ↓
        Static Supervision Tree (no tick-based activation)
```

---

## 1. Domain-by-Domain Analysis

### 1.1 Thunderblock — Persistence & Infrastructure

**Location**: `lib/thunderline/thunderblock/`  
**Purpose**: Core persistence, storage, timing, checkpoints, DAG workflows  
**Resources**: 33 Ash resources  
**Status**: ✅ PROPERLY IMPLEMENTED

**Resource Categories**:
```elixir
# Vault Subsystem (13 resources)
- VaultKnowledgeNode, VaultEntity, VaultRelationship, VaultCluster
- VaultMemory, VaultQuery, VaultIndex, VaultEmbedding
- VaultMetadata, VaultSnapshot, VaultAudit, VaultPolicy, VaultReplication

# Infrastructure (8 resources)
- SystemCheckpoint, DAGSnapshot, MigrationRecord, DataRetention
- HealthMonitoring, ExecutionContainer, ClusterNode, ResourcePool

# Orchestration (4 resources)
- OrchestratorTaskNode, TaskEdge, WorkflowRegistry, JobQueue

# DAG Management (4 resources) - BEING MOVED TO THUNDERVINE
- DAGExecution, DAGDependency, DAGNode, WorkflowDefinition

# Timing (4 resources) - CONSOLIDATION IN PROGRESS
- ScheduledJob, CronExpression, JobExecution, JobHistory
```

**Domain File**: `lib/thunderline/thunderblock/domain.ex`
```elixir
defmodule Thunderline.Thunderblock.Domain do
  use Ash.Domain, extensions: [AshAdmin.Domain]
  
  resources do
    # 33 resources defined
  end
end
```

**✅ CORRECT IMPLEMENTATION**:
- Clear persistence boundary
- Proper Ash.Domain usage
- AtomMap custom type for JSONB atom preservation
- No business logic in persistence layer

**⚠️ MISSING FEATURES**:
- **Registry for active domains NOT IMPLEMENTED**
- **Tick-based activation NOT WIRED**
- No `ActiveDomainRegistry` resource
- No tick subscription mechanism

**📋 ACTION REQUIRED**:
1. Create `Thunderblock.Resources.ActiveDomainRegistry`
2. Add tick subscription from Thunderlink
3. Implement domain activation/deactivation tracking

---

### 1.2 Thunderlink — Communication & Networking

**Location**: `lib/thunderline/thunderlink/`  
**Purpose**: Network connections, presence, heartbeat, node registry  
**Resources**: 17 Ash resources  
**Status**: ⚠️ PARTIALLY IMPLEMENTED (tick system missing)

**Resource Categories**:
```elixir
# Node Registry & Cluster (6 resources)
- Node, Heartbeat, LinkSession, NodeCapability, NodeGroup, NodeGroupMembership

# Community/Channels (5 resources)
- Community, Channel, Message, Role, FederationSocket

# Voice/WebRTC (3 resources)
- Voice.Room, Voice.Participant, Voice.Device

# Support (1 resource)
- Ticket

# Infrastructure (2 resources)
- Other network components
```

**Domain File**: `lib/thunderline/thunderlink/domain.ex`
```elixir
defmodule Thunderline.Thunderlink.Domain do
  use Ash.Domain,
    extensions: [
      AshAdmin.Domain,
      AshOban.Domain,
      AshGraphql.Domain,
      AshTypescript.Rpc
    ]
  
  resources do
    # 17 resources defined
  end
end
```

**⚠️ CRITICAL MISSING FEATURE**:
```elixir
# THIS DOES NOT EXIST - NEED TO CREATE
defmodule Thunderline.Thunderlink.TickGenerator do
  @moduledoc """
  Generates heartbeat ticks that flow through all domains.
  Domains only become active after receiving first tick.
  """
  use GenServer
  
  @tick_interval 1_000 # 1 second
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    schedule_tick()
    {:ok, %{tick_count: 0}}
  end
  
  def handle_info(:tick, state) do
    tick_count = state.tick_count + 1
    
    # Broadcast tick to all domains via PubSub
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      "system:domain_tick",
      {:domain_tick, tick_count, System.monotonic_time()}
    )
    
    # Update Thunderblock registry with tick
    Thunderblock.Registry.record_tick(tick_count)
    
    schedule_tick()
    {:noreply, %{state | tick_count: tick_count}}
  end
  
  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end
end
```

**📋 ACTION REQUIRED**:
1. Create `Thunderlink.TickGenerator` GenServer
2. Wire into application supervision tree
3. Implement PubSub broadcast system
4. Create domain activation listeners

---

### 1.3 Thunderbolt — Compute, ML, Automata

**Location**: `lib/thunderline/thunderbolt/`  
**Purpose**: ML/AI execution, HPO, AutoML, numeric computation  
**Resources**: 50+ Ash resources  
**Status**: ✅ PROPERLY IMPLEMENTED but ⚠️ TOO LARGE

**Resource Categories**:
```elixir
# Core Processing (5 resources)
- Task execution, resource allocation, workflow management

# ML Stack (6 resources)
- TrainingDatasets, Model artifacts, Experiments

# Cerebros ML (7 resources) - SHOULD BE SEPARATE DOMAIN
- Neural architecture search, training jobs, model management

# RAG (1 resource)
- Retrieval-augmented generation

# MLflow (2 resources)
- Experiment tracking integration

# UPM (4 resources)
- Unified project management, drift detection

# MoE (3 resources)
- Mixture of Experts routing

# Ising Optimization (3 resources)
- Quadratic optimization, QUBO solving

# Lane Processing (10 resources)
- Pipeline orchestration, lane coupling

# Automata (5 resources) - GOOD SEPARATION
- State machines, cellular automata

# Task Execution (3 resources)
- Async task management
```

**Domain File**: `lib/thunderline/thunderbolt/domain.ex`
```elixir
defmodule Thunderline.Thunderbolt.Domain do
  use Ash.Domain,
    extensions: [
      AshAdmin.Domain,
      AshOban.Domain,
      AshJsonApi.Domain,
      AshGraphql.Domain
    ]
  
  resources do
    # 50+ resources - TOO MANY
  end
end
```

**⚠️ ISSUES IDENTIFIED**:
1. **Cerebros should be separate domain** (7 resources)
2. **Domain too large** (50+ resources) - violates single responsibility
3. **Automata vs ML functions properly separated** ✅

**✅ CORRECT SEPARATION**:
```
Automata Functions (ThunderBolt):
- Cellular automata engine
- State machine execution
- Grid processing
- NOT ML/AI specific

ML/AI Functions (ThunderBolt):
- Model training
- HPO execution
- Expert routing
- Separate from automata
```

**📋 ACTION REQUIRED**:
1. Extract Cerebros to `Thunderline.Cerebros.Domain`
2. Move 7 Cerebros resources to new domain
3. Update CerebrosBridge to point to Cerebros domain
4. Consider splitting Thunderbolt into:
   - `Thunderbolt.Core` (orchestration)
   - `Thunderbolt.ML` (ML/AI)
   - `Thunderbolt.Automata` (CA/state machines)

---

### 1.4 Cerebros — Neural Architecture Search (SHOULD BE SEPARATE)

**Current Location**: `lib/thunderline/thunderbolt/cerebros_*/`  
**Proposed Location**: `lib/thunderline/cerebros/`  
**Purpose**: Neural architecture search, model training, Snex integration  
**Resources**: 7 (currently in Thunderbolt)  
**Status**: ⚠️ NEEDS EXTRACTION

**Current Resources (in Thunderbolt)**:
```elixir
# lib/thunderline/thunderbolt/resources/
- cerebros_run.ex
- cerebros_trial.ex
- cerebros_checkpoint.ex
- cerebros_metric.ex
- cerebros_training_job.ex
- cerebros_training_dataset.ex (duplicate with TrainingDataset)
- cerebros_artifact.ex
```

**Proposed Domain Structure**:
```elixir
# lib/thunderline/cerebros/domain.ex
defmodule Thunderline.Cerebros.Domain do
  @moduledoc """
  Cerebros Neural Architecture Search Domain
  
  Responsibilities:
  - NAS run orchestration
  - Trial management
  - Checkpoint persistence
  - Metric tracking
  - Snex runtime integration
  - Model artifact management
  """
  use Ash.Domain,
    extensions: [
      AshAdmin.Domain,
      AshOban.Domain,
      AshGraphql.Domain
    ]
  
  resources do
    resource Thunderline.Cerebros.Resources.Run
    resource Thunderline.Cerebros.Resources.Trial
    resource Thunderline.Cerebros.Resources.Checkpoint
    resource Thunderline.Cerebros.Resources.Metric
    resource Thunderline.Cerebros.Resources.TrainingJob
    resource Thunderline.Cerebros.Resources.Artifact
  end
end
```

**Bridge Layer** (stays in Thunderbolt):
```elixir
# lib/thunderline/thunderbolt/cerebros_bridge/
defmodule Thunderline.Thunderbolt.CerebrosBridge do
  @moduledoc """
  Bridge between Thunderbolt orchestration and Cerebros domain.
  Handles job submission, result polling, and state synchronization.
  """
  
  alias Thunderline.Cerebros.Resources.Run
  alias Thunderline.Cerebros.Resources.Trial
  
  # Bridge functions - calls into Cerebros domain
end
```

**Snex Integration**:
```elixir
# lib/thunderline/cerebros/snex_invoker.ex
defmodule Thunderline.Cerebros.SnexInvoker do
  @moduledoc """
  Snex runtime integration for Cerebros.
  Manages Python process lifecycle and communication.
  """
  
  # Snex-specific code stays with Cerebros domain
end
```

**📋 ACTION REQUIRED**:
1. Create `lib/thunderline/cerebros/` directory
2. Create `Thunderline.Cerebros.Domain`
3. Move 7 resources from Thunderbolt to Cerebros
4. Update CerebrosBridge imports
5. Update application supervision tree
6. Update feature flags (`:ml_nas` → `:cerebros`)

---

### 1.5 Thunderhelm — Helm Chart vs Current Reality

**Current Location**: `thunderhelm/` (directory exists)  
**Current Purpose**: Python services, MLflow, Cerebros service  
**Expected Purpose**: Helm chart for K8s deployment  
**Status**: ⚠️ MISLABELED

**Current Directory Structure**:
```bash
thunderhelm/
├── cerebros_service/       # Python Cerebros service
│   ├── cerebros_service.py
│   └── requirements.txt
├── mlflow/                 # MLflow configuration
│   └── mlflow.db
└── requirements.txt        # Python dependencies
```

**Expected Helm Chart Structure**:
```bash
thunderhelm/                # Helm chart root
├── Chart.yaml             # Helm chart metadata
├── values.yaml            # Default values
├── templates/             # K8s manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── ingress.yaml
└── charts/                # Sub-charts
    ├── cerebros/
    ├── mlflow/
    └── postgres/
```

**⚠️ ISSUE**: `thunderhelm/` is NOT a Helm chart, it's a Python services directory

**📋 ACTION REQUIRED**:
1. Rename `thunderhelm/` → `python_services/` or `sidecar/`
2. Create proper `helm/` directory with Helm charts
3. Structure as:
```
helm/
└── thunderline/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── elixir-deployment.yaml
        ├── cerebros-deployment.yaml
        ├── postgres-statefulset.yaml
        └── mlflow-deployment.yaml
```

---

### 1.6 Domain Activation Flow (NOT IMPLEMENTED)

**Your Vision**:
```
1. Server Starts
2. Thunderlink.TickGenerator starts
3. First tick flows through system
4. Domains subscribe to "system:domain_tick"
5. On first tick, domain activates
6. Thunderblock.ActiveDomainRegistry records activation
7. Subsequent ticks maintain heartbeat
```

**Current Reality**:
```
1. Server Starts
2. All domains start immediately via supervision tree
3. No tick system
4. No activation gating
5. No registry tracking
```

**Required Implementation**:

```elixir
# lib/thunderline/application.ex
def start(_type, _args) do
  children = [
    # Start core infrastructure first
    Thunderline.Repo,
    {Phoenix.PubSub, name: Thunderline.PubSub},
    
    # Start Thunderlink FIRST (generates ticks)
    Thunderline.Thunderlink.TickGenerator,
    
    # Start Thunderblock SECOND (registers activations)
    Thunderline.Thunderblock.DomainRegistry,
    
    # Other domains start but wait for tick activation
    {Thunderline.Thunderflow.Domain.Supervisor, wait_for_tick: true},
    {Thunderline.Thunderbolt.Domain.Supervisor, wait_for_tick: true},
    {Thunderline.Cerebros.Domain.Supervisor, wait_for_tick: true},
    {Thunderline.Thundercrown.Domain.Supervisor, wait_for_tick: true},
    {Thunderline.Thundergrid.Domain.Supervisor, wait_for_tick: true},
    {Thunderline.Thundergate.Domain.Supervisor, wait_for_tick: true},
    
    # Web endpoint starts last
    ThunderlineWeb.Endpoint
  ]
end
```

```elixir
# lib/thunderline/thunderblock/domain_registry.ex
defmodule Thunderline.Thunderblock.DomainRegistry do
  @moduledoc """
  Tracks which domains are active based on tick flow.
  Domains must receive at least one tick to be considered active.
  """
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Subscribe to tick events
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_tick")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_activated")
    
    {:ok, %{
      active_domains: MapSet.new(),
      tick_count: 0,
      last_tick_at: nil
    }}
  end
  
  def handle_info({:domain_tick, tick_count, timestamp}, state) do
    {:noreply, %{state | tick_count: tick_count, last_tick_at: timestamp}}
  end
  
  def handle_info({:domain_activated, domain_name}, state) do
    active_domains = MapSet.put(state.active_domains, domain_name)
    
    # Persist to database
    Thunderline.Thunderblock.Resources.ActiveDomainRegistry.record_activation!(
      domain: domain_name,
      tick_count: state.tick_count,
      activated_at: DateTime.utc_now()
    )
    
    {:noreply, %{state | active_domains: active_domains}}
  end
end
```

```elixir
# lib/thunderline/thunderflow/domain_supervisor.ex
defmodule Thunderline.Thunderflow.Domain.Supervisor do
  @moduledoc """
  Domain-level supervisor that waits for tick activation.
  """
  use Supervisor
  
  def start_link(opts) do
    wait_for_tick = Keyword.get(opts, :wait_for_tick, false)
    
    if wait_for_tick do
      # Subscribe and wait for first tick
      Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_tick")
      receive do
        {:domain_tick, _count, _timestamp} ->
          # Activate domain
          Phoenix.PubSub.broadcast(
            Thunderline.PubSub,
            "system:domain_activated",
            {:domain_activated, "thunderflow"}
          )
          Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      after
        30_000 -> {:error, :tick_timeout}
      end
    else
      Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end
  
  def init(_opts) do
    children = [
      # Domain-specific children
    ]
    
    Supervise.init(children, strategy: :one_for_one)
  end
end
```

---

## 2. Resource Boundary Validation

### 2.1 Cross-Domain Dependencies (Current State)

```elixir
# VIOLATION EXAMPLES (found in codebase)

# Thunderbolt calling Thunderblock directly (should use events)
defmodule Thunderline.Thunderbolt.SomeModule do
  alias Thunderline.Thunderblock.Resources.VaultKnowledgeNode
  # WRONG - direct cross-domain resource access
end

# Thunderflow calling Thundergate directly
defmodule Thunderline.Thunderflow.SomeModule do
  alias Thunderline.Thundergate.Resources.User
  # WRONG - authentication should be injected via context
end

# Thunderlink calling Thunderbolt directly
defmodule Thunderline.Thunderlink.SomeModule do
  alias Thunderline.Thunderbolt.Resources.CoreAgent
  # WRONG - should use events or bridge
end
```

### 2.2 Correct Patterns

```elixir
# CORRECT: Event-based communication
defmodule Thunderline.Thunderbolt.WorkflowExecutor do
  def execute(workflow) do
    # Emit event instead of direct call
    Thunderline.EventBus.publish_event(%{
      event_type: "dag.workflow.started",
      data: %{workflow_id: workflow.id},
      correlation_id: workflow.correlation_id
    })
  end
end

# CORRECT: Bridge pattern for external services
defmodule Thunderline.Thunderbolt.CerebrosBridge do
  # Bridge isolates external service integration
  def enqueue_run(spec, opts) do
    Thunderline.Cerebros.Resources.Run.create!(spec)
  end
end

# CORRECT: Context injection for auth
defmodule Thunderline.Thunderflow.EventPipeline do
  def process_event(event, context) do
    # Context contains current_user, permissions, etc.
    # No direct call to Thundergate.Resources.User
  end
end
```

---

## 3. Critical Action Items

### Priority 1 (Blocking Issues)

1. **Create Thunderlink.TickGenerator**
   - Implement GenServer heartbeat system
   - Broadcast ticks via PubSub
   - Wire into application supervision tree

2. **Create Thunderblock.DomainRegistry**
   - Track active domains
   - Record tick-based activation
   - Provide query interface for active domains

3. **Implement Domain Activation Pattern**
   - Add `wait_for_tick` option to domain supervisors
   - Subscribe to `system:domain_tick` events
   - Broadcast activation events

### Priority 2 (Architectural Debt)

4. **Extract Cerebros to Separate Domain**
   - Create `lib/thunderline/cerebros/`
   - Move 7 resources from Thunderbolt
   - Update CerebrosBridge
   - Update application supervision tree

5. **Fix Thunderhelm Naming**
   - Rename `thunderhelm/` → `python_services/`
   - Create proper `helm/` directory
   - Structure Helm charts correctly

6. **Split Thunderbolt Domain**
   - Too large (50+ resources)
   - Consider: Thunderbolt.Core, Thunderbolt.ML, Thunderbolt.Automata
   - Maintain clear boundaries

### Priority 3 (Enhancement)

7. **Document Domain Activation Flow**
   - Create sequence diagrams
   - Document tick flow
   - Add monitoring/observability

8. **Add Cross-Domain Guards**
   - Compile-time checks for direct resource access
   - Enforce event-based communication
   - Add Credo rules for domain boundaries

9. **Create Domain Health Dashboard**
   - Show active/inactive domains
   - Display tick count
   - Monitor activation times

---

## 4. Recommended Domain Structure (Target State)

```
lib/thunderline/
├── thunderblock/          # Persistence & Infrastructure
│   ├── domain.ex
│   ├── domain_registry.ex          # NEW - tracks active domains
│   └── resources/
│       ├── active_domain_registry.ex  # NEW - Ash resource
│       ├── system_checkpoint.ex
│       └── vault_knowledge_node.ex
│
├── thunderlink/           # Communication & Networking
│   ├── domain.ex
│   ├── tick_generator.ex            # NEW - heartbeat system
│   └── resources/
│       ├── node.ex
│       └── heartbeat.ex
│
├── thunderflow/           # Event Processing
│   ├── domain.ex
│   ├── domain_supervisor.ex         # UPDATED - wait for tick
│   └── resources/
│       └── event_stream.ex
│
├── thunderbolt/           # Compute & Orchestration (REDUCED SIZE)
│   ├── domain.ex
│   ├── domain_supervisor.ex         # UPDATED - wait for tick
│   └── resources/
│       ├── core_agent.ex
│       ├── workflow.ex
│       └── automata.ex             # Keep automata here
│
├── cerebros/              # NEW DOMAIN - Neural Architecture Search
│   ├── domain.ex
│   ├── domain_supervisor.ex
│   ├── snex_invoker.ex
│   └── resources/
│       ├── run.ex
│       ├── trial.ex
│       └── checkpoint.ex
│
├── thundercrown/          # AI Governance
│   ├── domain.ex
│   ├── domain_supervisor.ex         # UPDATED - wait for tick
│   └── resources/
│       └── agent_runner.ex
│
├── thundergrid/           # Spatial & Zones
│   ├── domain.ex
│   ├── domain_supervisor.ex         # UPDATED - wait for tick
│   └── resources/
│       └── zone.ex
│
└── thundergate/           # Security & Monitoring
    ├── domain.ex
    ├── domain_supervisor.ex         # UPDATED - wait for tick
    └── resources/
        ├── user.ex
        └── health_check.ex
```

---

## 7. Additional Domains Discovered

### 7.1 Thunderprism — ML Decision Trail DAG

**Location**: `lib/thunderline/thunderprism/`  
**Purpose**: Persistent "memory rails" for ML decision trails  
**Resources**: 2 Ash resources  
**Status**: ⚠️ UNDOCUMENTED IN CATALOG

**Resources**:
```elixir
# lib/thunderline/thunderprism/domain.ex
defmodule Thunderline.Thunderprism.Domain do
  resources do
    resource Thunderline.Thunderprism.PrismNode   # ML decision points
    resource Thunderline.Thunderprism.PrismEdge   # Connections between nodes
  end
end
```

**Purpose** (from moduledoc):
- DAG scratchpad for ML decision trails
- Records ML decision nodes and their connections
- Enables visualization and AI context querying
- Tracks PAC iteration, model selection, probabilities, distances

**⚠️ ISSUE**: This domain is NOT listed in THUNDERLINE_DOMAIN_CATALOG.md

**📋 ACTION REQUIRED**:
1. Add to domain catalog documentation
2. Determine if this should merge into Thunderbolt or stay separate
3. Update resource count in documentation
4. Consider renaming to follow Thunder* naming convention more clearly

---

### 7.2 Accounts Domain — Legacy Authentication

**Location**: `lib/thunderline/accounts/`  
**Resources**: 2 (User, Token)  
**Status**: ⚠️ SHOULD BE IN THUNDERGATE

**Current Resources**:
```elixir
# lib/thunderline/accounts/user.ex
defmodule Thunderline.Accounts.User do
  use Ash.Resource,
    domain: Thunderline.Accounts,  # References non-existent domain!
    extensions: [AshAuthentication]
end

# lib/thunderline/accounts/token.ex
defmodule Thunderline.Accounts.Token do
  use Ash.Resource,
    domain: Thunderline.Accounts
end
```

**⚠️ CRITICAL ISSUES**:
1. **No `Thunderline.Accounts` domain exists!**
2. Resources reference non-existent domain
3. Documentation says accounts consolidated into Thundergate
4. Files still exist in separate directory

**Expected Location**: `lib/thunderline/thundergate/resources/user.ex`

**📋 ACTION REQUIRED**:
1. Move `accounts/user.ex` → `thundergate/resources/user.ex`
2. Move `accounts/token.ex` → `thundergate/resources/token.ex`
3. Update domain references to `Thunderline.Thundergate.Domain`
4. Delete `lib/thunderline/accounts/` directory
5. Update all imports throughout codebase

---

### 7.3 Helm Chart Discovery

**Location**: `thunderhelm/deploy/chart/Chart.yaml`  
**Status**: ✅ HELM CHART EXISTS!

**Chart Metadata**:
```yaml
apiVersion: v2
name: thunderhelm
description: Helm chart for deploying Thunderline (web/worker) and optional Flower federation runtime.
type: application
version: 0.2.0
appVersion: "2.1.0"
```

**⚠️ ISSUE**: Chart exists but buried in `thunderhelm/deploy/chart/` instead of standard `helm/` location

**📋 ACTION REQUIRED**:
1. Restructure to standard Helm layout:
```
helm/
└── thunderline/
    ├── Chart.yaml           # Move from thunderhelm/deploy/chart/
    ├── values.yaml
    ├── templates/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── ingress.yaml
    └── charts/              # Sub-charts
        ├── cerebros/
        └── mlflow/
```

2. Keep Python services in `python_services/` or `sidecar/`
3. Update deployment documentation

---

## 8. Comprehensive Resource Count

### Actual Resource Inventory (Updated)

| Domain | Resources | Status | Location |
|--------|-----------|--------|----------|
| **Thunderblock** | 33 | ✅ Active | `lib/thunderline/thunderblock/` |
| **Thunderbolt** | 50+ | ⚠️ Too large | `lib/thunderline/thunderbolt/` |
| **Cerebros** | 7 | ⚠️ In Thunderbolt | Should be `lib/thunderline/cerebros/` |
| **Thundercrown** | 4 | ✅ Active | `lib/thunderline/thundercrown/` |
| **Thunderflow** | 9 | ✅ Active | `lib/thunderline/thunderflow/` |
| **Thundergate** | 19 | ✅ Active | `lib/thunderline/thundergate/` |
| **Thundergrid** | 5 | ✅ Active | `lib/thunderline/thundergrid/` |
| **Thunderlink** | 17 | ✅ Active | `lib/thunderline/thunderlink/` |
| **Thundervine** | 6 | ✅ Active | `lib/thunderline/thundervine/` |
| **Thunderprism** | 2 | ⚠️ Undocumented | `lib/thunderline/thunderprism/` |
| **Accounts** | 2 | ⚠️ Legacy | Should be in Thundergate |
| **TOTAL** | **154-164** | - | - |

### Domain Count: 9 Active + 2 Legacy = 11 Total

---

## 9. Critical Findings Summary

### ✅ What's Working Well

1. **Domain Boundaries**: Clear separation between domains
2. **Ash Framework Usage**: Consistent resource patterns
3. **Event-Driven Architecture**: EventBus and PubSub properly used
4. **Feature Flags**: Good use of runtime configuration
5. **Documentation**: Comprehensive guides and catalogs
6. **Cerebros Bridge**: Clean abstraction layer exists
7. **Helm Chart**: Actually exists (just misplaced)
8. **Registry Pattern**: Thunderlink.Registry is well-implemented ETS cache

### ⚠️ Critical Issues

1. **NO TICK SYSTEM**: Your vision of tick-based domain activation is NOT implemented
   - No `Thunderlink.TickGenerator`
   - No domain activation gating
   - All domains start immediately via supervision tree
   
2. **NO DOMAIN REGISTRY**: Thunderblock doesn't track active domains
   - No `ActiveDomainRegistry` resource
   - No tick-based activation recording
   
3. **CEREBROS NOT SEPARATE**: Still buried in Thunderbolt
   - 7 resources should be extracted
   - Bridge exists but points to wrong domain
   
4. **ACCOUNTS DOMAIN BROKEN**: References non-existent domain
   - `Thunderline.Accounts` doesn't exist
   - Resources orphaned
   
5. **THUNDERPRISM UNDOCUMENTED**: 2 resources not in catalog
   - Domain exists but not documented
   - Unknown if it should be merged
   
6. **HELM CHART MISPLACED**: Exists but in non-standard location
   - Should be in `helm/` not `thunderhelm/deploy/chart/`

### 🎯 Architecture Gaps

**Your Vision**:
```
Server → Tick Generator → Domains Wait → First Tick → Activate → Registry Tracks
```

**Current Reality**:
```
Server → All Domains Start Immediately (no tick system, no activation gating)
```

**The tick flow system you described does NOT exist.** This is the biggest architectural gap.

---

## 5. Next Steps

### Immediate Actions (This Week)

1. **Review this analysis with team**
2. **Prioritize action items**
3. **Create implementation tickets**
4. **Assign owners for each domain**

### Implementation Phases

**Phase 1: Tick System (Week 1-2)**
- Implement Thunderlink.TickGenerator
- Create Thunderblock.DomainRegistry
- Add tick-based activation to one domain (Thunderflow)
- Validate pattern works

**Phase 2: Domain Rollout (Week 3-4)**
- Apply tick activation to remaining domains
- Add monitoring and observability
- Create health dashboard

**Phase 3: Cerebros Extraction (Week 5-6)**
- Create Cerebros domain
- Move resources
- Update bridges
- Test integration

**Phase 4: Helm Charts (Week 7-8)**
- Rename thunderhelm/
- Create proper helm/ structure
- Build K8s deployment manifests

**Phase 5: Thunderbolt Split (Week 9-10)**
- Analyze 50+ resources
- Plan domain split
- Execute migration
- Update documentation

---

## 10. Detailed Implementation Roadmap

### Phase 0: Immediate Fixes (1-2 days)

**Priority: CRITICAL** - These are broken references that prevent proper compilation/operation

**Task 0.1: Fix Accounts Domain**
```bash
# Move accounts resources to Thundergate
mv lib/thunderline/accounts/user.ex lib/thunderline/thundergate/resources/user.ex
mv lib/thunderline/accounts/token.ex lib/thunderline/thundergate/resources/token.ex

# Update domain references in both files
# Change: domain: Thunderline.Accounts
# To: domain: Thunderline.Thundergate.Domain

# Delete orphaned directory
rm -rf lib/thunderline/accounts/
```

**Task 0.2: Document Thunderprism**
- Add Thunderprism to THUNDERLINE_DOMAIN_CATALOG.md
- Document purpose and relationship to Thunderbolt ML
- Update resource count to 11 domains, 154-164 resources

**Task 0.3: Reorganize Helm Structure**
```bash
# Create standard helm directory
mkdir -p helm/thunderline/templates

# Move chart files
mv thunderhelm/deploy/chart/Chart.yaml helm/thunderline/
mv thunderhelm/deploy/chart/values.yaml helm/thunderline/
mv thunderhelm/deploy/chart/templates/* helm/thunderline/templates/

# Rename python services
mv thunderhelm/ python_services/
```

---

### Phase 1: Tick System Foundation (Week 1-2)

**Priority: HIGH** - Core architectural pattern

**Task 1.1: Create Thunderlink.TickGenerator**

```elixir
# lib/thunderline/thunderlink/tick_generator.ex
defmodule Thunderline.Thunderlink.TickGenerator do
  @moduledoc """
  Generates heartbeat ticks that flow through all domains.
  Domains only become active after receiving first tick.
  
  Broadcasts:
  - "system:domain_tick" - {tick_count, timestamp, metrics}
  
  Metrics tracked:
  - tick_count: Monotonic counter
  - timestamp: System.monotonic_time()
  - active_domains: Count from registry
  - tick_latency_ms: Processing time
  """
  use GenServer
  require Logger
  
  @tick_interval 1_000  # 1 second default
  @pubsub_topic "system:domain_tick"
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @tick_interval)
    schedule_tick(interval)
    
    Logger.info("[TickGenerator] Started with #{interval}ms interval")
    
    {:ok, %{
      tick_count: 0,
      interval: interval,
      started_at: System.monotonic_time(),
      last_tick_at: nil
    }}
  end
  
  @impl true
  def handle_info(:tick, state) do
    tick_start = System.monotonic_time()
    tick_count = state.tick_count + 1
    
    # Get active domain count from registry
    active_count = Thunderline.Thunderblock.DomainRegistry.active_count()
    
    # Broadcast tick event
    Phoenix.PubSub.broadcast(
      Thunderline.PubSub,
      @pubsub_topic,
      {:domain_tick, tick_count, tick_start, %{active_domains: active_count}}
    )
    
    # Emit telemetry
    tick_latency = System.monotonic_time() - tick_start
    :telemetry.execute(
      [:thunderline, :tick_generator, :tick],
      %{count: tick_count, latency_ns: tick_latency, active_domains: active_count},
      %{interval: state.interval}
    )
    
    schedule_tick(state.interval)
    
    {:noreply, %{state | tick_count: tick_count, last_tick_at: tick_start}}
  end
  
  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
  
  # Public API
  def current_tick, do: GenServer.call(__MODULE__, :current_tick)
  
  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick_count, state}
  end
end
```

**Task 1.2: Create Thunderblock.DomainRegistry**

```elixir
# lib/thunderline/thunderblock/domain_registry.ex
defmodule Thunderline.Thunderblock.DomainRegistry do
  @moduledoc """
  Tracks which domains are active based on tick flow.
  Domains must receive and acknowledge at least one tick to be considered active.
  
  Listens to:
  - "system:domain_tick" - Update tick count
  - "system:domain_activated" - Record domain activation
  - "system:domain_deactivated" - Record domain deactivation
  """
  use GenServer
  require Logger
  
  @table_name :thunderblock_domain_registry
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    
    # Subscribe to system events
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_tick")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_activated")
    Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_deactivated")
    
    Logger.info("[DomainRegistry] Started and subscribed to system events")
    
    {:ok, %{
      active_domains: MapSet.new(),
      tick_count: 0,
      last_tick_at: nil,
      activation_history: []
    }}
  end
  
  @impl true
  def handle_info({:domain_tick, tick_count, timestamp, _meta}, state) do
    # Update ETS with latest tick
    :ets.insert(@table_name, {:last_tick, tick_count, timestamp})
    
    {:noreply, %{state | tick_count: tick_count, last_tick_at: timestamp}}
  end
  
  @impl true
  def handle_info({:domain_activated, domain_name, metadata}, state) do
    Logger.info("[DomainRegistry] Domain activated: #{domain_name}")
    
    active_domains = MapSet.put(state.active_domains, domain_name)
    
    # Update ETS
    :ets.insert(@table_name, {domain_name, :active, state.tick_count, System.monotonic_time()})
    
    # Record in history
    activation = %{
      domain: domain_name,
      tick: state.tick_count,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
    
    history = [activation | state.activation_history] |> Enum.take(100)  # Keep last 100
    
    # Emit telemetry
    :telemetry.execute(
      [:thunderline, :domain_registry, :activation],
      %{active_count: MapSet.size(active_domains)},
      %{domain: domain_name, tick: state.tick_count}
    )
    
    {:noreply, %{state | active_domains: active_domains, activation_history: history}}
  end
  
  @impl true
  def handle_info({:domain_deactivated, domain_name, _metadata}, state) do
    Logger.info("[DomainRegistry] Domain deactivated: #{domain_name}")
    
    active_domains = MapSet.delete(state.active_domains, domain_name)
    
    # Update ETS
    :ets.insert(@table_name, {domain_name, :inactive, state.tick_count, System.monotonic_time()})
    
    {:noreply, %{state | active_domains: active_domains}}
  end
  
  # Public API
  def active_domains do
    GenServer.call(__MODULE__, :active_domains)
  end
  
  def active_count do
    GenServer.call(__MODULE__, :active_count)
  end
  
  def domain_status(domain_name) do
    case :ets.lookup(@table_name, domain_name) do
      [{^domain_name, status, tick, timestamp}] -> {:ok, %{status: status, tick: tick, timestamp: timestamp}}
      [] -> {:error, :not_found}
    end
  end
  
  @impl true
  def handle_call(:active_domains, _from, state) do
    {:reply, MapSet.to_list(state.active_domains), state}
  end
  
  @impl true
  def handle_call(:active_count, _from, state) do
    {:reply, MapSet.size(state.active_domains), state}
  end
end
```

**Task 1.3: Create ActiveDomainRegistry Resource**

```elixir
# lib/thunderline/thunderblock/resources/active_domain_registry.ex
defmodule Thunderline.Thunderblock.Resources.ActiveDomainRegistry do
  @moduledoc """
  Persistent record of domain activations and deactivations.
  Complements the in-memory ETS registry with durable storage.
  """
  use Ash.Resource,
    otp_app: :thunderline,
    domain: Thunderline.Thunderblock.Domain,
    data_layer: AshPostgres.DataLayer
  
  postgres do
    table "active_domain_registry"
    repo Thunderline.Repo
  end
  
  attributes do
    uuid_primary_key :id
    
    attribute :domain_name, :string do
      allow_nil? false
      constraints max_length: 100
    end
    
    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:active, :inactive, :crashed, :restarting]
      default :active
    end
    
    attribute :tick_count, :integer do
      allow_nil? false
      description "Tick count when this status was recorded"
    end
    
    attribute :metadata, :map do
      default %{}
    end
    
    create_timestamp :activated_at
    update_timestamp :updated_at
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :record_activation do
      accept [:domain_name, :status, :tick_count, :metadata]
    end
    
    update :update_status do
      accept [:status, :tick_count, :metadata]
    end
  end
  
  code_interface do
    define :record_activation, args: [:domain_name, :tick_count]
    define :update_status, args: [:status]
    define :list_active, action: :read, args: []
  end
  
  identities do
    identity :unique_domain_name, [:domain_name]
  end
end
```

**Task 1.4: Update Application Supervision Tree**

```elixir
# lib/thunderline/application.ex (UPDATE)

defp build_children_list do
  core = [
    ThunderlineWeb.Telemetry,
    maybe_vault_child(),
    {Phoenix.PubSub, name: Thunderline.PubSub},
    {Task.Supervisor, name: Thunderline.TaskSupervisor}
  ]

  database = [maybe_repo_child()]

  # START TICK SYSTEM EARLY (after PubSub, before domains)
  tick_system = [
    Thunderline.Thunderblock.DomainRegistry,  # Registry FIRST
    Thunderline.Thunderlink.TickGenerator     # Generator SECOND
  ]

  domains =
    cerebros_children() ++
      saga_children() ++
      rag_children() ++
      upm_children() ++
      ml_pipeline_children()

  infrastructure_early = [
    Thunderline.Thunderflow.EventBuffer,
    Thunderline.Thunderflow.Blackboard,
    Thunderline.Thunderlink.Registry,
    Thundervine.Supervisor,
    ThunderlineWeb.Presence
  ]

  jobs = [maybe_oban_child()]

  infrastructure_late = [
    Thunderline.Thundergate.ServiceRegistry.HealthMonitor
  ]

  web = [ThunderlineWeb.Endpoint]

  # New order: core -> database -> tick_system -> domains -> early infra -> jobs -> late infra -> web
  (core ++ database ++ tick_system ++ domains ++ infrastructure_early ++ jobs ++ infrastructure_late ++ web)
  |> Enum.reject(&is_nil/1)
end
```

**Task 1.5: Create Migration**

```bash
# Generate migration for ActiveDomainRegistry
mix ash_postgres.generate_migrations --name add_active_domain_registry
```

**Validation Criteria**:
- [ ] TickGenerator starts and emits ticks every 1 second
- [ ] DomainRegistry receives ticks and updates ETS
- [ ] Tick events visible in logs
- [ ] Telemetry events firing for ticks
- [ ] ActiveDomainRegistry table created in Postgres

---

### Phase 2: Domain Activation Pattern (Week 3-4)

**Priority: HIGH** - Enable tick-based domain lifecycle

**Task 2.1: Create Activation Behavior**

```elixir
# lib/thunderline/domain_activation.ex
defmodule Thunderline.DomainActivation do
  @moduledoc """
  Behaviour for domains that wait for tick activation.
  
  Domains implementing this behavior will:
  1. Start in "waiting" state
  2. Subscribe to system:domain_tick
  3. Activate on first tick
  4. Broadcast activation event
  5. Start domain-specific children
  """
  
  @callback domain_name() :: String.t()
  @callback activate(tick_count :: integer(), metadata :: map()) :: :ok | {:error, term()}
  @callback deactivate(reason :: term()) :: :ok
  
  defmacro __using__(opts) do
    quote do
      @behaviour Thunderline.DomainActivation
      
      use GenServer
      require Logger
      
      @domain_name Keyword.fetch!(unquote(opts), :name)
      
      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
      
      @impl GenServer
      def init(opts) do
        wait_for_tick = Keyword.get(opts, :wait_for_tick, true)
        
        if wait_for_tick do
          Phoenix.PubSub.subscribe(Thunderline.PubSub, "system:domain_tick")
          Logger.info("[#{@domain_name}] Waiting for first tick to activate...")
          
          {:ok, %{
            status: :waiting,
            domain_name: @domain_name,
            activated_at: nil,
            tick_count: 0
          }}
        else
          # Skip activation pattern for testing/development
          {:ok, %{status: :active, domain_name: @domain_name}}
        end
      end
      
      @impl GenServer
      def handle_info({:domain_tick, tick_count, timestamp, meta}, %{status: :waiting} = state) do
        Logger.info("[#{@domain_name}] Received first tick #{tick_count}, activating...")
        
        # Call domain-specific activation
        case activate(tick_count, meta) do
          :ok ->
            # Broadcast activation
            Phoenix.PubSub.broadcast(
              Thunderline.PubSub,
              "system:domain_activated",
              {:domain_activated, @domain_name, %{tick: tick_count, timestamp: timestamp}}
            )
            
            {:noreply, %{state | status: :active, activated_at: timestamp, tick_count: tick_count}}
          
          {:error, reason} ->
            Logger.error("[#{@domain_name}] Activation failed: #{inspect(reason)}")
            {:stop, {:activation_failed, reason}, state}
        end
      end
      
      @impl GenServer
      def handle_info({:domain_tick, tick_count, _timestamp, _meta}, %{status: :active} = state) do
        # Already active, just update tick count
        {:noreply, %{state | tick_count: tick_count}}
      end
      
      @impl Thunderline.DomainActivation
      def domain_name, do: @domain_name
      
      # Override these in your domain
      defoverridable activate: 2, deactivate: 1
    end
  end
end
```

**Task 2.2: Implement Activation in One Domain (Thunderflow)**

```elixir
# lib/thunderline/thunderflow/domain_supervisor.ex (CREATE NEW FILE)
defmodule Thunderline.Thunderflow.DomainSupervisor do
  @moduledoc """
  Domain-level supervisor for Thunderflow that waits for tick activation.
  """
  use Thunderline.DomainActivation, name: "thunderflow"
  
  @impl Thunderline.DomainActivation
  def activate(tick_count, _metadata) do
    Logger.info("[Thunderflow] Activating at tick #{tick_count}")
    
    # Start domain-specific children
    children = [
      Thunderline.Thunderflow.EventProcessor,
      Thunderline.Thunderflow.StreamSupervisor
    ]
    
    # These would normally start via Supervisor
    # For now just log activation
    :ok
  end
  
  @impl Thunderline.DomainActivation
  def deactivate(_reason) do
    Logger.info("[Thunderflow] Deactivating")
    :ok
  end
end
```

**Task 2.3: Add to Supervision Tree**

```elixir
# lib/thunderline/application.ex
defp build_children_list do
  # ... existing code ...
  
  # Add domain supervisors with activation
  domain_supervisors = [
    {Thunderline.Thunderflow.DomainSupervisor, wait_for_tick: true}
    # Add others as we implement them
  ]
  
  # ... rest of children ...
end
```

**Validation Criteria**:
- [ ] Thunderflow waits for tick before activating
- [ ] Activation event broadcasted and logged
- [ ] DomainRegistry records activation
- [ ] Subsequent ticks don't re-activate

---

### Phase 3: Cerebros Extraction (Week 5-6)

**Priority: MEDIUM** - Clean up domain boundaries

**Task 3.1: Create Cerebros Domain**

```bash
# Create directory structure
mkdir -p lib/thunderline/cerebros/resources
mkdir -p lib/thunderline/cerebros/bridge

# Create domain file
```

```elixir
# lib/thunderline/cerebros/domain.ex
defmodule Thunderline.Cerebros.Domain do
  @moduledoc """
  Cerebros Neural Architecture Search Domain
  
  Extracted from Thunderbolt on November 24, 2025.
  
  Responsibilities:
  - Neural architecture search (NAS) orchestration
  - Trial management and metric tracking
  - Checkpoint persistence and artifact storage
  - Snex Python runtime integration
  - Integration with MLflow for experiment tracking
  
  This domain is separate from Thunderbolt's automata and general ML functions.
  Cerebros focuses specifically on NAS and hyperparameter optimization.
  """
  use Ash.Domain,
    extensions: [
      AshAdmin.Domain,
      AshOban.Domain,
      AshGraphql.Domain
    ]
  
  resources do
    resource Thunderline.Cerebros.Resources.Run
    resource Thunderline.Cerebros.Resources.Trial
    resource Thunderline.Cerebros.Resources.Checkpoint
    resource Thunderline.Cerebros.Resources.Metric
    resource Thunderline.Cerebros.Resources.TrainingJob
    resource Thunderline.Cerebros.Resources.Artifact
  end
end
```

**Task 3.2: Move Resources**

```bash
# Move 7 resources from Thunderbolt to Cerebros
mv lib/thunderline/thunderbolt/resources/cerebros_run.ex \
   lib/thunderline/cerebros/resources/run.ex
   
mv lib/thunderline/thunderbolt/resources/cerebros_trial.ex \
   lib/thunderline/cerebros/resources/trial.ex
   
mv lib/thunderline/thunderbolt/resources/cerebros_checkpoint.ex \
   lib/thunderline/cerebros/resources/checkpoint.ex
   
mv lib/thunderline/thunderbolt/resources/cerebros_metric.ex \
   lib/thunderline/cerebros/resources/metric.ex
   
mv lib/thunderline/thunderbolt/resources/cerebros_training_job.ex \
   lib/thunderline/cerebros/resources/training_job.ex
   
mv lib/thunderline/thunderbolt/resources/cerebros_artifact.ex \
   lib/thunderline/cerebros/resources/artifact.ex
```

**Task 3.3: Update Resource Modules**

```elixir
# Update each moved resource file
# FROM: domain: Thunderline.Thunderbolt.Domain
# TO:   domain: Thunderline.Cerebros.Domain

# Example for run.ex:
defmodule Thunderline.Cerebros.Resources.Run do
  use Ash.Resource,
    domain: Thunderline.Cerebros.Domain,  # CHANGED
    # ... rest unchanged
end
```

**Task 3.4: Move Cerebros Modules**

```bash
# Move cerebros-specific modules
mv lib/thunderline/thunderbolt/cerebros/ \
   lib/thunderline/cerebros/
   
# Move bridge
mv lib/thunderline/thunderbolt/cerebros_bridge/ \
   lib/thunderline/cerebros/bridge/
   
mv lib/thunderline/thunderbolt/cerebros_bridge.ex \
   lib/thunderline/cerebros/bridge.ex
```

**Task 3.5: Update Bridge References**

```elixir
# lib/thunderline/cerebros/bridge.ex
defmodule Thunderline.Cerebros.Bridge do
  # Update all resource references
  alias Thunderline.Cerebros.Resources.{Run, Trial, Checkpoint}
  # ... rest of implementation
end
```

**Task 3.6: Update Application Supervision**

```elixir
# lib/thunderline/application.ex
defp cerebros_children do
  if cerebros_enabled?() do
    [
      Thunderline.Cerebros.EventPublisher,
      Thunderline.Cerebros.Metrics,
      Thunderline.Cerebros.Bridge.Cache,
      Thunderline.Cerebros.AutoMLDriver
    ]
  else
    []
  end
end
```

**Task 3.7: Update All Imports**

```bash
# Search and replace across codebase
# FROM: Thunderline.Thunderbolt.CerebrosBridge
# TO:   Thunderline.Cerebros.Bridge

# FROM: Thunderline.Thunderbolt.Cerebros.*
# TO:   Thunderline.Cerebros.*
```

**Validation Criteria**:
- [ ] All tests pass after extraction
- [ ] Cerebros domain starts independently
- [ ] Bridge functionality preserved
- [ ] No references to old paths remain
- [ ] Documentation updated

---

### Phase 4: Thunderbolt Domain Split (Week 7-8)

**Priority: LOW** - Can be deferred

**Proposed Split**:
```
lib/thunderline/thunderbolt/        → Core orchestration (10-15 resources)
lib/thunderline/thunderml/          → ML/AI specific (15-20 resources)
lib/thunderline/thunderautomata/    → Cellular automata (10-15 resources)
```

**Defer until**:
- Tick system proven
- Cerebros extracted
- Team has bandwidth

---

## 11. Success Metrics

### Phase 1 Success Criteria
- [ ] TickGenerator running with 1-second interval
- [ ] DomainRegistry tracking tick count
- [ ] ETS table populated with tick data
- [ ] Telemetry events visible in logs
- [ ] ActiveDomainRegistry migration applied

### Phase 2 Success Criteria
- [ ] At least one domain (Thunderflow) using activation pattern
- [ ] Domain waits for tick before starting
- [ ] Activation event broadcasted and recorded
- [ ] Health dashboard shows domain status

### Phase 3 Success Criteria
- [ ] Cerebros domain independent
- [ ] All 7 resources moved and functional
- [ ] Bridge working correctly
- [ ] Documentation updated
- [ ] Zero references to old paths

---

## 6. Questions for Clarification

1. **Tick Interval**: What should be the default tick interval? (1 second?)
2. **Activation Timeout**: How long should domains wait for first tick before timing out?
3. **Registry Persistence**: Should ActiveDomainRegistry persist to database or stay in-memory?
4. **Helm Priority**: Is K8s deployment urgent or can it wait until after tick system?
5. **Cerebros Separation**: Should this happen before or after tick system implementation?

---

## Conclusion

**Current State**: Well-organized domain structure with clear boundaries, but missing the tick-based activation system that ties it all together.

**Target State**: Event-driven architecture where domains activate based on Thunderlink heartbeat ticks, with Thunderblock registry tracking active domains.

**Effort Estimate**: 6-10 weeks to fully implement tick system, extract Cerebros, create Helm charts, and split Thunderbolt.

**Risk Level**: Medium - Changes are additive and can be rolled out incrementally without breaking existing functionality.

**Recommendation**: Start with tick system (Phase 1) as proof of concept, then proceed with remaining phases based on results.

---

**Status**: 📋 AWAITING REVIEW AND PRIORITIZATION
