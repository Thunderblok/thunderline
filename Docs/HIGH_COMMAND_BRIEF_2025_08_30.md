# ⚡ High Command Brief — Thunderline Dev Team (Aug 30, 2025)

## What’s wired today (from the repo docs)

### Live auth & UI shell
- AshAuthentication is the auth layer, and LiveViews set the Ash actor on mount via `ThunderlineWeb.Live.Auth`. That’s the spine every UI surface hangs off of.

### ThunderLink (the app shell) already exposes a real UI
- Discord-style communities/channels, post-auth redirect to the first channel, websocket messaging, and an AI Panel stub region in the layout are present. This is the natural home for agent controls.

### Automata (ThunderCell / ThunderBolt) in UI
- Automata LiveView exists and shows real ThunderCell data; more viz polish remains. There’s also a Blackboard GenServer surfaced to LiveView for shared state.
- The ThunderCell CA engine is operational (process-per-cell, 3D grid, telemetry). This means the UI can subscribe and render today.

### Security & presence posture
- LiveViews run with a central actor; AshAuth is integrated under ThunderGate. Presence policy gating is planned to land next in ThunderLink’s layout.

## What’s not wired (and where to add it)

### 1) Ash Admin access in the UI
- No confirmed `/admin` route in prod.

Recommendation:
- Mount `AshAdmin.Router` under `/admin`.
- Protect via `on_mount ThunderlineWeb.Live.Auth` + a Gate policy (role in `[:owner, :steward]`).
- Link to it from ThunderLink’s sidebar (visible only to authorized roles).

### 2) ThunderBolt/ThunderCell automata controls
- UI exists and receives data, but viz + control panels (start/stop sim, rule sets, snapshot/restore) are incomplete.

Recommendation:
- Add an “Automata” workspace in ThunderLink (sidebar item).
- Panels: Grid Viz (current LiveView, finish controls), Blackboard (inspect/publish hints), Rules/Parameters (Ash forms for model/rule selection).
- Emit/subscribe through EventBus for consistent telemetry.

### 3) “Jido agents” access point
- No explicit “Jido” UI or resource in the code yet; AI Panel stub present.

Recommendation:
- Treat “Jido agents” as tools surfaced in the AI Panel inside ThunderLink, backed by ThunderCrown policies.
- First cut: a “Run Agent” drawer that invokes approved tools via EventBus → ThunderCrown (actor = Ash user).
- Add per-agent visibility via Gate policies.

## Concrete, dev-ready to-dos (UI access)

### AshAdmin (owner/steward only)
- Router: mount `AshAdmin.Router` at `/admin`, wrap with auth `on_mount` and role check.
- Sidebar: add “Admin” link visible only to Gate-approved roles.
- Audit: log admin access to `audit_log` in ThunderGate.

### Automata (ThunderCell/ThunderBolt)
- Route: `/automata` → LiveView that:
  - Subscribes to ThunderCell telemetry topics.
  - Exposes controls mapped to Ash actions (start/stop/snapshot/restore).
- Blackboard Panel: list keys, edit ephemeral hints; emit normalized events via EventBus.
- Viz polish: finish the 3D grid and rule metrics on the dashboard.

### Jido agents (via AI Panel)
- Panel wiring: replace the stub region with a tool runner:
  - Selector (approved agents/tools), prompt/config form, “Run” button.
  - Stream output back into the panel; emit `ui.command.agent.requested` + `system.agent.completed|failed` using Event constructor rules.
- Policy: Evaluate access in ThunderGate (role + community scope).

## Guardrails we must honor
- All cross-domain calls go through EventBus or Ash actions—no leaky joins.
- Every new UI surface must emit at least one health metric/telemetry event.
- Keep presence/security enforcement in ThunderGate; don’t sneak it into ThunderLink or automata modules.

## Quick status calls
- AshAdmin: Not mounted → mount `/admin` behind Gate roles; link in sidebar. (1 PR)
- Automata UI: LiveView present, needs controls/viz finish; expose Blackboard panel & Ash actions. (1–2 PRs)
- Jido agents: No direct UI yet → implement AI Panel tool runner via ThunderCrown; policy via Gate. (1 PR)

---

# 🎯 Full Orders — Immediate Mission Objectives (P0)

These are non‑negotiable. Must hit in next sprint window:

## HC-04: ML Persistence
- Run Cerebros migrations under ThunderBolt.
- Emit telemetry `ml.schema.version`.
- Blocker for email lineage + audit.

## HC-05: Email MVP ("Send an Email")
- Scaffold `Contact` + `OutboundEmail` Ash resources.
- Actions: `:create_contact`, `:queue_send`, `:mark_sent`, `:mark_failed`.
- Events: `ui.command.email.requested`, `system.email.sent|failed`.
- Keep scope minimal (no templates/bounce tracking yet).

## HC-06: Presence Policies
- Admission token stub at ANNOUNCE.
- Membership enforcement → no token, no gossip.
- Quarantine state in Membership + Router enforcement.

## HC-07/08: Ops First Brick
- Write Dockerfile + mix release script.
- Add `/healthz` plug endpoint.
- CI: Dialyzer PLT cache + `mix hex.audit`.

## HC-09: Error Classifier
- Skeleton classifier module.
- Broadway hook returning `{class, action}`.
- DLQ policy stubs.

## HC-03: Event Taxonomy Linter
- `mix thunderline.events.lint`.
- Validate event name/version. Fail CI on drift.
- Tiny slice, immediate win.

---

# 🔐 Security (Operation Iron Veil)

Ship Now:
- Sign ANNOUNCE/ADVERTISE/ACK frames.
- Replay window check (30s skew) + counters.
- `FlowControl.allowed?/1` stub → emit `:rate.drop`.
- Quarantine events on threshold breach.

Governance:
- Allow insecure presence flag only with boot-time WARN + telemetry (`[:tocp,:security,:insecure_mode]`).

Tripwires:
- Zero unsigned control frames in sim.
- Replay rejection ≥ 99.9% within 30s skew.
- Anomaly reaction < 60s (quarantine/hysteresis bump).

---

# 📊 Dev Team Checklist (Next 7 Days)
- Run ML migrations (ThunderBolt)
- Scaffold Email resources + events
- Admission token stub + presence gating
- Wire `Security.Impl` → Membership/Router
- Implement `FlowControl.allowed?/1`
- Dockerfile + release script + healthcheck
- Add Dialyzer PLT cache + `hex.audit` job
- ErrorClassifier skeleton + DLQ stub
- Event linter Mix task

---

# 🧭 Rallying Call — Θ‑03 Directive
Sign the frames. Drop the replays. Quarantine the ghosts. Ship the migrations. Send the email. Build the image. If it isn’t in the sim’s JSON, it doesn’t exist. Festina lente.
