# ThunderGrid Domain Overview

**Vertex Position**: Data Plane Ring — Spatial Intelligence Layer

**Purpose**: Spatial coordination and GraphQL façade that models zones, boundaries, and placement for distributed Thunderline workloads.

## Charter

ThunderGrid governs the spatial topology of Thunderline. It offers a canonical representation of zones, coordinates, and boundaries, enabling intelligent placement of compute, data, and agents. The domain exposes GraphQL interfaces, synchronizes ECS-like state, and ensures that cross-domain operations respect spatial ownership and replication policies.

## Core Responsibilities

1. **Spatial Modeling** — maintain hex-based spatial coordinates, zones, and boundaries for all deployment regions.
2. **Placement Decisions** — provide APIs and queries that ThunderBolt, ThunderForge, and agents use to request placement guidance.
3. **GraphQL Surface** — expose spatial data through GraphQL for dashboards, operators, and external integrators.
4. **Replication & Consistency** — track chunk state and zone events to support multi-zone replication and failover strategies.
5. **Telemetry & Monitoring** — emit spatial metrics and change events consumed by ThunderFlow and Thunderwatch.
6. **Policy Enforcement** — enforce tenancy and access policies across spatial resources (currently undergoing remediation).

## Ash Resources

- [`Thunderline.Thundergrid.Resources.SpatialCoordinate`](lib/thunderline/thundergrid/resources/spatial_coordinate.ex:1) — core coordinate entity with hex-based positioning.
- [`Thunderline.Thundergrid.Resources.Zone`](lib/thunderline/thundergrid/resources/zone.ex:9) — represents spatial zones with metadata about ownership and tier.
- [`Thunderline.Thundergrid.Resources.ZoneBoundary`](lib/thunderline/thundergrid/resources/zone_boundary.ex:11) — captures adjacency and boundaries between zones.
- [`Thunderline.Thundergrid.Resources.ZoneEvent`](lib/thunderline/thundergrid/resources/zone_event.ex:10) — logs spatial events (creation, failover, replication).
- [`Thunderline.Thundergrid.Resources.ChunkState`](lib/thunderline/thundergrid/resources/chunk_state.ex:10) — tracks chunk-level state for distributed data or workloads.

## Supporting Modules

- [`Thunderline.Thundergrid.Domain`](lib/thunderline/thundergrid/domain.ex:2) — Ash domain definition enabling GraphQL integration.
- [`Thunderline.Thundergrid.API`](lib/thunderline/thundergrid/api.ex:1) — GraphQL and RPC interface for spatial queries.
- [`Thunderline.Thundergrid.UnikernelDataLayer`](lib/thunderline/thundergrid/unikernel_data_layer.ex:1) — optional data layer for unikernel deployments.
- [`Thunderline.Thunderlink.DashboardMetrics`](lib/thunderline/thunderlink/dashboard_metrics.ex:183) — consumes ThunderGrid metrics for operator dashboards.

## Integration Points

### Vertical Edges

- **ThunderBolt → ThunderGrid**: requests zone placement and chunk availability before scheduling heavy compute.
- **ThunderGrid → ThunderFlow**: publishes `grid.*` events when zones change state or new spatial data is recorded.
- **ThunderGrid → ThunderBlock**: informs storage layer of replication targets and zone-level retention requirements.
- **ThunderGrid → Thundercrown**: provides spatial insight for governance decisions tied to geographic or tenant boundaries.

### Horizontal Edges

- **ThunderGrid ↔ ThunderForge**: shares spatial context for compiled workloads that must respect placement constraints.
- **ThunderGrid ↔ ThunderLink**: informs transport routing and presence decisions based on zone proximity.
- **ThunderGrid ↔ ThunderVine**: logs spatial events into lineage graphs to track where data transformations occurred.

## Telemetry Events

- `[:thunderline, :thundergrid, :zone, :created|:updated|:deleted]`
- `[:thunderline, :thundergrid, :boundary, :changed]`
- `[:thunderline, :thundergrid, :chunk, :state_changed]`
- `[:thunderline, :thundergrid, :replication, :started|:completed]`

## Performance Targets

| Operation | Latency (P50) | Latency (P99) | Throughput |
|-----------|---------------|---------------|------------|
| Spatial coordinate query | 8 ms | 50 ms | 5k/s |
| Zone placement decision | 20 ms | 120 ms | 1k/s |
| Chunk state update | 15 ms | 90 ms | 3k/s |
| GraphQL query | 25 ms | 150 ms | 2k/s |
| Zone replication event | 40 ms | 200 ms | 500/min |

## Security & Policy Notes

- Security audit identified multiple resources with `authorize_if always()` or commented policies (see [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:419)); reinstate tenancy enforcement.
- Placement decisions should validate tenant ownership before returning zone assignments.
- Ensure replication metadata is encrypted or masked when exposed via GraphQL.
- Align policy updates with ThunderCrown governance to respect cross-tenant rules.

## Testing Strategy

- Unit tests for spatial coordinate calculations, boundary updates, and GraphQL resolvers.
- Integration tests covering placement workflows between ThunderBolt and ThunderGrid.
- Property tests verifying hex coordinate invariants and adjacency relationships.
- Load tests to ensure GraphQL and API endpoints scale with dashboard traffic.

## Development Roadmap

1. **Phase 1 — Policy Restoration**: re-enable Ash policies across spatial resources and add tenancy coverage.
2. **Phase 2 — Metrics Activation**: populate dashboard metrics currently marked “OFFLINE” and integrate with Thunderwatch.
3. **Phase 3 — Replication Governance**: finalize replication policies, ensure zone events trigger consistent updates.
4. **Phase 4 — Spatial Analytics**: enhance APIs with load balancing and predictive placement signals.

## References

- [`lib/thunderline/thundergrid/domain.ex`](lib/thunderline/thundergrid/domain.ex:2)
- [`lib/thunderline/thundergrid/resources`](lib/thunderline/thundergrid/resources/zone.ex:9)
- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:350)
- [`docs/documentation/DOMAIN_SECURITY_PATTERNS.md`](docs/documentation/DOMAIN_SECURITY_PATTERNS.md:419)
- [`docs/documentation/planning/Thunderline_2025Q4_Squad_Matrix.md`](docs/documentation/planning/Thunderline_2025Q4_Squad_Matrix.md:29)
- [`docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md`](docs/documentation/THUNDERLINE_REBUILD_INITIATIVE.md:575)