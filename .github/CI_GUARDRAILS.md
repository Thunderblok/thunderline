# CI Guardrail Configuration

**Version**: 1.0.0  
**Last Updated**: November 5, 2025  
**Status**: ✅ Active & Enforced

## Overview

Thunderline's CI pipeline implements a **6-stage lockdown** workflow with multiple quality gates. All stages must pass before merging to protected branches (`main`, `develop`, `staging`).

## Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ STAGE 1: Test Suite (≥85% Coverage) ────────────────────────│
│   ├─ Unit tests                                              │
│   ├─ Integration tests                                       │
│   ├─ Property-based tests                                    │
│   └─ Coverage enforcement (HARD GATE: ≥85%)                  │
└──────────────────────────────────────────────────────────────┘
                            │
                            ├─────────────┬───────────────┐
                            ▼             ▼               ▼
┌────────────────────────────┐ ┌───────────────┐ ┌─────────────────────┐
│ STAGE 2: Dialyzer          │ │ STAGE 3:      │ │ STAGE 4: Event      │
│   (Type Safety)            │ │   Credo       │ │   Taxonomy Lint     │
│                            │ │   (Quality)   │ │   (AUDIT-05)        │
│ - Type checking            │ │ - Strict mode │ │ - Schema validation │
│ - Pattern exhaustiveness   │ │ - Complexity  │ │ - Reserved prefixes │
│ - Return type inference    │ │ - Readability │ │ - Metadata rules    │
└────────────────────────────┘ └───────────────┘ └─────────────────────┘
                            │             │               │
                            └─────────────┴───────────────┘
                                        ▼
┌──────────────────────────────────────────────────────────────┐
│ STAGE 5: Security (SBOM & Vulnerability Scanning) ──────────│
│   ├─ gitleaks (secret scan)                                  │
│   ├─ hex.audit (retired packages)                            │
│   ├─ Sobelow (Phoenix security)                              │
│   └─ Trivy FS (filesystem vulnerabilities)                   │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│ STAGE 6: Docker (Build, Scan, Sign) [push events only] ─────│
│   ├─ Multi-arch build (amd64/arm64)                          │
│   ├─ Trivy image scan (HIGH/CRITICAL gate)                   │
│   ├─ SBOM generation                                          │
│   └─ Keyless signing (Cosign + Sigstore)                     │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│ Migration Drift Check (AshPostgres) ────────────────────────│
│   - Detects uncommitted schema changes                       │
│   - Enforces `mix ash.codegen` discipline                    │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ✅ CI Lockdown Complete
```

## Quality Gates (HARD GATES)

### 1. Test Coverage ≥85%
- **Tool**: ExCoveralls
- **Failure Mode**: Blocks merge if coverage drops below 85%
- **Bypass**: ❌ Not allowed
- **Documentation**: Coverage report uploaded as artifact

### 2. Dialyzer (Type Safety)
- **Tool**: dialyxir
- **Failure Mode**: Any type error fails the build
- **Bypass**: ❌ Not allowed
- **Format**: `--format github` for inline PR annotations

### 3. Credo (Code Quality)
- **Tool**: Credo (strict mode)
- **Failure Mode**: Any issue (consistency, readability, complexity)
- **Bypass**: ❌ Not allowed
- **Config**: `.credo.exs` in project root

### 4. Event Taxonomy Lint (AUDIT-05)
- **Tool**: Custom Mix task (`mix thunderline.events.lint`)
- **Checks**:
  - Event name follows `domain.category.action` taxonomy
  - Reserved prefixes not used by unauthorized code
  - Required metadata fields present
- **Failure Mode**: Taxonomy violations block merge
- **Bypass**: ❌ Not allowed
- **Output**: JSON report uploaded as artifact

### 5. Security Scans
- **gitleaks**: Secret scanning (`.gitleaks.toml`)
  - Blocks on exposed secrets, API keys, tokens
- **hex.audit**: Retired/vulnerable Hex packages
- **Sobelow**: Phoenix/Plug security issues
- **Trivy FS**: Filesystem vulnerabilities (HIGH/CRITICAL only)
- **Failure Mode**: Any HIGH/CRITICAL issue blocks merge
- **Bypass**: Can add to `.trivyignore` with justification

### 6. Docker Image Security
- **Trivy Image Scan**: Scans built container for vulnerabilities
- **Failure Mode**: HIGH/CRITICAL vulnerabilities block deployment
- **SBOM**: Automatically generated with build
- **Signing**: Keyless Cosign signature via Sigstore
- **Bypass**: `.trivyignore` for false positives only

### 7. Migration Drift Check
- **Tool**: `mix ash_postgres.generate_migrations --check`
- **Purpose**: Ensures schema changes are committed as migrations
- **Failure Mode**: Uncommitted schema drift blocks merge
- **Resolution**: Run `mix ash.codegen` locally and commit migrations

## Branch Protection Rules

### Protected Branches
- `main` (production)
- `develop` (integration)
- `staging` (pre-production)

### Enforcement
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date
- ✅ Require conversation resolution before merging
- ✅ Require signed commits
- ✅ Require linear history
- ❌ Allow force pushes: **Disabled**
- ❌ Allow deletions: **Disabled**

### Required Status Checks
All checks in `ci_lockdown_complete` job:
1. `test` (Stage 1)
2. `dialyzer` (Stage 2)
3. `credo` (Stage 3)
4. `event_taxonomy` (Stage 4)
5. `security` (Stage 5)
6. `migration_drift` (AshPostgres)

## Caching Strategy

Aggressive caching for fast CI runs:

| Cache Key | Cached Paths | Invalidation |
|-----------|-------------|--------------|
| `deps-*` | `deps/` | `mix.lock` change |
| `build-*` | `_build/` | `mix.lock` change |
| `dialyzer-*` | `priv/plts/` | `mix.lock` change |
| `libtorch-*` | `~/.cache/libtorch`, `deps/torchx/cache` | `mix.lock` change |

## Artifact Uploads

| Artifact | Source | Retention |
|----------|--------|-----------|
| `coverage-json` | `cover/excoveralls.json` | 30 days |
| `event-taxonomy-report` | `tmp/taxonomy_report.json` | 30 days |
| `trivy-fs.sarif` | Filesystem scan | Permanent (SARIF) |
| `trivy-image.sarif` | Docker image scan | Permanent (SARIF) |

## Dependabot Auto-Merge

**Status**: ✅ Enabled

Dependabot PRs are automatically merged if:
1. All CI stages pass
2. PR is from Dependabot
3. Merge method: Squash

This ensures dependency updates are applied quickly while maintaining quality gates.

## Environment Variables

### Required Secrets
- `GITHUB_TOKEN` - Automatic (GitHub Actions)
- `LIBTORCH_VERSION` - Set in workflow (`2.7.0`)

### Required Feature Flags
- `RAG_ENABLED` - Controls RAG system tests
- `SKIP_ASH_SETUP` - Skips Ash setup for EventBus telemetry tests

### Environment Matrix
| Variable | Value |
|----------|-------|
| `MIX_ENV` | `test` |
| `ELIXIR_VERSION` | `1.18` |
| `OTP_VERSION` | `27` |
| `MIN_COVERAGE` | `85` |
| `LIBTORCH_VERSION` | `2.7.0` |

## Telemetry & Monitoring

### GitHub Step Summaries
Each job produces a summary visible in the Actions UI:
- Test coverage percentage
- Event taxonomy violations
- Security scan results
- Docker image digest

### SARIF Upload
Trivy scan results uploaded to GitHub Security tab:
- **Category**: `trivy-fs` (filesystem)
- **Category**: `trivy-image` (Docker image)
- Enables GitHub Advanced Security integration

## Failure Resolution

### Test Coverage < 85%
```bash
# Run locally to identify gaps
mix coveralls.html --color
open cover/excoveralls.html
```

### Dialyzer Errors
```bash
# Generate PLT and run Dialyzer
mix dialyzer
```

### Credo Issues
```bash
# Run in strict mode
mix credo --strict
```

### Event Taxonomy Violations
```bash
# Lint event names
mix thunderline.events.lint

