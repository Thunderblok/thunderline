## DIP-CEREBROS-BRIDGE-001 — Cerebros Core Bridge

Status: Draft (Phase-1 Scaffold)  
Related: CEREBROS_BRIDGE_PLAN.md, DIP-VIM-001  
High Command: HC-20 (Bridge), HC-21 (VIM Rollout)

### 1. Summary
Introduce a feature-flagged facade (`Thunderline.Thunderbolt.CerebrosBridge.*`) isolating integration with the external Cerebros core (local mirror or future RPC). Provides version discovery, invocation wrapper with telemetry, translation boundary, and optional caching. Disabled by default; safe no-op when flag absent.

### 2. Scope (Phase-1)
- Path & VERSION file resolution
- Invocation wrapper with timeout + telemetry events
- Encode/decode stubs (no shape enforcement yet)
- ETS cache scaffold (not yet used by invoker logic)
- Config & feature flag plumbing

Out of Scope (Deferred): real RPC/NIF, advanced translation validation, cache eviction policy beyond TTL, error classifier integration, metrics enrichment.

### 3. Telemetry
`[:cerebros,:bridge,:invoke,:start|:stop|:exception]` — execution lifecycle  
Future: `[:cerebros,:bridge,:cache,:hit|:miss]` when cache integrated into flow.

### 4. Configuration
See `config/config.exs` keys: `:cerebros_bridge` (enabled, repo_path, invoke.default_timeout_ms, cache ttl/max_entries).

### 5. Flags
`:cerebros_bridge` (disabled) — when enabled + config.enabled true, invocations active.

### 6. Error Semantics
Disabled: returns `{:error, %{class: :dependency, origin: :system}}`.  
Timeout: `{:error, %{class: :timeout, origin: :cerebros}}`.  
Exception: `{:error, %{class: :exception, origin: :cerebros}}`.

### 7. Acceptance (for merging Phase-1)
- Compiles clean; no supervision impact (cache not auto-started yet)  
- Telemetry events emitted (manual inspection)  
- Disabled path deterministic  
- Docs present (this DIP + plan)  
- Config + feature flags in place  

### 8. Follow-On (Phase-2)
| Item | Description |
|------|-------------|
| RPC Integration | Real callouts (Port or direct module) with allowlist |
| Cache Wiring | Use `Cache.get/put` for repeated persona/routing fetches |
| ErrorClassifier | Wrap errors into `%Thunderline.ErrorClass{}` |
| Metrics Enrichment | Add duration_ms, version, success? metadata expansions |
| Bridge Tests | Unit tests for version/timeout/exception branches |
| Security | Payload sanitization & PII hashing (persona) |

### 9. Ownership
Steward: ThunderBolt. Observability review required for telemetry changes.

---
"Bridge returns value or structured reason; never an opaque crash."
