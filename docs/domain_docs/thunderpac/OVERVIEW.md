# ThunderPac Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thunderpac/domain.ex`  
**Pantheon Position**: #2 — PAC Lifecycle Domain

## Purpose

ThunderPac is the **PAC lifecycle management domain** (PAC = Personal Autonomous Construct):
- PAC lifecycle (dormant → active → suspended → archived)
- Intent management
- Role definitions and capabilities
- State persistence and memory

**Domain Vector**: Pac → Block → Vine (state → persist → orchestrate)

## Domain Extensions

```elixir
use Ash.Domain,
  extensions: [AshAdmin.Domain],
  otp_app: :thunderline
```

## Registered Resources (6)

| Resource | Module |
|----------|--------|
| PAC | `Thunderline.Thunderpac.Resources.PAC` |
| PACRole | `Thunderline.Thunderpac.Resources.PACRole` |
| PACIntent | `Thunderline.Thunderpac.Resources.PACIntent` |
| PACState | `Thunderline.Thunderpac.Resources.PACState` |
| TraitsEvolutionJob | `Thunderline.Thunderpac.Resources.TraitsEvolutionJob` |
| MemoryCell | `Thunderline.Thunderpac.Resources.MemoryCell` |

## Event Categories

- `pac.lifecycle.*` — Lifecycle transitions
- `pac.intent.*` — Intent events
- `pac.state.*` — State updates and snapshots

## Reference

- HC-47 in THUNDERLINE_MASTER_PLAYBOOK.md
