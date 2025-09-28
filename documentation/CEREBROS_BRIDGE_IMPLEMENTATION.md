# Thunderline ↔ Cerebros Bridge Implementation Overview

_Status: 2025-09-06_

This note captures the concrete code that currently powers the Cerebros bridge inside the Thunderbolt domain. It connects the original bridge plan to the shipping Elixir modules, highlights how operations are configured and invoked, and calls out the remaining work required before we can run NAS loops from production flows or dashboard agents.

## What the bridge does today

* **Feature gate:** All entry points live behind the `:ml_nas` feature flag (`Thunderline.Feature.enabled?/2`).
* **Runtime surface:** Configuration is sourced from `config :thunderline, :cerebros_bridge` with environment overrides (for example `CEREBROS_REPO`, `CEREBROS_SCRIPT`, `CEREBROS_PYTHON`, `CEREBROS_TIMEOUT_MS`).
* **External process execution:** Contracts are JSON encoded and sent to a Python script via `System.cmd/3` with an isolated environment. The default script shipped in-repo is `generative-proof-of-concept-CPU-preprocessing-in-memory.py`.
* **Error semantics:** All failures are normalized into `%Thunderline.Thunderflow.ErrorClass{}` structures so upstream callers can distinguish timeouts, dependency issues, exit codes, and parser failures.
* **Telemetry + events:** Every call emits `[:cerebros, :bridge, :invoke, *_]` telemetry and publishes `ml.run.*` events on the Thunderflow bus, allowing observability dashboards to light up without dashboard coupling.
* **Cache stub:** An ETS-backed cache module exists but is not yet wired into the supervision tree, so caching is effectively disabled.

## Module map (lib/thunderline/thunderbolt/cerebros_bridge)

| Module | Key responsibilities |
| --- | --- |
| `Client` | Main facade. Guards feature flag, materializes config, marshals contracts through the translator, invokes the subprocess, caches results, and emits Thunderflow events (`ml.run.start/stop/exception`, `ml.run.trial`). |
| `Contracts` | Versioned structs (`RunStartedV1`, `TrialReportedV1`, `RunFinalizedV1`) encoding the payloads exchanged with the bridge and Thunderflow events. |
| `Translator` | Converts contracts/payloads into executable call specs (command, args, env, JSON stdin) and back into decoded results. Adds metadata, cache keys, and environment variables such as `CEREBROS_BRIDGE_OP`, `CEREBROS_BRIDGE_RUN_ID`, and `CEREBROS_BRIDGE_PAYLOAD`. |
| `Invoker` | Executes the subprocess via `Task.Supervisor.async_nolink/2` (expects a supervisor named `Thunderline.TaskSupervisor`), applies retry/backoff logic, enforces per-attempt timeouts, parses stdout (JSON by default), and emits telemetry (`start`, `stop`, `exception`). |
| `Cache` | Intended ETS cache for bridge responses with TTL and max-entry enforcement. Currently **not started** anywhere, so cache hits never happen. |
| `Validator` | Runs readiness checks for feature flag, config enabled, repo/script paths, Python executable, working directory, VERSION file, and cache sizing. Powers `mix thunderline.ml.validate`. |

## Runtime configuration quick reference

```elixir
config :thunderline, :cerebros_bridge,
  enabled: false,
  repo_path: System.get_env("CEREBROS_REPO") || "../../cerebros-core-algorithm-alpha",
  script_path: System.get_env("CEREBROS_SCRIPT") || "../../cerebros-core-algorithm-alpha/generative-proof-of-concept-CPU-preprocessing-in-memory.py",
  python_executable: System.get_env("CEREBROS_PYTHON") || "python3",
  working_dir: System.get_env("CEREBROS_WORKDIR") || "../../cerebros-core-algorithm-alpha",
  invoke: [
    default_timeout_ms: System.get_env("CEREBROS_TIMEOUT_MS") |> parse_int(15_000),
    max_retries: System.get_env("CEREBROS_MAX_RETRIES") |> parse_int(2),
    retry_backoff_ms: System.get_env("CEREBROS_RETRY_BACKOFF_MS") |> parse_int(750)
  ],
  env: %{"PYTHONUNBUFFERED" => "1"},
  cache: [
    enabled: truthy?(System.get_env("CEREBROS_CACHE_ENABLED"), default: true),
    ttl_ms: System.get_env("CEREBROS_CACHE_TTL_MS") |> parse_int(30_000),
    max_entries: System.get_env("CEREBROS_CACHE_MAX_ENTRIES") |> parse_int(512)
  ]
```

To actually execute the bridge you must:

1. Enable the feature flag (`config :thunderline, features: [:ml_nas, …]` or `FEATURES=ml_nas` in deployments).
2. Set `enabled: true` under `:cerebros_bridge` (or export `CEREBROS_ENABLED=1` once we add that env switch).
3. Provide a resolvable repo and script path (the validator enforces these).
4. Ensure Python dependencies for the Cerebros script are installed in the same environment as the Thunderline release / pod.

Helm values example (`thunderhelm/deploy/chart/examples/values-hpo-demo.yaml`):

```yaml
env:
  FEATURES: "ml_nas,cerebros_bridge"
  CEREBROS_REPO: "/opt/cerebros-core"
  CEREBROS_SCRIPT: "/opt/cerebros-core/generative-proof-of-concept-CPU-preprocessing-in-memory.py"
  CEREBROS_PYTHON: "python3"
```

## Invocation flow

