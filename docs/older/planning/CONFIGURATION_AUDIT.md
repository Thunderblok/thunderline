# ⚙️ Thunderline Configuration Audit (Sprint 2)

**Date:** 2025-10-31  
**Audited By:** Rookie Team — Configuration Cleanup (Epic 5)  
**Scope:** Consolidate all environment variables, configuration surfaces, and identify redundancies across the Phoenix `config/` directory and runtime Elixir code.

---

## 🗂 Overview

The Thunderline application’s configuration system spans both runtime and compile-time definitions under `config/`.  
This audit identifies environment variables, their purpose, current duplication, and hard-coded defaults.

---

## 🔧 Configuration Sources

| File | Purpose |
|------|----------|
| [`config/config.exs`](../../../../config/config.exs) | Primary project setup, feature flags, domains, numerics, Cerebros routes |
| [`config/dev.exs`](../../../../config/dev.exs) | Local developer setup: Postgres dev pool, Tailwind/esbuild |
| [`config/test.exs`](../../../../config/test.exs) | CI/Test configuration with reduced timeouts and caches |
| [`config/prod.exs`](../../../../config/prod.exs) | Production-level hints (delegates secrets to `runtime.exs`) |
| [`config/runtime.exs`](../../../../config/runtime.exs) | Central runtime env parser: OTEL, DATABASE_URL, secrets, vault, flags |

---

## 🧩 Environment Category Matrix

### **1️⃣ Required Environment Variables**

| Variable | Purpose | Default/Behavior | Ctx/File |
|-----------|----------|------------------|-----------|
| `DATABASE_URL` | Core PostgreSQL connection string | None (raises if missing) | runtime.exs |
| `PHX_HOST` | Phoenix endpoint domain hostname | `"example.com"` | runtime.exs |
| `PORT` | Application HTTP listener port | `"4000"` | runtime.exs |
| `SECRET_KEY_BASE` | Required for session/cookie signing | None (raises) | runtime.exs |
| `TOKEN_SIGNING_SECRET` | Used for internal JWT & AshAuth keys | None (raises) | runtime.exs |
| `THUNDERLINE_VAULT_KEY` | AES-GCM encryption key for Cloak Vault | Optional (dev/test use defaults) | runtime.exs |
| `POOL_SIZE` | DB connection pool size | `"10"` | runtime.exs |
| `ECTO_IPV6` | IPv6 toggle for Repo socket binding | Disabled by default | runtime.exs |

---

### **2️⃣ Service URLs & External Integrations**

| Variable | External Service | Default | Notes |
|-----------|------------------|----------|-------|
| `THUNDERLINE_NUMERICS_SIDECAR_URL` | Python numerics HTTP service | `http://localhost:8089` | Replace in production |
| `MLFLOW_TRACKING_URI` | MLflow experiment tracker | `http://localhost:5000` | Key dependency for model versioning |
| `CEREBROS_SCRIPT` / `CEREBROS_REPO` / `CEREBROS_WORKDIR` | Cerebros AI runner linkage | embedded fallback path | Aligned with thunderbolt.mlflow adaptability |
| `CEREBROS_PYTHON` | Python interpreter path | `"python3"` | runtime fallback |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry tracing endpoint | none | configures via `runtime.exs` |
| `JIDO_ACTION_ROUTER_URL` | Action routing base URL | `https://registry.jido.ai` | external MCP route logic |

---

### **3️⃣ Feature Flags**

| Variable | Feature | Default | Notes |
|-----------|----------|----------|-------|
| `FEATURES` | master flag list (CSV) | empty string | compiled-time load in `config.exs` |
| `FEATURE_CA_VIZ` | enables CA visualizations | false | runtime override in `runtime.exs` |
| `FEATURE_AI_CHAT_PANEL` | toggles chat UI | false | feature module flag |
| `FEATURE_TOCP` | activates TOCP protocol runtime | false | TOCP subsystem |
| `FEATURE_THUNDERVINE_LINEAGE` | telemetry lineage view | false | runtime injection |
| `DEMO_MODE` | UI demo enablement | false | triggers scoped routing guard in LiveView router |
| `ENABLE_UPS`, `ENABLE_NDJSON` | optional observability / diagnostics | false | backward-compat alias `ENABLE_*` vs `FEATURE_*` |

