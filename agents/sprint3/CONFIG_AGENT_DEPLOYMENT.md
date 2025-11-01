# ⚙️ Config Agent Deployment Plan

**Agent ID:** `config-agent`  
**Epic:** 3.1 Cerebros Integration Execution  
**Priority:** 🔴 CRITICAL (Priority 1)  
**Duration:** 20 minutes  
**Can Run Parallel With:** fix-agent, test-agent  

## Mission
Configure environment, feature flags, and validate service connectivity.

## Tasks

### Task 1: Enable Feature Flag (2 min)
**File:** `config/config.exs` or `config/runtime.exs`

**Add:**
```elixir
config :thunderline, :features,
  cerebros_enabled: System.get_env("CEREBROS_ENABLED", "false") == "true"
```

**File:** `.env` (create if needed)
```bash
export CEREBROS_ENABLED=1
```

**Verification:** `Application.get_env(:thunderline, :features)[:cerebros_enabled]` returns true

---

### Task 2: Python Service Configuration (5 min)
**File:** `.env` (add Cerebros service settings)

```bash
# Cerebros Service Configuration
CEREBROS_SERVICE_URL=http://localhost:5000
CEREBROS_SERVICE_TIMEOUT=30000
CEREBROS_API_KEY=dev_key_12345
```

**File:** `config/runtime.exs` (add config)
```elixir
config :thunderline, :cerebros,
  service_url: System.get_env("CEREBROS_SERVICE_URL", "http://localhost:5000"),
  timeout: String.to_integer(System.get_env("CEREBROS_SERVICE_TIMEOUT", "30000")),
  api_key: System.get_env("CEREBROS_API_KEY")
```

---

### Task 3: Update .env.example (2 min)
**File:** `.env.example`

**Add section:**
```bash
# Cerebros Integration (Optional - enable advanced features)
CEREBROS_ENABLED=1
CEREBROS_SERVICE_URL=http://localhost:5000
CEREBROS_SERVICE_TIMEOUT=30000
CEREBROS_API_KEY=your_api_key_here
```

---

### Task 4: Validate Service Connection (5 min)
**Create test script:** `scripts/test_cerebros_connection.exs`

```elixir
# Test Cerebros service connectivity
url = Application.get_env(:thunderline, :cerebros)[:service_url]
timeout = Application.get_env(:thunderline, :cerebros)[:timeout]

IO.puts("Testing connection to: #{url}")

case Req.get(url <> "/health", receive_timeout: timeout) do
  {:ok, %{status: 200}} -> IO.puts("✅ Cerebros service reachable")
  {:ok, %{status: status}} -> IO.puts("⚠️  Service returned: #{status}")
  {:error, reason} -> IO.puts("❌ Connection failed: #{inspect(reason)}")
end
```

**Run:** `mix run scripts/test_cerebros_connection.exs`

---

### Task 5: Document Startup Sequence (3 min)
**File:** `docs/CEREBROS_SETUP.md` (create)

```markdown
# Cerebros Service Setup

## Prerequisites
1. Python service running at configured URL
2. Environment variables set
3. Feature flag enabled

## Startup Sequence
1. Start Python service: `cd /home/mo/DEV/cerebros && python app.py`
2. Enable flag: `export CEREBROS_ENABLED=1`
3. Start Thunderline: `mix phx.server`
4. Access dashboard: http://localhost:4000/cerebros

## Troubleshooting
- Service not reachable → Check Python service is running
- Connection timeout → Increase CEREBROS_SERVICE_TIMEOUT
- Auth errors → Verify CEREBROS_API_KEY matches
```

---

## Deliverables

- [ ] Feature flag configured in config files
- [ ] `.env` with Cerebros settings
- [ ] `.env.example` updated
- [ ] Connection test script created
- [ ] Service connectivity validated
- [ ] Startup documentation created

## Success Criteria
✅ Feature flag working (can enable/disable)  
✅ Environment variables loaded  
✅ Service connection test passes  
✅ Documentation complete  

## Blockers
- ❌ Python service not running → Start it or update URL
- ❌ Port conflict → Change port in config
- ❌ Missing API key → Generate or disable auth

## Communication
**Report When:**
- Feature flag added (2 min mark)
- Config complete (7 min mark)
- Connection validated (12 min mark)
- Docs written (15 min mark)
- All verified (20 min mark)

**Estimated Completion:** 20 minutes  
**Status:** 🟢 READY TO DEPLOY
