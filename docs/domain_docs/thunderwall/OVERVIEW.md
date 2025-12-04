# ThunderWall Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thunderwall/domain.ex`  
**Pantheon Position**: #12 — System Boundary/Entropy Sink

## Purpose

ThunderWall is the **system boundary and entropy sink**:
- Decay processing (archive expired resources)
- Overflow handling (reject streams)
- Entropy metrics (system decay tracking)
- GC scheduling

**System Cycle**: Wall is the END of the cycle (Core → Wall).

## Domain Extensions

```elixir
use Ash.Domain, extensions: [AshAdmin.Domain]

authorization do
  authorize :by_default
  require_actor? false
end
```

## Registered Resources (3)

| Resource | Module |
|----------|--------|
| DecayRecord | `Thunderline.Thunderwall.Resources.DecayRecord` |
| ArchiveEntry | `Thunderline.Thunderwall.Resources.ArchiveEntry` |
| SandboxLog | `Thunderline.Thunderwall.Resources.SandboxLog` |

## Receives From

- Expired PACs from Thunderpac
- Stale events from Thunderflow
- Orphaned data from Thunderblock
- Failed saga states from Thundercrown

## Event Categories

- `wall.decay.*` — Resource decay events
- `wall.archive.*` — Archival events
- `wall.gc.*` — Garbage collection events
- `wall.overflow.*` — Overflow/reject events