---

### **4️⃣ Secrets & Tokens**

| Variable | Category | Default | Status |
|-----------|-----------|----------|--------|
| `SECRET_KEY_BASE` | Phoenix session cryptography | none | required for prod |
| `TOKEN_SIGNING_SECRET` | JWT signing | none | required |
| `THUNDERLINE_VAULT_KEY` | Cloak Vault | optional | recommend setting non-empty in QA/prod |
| `CEREBROS_TIMEOUT_MS` / `CEREBROS_MAX_RETRIES` | Python subprocess safety | fallback integers set | validate upper bounds in prod |
| `OTEL_*` vars | Observability credentials | none | sensitive if OTLP endpoints externalize |

---

## ⚠️ Duplications & Conflicts

| Issue | Details | Suggested Action |
|--------|----------|------------------|
| **`CEREBROS_*` variables** | defined in both `config.exs`, `test.exs`, and `runtime.exs` | consolidate runtime parsing; remove duplicate integer conversion blocks |
| **`FEATURES` vs `FEATURE_*`** | compile-time `FEATURES` and runtime `FEATURE_*` both define features | merge under runtime dynamic override, prioritize runtime toggles |
| **`SECRET_KEY_BASE` duplication** | dev/test have static literal strings | move to `.env.example` and reference consistently |
| **localhost hard-coded URLs** | appears in multiple numerics/mlflow modules | extract to config/environment variable surface |

---

## 🕵️‍♂️ Code-Level Hardcoding Findings

| Instance | Example | File | Cleanup Recommendation |
|-----------|----------|------|-------------------------|
| `"http://localhost:8089"` | Numerics sidecar service | [`thunderbolt/numerics/adapters/sidecar.ex`](../../../lib/thunderline/thunderbolt/numerics/adapters/sidecar.ex:10) | replace with `System.get_env("THUNDERLINE_NUMERICS_SIDECAR_URL")` |
| `"http://localhost:5000"` | MLFlow tracker | [`thunderbolt/mlflow/config.ex`](../../../lib/thunderline/thunderbolt/mlflow/config.ex:25) | align with `.env` variable default |
| `"user@example.com"` | hardcoded test user | Saga seeds (Thunderbolt) | enclosure under `MIX_ENV=test` block only |
| `"example.com"` / `"127.0.0.1"` defaults | Repo runner & Phoenix host | config/runtime.exs & migration_runner | inject defaults via `.env` |

---

## 🧱 Consolidation & Cleanup Strategy

- **Centralize env parsing** in `runtime.exs` only (avoid conversions in `config.exs`).
- **Merge feature toggles**: unify runtime and compile-time sources (favor runtime).
- **Parameterize service endpoints** using `.env` defaults.
- **Document all secrets** directly in `.env.example` to guide developer onboarding.
- **Enforce `MIX_ENV` awareness** to prevent vaulted/test overlap.

---

## 📋 Action Items

1. Move Cerebros and MLflow variable parsing to runtime.
2. Add missing OTEL_* docstrings to `.env.example`.
3. Eliminate duplicated cache control entries (`CEREBROS_CACHE_*`) across envs.
4. Migrate all localhost URLs to dynamic envs with fallback.
5. Include service registries, UPS backend, and Oban verbose toggles under `.env.example`.

---

## ✅ Summary

This audit validates Thunderline’s configuration hierarchy and offers a unified, environment-driven configuration structure.  
Adopting these cleanup actions will improve reproducibility, onboarding, and deployment consistency.
