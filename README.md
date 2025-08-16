# Thunderline

**A Domain-Driven Intelligent System for Advanced Event Processing and Spatial Computing**

*An OKO Holding Corporation Initiative*

## Overview

Thunderline represents the next evolution in distributed intelligent systems, combining event-driven architecture with spatial computing capabilities. Built on the robust foundation of Phoenix and Ash Framework, Thunderline orchestrates complex domain interactions through a sophisticated network of specialized processing units called Thunderblocks.

The system employs a unique hybrid architecture that seamlessly integrates Entity-Component-System (ECSx) patterns with Ash's declarative resource management, creating an environment where real-time agent coordination meets persistent policy-driven governance.

## Core Architecture

### Domain-Driven Excellence

Thunderline is architected around seven specialized domains, each handling distinct aspects of the intelligent system:

- **ThunderBlock**: Secure data persistence and infrastructure management
- **ThunderBolt**: High-performance compute and processing acceleration
- **ThunderCrown**: AI governance, orchestration and decision architecture
- **ThunderFlow**: Event streaming and data pipeline coordination
- **ThunderGate**: External system integrations, security and gateway services
- **ThunderGrid**: Spatial management and coordinate systems
- **ThunderLink**: Federation protocols and inter-system communication

### Event-Driven Foundation

The system leverages **AshEvents** for comprehensive event sourcing, providing:

- Complete audit trails with immutable event logs
- System state reconstruction from historical events
- Temporal queries for analytical insights
- Compliance-ready data governance

### Intelligent Resource Selection

Thunderline incorporates the **THUNDERSTRUCK** algorithm, a sophisticated implementation of the Josephus problem, to mathematically optimize resource allocation and ensure peak system efficiency through strategic selection processes.

## Technical Excellence

### Framework Foundation
- **Phoenix LiveView**: Real-time user interfaces with server-side rendering
- **Ash Framework 3.x**: Declarative resource modeling with built-in APIs
- **ECSx**: High-performance entity-component-system for agent coordination
- **AshEvents**: Enterprise-grade event sourcing and audit capabilities
- **PostgreSQL + Mnesia**: Dual-layer persistence for durability and performance

### Advanced Capabilities
- **3D Cellular Automata**: Real-time spatial computing with 60 FPS visualization
- **Federation Protocols**: Multi-node coordination and distributed consensus
- **Behavioral Intelligence**: Agent-based processing with learning capabilities
- **Spatial Computing**: Hexagonal coordinate systems for complex spatial relationships

## Getting Started

### Prerequisites
- Elixir 1.15+ with OTP 26+
- PostgreSQL 14+ for persistent storage
- Node.js 18+ for asset compilation

### Installation

```bash
# Clone the repository
git clone https://github.com/Thunderblok/Thunderline.git
cd Thunderline

# Install dependencies and setup database
mix setup

# Start the development server
mix phx.server
```

The application will be available at [localhost:4000](http://localhost:4000).

### Production Deployment

For production environments, Thunderline supports containerized deployment with comprehensive monitoring and distributed coordination capabilities. Consult the deployment documentation for environment-specific configuration guidance.

## System Capabilities

### Real-Time Processing
Thunderline processes events with sub-millisecond latency through its distributed event architecture, enabling real-time decision making and immediate system responsiveness.

### Intelligent Coordination
The system employs sophisticated algorithms for resource allocation, task distribution, and agent coordination, ensuring optimal performance across all operational domains.

### Comprehensive Observability
Built-in monitoring and observability tools provide deep insights into system behavior, performance metrics, and operational health across all domains.

### Scalable Architecture
The domain-driven design allows for selective scaling of individual system components based on load patterns and operational requirements.

## Event Processing Pipeline

### Gated Architecture (Phase-0 Operational Improvements)

Thunderline uses a **gated event processing architecture** that provides both simplicity and power:

**Default Path (TL_ENABLE_REACTOR=false)**:
- Simple, direct event processing via `Thunderline.EventProcessor`
- Optimized for high-throughput with minimal overhead
- Exponential backoff with jitter for resilient retries
- Circuit breaker protection for external services
- Comprehensive telemetry and error classification

**Advanced Path (TL_ENABLE_REACTOR=true)**:
- Reactor-based saga orchestration (available when needed)
- Complex compensation and undo logic
- Recursive workflows and advanced DAG patterns

### Operational Features

**Smart Retry Strategy:**
```elixir
# Exponential backoff: 1s → 2s → 4s → 8s → 16s (capped at 5min)
# With ±20% jitter to prevent thundering herd
```

**Circuit Breaker Protection:**
```elixir
# Protects against failing domains:
# 5 failures → open for 30s → half-open test → closed
```

**Error Classification:**
- `:transient` - Network/timeout errors (retry)
- `:permanent` - Validation/constraint errors (discard)
- `:unknown` - Unclassified errors (retry with caution)

**Key Telemetry Metrics:**
- `thunderline.jobs.retries` - Retry attempts by queue/worker
- `thunderline.jobs.failures` - Failures by error type
- `thunderline.cross_domain.latency` - Cross-domain operation timing
- `thunderline.circuit_breaker.calls` - Circuit breaker activity

### Usage

**Simple Event Processing:**
```elixir
# Canonical interface - routes to simple processor by default
Ash.run!(Thunderline.Integrations.EventOps, :process_event, %{
  event: %{
    "type" => "agent_created", 
    "payload" => %{"agent_id" => "123", "status" => "active"},
    "source_domain" => "thundercrown",
    "target_domain" => "thunderlink"
  }
})
```

**Job Queue Integration:**
```elixir
# For background processing
%{"event" => %{
  "type" => "cross_domain_sync",
  "payload" => sync_data,
  "source_domain" => "thunderblock"
}}
|> Thunderline.Thunderflow.Jobs.ProcessEvent.new()
|> Oban.insert()
```

**Canonical Event Structure:**
```elixir
# All events normalized to this shape
%Thunderline.Event{
  type: :agent_created,
  payload: %{"agent_id" => "123"},
  source_domain: "thundercrown",
  target_domain: "thunderlink",
  timestamp: ~U[2025-08-16 10:30:00Z],
  correlation_id: "abc123...",
  hop_count: 0,
  priority: :normal,
  metadata: %{}
}
```

## Development Philosophy

Thunderline embodies a commitment to architectural excellence through:

- **Systematic Methodology**: Every component designed with mathematical precision
- **Event-Driven Clarity**: Complete system transparency through comprehensive event logging
- **Domain Expertise**: Specialized processing units optimized for specific operational domains
- **Intelligent Adaptation**: Self-optimizing algorithms that improve system performance over time

## Contributing

Thunderline development follows rigorous engineering standards with comprehensive testing, documentation-driven development, and systematic code review processes. The system maintains living documentation through the OKO Handbook, ensuring continuous knowledge preservation and team alignment.

## License

This project is proprietary software of OKO Holding Corporation. All rights reserved.

---

**Engineered with precision. Operated with intelligence.**

⚡ ⚡

"Aut viam inveniam aut faciam"

