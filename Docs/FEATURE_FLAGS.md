# 🎛 Feature Flags Registry (Draft v0.2)

> High Command Item: HC-10 (P0)  
> Status: Expanded draft — adds helper contract, governance workflow, override mechanics, testing guidance.

## 1. Purpose
Central catalog of all runtime feature & capability toggles controlling optional subsystems, experimental surfaces, or staged rollouts. Ensures:
- Auditable change surface
- Safe progressive delivery
- Consistent naming & evaluation semantics

## 2. Naming Convention
```
:thunderline, :features, <snake_case_flag>
```
Environment variables map where applicable (e.g. `ENABLE_UPS=true`). Prefer explicit boolean; avoid tri-state unless documented.

## 3. Flag Table (Initial)
| Flag Key (app env) | Env Var | Default | Type | Scope | Description | Lifecycle |
|--------------------|---------|---------|------|-------|-------------|-----------|
| `:enable_ups` | ENABLE_UPS | false | boolean | Infra | Enable UPS watcher process & status events | stable |
| `:enable_ndjson` | ENABLE_NDJSON | false | boolean | Logging | Start NDJSON logging writer | stable |
| `:ml_nas` | FEATURES_ML_NAS | false | boolean | ML | Expose experimental NAS / search APIs | experimental |
| `:voice_input` | FEATURES_VOICE | false | boolean | UX | Enable voice/WebRTC ingestion pipeline (HC-13) | planned |
| `:email_mvp` | FEATURES_EMAIL_MVP | true | boolean | Product | Gate email automation surfaces (UI + events) | preview |
| `:presence_debug` | FEATURES_PRESENCE_DEBUG | false | boolean | Debug | Extra presence event logging | debug |
| `:crown_daisy` | FEATURES_CROWN_DAISY | false | boolean | AI Governance | Enable Daisy cognitive swarm processes | experimental |
| `:signal_stack` | FEATURES_SIGNAL_STACK | false | boolean | Compute | Enable signal/phase processing stack (migrated from ENABLE_SIGNAL_STACK) | experimental |

(Extend table as flags added.)

## 4. Evaluation Pattern
```elixir
if Thunderline.Feature.enabled?(:ml_nas) do
  # experimental path
end
```
Proposed helper module (to implement): `Thunderline.Feature.enabled?(flag :: atom)` reading from `Application.get_env(:thunderline, :features, [])`.

Helper Contract (planned):
```elixir
@spec enabled?(atom(), keyword()) :: boolean()
# Options (future):
#   :actor => %User{} (for per-tenant rules later)
#   :default => boolean (override global default in specific call sites)
```

Invariants:
- Function MUST be pure (no side effects) for same arguments until config reload.
- Flag atoms not present return `false` unless explicit `:default` provided.
- All read operations O(1); precompute map in an ETS cache on config change (future optimization).

## 5. Change Management
| Action | Requirement |
|--------|-------------|
| Add flag | PR updates this file + commit message `FEATURE-FLAG:` |
| Remove flag | Mark `Lifecycle=deprecated`, keep 1 release, then delete |
| Promote experimental → stable | Update table + changelog entry |

## 6. Telemetry & Audit
Emit on evaluation (optional future): `[:thunderline,:feature,:check]` (sampled) with `flag`, `enabled` for adoption metrics.

## 7. Testing Guidelines
- Feature-specific tests wrap with explicit env override.
- Use setup tags: `@tag features: [:ml_nas]` to inject config for test process.

## 8. Governance Workflow
1. Propose new flag via PR editing this file + implementation.
2. Provide rationale: rollout risk mitigated, fallback path, anticipated removal date (if experimental/preview).
3. Assign Lifecycle: `experimental` (high churn), `preview` (stable API, not default), `stable`, `deprecated`, `debug`.
4. Steward approval required for `experimental` flags that touch security or persistence.
5. Quarterly review: remove or promote stale experimental flags (>90d).

Escalation: Any flag toggling persistence schema or data integrity MUST undergo DIP review.

## 9. Override Mechanics
Runtime (test/dev) temporary override pattern:
```elixir
ExUnit.Callbacks.setup do
  Thunderline.Feature.override(:ml_nas, true)
  on_exit(fn -> Thunderline.Feature.clear_override(:ml_nas) end)
end
```

Implementation sketch:
```elixir
def override(flag, value) when is_boolean(value) do
  Process.put({:thunderline_flag_override, flag}, value)
end
def clear_override(flag), do: Process.delete({:thunderline_flag_override, flag})
def enabled?(flag, _opts \\ []) do
  case Process.get({:thunderline_flag_override, flag}) do
    nil -> lookup(flag)
    override -> override
  end
end
```

## 10. Open TODOs (HC-10 Completion)
- [ ] Implement `Thunderline.Feature` module (lookup + overrides)
- [ ] Add test helpers for temporary flag overrides
- [ ] Add CI check ensuring flags documented here (mix task scanning code for `Feature.enabled?` atoms)
- [ ] Wire NDJSON & UPS processes to use unified feature lookup (if not already)
- [ ] Add telemetry emission (sampled) for evaluations
- [ ] Add quarterly review script (list flags by lifecycle & age)

## 11. Future Enhancements
- Per-tenant dynamic store (Ash resource + caching)
- Percentage rollouts (`rollout: %{ml_nas: 10}` semantics)
- Cohort targeting (hash actor id)
- Live flag toggling dashboard
- CLI tooling: `mix thunderline.flags` list & audit


## 12. Example Feature Helper (Sketch)
```elixir
defmodule Thunderline.Feature do
  @moduledoc "Runtime feature flag evaluation"
  @features Application.compile_env(:thunderline, :features, []) |> Map.new()
  @doc """Return true if flag enabled. Supports per-process override for tests."""
  def enabled?(flag, opts \\ []) when is_atom(flag) do
    case Process.get({:thunderline_flag_override, flag}) do
      nil -> Map.get(@features, flag, Keyword.get(opts, :default, false))
      override -> override
    end
  end
  def override(flag, value) when is_boolean(value), do: Process.put({:thunderline_flag_override, flag}, value)
  def clear_override(flag), do: Process.delete({:thunderline_flag_override, flag})
end
```

---
Expanded draft complete. Implement helper + CI lint in HC-10 PR.
