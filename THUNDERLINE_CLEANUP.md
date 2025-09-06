# Thunderline Cleanup & Sweep Tasks

Operational helpers to keep the workspace tidy and to audit domain alignment.

## Tasks

  - Scans the codebase for:
    - Duplicate Ash resource modules by basename (e.g. two ModelArtifact resources)
    - Non-Ising optimization modules (flags modules like anneal/genetic/tpe/bayes)
  - Options:
    - --format=json to emit JSON (default: human text)

  - Garbage-collect logs and artifacts under the repo.
  - Dry-run by default; prints candidate files and sizes.
  - Options:
    - --category=<logs|artifacts|all> (default: all)
    - --age=<Ns|Nm|Nh|Nd|Nw> (default: 7d)
    - --force to actually delete

## Configuration

You can override default paths in config/runtime.exs (or env-specific):

    config :thunderline, Thunderline.Maintenance.Cleanup,
      log_paths: ["log", "erl_crash.dump", "thunderline_chk.dets"],
      artifact_paths: [
        "cerebros/checkpoint",
        "cerebros/results",
        "tmp",
        "priv/static/uploads"
      ]

Notes:

## Review and Next Steps

  - Keep ThunderLink resources for chat/community; deprecate legacy ThunderCom copies.
  - Keep ThunderFlow SystemAction; move any security-centric actions to ThunderGate only.
  - Unify Thunderbolt ML ModelArtifact/ModelRun under a single module, plan DB migration.
  - `mix thunderline.ml.migrate_artifacts` — safe, idempotent migration from legacy cerebros_model_artifacts to ml_model_artifacts (dry‑run by default)
  - Genetic/GA style evolution calls in Erlang bridge are now compile‑gated and return {:error, :feature_disabled} unless explicitly enabled via `config :thunderline, thunderbolt: [enable_non_ising: true]`.
  - Anneal supervisor stub is also compile‑gated with the same flag.
