## Module Migration Matrix

This file tracks the canonical namespace migration. Deprecated modules emit
`:telemetry` events under `[:thunderline, :deprecated_module, :used]` with tags `{module: OldModule}`.

| Legacy Module | Canonical Replacement | Status | Notes |
|---------------|-----------------------|--------|-------|
| `Thunderline.Log.NDJSON` | `Thunderline.Thunderflow.Observability.NDJSON` | Deprecated delegate | Replace imports/aliases |
| `Thunderline.Hardware.UPS` | `Thunderline.Thundergate.UPS` | Deprecated delegate | Feature flag gating via `:enable_ups` (if added later) |
| `Thunderline.Boot.Resurrector` | `Thunderline.Thunderflow.Resurrector` | Deprecated delegate | Resurrection logic consolidated |
| `Thunderline.Persistence.Checkpoint` | `Thunderline.Thunderblock.Checkpoint` | Deprecated delegate | DETS file unchanged |
| `Thunderline.Daisy.*` | `Thunderline.Thundercrown.Daisy.*` | Deprecated delegates | Crown domain canonicalized |
| `Thunderline.EventProcessor` | `Thunderline.Thunderflow.Processor` | Deprecated delegate | Minimal processor canonicalized |
| `Thunderchief.ObanHealth` | `Thunderline.Thunderflow.Telemetry.ObanHealth` | Deprecated delegate | Health telemetry domain-sorted |
| `Thunderchief.ObanDiagnostics` | `Thunderline.Thunderflow.Telemetry.ObanDiagnostics` | Deprecated delegate | Diagnostics domain-sorted |
| `Thunderline.Changes.*` | `Thunderline.Thunderbolt.Changes.*` | Deprecated delegates | Change modules domain-sorted |
| `Thunderchief.Jobs.DomainProcessor` | `Thunderline.Thunderflow.Jobs.DomainProcessor` (planned) | TODO | Stub still under thunderchief pending refactor |

### Telemetry

Register a handler if you want to surface usage during rollout:

```elixir
:telemetry.attach_many(
  "thunderline-deprecated-log",
  [[:thunderline, :deprecated_module, :used]],
  fn _event, _meas, meta, _cfg ->
    IO.puts("Deprecated module used: #{inspect(meta.module)}")
  end,
  nil
)
```

### Removal Plan

- Phase 1 (current): Delegates + telemetry + warnings.
- Phase 2: Update all internal call sites to canonical namespaces (in progress).
- Phase 3: CI failing test if deprecated modules are referenced (static grep + test helper).
- Phase 4: Remove deprecated files after two release cycles or zero telemetry hits for 14 days.

### Checklist

- [x] Add canonical modules
- [x] Add delegates
- [x] Emit telemetry on usage
- [x] Add migration matrix doc
- [x] Replace all call sites
- [ ] Add CI enforcement
- [ ] Remove legacy modules
