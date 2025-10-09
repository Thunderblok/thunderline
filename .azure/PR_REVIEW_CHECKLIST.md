# Pull Request Review Checklist
**Thunderline Rebuild Initiative - Quality Gate**

Copy this checklist into every PR description for HC task work.

---

## PR Information

**HC Task ID:** HC-[XX]  
**Domain:** [Thunderbolt|Thundercrown|Thunderlink|Thunderblock|ThunderFlow|Thundergrid|Thundergate|Thunderforge]  
**Type:** [Feature|Bugfix|Refactor|Documentation|Migration]  
**Priority:** [P0|P1|P2]  
**Breaking Change:** [Yes|No]

**Related PRs:**
- #[N]
- #[N]

---

## 1. Functional Review

### Requirements
- [ ] Implements all acceptance criteria from HC task
- [ ] Happy path tested with examples
- [ ] Error paths tested (validation, not_found, unauthorized)
- [ ] Edge cases identified and tested
- [ ] No regressions in existing functionality

### Code Quality
- [ ] Functions are single-purpose and well-named
- [ ] No code duplication (DRY principle)
- [ ] Complex logic has explanatory comments
- [ ] No magic numbers (use named constants)
- [ ] Error messages are clear and actionable

---

## 2. Ash 3.x Compliance

### Resource Structure
- [ ] `use Ash.Resource, domain: CorrectDomain` specified
- [ ] Domain matches directory structure (`lib/thunderline/<domain>/resources/`)
- [ ] No legacy `prepare` or `fragment` query builders
- [ ] Uses `Ash.Query` APIs for complex queries

### Policies
- [ ] Uses `Ash.Policy.Authorizer` (if resource has auth)
- [ ] Policies defined in `policies do` block
- [ ] No inline policy checks scattered in code
- [ ] Default deny posture (`policy action_type(:*) do forbid_if always() end`)
- [ ] Actor context passed correctly

### State Machines (if applicable)
- [ ] `use AshStateMachine` syntax correct
- [ ] All states defined in `initial_states` and `default_initial_state`
- [ ] Transitions defined with `from:`, `to:`, and valid actions
- [ ] State change events emitted via EventBus

### Validations & Calculations
- [ ] Validations re-enabled (not commented out)
- [ ] Aggregates re-enabled (not commented out)
- [ ] Calculations use `expr()` macro correctly
- [ ] No deprecated validation syntax

---

## 3. Event & Telemetry Compliance

### EventBus Usage
- [ ] Uses `Thunderline.EventBus.publish_event/1` (not legacy `Bus.put/1`)
- [ ] Event struct follows canonical format:
  ```elixir
  %{
    name: "domain.component.action",
    source: "thunderline.domain",
    category: :system | :domain | :integration | :user | :error,
    priority: :critical | :high | :normal | :low,
    payload: %{...}
  }
  ```
- [ ] Event name follows taxonomy (verified with `mix thunderline.events.lint`)
- [ ] Handles `{:ok, event} | {:error, reason}` return values

### Telemetry Spans
- [ ] Critical operations emit telemetry:
  - `[:thunderline, :domain, :component, :start]`
  - `[:thunderline, :domain, :component, :stop]`
  - `[:thunderline, :domain, :component, :exception]`
- [ ] Measurements include timing, counts, sizes
- [ ] Metadata includes actor_id, resource_id, action

---

## 4. Testing Requirements

### Coverage
- [ ] New code has ≥ 85% line coverage
- [ ] New code has ≥ 80% branch coverage
- [ ] `mix test --cover` output included in PR description

### Test Types
- [ ] Unit tests for pure functions
- [ ] Integration tests for Ash actions
- [ ] Policy tests (authorized/unauthorized scenarios)
- [ ] State machine transition tests (if applicable)
- [ ] Event emission tests (telemetry captured)
- [ ] Error path tests (validation failures, exceptions)

### Test Quality
- [ ] Tests are deterministic (no flakiness)
- [ ] Tests are isolated (no shared state)
- [ ] Test names describe behavior clearly
- [ ] Fixtures/factories used (not hardcoded data)
- [ ] Async tests where possible (`async: true`)

---

## 5. Documentation

### Code Documentation
- [ ] Public functions have `@doc` annotations
- [ ] Complex algorithms have explanatory comments
- [ ] Modules have `@moduledoc` with purpose and examples
- [ ] Type specs for public functions (`@spec`)

### User Documentation
- [ ] README updated (if new feature)
- [ ] CHANGELOG.md entry added (if notable change)
- [ ] Migration guide (if breaking change)
- [ ] API examples in relevant `.md` files

### Domain Documentation
- [ ] Updates to domain catalog (if new resource)
- [ ] Updates to EVENT_TAXONOMY.md (if new event categories)
- [ ] Updates to ERROR_CLASSES.md (if new error types)
- [ ] Updates to FEATURE_FLAGS.md (if new flag)

---

## 6. Security Review

