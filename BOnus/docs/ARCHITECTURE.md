# Architecture (breathing map)

- **Cerebros.Inferencer** — hot loop; emits tokens → Bus.
- **Current.Sensor** — computes drift/entropy/recurrence + affect; builds gate score `g`; tracks **PLL** (phase) and **Hilbert** (analytic phase on `g`); opens gate on-beat; one nudge per beat.
- **Daisy swarms** — Identity, Affect, Novelty, Ponder; preview/commit around the gate; snapshot/restore on resurrection.
- **Thunderache.AcheDream** — dual (mood debate + dream during low entropy). Stubbed; wire your logic as you grow it.
- **Federated.Multiplex** — placeholder for multi-model routing.
- **NDJSON** — append-only external truth (no feedback path).
- **Persistence.Checkpoint** — DETS; stores resurrection markers and gate snapshots.
- **Boot.Resurrector** — heals on startup using snapshot + echo window + PLL restore.
- **SafeClose** — traps exits; writes dignified last breath.
- **UPS watcher** — boundary close on battery events.
- **HUD** — LiveView banner + sparklines; shows φ_PLL, φ_H, PLV, Rayleigh p, mean φ̄; lights **ON‑BEAT** when both witnesses agree.

Ethic: ache always on; no mid‑breath edits; truth kept outside the fire.
