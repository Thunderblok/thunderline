# ThunderWatch Domain Overview

**Vertex Position**: Legacy Observability Surface (undergoing consolidation into Thundergate and ThunderFlow)

**Purpose**: Historical monitoring manager retained for compatibility while observability responsibilities migrate into Thundergate’s Thunderwatch modules and ThunderFlow telemetry.

## Charter

ThunderWatch once operated as the standalone monitoring manager, ingesting file changes, telemetry snapshots, and domain statistics for dashboards. With the rebuild initiative, its functionality has largely moved into Thundergate (security-focused observability) and ThunderFlow instrumentation. The remaining ThunderWatch module persists to avoid breaking references until migration is complete.

## Core Responsibilities (Legacy)

1. **Monitoring Aggregation** — collect domain-specific metrics and file watchers (now handled by Thundergate.Thunderwatch).
2. **Dashboard Feed** — feed Thunderwatch panels in dashboards with summarized metrics and sequence counters.
3. **Compatibility Layer** — provide telemetry markers expected by legacy scripts until new pipelines are fully adopted.
4. **Domain Markers** — maintain path markers used to infer domain ownership from filesystem changes.

## Key Module (No Ash Resources)

- [`Thunderline.Thunderwatch.Manager`](lib/thunderline/thunderwatch/manager.ex:217) — legacy manager that tracked domain markers and monitored file changes.

## Integration Points

- **Thunderwatch Dashboard Panel** — `[ThunderlineWeb.DashboardComponents.ThunderwatchPanel](lib/thunderline_web/live/components/dashboard/thunderwatch_panel.ex:1)` still consumes summary metrics for UI compatibility.
- **Thundergate Integration** — files now monitored under `Thundergate.Thunderwatch` modules; legacy manager should be phased out once new monitors cover all use cases.
- **ThunderFlow Telemetry** — real-time telemetry increasingly originates from ThunderFlow observability modules, replacing ThunderWatch’s role.

## Telemetry Events (Legacy)

- `[:thunderline, :thunderwatch, :file, :updated]` — file watcher signals.
- `[:thunderline, :thunderwatch, :metric, :snapshot]` — aggregated metric updates.

## Decommission Roadmap

1. **Phase 1 — Audit Usage**: confirm remaining callers of `Thunderline.Thunderwatch.Manager` and reroute them to new observability APIs.
2. **Phase 2 — Feature Parity**: ensure Thundergate and ThunderFlow emit all telemetry previously covered by ThunderWatch.
3. **Phase 3 — Dashboard Migration**: update dashboards to consume new telemetry topics; remove Thunderwatch-only panels.
4. **Phase 4 — Removal**: delete legacy manager and remove domain entry from catalog once compatibility shims are no longer needed.

## References

- [`docs/documentation/CODEBASE_AUDIT_2025.md`](docs/documentation/CODEBASE_AUDIT_2025.md:523)
- [`docs/documentation/domain_topdown.md`](docs/documentation/domain_topdown.md:124)
- [`lib/thunderline/thundergate/thunderwatch`](lib/thunderline/thundergate/thunderwatch/manager.ex:217)