### Authentication & Authorization
- [ ] All actions require actor context (no anonymous access unless explicit)
- [ ] Policies enforce least privilege
- [ ] No hardcoded credentials or API keys
- [ ] Secrets use environment variables or vault

### Input Validation
- [ ] All user input validated (type, format, range)
- [ ] No SQL injection vectors (uses Ash queries)
- [ ] No XSS vectors (templates escape output)
- [ ] File uploads validated (type, size, content)

### Data Protection
- [ ] Sensitive data encrypted at rest (uses `AshCloak` if needed)
- [ ] Sensitive data not logged
- [ ] PII handling compliant (GDPR considerations)
- [ ] Database migrations reviewed for data safety

---

## 7. Performance Review

### Database Queries
- [ ] No N+1 queries (use `Ash.load/2` for associations)
- [ ] Appropriate indexes added in migrations
- [ ] Query plans reviewed for large tables
- [ ] Pagination used for large result sets

### Resource Usage
- [ ] No unbounded loops or recursion
- [ ] Large collections streamed (use `Stream` not `Enum`)
- [ ] Proper timeouts set for external calls
- [ ] Memory allocations reasonable

### Telemetry
- [ ] Slow operations (>100ms) have telemetry
- [ ] Database query times tracked
- [ ] External API call times tracked

---

## 8. CI/CD Checks

### Automated Checks
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes (all tests green)
- [ ] `mix thunderline.events.lint` passes
- [ ] `mix ash doctor` passes (no warnings)
- [ ] `mix credo --strict` passes
- [ ] `mix dialyzer` passes (if applicable)
- [ ] `mix sobelow --config` passes

### Manual Checks
- [ ] No new compiler warnings introduced
- [ ] No test flakiness observed
- [ ] CI build time reasonable (<15 minutes)

---

## 9. Duplicate Asset Removal (if applicable)

### Deprecation Process
- [ ] Old asset usage identified (grep results documented)
- [ ] Migration path provided for callers
- [ ] Deprecation warning added (if interim period needed)
- [ ] Metrics tracked for adoption (if applicable)
- [ ] Removal PR linked (if two-phase deprecation)

### Validation
- [ ] No references to deprecated asset remain
- [ ] Tests updated to use new API
- [ ] Documentation updated
- [ ] `mix thunderline.events.lint` confirms no violations

---

## 10. Deployment Readiness

### Configuration
- [ ] Environment variables documented (if new)
- [ ] Feature flags configured (if applicable)
- [ ] Default values safe for production
- [ ] Runtime configuration tested (`config/runtime.exs`)

### Migrations
- [ ] Database migrations are reversible
- [ ] Migrations tested on sample data
- [ ] Migration downtime estimated (if any)
- [ ] Rollback plan documented

### Monitoring
- [ ] Relevant metrics exposed (Prometheus, Telemetry)
- [ ] Alerts configured for failures
- [ ] Logs structured and parseable
- [ ] Dashboards updated (if new metrics)

---

## 11. Review Sign-Off

### Domain Steward Review
**Reviewer:** [Name]  
**Date:** [YYYY-MM-DD]  
**Verdict:** ✅ APPROVED | ⚠️ APPROVED WITH COMMENTS | 🔴 CHANGES REQUESTED

**Comments:**
- [Bullet points with feedback]

### Platform Lead Review (if needed)
**Reviewer:** [Name]  
**Date:** [YYYY-MM-DD]  
**Verdict:** ✅ APPROVED | ⚠️ APPROVED WITH COMMENTS | 🔴 CHANGES REQUESTED

**Comments:**
- [Bullet points with feedback]

### High Command Review (if P0 or breaking change)
**Reviewer:** [Name]  
**Date:** [YYYY-MM-DD]  
**Verdict:** ✅ APPROVED | ⚠️ APPROVED WITH COMMENTS | 🔴 CHANGES REQUESTED

**Comments:**
- [Bullet points with feedback]

---

## 12. Pre-Merge Checklist

### Final Validation
- [ ] All review comments addressed
- [ ] All CI checks passing
- [ ] Conflicts resolved with main branch
- [ ] Commit messages follow convention (e.g., "HC-XX: Brief description")
- [ ] PR description updated with final notes

### Merge Strategy
- [ ] **Squash & Merge** (default for feature PRs)
- [ ] **Merge Commit** (for multi-commit PRs with logical history)
- [ ] **Rebase & Merge** (for linear history requirement)

### Post-Merge Tasks
- [ ] Linked issues closed
- [ ] Dependent PRs notified
- [ ] Documentation site rebuilt (if applicable)
- [ ] Warden Chronicles updated

---

## Notes & Considerations

**Reviewer Notes:**
[Space for reviewer to add context, concerns, or follow-up items]

**Author Notes:**
[Space for author to explain complex decisions, trade-offs, or future work]

---

**Checklist Version:** 1.0  
**Last Updated:** October 9, 2025  
**Maintained By:** Platform Lead
