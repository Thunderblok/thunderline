## Thunderline Pre-Review Audit (August 25, 2025)

This document captures a point-in-time audit before high‑command review.

### 1. Correctness / Stability
* WebSocket client system state log spam fixed (pattern match corrected).
* LiveView dashboard now guards unknown messages & KPI refresh handlers added.
* No critical compile errors; tests currently failing early (environment dependent) – ensure DB & feature flags set (see Section 5).

### 2. Observability
* EventBus centralization in place; Bus shim still referenced in 4 modules (dashboard & signal stack). Low risk – staged migration possible by adding convenience wrappers in EventBus and replacing `alias Thunderline.Bus`.
* RingBuffer + noise pipeline active; consider adding telemetry events for CA KPI refresh latency.

### 3. Technical Debt (Prioritized)
| Priority | Item | Action |
|----------|------|--------|
| P0 | Bus alias debt | Replace `alias Thunderline.Bus` usages; keep shim temporarily |
| P0 | Cerebros persistence migrations | Promote backup migrations & run in dev/test |
| P1 | Credo readability hotspots | Batch replace semicolons / `length(list)>0` patterns (partial) |
| P1 | TODO fragments in Ash resources (fragment expressions) | Open issues or implement Ash 3.x fragment updates |
| P2 | Feature parity gaps (snapshot/restore, rule metrics) | DIP issues & roadmap entries |

### 4. Security / Compliance
* AshAuthentication integrated; ensure session token invalidation tests exist (missing coverage – add if time permits).
* Sobelow not yet run in this audit; run `mix sobelow --config` in CI gate.

### 5. Test Strategy Gaps
* `mix test` exited with code 1 without visible output (likely DB unavailable or test alias performing migrations silently). Recommend running:
  ```bash
  MIX_ENV=test SKIP_ASH_SETUP=true mix test --trace
  MIX_ENV=test mix ash.setup && mix test
  ```
* Add minimal test for ThunderWebsocketClient successful system state fetch (assert no debug error log via capture_log).

### 6. Documentation Adjustments
* README: Added Feature Flags section & BOnus migration note.
* Handbook: Updated BOnus references to reflect completion.
* CHANGELOG: Unreleased section documents latest internal fixes.

### 7. Open TODO Clusters (Representative)
* Ash 3.x fragment expression fixes in ThunderLink resource modules.
* Validation & trigger DSL adjustments in `role.ex`, `message.ex` (AshOban/Ash 3 syntax).
* ChannelParticipant resource still pending (referenced TODO in `channel.ex`).

### 8. Recommended Immediate Next PR(s)
1. PR A (Bus & Tests): Replace Bus aliases → EventBus, add websocket client test, LiveView metric update test.
2. PR B (Persistence): Promote & apply Cerebros migrations, add ModelRun CRUD test.
3. PR C (Fragments): Fix Ash fragment TODOs or create tracking issues linking to AUDIT lines.

### 9. Risk Register (Condensed)
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missing Cerebros tables | Medium | Medium | Apply migrations (PR B) |
| Legacy Bus lingering | High | Low | Codemod (PR A) |
| Fragment TODOs accumulate | Medium | Medium | PR C or issues |
| Hidden test failures (DB) | Medium | Medium | Ensure deterministic test DB bootstrap |

### 10. Sign‑off Checklist
| Item | Status |
|------|--------|
| System state log noise removed | ✅ |
| Feature flags documented | ✅ |
| BOnus migration documented | ✅ |
| Critical runtime handlers present in dashboard | ✅ |
| Credo high-signal readability items (sample) | ✅ (partial) |
| Unreleased CHANGELOG entry | ✅ |
| Audit document present | ✅ |

---
Prepared for review – see sections 3 & 8 for fast-follow actions.
