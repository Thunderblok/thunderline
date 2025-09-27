# PAC Training Cycle Kanban (Short-Term Goal)

This board captures every thread we need to run a full training cycle for a single PAC: data prep → Cerebros NAS trials → artifact promotion → capability vector update → observability + runbook. Use it as the shared source of truth when coordinating work between the core maintainer and the assisting AI dev.

## Board Structure

- **Columns:** Ready ▸ In Progress ▸ Review ▸ Blocked ▸ Done
- **WIP Limits:** 2 cards per contributor in _In Progress_; keep at least one card open for pairing across domains when dependencies clear.
- **Rituals:**
  - Standup update = card ID + status change + blockers.
  - Every PR must reference the card ID in its title or body.
  - When a card hits **Review**, attach test logs / screenshots / telemetry snapshots.

## Ready / Backlog

| ID | Task | Domain | Primary Owner | Support | Dependencies | Acceptance Notes |
| --- | --- | --- | --- | --- | --- | --- |
| DATA-01 | Validate `memory_nodes` IVFFlat index and capture EXPLAIN ANALYZE output | Thunderblock | You | AI Dev | None | Index exists, EXPLAIN screenshot committed, index creation idempotent |
| DATA-02 | Document retention/TTL + backfill process for vectors | Thunderblock | You | Gate | DATA-01 | Runbook section added, CRON/Oban job listed, link from handbook |
| DATA-03 | Author PAC-specific dataset manifest (features + labels) | Thunderblock | AI Dev | Bolt | DATA-01 | Manifest committed, validated via `mix thunderline.dataset.check` (or stub) |
| BOLT-01 | Land Cerebros Bridge facade + telemetry (flag off) | Thunderbolt | AI Dev | Bolt | None | Modules compiled, telemetry events emitted, unit tests for enabled/disabled/timeout |
| BOLT-02 | Implement first training invocation path (mock pods ok) | Thunderbolt | AI Dev | Flow | BOLT-01 | Mix task or function triggers training run, returns metrics struct, recorded in tests |
| FLOW-01 | Generate Rose-Tree Parzen shortlist for target PAC | Flow | You | AI Dev | DATA-03 | Shortlist persisted, logged, reviewed with Bolt |
| FLOW-02 | Configure MOTPE objectives + search budget | Flow | You | Bolt | FLOW-01 | Config checked into repo, documented trade-offs (latency, accuracy, energy) |
| GRID-01 | Update Thundergrid VCV schema + write promotion helper | Thundergrid | You | Crown | BOLT-02 | VCV entry includes cost/latency/accuracy, GraphQL schema updated, tests added |
| OBS-01 | Emit training run telemetry (duration, cost, energy) | Observability | AI Dev | Flow | BOLT-02 | Telemetry events present, sampled in tests |
| OBS-02 | Add dashboard panels (training stats + BRG inputs) | Observability | AI Dev | You | OBS-01 | Grafana JSON or screenshot committed; BRG consumes metrics |
| CROWN-01 | Extend BRG checks to gate on training telemetry & policy verdict | ThunderCrown | You | Gate | OBS-02 | `mix thunderline.brg.check` fails if telemetry missing or verdict stale |
| GOV-01 | Document policy guardrails + approval workflow for new training outputs | Thundergate | Gate | Crown | GRID-01 | Policy matrix updated, approval runbook included, link in handbook |
| QA-01 | Add integration test covering Cerebros training happy path (stub) | Test | You | AI Dev | BOLT-02, FLOW-02 | Test exercises end-to-end path, asserts telemetry + VCV update, runs in CI |
| OPS-01 | Publish PAC training cycle operator runbook | Ops | You | Gate | QA-01 | Runbook lives in `/documentation/planning/`, includes pre-flight, execution, rollback |

## In Progress

_Move cards here with owner initials and current branch once work begins._

## Review

_Cards waiting for PR review, test results, or stakeholder sign-off. Attach artefacts (logs, screenshots, EXPLAIN output)._ 

## Blocked

_List blockers with cause + expected unblock date. Escalate anything stuck > 24h._

## Done

_Definition: code merged to `main`, docs updated, telemetry verified, runbook signed off, and BRG checks green._

## Sprint Milestone – Definition of Done

- One PAC completes a training cycle via Cerebros (even if pods mocked) with metrics captured.
- VCV entry refreshed and visible through Thundergrid API.
- Training telemetry surfaced on dashboards and included in BRG gate.
- Operator runbook + policy guardrails merged.
- Integration test and supporting unit tests pass under `mix precommit`.
- Post-mortem notes captured (what worked, what to automate next cycle).
