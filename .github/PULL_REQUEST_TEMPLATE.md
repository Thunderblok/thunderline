# Pull Request Review Checklist

<!-- 
  Copy this checklist into your PR description and check off items as you complete them.
  This ensures all PRs meet Thunderline's quality standards before merge.
-->

## PR Information

- **HC Task ID**: [e.g., HC-01, IRON_TIDE-003]
- **Domain**: [ThunderBolt, ThunderFlow, ThunderGate, ThunderCrown, etc.]
- **Type**: [Feature, Bugfix, Refactor, Documentation, Infrastructure]
- **Priority**: [Critical, High, Normal, Low]
- **Breaking Change**: [Yes/No] (if yes, describe migration path)
- **Related PRs**: [List any dependent or related PRs]

---

## 1. Functional Review

- [ ] **Requirements met**: All acceptance criteria from the task are satisfied
- [ ] **Code quality**: Logic is clear, maintainable, and follows Elixir conventions
- [ ] **Edge cases handled**: Boundary conditions, null checks, error states are covered
- [ ] **No regressions**: Existing functionality remains intact

---

## 2. Ash 3.x Compliance

- [ ] **Resource structure**: Resources follow Ash 3.x patterns (attributes, actions, relationships)
- [ ] **Policies**: Authorization policies are defined and tested (or authorization bypassed explicitly with `authorize?: false`)
- [ ] **State machines**: If applicable, `AshStateMachine` is used correctly with proper transitions
- [ ] **Validations**: Input validation uses Ash validations (not manual checks in actions)
- [ ] **Code interfaces**: Actions exposed via domain code interfaces (not direct `Ash.create!/2` calls in controllers/LiveViews)

---

## 3. Event & Telemetry Compliance

- [ ] **EventBus usage**: All events use `Thunderline.EventBus.publish_event/1` (not legacy Bus)
- [ ] **Event taxonomy**: Events follow `EVENT_TAXONOMY.md` v0.2 naming conventions (`<domain>.<component>.<action>`)
- [ ] **Telemetry spans**: Critical operations emit telemetry spans (`:start`, `:stop`, `:exception`)
- [ ] **Correlation IDs**: `correlation_id` propagated through saga steps, events, and external calls

---

## 4. Testing Requirements

- [ ] **Coverage target**: Test coverage ≥85% line, ≥80% branch (run `mix test --cover`)
- [ ] **Test types**: Unit tests, integration tests, and property-based tests where appropriate
- [ ] **Test quality**: Tests are clear, deterministic, and use meaningful assertions
- [ ] **CI green**: All CI/CD checks pass (see section 8)

---

## 5. Documentation

- [ ] **Code docs**: All public functions have `@doc` and `@moduledoc` with examples
- [ ] **User docs**: If user-facing, updated relevant guides (QUICKSTART.md, user docs)
- [ ] **Domain docs**: If new domain functionality, updated domain-specific documentation
- [ ] **Changelog**: Added entry to CHANGELOG.md (if significant change)

---

## 6. Security Review

- [ ] **Authentication/Authorization**: Policies enforce least-privilege access
- [ ] **Input validation**: All external inputs validated (Ash validations, NimbleOptions)
- [ ] **Data protection**: Sensitive data (passwords, tokens) never logged or exposed
- [ ] **Injection prevention**: No raw SQL, shell commands, or unsafe string interpolation

---

## 7. Performance Review

- [ ] **Database queries**: No N+1 queries (use Ash `load` or Ecto preloads)
- [ ] **Resource usage**: No unbounded loops, memory leaks, or blocking operations
- [ ] **Telemetry**: Performance-critical paths emit duration metrics

---

## 8. CI/CD Checks

- [ ] **Compile**: `mix compile --warnings-as-errors` (zero warnings)
- [ ] **Tests**: `mix test` (all tests green)
- [ ] **Ash Doctor**: `mix ash.doctor` (no Ash resource issues)
- [ ] **Credo**: `mix credo --strict` (code quality standards)
- [ ] **Dialyzer**: `mix dialyzer` (type safety, if configured)
- [ ] **Sobelow**: `mix sobelow` (security scan, if applicable)

---

## 9. Duplicate Asset Removal

- [ ] **Deprecation process**: If removing assets, followed deprecation process (mark deprecated first, then remove)
- [ ] **No duplicates**: Verified no duplicate functionality exists elsewhere

---

## 10. Deployment Readiness

- [ ] **Config**: All new config keys documented and added to releases.exs/runtime.exs
- [ ] **Migrations**: Database migrations tested (up and down) and backward-compatible
- [ ] **Monitoring**: Alerts/dashboards updated if new critical paths added

---

## 11. Review Sign-Off

- [ ] **Domain Steward**: Domain owner has approved (tag in PR comments)
- [ ] **Platform Lead**: Platform team has approved (if infrastructure/cross-domain)
- [ ] **High Command**: HC approval obtained (if HC task)

---

## 12. Pre-Merge Checklist

- [ ] **Final validation**: All CI checks green, all reviewers approved
- [ ] **Merge strategy**: Squash/merge commits as appropriate (keep history clean)
- [ ] **Post-merge tasks**: Deployment plan documented (if applicable), monitoring alerts verified

---

**For the Line, the Bolt, and the Crown.** ⚡
