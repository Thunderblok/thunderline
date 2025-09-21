# Thunderline Ops One-Pager

## Purpose

- How to run, test, build, and ship Thunderline consistently.

## Prereqs

- Elixir/OTP: Elixir 1.18, OTP 26 (see mix.exs)
- Node for assets in dev; Docker for container builds; Fly CLI for demo deploys (optional)
- Postgres for DB-backed paths

## Run (dev)

- mix deps.get && mix setup (alias runs ash.setup, assets)
- mix phx.server (PHX_SERVER=true can be set for releases)
- DB URL (dev/test) set via config; for prod, set DATABASE_URL

## Test

- mix test --color --slowest 10
- Lint bundle: mix lint (format --check + credo --strict)
- Dialyzer: mix dialyzer (PLT cached to priv/plts)
- CI mirrors these: see .github/workflows/ci.yml

## Build (assets + release)

- mix assets.deploy && mix compile && mix release
- Container: docker build -t ghcr.io/ORG/REPO/thunderline-demo:latest .

## Ship (demo)

- GHCR push via .github/workflows/demo-deploy.yml (build-and-push)
- Fly.io (demo): fly deploy (uses fly.toml)

## Observability

- OpenTelemetry exporter toggles: set `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME=thunderline`.
- Golden signals (emitted via :telemetry):
  - per-stage lag/throughput/error for Broadway pipelines
  - DLQ depth (pipeline dlq events)
  - per-trial time-to-metric p50/p95 (via metrics processing)

## Security

- CI runs Sobelow and Trivy. Trivy SARIF uploaded to code scanning. See `.trivyignore` for allowlist.

## Notes

- Entry script scripts/docker/dev_entrypoint.sh runs migrations before server in container.
