# ThunderCore Domain Overview (Grounded)

**Last Verified**: 2025-01-XX  
**Source of Truth**: `lib/thunderline/thundercore/domain.ex`  
**Pantheon Position**: #1 — Origin/Seedpoint Domain

## Purpose

ThunderCore is the **system origin and heartbeat domain**:
- Tick emanation (system heartbeat)
- System clock (monotonic time)
- Identity kernel (PAC seedpoint generation)
- Temporal alignment

**System Cycle**: Core is the START of the cycle (Core → Wall).

## Domain Extensions

```elixir
use Ash.Domain,
  extensions: [AshAdmin.Domain],
  otp_app: :thunderline
```

## Registered Resources (2)

| Resource | Module |
|----------|--------|
| TickState | `Thunderline.Thundercore.Resources.TickState` |
| IdentityKernel | `Thunderline.Thundercore.Resources.IdentityKernel` |

## Event Categories

- `core.tick.*` — Tick/heartbeat events
- `core.identity.*` — Identity kernel events
- `core.clock.*` — Clock synchronization events

## Reference

- HC-46 in THUNDERLINE_MASTER_PLAYBOOK.md
