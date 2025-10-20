# T-0h CI Lockdown: Operational Runbook

**Status**: ✅ ENFORCED (October 2025)  
**Directive**: T-0h #3 - CI Lockdown Enforcement  
**Pipeline**: 6-stage modular architecture with hard gates  
**Coverage Gate**: ≥85% (increased from 70%)  
**Related**: [CODEBASE_STATUS.md](./CODEBASE_STATUS.md), [EVENT_TAXONOMY.md](./EVENT_TAXONOMY.md) (AUDIT-05)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Pipeline Architecture](#2-pipeline-architecture)
3. [Stage Details](#3-stage-details)
4. [Supply Chain Security](#4-supply-chain-security)
5. [Branch Protection Configuration](#5-branch-protection-configuration)
6. [Local Verification](#6-local-verification)
7. [Troubleshooting](#7-troubleshooting)
8. [Reference](#8-reference)

---

## 1. Overview

The **Thunderline CI Lockdown** is a 6-stage GitHub Actions pipeline enforcing quality gates before code reaches production. This directive addresses AUDIT-05 (event taxonomy automation), increases test coverage requirements, and implements supply chain security best practices.

### Key Features

- **6 Parallel Stages**: Test, Dialyzer, Credo, Event Taxonomy, Security, Docker
- **Hard Gates**: 85% coverage threshold, type safety, code quality, event linting
- **Supply Chain Security**: SBOM generation, SLSA provenance, Cosign image signing
- **Vulnerability Scanning**: Trivy FS + Image scans (fail on HIGH/CRITICAL)
- **Secret Detection**: Gitleaks scanning with `.gitleaks.toml` config
- **Migration Drift Detection**: AshPostgres schema validation
- **Dependabot Auto-merge**: Automatic dependency updates (if all gates pass)

### Pipeline Triggers

```yaml
on:
  push:
    branches: [ main, develop, staging ]
  pull_request:
    branches: [ main, develop, staging ]
  workflow_dispatch:
```

---

## 2. Pipeline Architecture

```
┌──────────────────────┐
│ Stage 1: Test Suite  │──┬──> Stage 2: Dialyzer ──┐
│   (≥85% coverage)    │  │                         │
└──────────────────────┘  ├──> Stage 3: Credo ─────┤
                          │                         ├──> Stage 6: Docker
                          ├──> Stage 4: Event Tax ─┤   (build/sign)
                          │                         │
                          ├──> Stage 5: Security ──┤
                          │                         │
                          └──> Migration Drift ────┘
                                      │
                                      ▼
                          ┌─────────────────────────┐
                          │ CI Lockdown Complete    │
                          │  (Status Check)         │
                          └─────────────────────────┘
                                      │
                                      ▼
                          ┌─────────────────────────┐
                          │ Dependency Auto-Merge   │
                          │  (Dependabot PRs)       │
                          └─────────────────────────┘
```

### Execution Strategy

- **Parallel Execution**: Stages 2-6 run in parallel after Stage 1 completes
- **Fail Fast**: Any stage failure blocks downstream stages
- **Caching**: Aggressive caching for deps, build, PLTs (reduces runtime)
- **Artifacts**: Coverage JSON, taxonomy reports uploaded for analysis

### Environment Variables

```yaml
env:
  MIX_ENV: test
  ELIXIR_VERSION: "1.18"
  OTP_VERSION: "27"
  MIN_COVERAGE: 85
```

---

## 3. Stage Details

### Stage 1: Test Suite (≥85% Coverage)

**Purpose**: Execute full test suite with hard coverage gate  
**Hard Gate**: ≥85% line coverage (fails if below threshold)  
**Runtime**: ~5-8 minutes (with PostgreSQL service)

#### Key Steps

1. **Secret Scanning**: Gitleaks checks for leaked credentials
2. **EventBus Telemetry**: Isolated telemetry assertion tests
3. **Database Setup**: `mix ash.setup` (migrations + seeds)
4. **Test Execution**: `mix coveralls.json --min-coverage 85`
5. **Coverage Reporting**: Upload JSON artifact + GitHub summary

#### Local Verification

```bash
# Run tests with coverage report
MIX_ENV=test mix coveralls.html --min-coverage 85

# Open coverage report
open cover/excoveralls.html

# Run specific test file
mix test test/thunderflow/event_bus_test.exs
```

#### Coverage Threshold History

- **Week -1**: 70% (baseline)
- **T-0h (Oct 2025)**: 85% ⬆️ (T-0h Directive #3)
- **Target (Week 4)**: 90% (stretch goal)

---

### Stage 2: Dialyzer (Type Safety)

**Purpose**: Static type analysis to catch type errors  
**Hard Gate**: Dialyzer failures block merge  
**Runtime**: ~3-5 minutes (with PLT caching)

#### Key Steps

1. **PLT Caching**: Persistent Lookup Table cached across runs
2. **Type Analysis**: `mix dialyzer --halt-exit-status --format github`
3. **GitHub Annotations**: Errors displayed inline in PR

#### Local Verification

```bash
# Run Dialyzer locally
mix dialyzer

# Build PLT (first run only)
mix dialyzer --plt

# Check specific module
mix dialyzer lib/thunderline/thunderflow/event_bus.ex
```

#### Common Dialyzer Errors

- **Callback mismatch**: `@impl true` with wrong arity
- **Spec mismatch**: Function return doesn't match `@spec`
- **Pattern mismatch**: Unreachable pattern in function clause
- **Unknown type**: Custom type not defined or imported

---

### Stage 3: Credo (Code Quality)

**Purpose**: Enforce code style and best practices  
**Hard Gate**: Credo strict mode failures block merge  
**Runtime**: ~1-2 minutes

#### Key Steps

1. **Strict Mode**: `mix credo --strict` (no warnings allowed)
2. **Checks**: Consistency, readability, refactoring opportunities, warnings, design

#### Local Verification

```bash
# Run Credo locally
mix credo --strict

# Show detailed explanations
mix credo explain

# Fix auto-fixable issues
mix credo --strict --fix

# Check specific file
mix credo lib/thunderline/thunderflow/event_bus.ex
```

#### Common Credo Issues

- **Alias ordering**: Alphabetize `alias` statements
- **Pipe chain length**: Refactor pipes >5 steps
- **Module attribute naming**: Use snake_case for `@moduledoc`
- **Unused function**: Remove or mark with `@doc false`

---

### Stage 4: Event Taxonomy (AUDIT-05)

**Purpose**: Enforce event naming conventions and metadata completeness  
**Hard Gate**: Malformed events block merge  
**Runtime**: ~1-2 minutes

#### Key Steps

1. **Taxonomy Lint**: `mix thunderline.events.lint --format=json`
2. **Validation Rules**:
   - Event names match taxonomy (dot notation: `domain.category.action`)
   - Required metadata fields present (`source`, `type`, `data`)
   - No forbidden event names (reserved prefixes)
   - Metadata schema compliance
3. **Report Upload**: Taxonomy report artifact for debugging

#### Local Verification

```bash
# Run event taxonomy linter
mix thunderline.events.lint --format=json

# Strict mode (fail on warnings)
mix thunderline.events.lint --strict

# Generate taxonomy report
mix thunderline.events.lint --format=json > tmp/taxonomy_report.json
```

#### Event Taxonomy Rules

See [EVENT_TAXONOMY.md](./EVENT_TAXONOMY.md) for complete taxonomy specification.

**Reserved Prefixes**: `system.*`, `internal.*`, `test.*`  
**Required Fields**: `type`, `source`, `data`, `id`, `timestamp`  
**Naming Convention**: `<domain>.<category>.<action>` (e.g., `flow.event.processed`)

#### AUDIT-05 Compliance

This stage directly addresses **AUDIT-05** from the High Command review:

> **AUDIT-05**: Event Taxonomy Automation  
> *Automate event taxonomy validation in CI/CD. Developers should not manually verify event names against the taxonomy—this should be a hard gate in the pipeline.*

✅ **Status**: ENFORCED (T-0h Directive #3)

---

### Stage 5: Security (SBOM & Vuln Scan)

**Purpose**: Detect security vulnerabilities and leaked secrets  
**Hard Gate**: HIGH/CRITICAL vulnerabilities block merge  
**Runtime**: ~3-5 minutes

#### Key Steps

1. **Secret Scanning**: Gitleaks checks for API keys, tokens, passwords
2. **Hex Audit**: Detect retired Hex packages (`mix hex.audit`)
3. **Sobelow**: Security-focused static analysis (`mix sobelow --exit`)
4. **Trivy FS Scan**: Filesystem vulnerability scan (exit-code 1 on HIGH/CRITICAL)
5. **SARIF Upload**: Results uploaded to GitHub Security tab

#### Local Verification

```bash
# Run Gitleaks locally
docker run -v $(pwd):/path ghcr.io/gitleaks/gitleaks:latest detect --source /path --config /path/.gitleaks.toml

# Run Hex audit
mix hex.audit

# Run Sobelow
mix sobelow --exit

# Run Trivy FS scan
trivy fs --severity HIGH,CRITICAL --ignore-unfixed .
```

#### Security Configuration

**Gitleaks Config**: `.gitleaks.toml` (custom rules for Thunderline)  
**Trivy Ignore**: `.trivyignore` (false positive suppressions)  
**Sobelow**: `.sobelow-conf` (security checks configuration)

#### Common Security Issues

- **Exposed Secrets**: API keys in code (use env vars or secrets manager)
- **Retired Packages**: Deprecated Hex packages (update dependencies)
- **SQL Injection**: Raw SQL queries (use Ash/Ecto parameterized queries)
- **XSS**: Unescaped user input in templates (use HEEx auto-escaping)

---

### Stage 6: Docker (Build & Sign)

**Purpose**: Build production image with supply chain attestation  
**Hard Gate**: Image vulnerabilities block merge (only on push events)  
**Runtime**: ~8-12 minutes (with layer caching)  
**Trigger**: Only runs on `push` events (not PRs)

#### Key Steps

1. **Docker Buildx**: Multi-platform build with layer caching
2. **SBOM Generation**: Automatic CycloneDX SBOM (`sbom: true`)
3. **SLSA Provenance**: Build attestation (`provenance: true`)
4. **Image Push**: Push to `ghcr.io/<repo>` with tags
5. **Trivy Image Scan**: Scan pushed image (exit-code 1 on HIGH/CRITICAL)
6. **Cosign Signing**: Keyless signing with Sigstore transparency log

#### Image Tagging Strategy

```
ghcr.io/thunderblok/thunderline:main
ghcr.io/thunderblok/thunderline:main-abc1234
ghcr.io/thunderblok/thunderline:sha-abc1234567890abcdef
ghcr.io/thunderblok/thunderline:v1.2.3 (on semver tags)
```

#### Local Verification

```bash
# Build Docker image locally
docker build -t thunderline:local .

# Run Trivy scan on local image
trivy image thunderline:local

# Verify image signature (after CI push)
cosign verify ghcr.io/thunderblok/thunderline:main

# Inspect SBOM
cosign download sbom ghcr.io/thunderblok/thunderline:main
```

#### Supply Chain Artifacts

- **SBOM**: CycloneDX format (attached to image)
- **Provenance**: SLSA attestation (GitHub Actions provenance)
- **Signature**: Cosign keyless signature (Sigstore Rekor log)

---

### Migration Drift Check

**Purpose**: Detect schema drift before merge  
**Hard Gate**: Uncommitted migrations block merge  
**Runtime**: ~2-3 minutes

#### Key Steps

1. **Schema Generation**: `mix ash_postgres.generate_migrations --check --dry-run`
2. **Drift Detection**: Fails if schema doesn't match resources
3. **Error Guidance**: Instructs developer to run codegen locally

#### Local Verification

```bash
# Check for migration drift
mix ash_postgres.generate_migrations --check --dry-run

# Generate migrations (if drift detected)
mix ash.codegen add_my_feature_name

# Run migrations
mix ash.migrate
```

#### Common Drift Causes

- **Attribute changes**: Added/removed fields without codegen
- **Relationship changes**: New associations without migration
- **Constraint changes**: Check constraints or indexes modified
- **Data layer changes**: Postgres config changed without migration

---

### CI Lockdown Status Check

**Purpose**: Final gate - verify all stages passed  
**Hard Gate**: Blocks auto-merge if any stage failed  
**Runtime**: <1 minute

#### Verification Logic

```bash
if [ "${{ needs.test.result }}" != "success" ] || \
   [ "${{ needs.dialyzer.result }}" != "success" ] || \
   [ "${{ needs.credo.result }}" != "success" ] || \
   [ "${{ needs.event_taxonomy.result }}" != "success" ] || \
   [ "${{ needs.security.result }}" != "success" ] || \
   [ "${{ needs.migration_drift.result }}" != "success" ]; then
  echo "❌ CI Lockdown FAILED"
  exit 1
fi
```

#### GitHub Summary Output

```markdown
## 🔒 CI Lockdown Status

✅ **All quality gates passed**

### Pipeline Stages
- ✅ Stage 1: Test Suite (≥85% coverage)
- ✅ Stage 2: Dialyzer (type safety)
- ✅ Stage 3: Credo (code quality)
- ✅ Stage 4: Event Taxonomy (AUDIT-05)
- ✅ Stage 5: Security (SBOM & vuln scan)
- ✅ Migration Drift Check
- ✅ Stage 6: Docker (build & sign)

**Branch**: `main`
**Commit**: `abc1234567890`
**Triggered by**: @username
```

---

## 4. Supply Chain Security

### SBOM (Software Bill of Materials)

**Format**: CycloneDX JSON  
**Generation**: Automatic via Docker Buildx `sbom: true`  
**Attached To**: Docker image metadata

#### Viewing SBOM

```bash
# Download SBOM from image
cosign download sbom ghcr.io/thunderblok/thunderline:main

# Parse SBOM (requires jq)
cosign download sbom ghcr.io/thunderblok/thunderline:main | jq '.components[] | {name, version}'
```

#### SBOM Contents

- **Base Image**: Elixir/OTP versions
- **Dependencies**: Hex packages + versions
- **System Packages**: OS-level dependencies
- **Build Tools**: Mix, Rebar3

### SLSA Provenance

**Format**: SLSA v1.0 attestation  
**Generation**: Automatic via Docker Buildx `provenance: true`  
**Signed By**: GitHub Actions (OIDC token)

#### Viewing Provenance

```bash
# Download provenance from image
cosign download attestation ghcr.io/thunderblok/thunderline:main

# Verify provenance signature
cosign verify-attestation ghcr.io/thunderblok/thunderline:main \
  --type slsaprovenance \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/Thunderblok/Thunderline'
```

#### Provenance Contents

- **Builder**: GitHub Actions runner info
- **Build Config**: Dockerfile, build args
- **Source**: Git repository, commit SHA
- **Build Time**: Timestamp, duration
- **Inputs**: Base image, dependencies

### Image Signing (Cosign)

**Method**: Keyless signing (Sigstore)  
**Transparency Log**: Rekor public log  
**OIDC Issuer**: GitHub Actions

#### Verifying Signatures

```bash
# Verify image signature
cosign verify ghcr.io/thunderblok/thunderline:main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/Thunderblok/Thunderline'

# Inspect signature metadata
cosign tree ghcr.io/thunderblok/thunderline:main
```

#### Signature Contents

- **Signature**: Cryptographic signature (ECDSA-P256)
- **Certificate**: Short-lived x509 cert (GitHub OIDC)
- **Rekor Entry**: Transparency log entry (tamper-proof)
- **Metadata**: Git commit, actor, workflow

---

## 5. Branch Protection Configuration

### GitHub Settings

Navigate to: **Settings → Branches → Branch protection rules → Add rule**

#### Rule Configuration

**Branch name pattern**: `main` (repeat for `develop`, `staging`)

**Require a pull request before merging**:
- ✅ Require approvals: **2**
- ✅ Dismiss stale pull request approvals when new commits are pushed
- ✅ Require review from Code Owners (optional, configure `CODEOWNERS`)

**Require status checks to pass before merging**:
- ✅ Require branches to be up to date before merging
- **Required checks**:
  - `test / Stage 1: Test Suite (≥85% Coverage)`
  - `dialyzer / Stage 2: Dialyzer (Type Safety)`
  - `credo / Stage 3: Credo (Code Quality)`
  - `event_taxonomy / Stage 4: Event Taxonomy (AUDIT-05)`
  - `security / Stage 5: Security (SBOM & Vuln Scan)`
  - `migration_drift / Migration Drift (AshPostgres)`
  - `ci_lockdown_complete / ✅ CI Lockdown Complete`

**Require conversation resolution before merging**: ✅ Enabled

**Do not allow bypassing the above settings**: ✅ Enabled (even for admins)

### Enforcement Timeline

- **Week -1**: No branch protections (developer discretion)
- **T-0h (Oct 2025)**: Branch protections enforced (2 approvals + green CI)
- **Week 1**: Audit existing PRs for compliance

---

## 6. Local Verification

Before pushing, verify your changes pass all gates locally.

### Pre-Push Checklist

```bash
# 1. Run tests with coverage
MIX_ENV=test mix coveralls.html --min-coverage 85

# 2. Run Dialyzer
mix dialyzer

# 3. Run Credo
mix credo --strict

# 4. Run Event Taxonomy Linter
mix thunderline.events.lint --format=json

# 5. Run Sobelow
mix sobelow --exit

# 6. Check migration drift
mix ash_postgres.generate_migrations --check --dry-run

# 7. Build Docker image (optional)
docker build -t thunderline:local .

# 8. Run Trivy scan (optional)
trivy image thunderline:local
```

### Quick Verification Script

```bash
#!/bin/bash
# scripts/verify_ci.sh

set -e

echo "🧪 Running tests..."
MIX_ENV=test mix coveralls.json --min-coverage 85

echo "🔍 Running Dialyzer..."
mix dialyzer --halt-exit-status

echo "📝 Running Credo..."
mix credo --strict

echo "📋 Running Event Taxonomy Linter..."
mix thunderline.events.lint --format=json

echo "🔒 Running Sobelow..."
mix sobelow --exit

echo "🗄️  Checking migration drift..."
mix ash_postgres.generate_migrations --check --dry-run

echo "✅ All checks passed! Safe to push."
```

**Usage**:

```bash
chmod +x scripts/verify_ci.sh
./scripts/verify_ci.sh
```

---

## 7. Troubleshooting

### Test Coverage Below 85%

**Symptom**: `mix coveralls.json --min-coverage 85` fails

**Diagnosis**:

```bash
# Generate HTML coverage report
MIX_ENV=test mix coveralls.html

# Open report
open cover/excoveralls.html

# Identify uncovered modules
grep -A 5 "Coverage" cover/excoveralls.html | grep "0%"
```

**Solutions**:
- Add tests for uncovered modules (focus on `0%` coverage first)
- Remove dead code (unused functions)
- Exclude generated code (add to `coveralls.json` exclude list)
- Add `@doc false` for internal-only functions (reduces coverage requirements)

**Exclude Configuration** (`coveralls.json`):

```json
{
  "coverage_options": {
    "minimum_coverage": 85,
    "treat_no_relevant_lines_as_covered": true
  },
  "skip_files": [
    "test/support",
    "priv/repo/migrations"
  ]
}
```

---

### Dialyzer Failures

**Symptom**: `mix dialyzer --halt-exit-status` exits with non-zero code

**Common Errors**:

#### 1. Callback Mismatch

```
lib/my_module.ex:10:callback_info_missing
The @impl attribute is present but no behaviour specifies the callback.
```

**Fix**: Remove `@impl true` or add `@behaviour MyBehaviour`

#### 2. Spec Mismatch

```
lib/my_module.ex:15:invalid_contract
The return type :ok | {:error, term()} does not match the @spec.
```

**Fix**: Update `@spec` to match actual return type

#### 3. Unreachable Pattern

```
lib/my_module.ex:20:no_return
Function clause will never match.
```

**Fix**: Remove unreachable pattern or refactor logic

#### Rebuild PLT

```bash
# Clear PLT cache
rm -rf priv/plts

# Rebuild PLT
mix dialyzer --plt
```

---

### Credo Warnings

**Symptom**: `mix credo --strict` fails

**Common Issues**:

#### Alias Ordering

```
lib/my_module.ex:3:C: Alphabetically sort aliases.
```

**Fix**: Alphabetize `alias` statements

#### Pipe Chain Length

```
lib/my_module.ex:10:R: Pipe chain is too long (6 steps).
```

**Fix**: Extract intermediate steps into named functions

#### Module Attribute Naming

```
lib/my_module.ex:5:C: Module attributes should use snake_case.
```

**Fix**: Rename `@myAttribute` → `@my_attribute`

---

### Event Taxonomy Linter Failures

**Symptom**: `mix thunderline.events.lint --format=json` fails

**Common Errors**:

#### Invalid Event Name

```
ERROR: Event name "userCreated" does not match taxonomy (expected dot notation).
```

**Fix**: Use dot notation: `user.created`

#### Missing Metadata Field

```
ERROR: Event missing required field "source".
```

**Fix**: Add `source` field to event metadata

#### Reserved Prefix

```
ERROR: Event name "system.internal.test" uses reserved prefix.
```

**Fix**: Use domain-specific prefix (e.g., `flow.event.test`)

**Taxonomy Reference**: See [EVENT_TAXONOMY.md](./EVENT_TAXONOMY.md)

---

### Security Scan Failures

**Symptom**: Trivy or Sobelow fails with HIGH/CRITICAL findings

#### Trivy FS Scan

```bash
# Run Trivy with detailed output
trivy fs --severity HIGH,CRITICAL --ignore-unfixed --format table .

# Suppress false positives (.trivyignore)
echo "CVE-2024-12345" >> .trivyignore
```

#### Sobelow Scan

```bash
# Run Sobelow with detailed output
mix sobelow --verbose

# Suppress false positives (.sobelow-conf)
[
  ignore: ["XSS.Raw"],
  ignore_files: ["lib/my_module.ex"]
]
```

**Remediation Priority**:
1. **HIGH/CRITICAL**: Fix immediately (blocks merge)
2. **MEDIUM**: Fix within 1 sprint
3. **LOW**: Fix within 2 sprints

---

### Docker Build Failures

**Symptom**: Docker image build fails

**Common Issues**:

#### Missing Build Args

```
ERROR: failed to solve: failed to compute cache key: "/app/deps" not found
```

**Fix**: Ensure `mix deps.get` runs in Dockerfile

#### Layer Caching Issues

```
ERROR: failed to pull layer: context canceled
```

**Fix**: Clear Docker Buildx cache:

```bash
docker buildx prune -af
```

#### Image Size Too Large

**Symptom**: Image size >500MB

**Fix**: Use multi-stage builds:

```dockerfile
# Builder stage
FROM elixir:1.18-alpine AS builder
# ... build steps ...

# Runtime stage
FROM elixir:1.18-alpine
COPY --from=builder /app/_build/prod/rel/thunderline ./
```

---

### Migration Drift Detected

**Symptom**: `mix ash_postgres.generate_migrations --check` fails

**Fix**:

```bash
# Generate missing migrations
mix ash.codegen add_my_feature_name

# Review generated migrations
ls -l priv/repo/migrations/

# Run migrations locally
mix ash.migrate

# Commit migrations
git add priv/repo/migrations/
git commit -m "Add migrations for feature X"
```

---

### CI Pipeline Stalled

**Symptom**: Pipeline runs for >30 minutes

**Diagnosis**:

1. Check GitHub Actions logs for stuck step
2. Look for infinite loops or hanging processes
3. Review PostgreSQL service health

**Common Causes**:
- **Database deadlock**: Concurrent test execution
- **Network timeout**: External API calls without timeout
- **Memory exhaustion**: Large dataset processing

**Fix**:

```elixir
# Add timeout to API calls
Req.get!(url, receive_timeout: 5_000)

# Add timeout to tests
@tag timeout: 60_000
test "my slow test" do
  # ...
end
```

---

### Dependabot Auto-Merge Blocked

**Symptom**: Dependabot PRs not auto-merging

**Diagnosis**:

1. Check if CI lockdown status passed
2. Verify Dependabot PR has `dependencies` label
3. Check if branch protections are configured

**Fix**:

```bash
# Manually approve Dependabot PR
gh pr review <pr-number> --approve

# Manually merge (if auto-merge failed)
gh pr merge <pr-number> --squash
```

---

## 8. Reference

### Quick Command Reference

```bash
# Test Suite
mix test                                      # Run all tests
mix test --cover                             # With coverage
mix coveralls.html --min-coverage 85         # HTML coverage report
mix test test/my_test.exs:42                # Run specific test line

# Code Quality
mix dialyzer                                 # Type checking
mix dialyzer --format dialyxir               # Pretty output
mix credo --strict                           # Code quality
mix credo explain                            # Show all issues

# Security
mix hex.audit                                # Hex package audit
mix sobelow --exit                           # Security scan
trivy fs --severity HIGH,CRITICAL .          # Vuln scan

# Events
mix thunderline.events.lint                  # Event taxonomy lint
mix thunderline.events.lint --format=json    # JSON output

# Migrations
mix ash.codegen my_feature                   # Generate migrations
mix ash.migrate                              # Run migrations
mix ash_postgres.generate_migrations --check # Check drift

# Docker
docker build -t thunderline:local .          # Build image
trivy image thunderline:local                # Scan image
cosign verify ghcr.io/.../thunderline:main   # Verify signature
```

### File Locations

```
.github/workflows/ci.yml      # CI pipeline definition
.gitleaks.toml                # Secret scanning config
.trivyignore                  # Trivy false positive suppressions
.sobelow-conf                 # Sobelow security config
coveralls.json                # Coverage configuration
.credo.exs                    # Credo code quality rules
dialyzer.ignore-warnings      # Dialyzer suppressions
```

### Environment Variables

```bash
MIX_ENV=test                  # Test environment
ELIXIR_VERSION=1.18           # Elixir version
OTP_VERSION=27                # OTP version
MIN_COVERAGE=85               # Coverage threshold
DATABASE_URL=ecto://...       # PostgreSQL connection
COSIGN_EXPERIMENTAL=1         # Enable Cosign keyless signing
```

### GitHub Actions Cache Keys

```
deps-linux-<mix.lock hash>    # Dependency cache
build-linux-<mix.lock hash>   # Build cache
dialyzer-linux-<mix.lock>     # PLT cache
```

### Related Documentation

- **[CODEBASE_STATUS.md](./CODEBASE_STATUS.md)**: T-0h Directive #3 requirements
- **[EVENT_TAXONOMY.md](./EVENT_TAXONOMY.md)**: Event naming conventions (AUDIT-05)
- **[THUNDERLINE_MASTER_PLAYBOOK.md](./THUNDERLINE_MASTER_PLAYBOOK.md)**: Overall system architecture
- **[DOMAIN_CATALOG.md](./THUNDERLINE_DOMAIN_CATALOG.md)**: Ash domain structure
- **[NERVES_DEPLOYMENT.md](./NERVES_DEPLOYMENT.md)**: Edge device provisioning

### AUDIT Compliance Matrix

| Audit ID | Description | CI Stage | Status |
|----------|-------------|----------|--------|
| AUDIT-05 | Event taxonomy automation | Stage 4: Event Taxonomy | ✅ ENFORCED |
| AUDIT-07 | Field-level security | Stage 5: Security (Sobelow) | 🟡 PARTIAL |
| AUDIT-08 | Event traffic monitoring | Stage 1: Test (coverage) | 🟡 PARTIAL |

### Contact & Support

**High Command Lead**: Renegade-S (strategy)  
**CI/CD Owner**: Renegade-E (execution)  
**Security Review**: Shadow-Sec (security audits)  
**Event Taxonomy**: Prometheus (observability)

---

**Document Version**: 1.0.0  
**Last Updated**: October 2025 (T-0h Directive #3)  
**Status**: ✅ ENFORCED (85% coverage gate active)

---

## Appendix: Pipeline YAML Snippet

```yaml
name: Thunderline CI Lockdown

env:
  MIN_COVERAGE: 85

jobs:
  test:
    name: "Stage 1: Test Suite (≥85% Coverage)"
    steps:
      - run: mix coveralls.json --min-coverage ${{ env.MIN_COVERAGE }}

  dialyzer:
    name: "Stage 2: Dialyzer (Type Safety)"
    needs: test
    steps:
      - run: mix dialyzer --halt-exit-status --format github

  credo:
    name: "Stage 3: Credo (Code Quality)"
    needs: test
    steps:
      - run: mix credo --strict

  event_taxonomy:
    name: "Stage 4: Event Taxonomy (AUDIT-05)"
    needs: test
    steps:
      - run: mix thunderline.events.lint --format=json

  security:
    name: "Stage 5: Security (SBOM & Vuln Scan)"
    needs: test
    steps:
      - uses: gitleaks/gitleaks-action@v2
      - run: mix sobelow --exit
      - run: trivy fs --exit-code 1 --severity HIGH,CRITICAL .

  docker:
    name: "Stage 6: Docker (Build & Sign)"
    needs: [test, dialyzer, credo, event_taxonomy, security]
    if: github.event_name == 'push'
    steps:
      - uses: docker/build-push-action@v5
        with:
          sbom: true
          provenance: true
      - run: cosign sign --yes ${{ steps.build.outputs.digest }}

  ci_lockdown_complete:
    needs: [test, dialyzer, credo, event_taxonomy, security, migration_drift]
    steps:
      - run: echo "✅ CI Lockdown COMPLETE"
```

---

**🔒 THUNDERLINE CI LOCKDOWN: OPERATIONAL AND ENFORCED 🔒**
