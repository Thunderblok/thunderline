# Contributing / Schema & Release Workflow

> This project uses Ash Framework + AshPostgres + Oban. Migrations are generated from resource definitions. Do **not** hand-edit old migrations.

## Golden Rules
1. Never modify an existing migration file once merged to `main`.
2. All schema changes start by editing Ash resources (attributes, relationships, indexes in the `postgres do` block).
3. Generate forward migrations + snapshots:

```bash
mix ash_postgres.generate_migrations
```

4. Review the generated migration file(s); ensure only additive or intentional changes. Commit *both* the resource changes and new migration(s) together.
5. Run tests & Dialyzer before pushing.
6. For destructive changes (drops/renames), prefer a 2-step deprecation (add new column + backfill + later remove) to keep rolling deploy safety.

## Quick Commands

```bash
# Generate migrations & snapshots (interactive if conflicts)
mix ash_postgres.generate_migrations

# Just check drift in CI (non-zero exit if drift)
mix ash_postgres.generate_migrations --check --dry-run || echo "Drift detected"

# Apply migrations locally
mix ecto.migrate

# Reset & seed (be careful!)
mix ecto.reset

# Full setup (deps + db + assets)
mix ash.setup

## Local Git Hooks (Optional but Recommended)
Install project-provided hooks:

```bash
git config core.hooksPath .githooks
```

Pre-commit hook enforces:
1. No edits to historical migrations (`scripts/check_migration_history.sh`).
2. No schema drift (`mix ash_postgres.generate_migrations --check --dry-run`).

If it blocks you due to drift:
```bash
mix ash_postgres.generate_migrations
mix ecto.migrate
git add priv/repo/migrations priv/resource_snapshots
```
```

## Handling Column Renames
Ash cannot infer a safe rename vs. drop/add. Strategy:
1. Add the new attribute (keep old).
2. Backfill data (custom migration or one-off task).
3. Migrate code to use new attribute.
4. Remove old attribute in later sprint (forward migration).

## Oban
Run once (if not already applied) to install base Oban tables:
```bash
mix oban.migrations
mix ecto.migrate
```
Do not inline Oban table changes manually.

## CI Guard
CI runs the generator in check/dry-run mode. If drift is reported, add the missing migration.

## Versioning & Releases
Use conventional commits; run `mix git_ops.release --yes` (dev only) to cut releases. Never manually bump version in `mix.exs`.

## Telemetry & Observability
Emit telemetry for new background jobs. Name: `[:thunderline, :<domain>, :<thing>]` with clear measurements & metadata keys.

## Test Expectations
- Every new resource: at least one CRUD test (read/create) + any custom action logic.
- Background workers: happy path test + telemetry assertion.
- Migrations altering data: add a reversible test if logic (backfills) are included.

## Security & Quality Gates
- Credo: `mix credo --strict` must pass.
- Sobelow: No High findings unchecked into `main`.
- Dialyzer: No new warnings without rationale.

## FAQ
**Q: Generator says drift but I just added code?** You forgot to commit the generated migration or a teammate changed the DB structure.

**Q: Can I hand-write a migration?** Only for nuanced data transforms or backfills. Still prefer `generate_migrations` for schema shape then layer manual changes inside that file.

**Q: Multiple domains share a table?** Resolve prompts during generator run; pick the proper PK; others become unique constraints.

---
Happy hacking ⚡
