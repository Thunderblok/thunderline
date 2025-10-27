# Thunderline Codebase Review Checklist

Last updated: September 26, 2025

This checklist captures the minimum bar before merging into `main` or cutting a release. Treat every unchecked box as a ship blocker.

---

## 0. Source Hygiene & Secrets

- [ ] `.roo/` and `mcp/` remain untracked (`git ls-files` shows neither path).
- [ ] Local MCP credentials supplied through env (`.envrc`, shell exports) – never committed.
- [ ] `gitleaks` (pre-push hook via `./scripts/git-hooks/install.sh` or `mix security.gitleaks`) passes with `--redact` off.
- [ ] PATs / cloud keys revoked immediately if leaked; commit history rewritten.

## 1. Configuration Drift

- [ ] `CODEBASE_REVIEW_CHECKLIST.md` (this file) present and current.
- [ ] `config/*.exs` reviewed for accidental flag flips, secrets, or env-specific values.
- [ ] Feature flag defaults in `config/config.exs` match documentation (`FEATURE_FLAGS.md`).
- [ ] Runtime overrides documented in README + env samples.

## 2. Ash & Domain Guardrails

- [ ] Every Ash resource compiles under Ash 3.x (fragment/validation/prepare syntax verified).
- [ ] No new cross-domain shortcuts: only Block touches `Repo`; other domains use Ash actions/events.
- [ ] Policies re-enabled where auth context exists (Vault, Thundergrid, Thundercom).
- [ ] New resources include migrations, tests, and appear in `THUNDERLINE_DOMAIN_CATALOG.md`.

## 3. Event & Feature Linting

- [ ] `mix thunderline.events.lint --format=json` passes (canonical names, versioning, metadata).
- [ ] `mix thunderline.flags.audit --format=table` shows no orphan or undocumented flags.
- [ ] Event producers include provenance + schema version, especially for Cerebros bridge.

## 4. Authentication & Authorization

- [ ] `ThunderlineWeb.UserSocket` assigns `current_user` via AshAuthentication token.
- [ ] API key protected routes require minted keys (mix task exercised).
- [ ] Feature-gated code checks `Thunderline.Feature.enabled?/2` (no bare `Application.get_env`).

## 5. Streaming Spine & Async Work

- [ ] `Thunderline.Thunderbolt.StreamManager` supervisor running; PubSub topic configured.
- [ ] Stream telemetry emits depth / ingest / drop counters (visible in LiveDashboard).
- [ ] Oban queues sized appropriately; new workers have retry/backoff + telemetry.

## 6. ML & Suggestion Pipeline

- [ ] Suggestion facade handles Nx + Cerebros fallback with accurate latency metrics.
- [ ] ML/NAS events tagged with `source`, `duration_ms`, `correlation_id`.
- [ ] Benchmark artifacts (Nx vs Cerebros) committed under `bench/` or `documentation/`.

## 7. Observability & Telemetry

- [ ] Missing `opentelemetry_exporter` no longer crashes boot (warns once).
- [ ] Dashboards updated (LiveDashboard / Grafana JSON) with new metrics.
- [ ] Telemetry prefixes follow `[:thunderline, <domain>, ...]` convention.

## 8. Docs & Runbooks

- [ ] README sections updated for new feature flags, secrets handling, setup deltas.
- [ ] Deployment or runbook changes captured in `DEPLOY_DEMO.md` or ops docs.
- [ ] DIPs / RFCs referenced for new architectural edges.

## 9. Testing & CI

- [ ] `mix test` + domain-specific suites green; new ExUnit coverage for key paths.
- [ ] CI matrix (compile, Credo, Dialyzer, Sobelow) passes locally or on branch.
- [ ] New mix tasks documented and have smoke tests where feasible.

---

_Print this checklist in PR descriptions. High Command will spot-check._
