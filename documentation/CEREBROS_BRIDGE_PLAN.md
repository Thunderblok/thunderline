# Cerebros Core Bridge Plan (Draft)

Status: Draft (Aug 30 2025)
Owner: ThunderBolt Steward
Related DIPs: (Planned) DIP-CEREBROS-BRIDGE-001, DIP-VIM-001 (consumes persona board outputs)
High Command Items: HC-20 (Bridge), HC-21 (VIM Rollout)

## 1. Purpose
Define a clean, auditable integration boundary between Thunderline (application & orchestration) and the external Cerebros core algorithm repository (private R&D code) without leaking experimental internals or creating tight compile-time coupling.

## 2. Scope
In-Scope:
- Read-only consumption of model search / optimization results
- Invocation API for trial evaluation & artifact registration
- Persona style board generation inputs consumed by VIM PersonaAdaptor
- Telemetry normalization & error classification

Out-of-Scope (Deferred):
- Direct embedding of Cerebros training loops
- Auto code generation into Thunderline runtime
- Cross-repo migrations

## 3. Repository Strategy
External upstream: `cerebros-core-algorithm-alpha` (mirrored locally under `cerebros_core/` which is gitignored).

Local layout (gitignored):
```
./cerebros_core/
  lib/
  scripts/
  README.md
  VERSION
```

Synchronization: Manual pull or subtree vendor script (future). Record commit hash in `Docs/CEREBROS_BRIDGE_VERSION.md` with each update.

## 4. Integration Boundary (Facade)
Introduce facade modules under `Thunderline.ThunderBolt.CerebrosBridge`:
| Module | Responsibility |
|--------|----------------|
| `Client` | Resolve paths, verify version, load NIFs (if any), guard feature flag `:ml_nas` |
| `Invoker` | Execute algorithm entrypoints (e.g. `run_search/2`, `score_persona/2`) with timeout & telemetry |
| `Translator` | Map raw external structs/maps into Ash resource changesets or VIM Problem inputs |
| `Cache` | Optional ETS caching of expensive intermediate results |

All outward calls return `{:ok, value}` / `{:error, %Thunderline.Thunderflow.ErrorClass{}}` (classifier enforced).

## 5. Data Flow Examples
Persona Board → VIM:
1. `PersonaAdaptor` requests candidate feature toggles & pairwise priors.
2. Bridge `Invoker.score_persona/2` returns `%{features: [...], co_occurrence: %{ {a,b} => weight }}`.
3. Adaptor builds BQM (spins = features) → VIM solve (shadow).
4. Solution hashed feature ids logged (privacy gate).

NAS Trial Recording:
1. `Client.run_search/2` yields trial proposals.
2. Each proposal persisted as `Trial` Ash resource (future resource) with state machine.
3. Failures classified (timeout vs dependency).

## 6. Telemetry
Emit:
`[:cerebros, :bridge, :invoke, :start|:stop|:exception]` — measurements: `duration_ms`; metadata: `op`, `version`, `success?`.
`[:cerebros, :bridge, :cache, :hit|:miss]` — metadata: `namespace`.

Link to VIM: Add `bridge_fetch_ms` to VIM solve metadata when persona adaptor includes external fetch.

## 7. Configuration
```elixir
config :thunderline, :cerebros_bridge, %{
  enabled: false,
  repo_path: Path.expand("./cerebros_core", Mix.Project.root()),
  version_file: "VERSION",
  invoke: %{default_timeout_ms: 5_000},
  cache: %{enabled: true, ttl_ms: 60_000, max_entries: 5_000}
}
```

## 8. Security & Privacy
- Enforce allowlist of callable functions (no dynamic eval).
- Strip PII from payloads before logging.
- Hash persona feature names `:blake3_128` before telemetry.
- Version mismatch (local vs declared) → error classification `dependency`.

## 9. Failure & Fallback
| Failure | Detection | Fallback | Code |
|---------|-----------|----------|------|
| Timeout | `Task.await/2` exits | Return cached last successful result or default heuristics | CEREBROS-TIMEOUT |
| Version mismatch | VERSION diff | Disable bridge (flag) & warn | CEREBROS-VERSION |
| Unknown function | Allowlist miss | Error classify validation | CEREBROS-NOFUNC |
| Data shape invalid | Translator validation fail | Error classify validation | CEREBROS-DATA |

## 10. Rollout Phases
| Phase | Mode | Scope | Exit Criteria |
|-------|------|-------|---------------|
| 0 | Disabled | Code merged, flags off | CI green, docs published |
| 1 | Shadow | Persona feature fetch only | Telemetry stability, error rate <1% |
| 2 | Shadow+VIM | Persona + routing metrics feeding VIM | VIM improvement histogram stable |
| 3 | Active (canary) | Persona decisions applied 5% | Uplift KPI (TBD) observed |
| 4 | Expansion | Broader application | SLA stable 2 weeks |

## 11. Open Questions
1. KPI definitions for persona uplift (align with DIP-VIM-001 §10).  
2. Version pinning policy (lockfile vs manual record).  
3. Cache invalidation events — manual vs time-based only?  
4. Multi-tenant isolation concerns (future).  

## 12. Acceptance Checklist
| Item | Status |
|------|--------|
| Flags defined (`:ml_nas`, future `:cerebros_bridge`) | pending |
| Facade modules scaffolded | pending |
| Telemetry events emitted | pending |
| Error codes mapped | pending |
| Docs (this file + DIP draft) | draft |
| CI guard for absence when disabled | pending |

## 13. Next Actions
1. Add flags & config surface.  
2. Scaffold `CerebrosBridge.Client` (path + version resolve) + `Invoker`.  
3. Add telemetry + classifier integration.  
4. Draft DIP-CEREBROS-BRIDGE-001 referencing this plan.  
5. Integrate into VIM PersonaAdaptor (graceful no-op when disabled).  

---
"A bridge is secure when its absence produces a warning, not a crash."  

# Cerebros Bridge Version Record

Tracks the external cerebros core algorithm repo commit hash used locally.

| Date | Commit | Notes |
|------|--------|-------|
| (pending) | (none) | Bridge not yet synced locally |

Update workflow: On sync, update table + include diff summary; PR commit message prefix `CEREBROS-BRIDGE:`.
