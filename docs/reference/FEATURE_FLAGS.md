# 🎛 Feature Flags Registry (v1.0)

> High Command Item: HC-10 (P0)  
> Status: **✅ COMPLETE** (Nov 27, 2025) — Helper implemented, flags documented, governance defined.

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

## 3. Flag Table (Complete)

### Core Feature Flags (via `Thunderline.Feature`)
| Flag Key (app env) | Env Var | Default | Type | Scope | Description | Lifecycle |
|--------------------|---------|---------|------|-------|-------------|-----------|
| `:enable_ups` | `ENABLE_UPS` | false | boolean | Infra | Enable UPS watcher process & status events | stable |
| `:enable_ndjson` | `ENABLE_NDJSON` | false | boolean | Logging | Start NDJSON logging writer | stable |
| `:ml_nas` | `TL_FEATURES_ML_NAS` | false | boolean | ML | Expose experimental NAS / search APIs via CerebrosBridge | experimental |
| `:unified_model` | `TL_FEATURES_UNIFIED_MODEL` | false | boolean | AI | Enable Unified Persistent Model trainer + agent adapters | preview |
| `:voice_input` | `TL_FEATURES_VOICE` | false | boolean | UX | Enable voice/WebRTC ingestion pipeline (HC-13) | planned |
| `:email_mvp` | `TL_FEATURES_EMAIL_MVP` | true | boolean | Product | Gate email automation surfaces (UI + events) | preview |
| `:presence_debug` | `TL_FEATURES_PRESENCE_DEBUG` | false | boolean | Debug | Extra presence event logging | debug |
| `:crown_daisy` | `TL_FEATURES_CROWN_DAISY` | false | boolean | AI Governance | Enable Daisy cognitive swarm processes | experimental |
| `:signal_stack` | `TL_FEATURES_SIGNAL_STACK` | false | boolean | Compute | Enable signal/phase processing stack | experimental |
| `:ai_chat_panel` | `TL_FEATURES_AI_CHAT_PANEL` | false | boolean | UI | Enable experimental Ash AI chat assistant panel | experimental |
| `:tocp` | `TL_FEATURE_TOCP` | false | boolean | Protocol | Enable TOCP supervisor & processes | scaffold |
| `:tocp_presence_insecure` | `TL_FEATURE_TOCP_PRESENCE_INSECURE` | false | boolean | Protocol | Disable control-frame signing (perf tests only) | debug |
| `:vim` | `TL_FEATURE_VIM` | false | boolean | Optimization | Enable Virtual Ising Machine layer | experimental |
| `:vim_active` | `TL_FEATURE_VIM_ACTIVE` | false | boolean | Optimization | Force VIM into active (non-shadow) mode | preview |

### Direct Environment Variable Flags
| Env Var | Default | Scope | Description | Used By |
|---------|---------|-------|-------------|---------|
| `TL_ENABLE_REACTOR` | `false` | Orchestration | Switch between simple EventProcessor path and Reactor orchestration | `Thunderchief.Orchestrator`, `EventOps` |
| `SKIP_ASH_SETUP` | `false` | Boot | Skip Ash domain setup during application start | `Thunderline` module |
| `DISABLE_THUNDERWATCH` | `false` | Infra | Disable ThunderWatch supervisor | `Thundergate.Thunderwatch.Supervisor` |
| `GATE_SELFTEST_DISABLED` | `false` | Infra | Disable Gate self-test on boot | `Thundergate.SelfTest` |
| `DEMO_MODE` | `false` | Auth | Enable demo mode authentication bypass | `ThunderlineWeb.Auth.Actor` |
| `TL_ENABLE_CEREBROS_BRIDGE` | `false` | ML | Enable Cerebros NAS bridge | `Thunderbolt.CerebrosBridge` |
| `TL_ENABLE_OBAN` | `false` | Jobs | Enable Oban job processing | Training scripts |
| `TL_ENABLE_ML_PIPELINE` | `false` | ML | Enable full ML pipeline at boot | ML pipeline |

### Service Configuration (Not Feature Flags)
| Env Var | Default | Scope | Description |
|---------|---------|-------|-------------|
| `UPS_BACKEND` | `nut` | Infra | UPS monitoring backend |
| `UPS_NAME` | `ups@localhost` | Infra | UPS device identifier |
| `UPS_POLL_MS` | `2000` | Infra | UPS polling interval |
| `MLFLOW_TRACKING_URI` | (none) | ML | MLflow server URI |
| `MLFLOW_ENABLED` | `false` | ML | Enable MLflow integration |

### Cross-Domain Layer Flags (HC-31+)
| Env Var | Default | Scope | Description |
|---------|---------|-------|-------------|
| `LAYER_ROUTING_ENABLED` | `true` | Layers | Enable Flow×Grid routing layer |
| `LAYER_OBSERVABILITY_ENABLED` | `true` | Layers | Enable Gate×Crown observability layer |
| `LAYER_INTELLIGENCE_ENABLED` | `true` | Layers | Enable Bolt×Crown intelligence layer |
| `LAYER_PERSISTENCE_ENABLED` | `true` | Layers | Enable Block×Flow persistence layer |
| `LAYER_COMMUNICATION_ENABLED` | `true` | Layers | Enable Link×Gate communication layer |
| `LAYER_ORCHESTRATION_ENABLED` | `false` | Layers | Enable Vine×Crown orchestration layer |
| `LAYER_CLUSTERING_ENABLED` | `false` | Layers | Enable Bolt×Vine clustering layer |

## 4. Evaluation Pattern
```elixir
# Using the implemented Thunderline.Feature module
if Thunderline.Feature.enabled?(:ml_nas) do
  # experimental path
end

# With default fallback
if Thunderline.Feature.enabled?(:new_feature, default: false) do
  # feature path
end
```

The `Thunderline.Feature` module is implemented at `lib/thunderline/feature.ex` and provides:

```elixir
@spec enabled?(atom(), keyword()) :: boolean()
# Options:
#   :default => boolean (override global default in specific call sites)

@spec override(atom(), boolean()) :: :ok
# Per-process override for tests

@spec clear_override(atom()) :: :ok
# Clear test override

@spec all() :: map()
# Return all configured flags
```

Invariants:
- Function is pure (no side effects) for same arguments until config reload.
- Flag atoms not present return `false` unless explicit `:default` provided.
- Runtime reads from `Application.get_env(:thunderline, :features, [])` for flexibility.

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

## 10. Completion Status (HC-10)
- [x] Implement `Thunderline.Feature` module (lookup + overrides) — `lib/thunderline/feature.ex`
- [x] Add test helpers for temporary flag overrides (`Feature.override/2`, `Feature.clear_override/1`)
- [x] Document all discovered flags (core flags, env vars, layer flags)
- [x] Define governance workflow
- [ ] Add CI check ensuring flags documented here (mix task scanning code for `Feature.enabled?` atoms)
- [ ] Wire NDJSON & UPS processes to use unified feature lookup (currently use direct env reads)
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
defmodule Thunderline.Feature do`
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
