# Thunderline AI Coding Assistant (Concise Guide)

Goal: Fast, safe edits in a Phoenix + Ash + Event + Oban + (optional) Reactor system.

## Big Picture
Phoenix shell + 12-Domain Pantheon: **Core** (tick/identity), **Pac** (PAC lifecycle), **Crown** (governance+orchestration), **Bolt** (ML/automata), **Gate** (security), **Block** (persistence), **Flow** (events), **Grid** (API), **Vine** (DAG), **Prism** (UX), **Link** (communication), **Wall** (entropy/GC). Only Block touches raw `Repo`; everywhere else use Ash actions. Events flow through `Thunderline.Thunderflow.*`; async work = Oban jobs. Optional saga path if `TL_ENABLE_REACTOR=true`.

**System Cycle**: Core → Wall (Spark to containment)
**Domain Vectors**: Crown→Bolt (policy→execute), Flow→Grid→Prism (IO→surface→UX), Pac→Block→Vine (state→persist→orchestrate)

## Always Do
1. Start new behavior inside correct domain folder (`lib/thunderline/<domain>`).
2. Model data via Ash Resource; then run `mix ash_postgres.generate_migrations` and commit resource + migration + snapshot.
3. Emit events only via `Thunderline.Thunderflow.EventBus.publish_event/1` (pattern-match on `{:ok, _} | {:error, _}`).
4. LiveView templates begin with `<Layouts.app ...>` and use `@form = to_form(...)` + `<.input>` components (never expose raw changeset in HEEx).
5. Use `Req` for outbound HTTP; add no alternate clients.
6. Telemetry names: `[:thunderline, :<domain>, :<component>]`.

## Feature / Change Checklist
Resource change? -> Update Ash resource -> generate migration -> tests. Background work? -> Create Oban worker (`*.new() |> Oban.insert()`). Cross-domain need? -> Prefer event or Ash action; do NOT call Repo from other domains. Add env flag? -> Follow `FEATURES_X` pattern & document in README table.

## Events & Retries
Processor applies exponential backoff + jitter, classifies `:transient | :permanent | :unknown`. Preserve canonical event struct (see README) and only add optional fields. Keep non‑reactor fast path intact when adding Reactor logic.

## Env / Setup Nuances
`mix setup` runs `deps.get` only if lock or `deps/phoenix` missing (or you call `mix deps.get` manually). `ash_jido` loads only with Elixir ≥ 1.18 or `INCLUDE_ASH_JIDO=1`; guard optional usage with `Code.ensure_loaded?`.

## Testing
Add CRUD + custom action test per new resource. For data-transform migrations: forward test (and reversal if applicable). Oban workers: happy path + telemetry assertion. LiveViews: assert by element IDs using `Phoenix.LiveViewTest` & `LazyHTML`.

## Avoid
Raw `Repo` outside Block; deprecated `live_redirect`/`live_patch`; accessing changeset fields directly; adding new HTTP libs; mutating event structs in place; multi-branch `if` instead of `cond`/`case`.

## Key Files
`mix.exs` (aliases, conditional deps)
`lib/thunderline/thunderflow/*` (event pipeline, retry, telemetry)
`lib/thunderline/thunderblock/**` (resources + allowed Repo)
`README.md` (architecture, feature flags, event struct)
`CONTRIBUTING.md` (migration workflow)
`AGENTS.md` (Phoenix/Ash LiveView rules)

## Snippets
Publish event:
```elixir
with {:ok, ev} <- Thunderline.Thunderflow.EventBus.publish_event(attrs) do {:ok, ev} else {:error, r} -> {:error, r} end
```
LiveView form:
```elixir
socket = assign(socket, form: to_form(changeset))
```
Stream:
```heex
<div id="items" phx-update="stream"><div :for={{id, it} <- @streams.items} id={id}>{it.name}</div></div>
```

If something is unclear (domain boundaries, event shape, LiveView pattern), state your task + missing context and request refinement.
