# Ops Scorecard (RAG)

- Build: Green — CI compiles, lints, tests on push/PR (GitHub Actions)
- Test: Amber — Tests run; need coverage metrics & gates
- Deploy: Green — Demo container build to GHCR; Fly.io config present
- Observability: Amber — Telemetry libs; exporter/dashboards TBD
- Security: Amber — Sobelow in CI; add gitleaks/Trivy, secret hygiene
- Docs: Amber — README present; ops docs bootstrapped
- Bus factor: Amber — Key areas concentrated; add runbooks & ADRs

> Updated: Phase 0 baseline