# Fix naming issues in event code
# Follow docs/EVENT_TAXONOMY.md
```

### Security Vulnerabilities
```bash
# Check hex packages
mix hex.audit

# Run Sobelow
mix sobelow --exit

# Trivy scan (requires Docker)
trivy fs --severity HIGH,CRITICAL .
```

### Migration Drift
```bash
# Generate migrations
mix ash.codegen add_my_feature

# Review and commit
git add priv/repo/migrations/
git commit -m "Add migration for feature X"
```

## Bypass Procedures

### Emergency Hotfix
For critical production issues only:

1. Create branch: `hotfix/YYYY-MM-DD-issue-description`
2. Obtain approval from **2 maintainers**
3. Apply minimal fix
4. Create follow-up issue for proper fix
5. Merge with `--no-verify` (requires admin)

**Note**: Hotfix PRs still run CI but can be merged with failures by admins only.

## Performance Targets

| Stage | Target Duration | Actual (Avg) |
|-------|-----------------|--------------|
| Test Suite | < 5 min | 3.5 min |
| Dialyzer | < 3 min | 2 min |
| Credo | < 1 min | 30 sec |
| Event Taxonomy | < 1 min | 20 sec |
| Security | < 5 min | 4 min |
| Docker Build | < 10 min | 8 min |
| **Total** | **< 25 min** | **18 min** |

## Troubleshooting

### Postgres Connection Issues
- Check `services` health check in workflow
- Verify `DATABASE_URL` format
- Ensure port 5432 is available

### LibTorch Cache Miss
- Check cache key includes `mix.lock`
- Verify `~/.cache/libtorch` path
- May take 5-10 min to download on cache miss

### Dialyzer PLT Issues
```bash
# Clean and rebuild PLT locally
mix dialyzer --plt
```

### Event Taxonomy Linter Failures
- Check `EVENT_TAXONOMY.md` for rules
- Ensure event names use `domain.category.action` format
- Verify reserved prefixes (`system.*`, `ui.*`, etc.)

## References

- **CI Workflow**: `.github/workflows/ci.yml`
- **Credo Config**: `.credo.exs`
- **Gitleaks Config**: `.gitleaks.toml`
- **Trivy Ignore**: `.trivyignore`
- **Event Taxonomy**: `docs/EVENT_TAXONOMY.md`
- **Coverage Config**: `coveralls.json`

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2025-11-05 | 1.0.0 | Initial CI guardrail configuration documented |

## Approval

**Document Owner**: Infrastructure Team  
**Reviewers**: Security Team, Platform Team  
**Last Review**: 2025-11-05  
**Next Review**: 2025-12-05 (monthly)
