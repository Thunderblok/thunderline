# ThunderGrid Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thundergrid/domain.ex`  
**Vertex Position**: Data Plane Ring — Spatial Intelligence Layer

## Purpose

ThunderGrid is the **spatial coordination and GraphQL façade** of Thunderline:
- Spatial coordinate systems (hexagonal grids)
- Zone boundary definitions and management
- GraphQL API for spatial operations
- Grid resource allocation
- Spatial event tracking and replication

**Design Principle**: "Grid places, Bolt computes" — spatial topology for intelligent workload placement.

## Domain Extensions

```elixir
use Ash.Domain,
  validate_config_inclusion?: false,
  extensions: [AshGraphql.Domain, AshJsonApi.Domain]
```

- **AshGraphql** — GraphQL queries/mutations for zones
- **AshJsonApi** — JSON:API at `/api/thundergrid`

## Directory Structure

```
lib/thunderline/thundergrid/
├── domain.ex                    # Ash domain (5 resources)
├── supervisor.ex                # Domain supervisor
├── api.ex                       # GraphQL/RPC interface
├── validations.ex               # Custom validations
├── unikernel_data_layer.ex      # Optional unikernel data layer
└── resources/                   # Ash resources (7 files)
    ├── spatial_coordinate.ex    # Registered
    ├── zone_boundary.ex         # Registered
    ├── zone.ex                  # Registered
    ├── zone_event.ex            # Registered
    ├── chunk_state.ex           # Registered
    ├── grid_zone.ex             # Embedded (not registered)
    └── grid_resource.ex         # Embedded (not registered)
```

## Registered Ash Resources

### Main Domain (5 resources)

| Resource | Module | File |
|----------|--------|------|
| SpatialCoordinate | `Thunderline.Thundergrid.Resources.SpatialCoordinate` | resources/spatial_coordinate.ex |
| ZoneBoundary | `Thunderline.Thundergrid.Resources.ZoneBoundary` | resources/zone_boundary.ex |
| Zone | `Thunderline.Thundergrid.Resources.Zone` | resources/zone.ex |
| ZoneEvent | `Thunderline.Thundergrid.Resources.ZoneEvent` | resources/zone_event.ex |
| ChunkState | `Thunderline.Thundergrid.Resources.ChunkState` | resources/chunk_state.ex |

### Embedded Resources (Not Registered)

| Resource | Module | File |
|----------|--------|------|
| GridZone | `Thunderline.Thundergrid.Resources.GridZone` | resources/grid_zone.ex |
| GridResource | `Thunderline.Thundergrid.Resources.GridResource` | resources/grid_resource.ex |

## GraphQL Endpoints

```elixir
graphql do
  authorize? false

  queries do
    list Zone, :zones, :read
    list Zone, :available_zones, :available_zones
    get Zone, :zone_by_coordinates, :by_coordinates
  end

  mutations do
    create Zone, :spawn_zone, :spawn_zone
    update Zone, :adjust_zone_entropy, :adjust_entropy
    update Zone, :activate_zone, :activate
    update Zone, :deactivate_zone, :deactivate
  end
end
```

## JSON:API Configuration

```elixir
json_api do
  prefix "/api/thundergrid"
  log_errors? true
end
```

## Resource Responsibilities

| Resource | Purpose |
|----------|---------|
| SpatialCoordinate | Core hex-based coordinate entity |
| Zone | Spatial zones with ownership and tier metadata |
| ZoneBoundary | Adjacency and boundaries between zones |
| ZoneEvent | Logs spatial events (creation, failover, replication) |
| ChunkState | Chunk-level state for distributed data/workloads |
| GridZone (embedded) | Embedded zone representation |
| GridResource (embedded) | Embedded resource allocation |

## Supporting Modules

| Module | Purpose | File |
|--------|---------|------|
| API | GraphQL/RPC interface | api.ex |
| UnikernelDataLayer | Optional unikernel data layer | unikernel_data_layer.ex |
| Validations | Custom validation modules | validations.ex |

## Authorization

```elixir
graphql do
  authorize? false  # GraphQL authorization disabled!
end
```

⚠️ **Security Note**: GraphQL authorization is currently disabled. Reinstate `authorize? true` before production.

## Known Issues & TODOs

### 1. GraphQL Authorization Disabled
`authorize? false` on GraphQL — all operations are public.

### 2. Policy Patterns
Resources may have `authorize_if always()` or commented policies.
See `DOMAIN_SECURITY_PATTERNS.md` for audit results.

### 3. Embedded vs Registered
`GridZone` and `GridResource` are embedded resources but not explicitly documented as such in the domain.

### 4. validate_config_inclusion? false
Domain has `validate_config_inclusion?: false` — resources may exist in files but not be explicitly listed.

## Telemetry Events

- `[:thunderline, :thundergrid, :zone, :created|:updated|:deleted]`
- `[:thunderline, :thundergrid, :boundary, :changed]`
- `[:thunderline, :thundergrid, :chunk, :state_changed]`
- `[:thunderline, :thundergrid, :replication, :started|:completed]`

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Spatial coordinate query | 8 ms | 50 ms | 5k/s |
| Zone placement decision | 20 ms | 120 ms | 1k/s |
| Chunk state update | 15 ms | 90 ms | 3k/s |
| GraphQL query | 25 ms | 150 ms | 2k/s |
| Zone replication event | 40 ms | 200 ms | 500/min |

## Development Priorities

1. **Enable Authorization** — Set `authorize? true` on GraphQL
2. **Policy Restoration** — Re-enable Ash policies across spatial resources
3. **Metrics Activation** — Populate dashboard metrics marked "OFFLINE"
4. **Replication Governance** — Finalize zone event replication policies

## Related Domains

- **ThunderBolt** — Requests zone placement before scheduling compute
- **ThunderFlow** — Receives `grid.*` events on zone state changes
- **ThunderBlock** — Informed of replication targets and retention
- **ThunderCrown** — Provides spatial insight for governance
- **ThunderLink** — Transport routing based on zone proximity
- **ThunderVine** — Logs spatial events into lineage graphs