1. **Caller produces a contract** (for example `Contracts.RunStartedV1` when starting a NAS run).
2. `Client.start_run/2` (or `record_trial/2`, `finalize_run/2`) verifies the feature flag and `config.enabled?` before proceeding.
3. `Translator.encode/4` converts the contract into a call spec:
   * Command defaults to `python3 <script_path> --bridge-op start_run`.
   * Payload JSON is written to STDIN and also exported as `CEREBROS_BRIDGE_PAYLOAD`.
   * Operational metadata (run_id, trial_id, etc.) flows into telemetry and cache keys.
4. `Invoker.invoke/3` launches the subprocess under `Task.Supervisor`. It handles:
   * Retry loop (default 2 retries) with exponential backoff.
   * Timeout per attempt (`default_timeout_ms`).
   * Structured telemetry: `[:cerebros, :bridge, :invoke, :start|:stop|:exception]` with duration + metadata.
   * JSON decoding of stdout (overridable via custom parser) and exit status validation.
   * Error classification into `%ErrorClass{}` for dependency, timeout, subprocess exit, parse errors, or unexpected exceptions.
5. Successful responses are decoded by `Translator.decode/5`, merged with duration telemetry, cached (when the cache is wired), and returned to the caller.
6. `Client` publishes lifecycle events on the Thunderflow bus:
   * `ml.run.start` / `ml.run.stop` / `ml.run.exception`
   * `ml.run.trial` (when recording a trial)

## Telemetry + observability

* `[:cerebros, :bridge, :invoke, :start|:stop|:exception]` – emitted for every attempt with metadata `{op, attempt, run_id, …}` and measurements `%{duration_ms: …}` on success.
* `[:cerebros, :bridge, :cache, :hit|:miss|:store|:evict|:purge]` – prepared but currently dormant until the cache server is supervised.
* Thunderflow events produced by the client (`ml.run.*`) land on the shared `Thunderline.Thunderflow.EventBus` with source `:bolt`. These feed any subscriber listening for NAS telemetry, including LiveDashboard panels.

## Validation + tooling

`mix thunderline.ml.validate` runs the validator checks. Options:

* `--require-enabled` – treat a disabled `enabled: false` config as an error.
* `--json` – emit JSON suitable for CI gating.

A typical success output looks like:

```
[OK] Cerebros Bridge Validation
  ✔ feature_flag: Feature flag :ml_nas is enabled
  ✔ config_enabled: Cerebros bridge configuration enabled
  ✔ repo_path: repo_path exists (…)
  ✔ script_path: script_path exists (…)
  ✔ python: python executable found (/usr/bin/python3)
  ✔ cache_capacity: Cache configuration valid (max_entries: 512)
```

The validator already powers our CI smoke test (`mix test test/thunderline/thunderbolt/cerebros_bridge/validator_test.exs`).

## Current gaps and risks

* **No production caller yet.** Nothing in the codebase instantiates the contracts or calls `Thunderline.Thunderbolt.CerebrosBridge.Client`. The NAS façade (`Thunderline.Thunderbolt.Cerebros.Adapter`) still delegates to the in-process stub / CLI fallback and never touches the bridge.
* **Supervisor wiring missing.**
  * `Task.Supervisor` named `Thunderline.TaskSupervisor` is not started in `Thunderline.Application`, so `Invoker` will crash unless another boot path adds it.
  * `CerebrosBridge.Cache` is not part of any supervision tree, leaving caching disabled.
* **Deployment toggles incomplete.** There is no dedicated `CEREBROS_ENABLED` env yet; enabling the bridge still requires editing config or using runtime overrides.
* **Error propagation consumers TBD.** We classify failures into `ErrorClass` structs, but no service consumes them to trigger retries or surfaced UI messages.
* **Contracts unused downstream.** `Contracts.TrialReportedV1` and `RunFinalizedV1` are not stored in Ash resources or displayed in the dashboard, so trial metrics would currently drop on the floor.

## Questions for leadership

1. **Ownership of the call site:** Which component (dashboard LiveView, Oban job, or external agent) should instantiate contracts and drive `start_run/record_trial/finalize_run`? We need a clear orchestration owner before wiring the facade.
2. **Task supervisor location:** Do we add a global `Task.Supervisor` to the OTP tree or should the bridge own a dedicated supervisor (with restart strategy) to isolate subprocess crashes?
3. **Cache strategy:** Should bridge responses be cached at all once trials become stateful? If so, what invalidation triggers (new pulse, contract hash) do we require?
4. **Artifact persistence:** When the bridge returns artifact references, should we extend `Thunderline.Thunderbolt.Cerebros.Artifacts` to ingest them, or rely on the existing adapter persistence path?
5. **Telemetry consumers:** Who is responsible for visualizing or alerting on `ml.run.*` events? (Dashboard, Ops, or external observability stack.)

## Next implementation steps

1. Add a supervised `{Task.Supervisor, name: Thunderline.TaskSupervisor}` child and register `CerebrosBridge.Cache` under the application tree.
2. Extend `Thunderline.Thunderbolt.Cerebros.Adapter` (or a dedicated Oban worker) to call the bridge client when the `:ml_nas` flag is active.
3. Persist contract outputs to Ash resources (e.g., `ModelRun` state updates, per-trial metrics) so dashboards and APIs can display NAS progress.
4. Expose runtime toggle via env (`CEREBROS_ENABLED`) and ensure Helm chart templates propagate it.
5. Build LiveView or agent flows that surface validator results and allow enabling the feature once the environment passes checks.
