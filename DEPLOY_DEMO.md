# Thunderline Public Presence & Demo Deployment

This document captures the operational steps to satisfy the Phase I "OPEN THE GATES" brief:

Public Landing (www.thunderline.net) via GitHub Pages + Live Demo (demo.thunderline.net) via container deploy (Fly.io example).

## 1. DNS Layout

| Host | Target | Record Type | Notes |
|------|--------|-------------|-------|
| www.thunderline.net | <username>.github.io | CNAME | GitHub Pages site (serves /site contents) |
| thunderline.net | www.thunderline.net | ALIAS/A | Optional apex redirect to www (use provider ALIAS/ANAME) |
| demo.thunderline.net | Fly allocated hostname (e.g. thunderline-demo.fly.dev) | CNAME | Phoenix demo runtime |

GitHub Pages requires the CNAME file (already added under `site/CNAME`).

## 2. Landing Site (GitHub Pages)

Structure:
```
site/
  index.html  (hero + CTA + overview)
  CNAME       (www.thunderline.net)
```

Workflow: `.github/workflows/pages.yml` publishes `site/` to Pages on push to `main` (paths filter).

To enable:
1. In repo settings → Pages: Set source to GitHub Actions.
2. Add custom domain `www.thunderline.net` & enforce HTTPS.
3. Verify DNS CNAME points to `<org>.github.io`.

## 3. Demo Container (Fly.io Example)

Files added:
* `Dockerfile` – multi‑stage release image
* `fly.toml` – baseline app config with demo feature flags
* `.github/workflows/demo-deploy.yml` – builds & pushes image to GHCR (manual deploy step to Fly)
* `scripts/demo/reset_demo.sh` – nightly reset script
* `priv/repo/demo_seeds.exs` – placeholder seeds (extend with real data)

Provision steps (Fly.io):
```
flyctl apps create thunderline-demo
flyctl secrets set \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  TOKEN_SIGNING_SECRET=$(mix phx.gen.secret) \
  DATABASE_URL=ecto://postgres:postgres@<external-db-host>:5432/thunderline \
  PHX_HOST=demo.thunderline.net

flyctl deploy --build-only # (optional validate build)
flyctl deploy

# Map demo subdomain DNS CNAME -> thunderline-demo.fly.dev
```

If using Fly Postgres:
```
flyctl postgres create --name thunderline-demo-db
flyctl postgres attach --app thunderline-demo thunderline-demo-db
```

## 4. Feature Flags & Demo Mode

`DEMO_MODE=1` triggers runtime overlay (see `config/runtime.exs`) enabling:
* `:ca_viz`
* `:thundervine_lineage`
* `:ai_chat_panel`

Additional env feature toggles:
```
FEATURE_CA_VIZ=1
FEATURE_THUNDERVINE_LINEAGE=1
FEATURE_AI_CHAT_PANEL=1
FEATURE_ENABLE_NDJSON=0
FEATURE_ENABLE_UPS=0
```

## 5. Security & Safety

Middleware: `ThunderlineWeb.Plugs.DemoSecurity` (added to router when `DEMO_MODE` set) provides:
* Optional Basic Auth (`DEMO_BASIC_AUTH_USER`/`DEMO_BASIC_AUTH_PASS`)
* Lightweight ETS rate limiting (default 120 req/min/IP)
* Security headers (CSP, X-Frame-Options, Referrer-Policy, X-Content-Type-Options)
* `x-robots-tag: noindex` unless `DEMO_ALLOW_INDEX=1`

Recommended First Pass:
```
DEMO_BASIC_AUTH_USER=demo
DEMO_BASIC_AUTH_PASS=<strong-password>
```

## 6. Nightly Reset (Workflow Sketch)

Add a scheduled GitHub Action (not yet committed) calling:
```
flyctl ssh console -C "bash -lc 'export DATABASE_URL=...; ./bin/thunderline eval \"Mix.Task.run(\'run\', [\'priv/repo/demo_seeds.exs\'])\"'"
```
Or run `scripts/demo/reset_demo.sh` in a build runner with network access.

## 7. Next Phase Hooks (Placeholders)

| Phase | Deliverable | Hook Point |
|-------|-------------|-----------|
| II | DAG resources & Broadway ingress | Add `dag_*` Ash resources, pipeline child spec, feature flag `:thundervine_lineage` already reserved |
| III | CA Runner 20–30Hz | `Thunderline.Thunderbolt.CA.RunnerSupervisor` already gated by `:ca_viz` |
| IV | Jido → spec parse | Ensure `cmd.workflow.spec.parse` events captured; extend taxonomy doc & linter |

## 8. Hardening TODOs

* Add SRI hashes for CDN resources on landing page
* Add separate minimal `robots.txt` served by Pages (`Disallow: /` until public launch)
* Implement proper structured demo seeds (communities, channels, sample events)
* Add smoke test GitHub Action hitting demo health endpoint after deploy
* Add `mix thunderline.demo.audit` task (future) verifying required flags & routes

---
Maintained: High Command Operations. Update upon phase transitions.
