# Rookie Team Sprint 2: Codebase Consolidation & Structure

**Mission:** Clean up the architecture, establish patterns, and prepare for the Cerebros integration fix.

**Context:** You crushed Sprint 1 with documentation. Now we need you to help organize the actual code structure so we can ship this thing. The Python/UI team merged and they're gunning for us - we need to prove pure Elixir can dominate.

**Timeline:** 1 week sprint (Nov 1-8, 2025)

---

## 🎯 Sprint Objectives

By end of sprint, we should have:
1. ✅ Clean directory structure (no abandoned code)
2. ✅ Consistent naming patterns across domains
3. ✅ Single source of truth for each concept
4. ✅ Clear separation of concerns
5. ✅ Ready for Cerebros integration fix

---

## 📋 Epic 1: Domain Boundary Enforcement (Priority: CRITICAL)

**Goal:** Make sure domains don't leak into each other

### Task 1.1: Find Cross-Domain Violations

**Search for violations:**
```bash
cd /home/mo/DEV/Thunderline

# ThunderBlock should only be called by other domains, never call out
grep -r "alias Thunderline.Thunder" lib/thunderline/thunderblock/ --include="*.ex" | grep -v "ThunderBlock" > block_violations.txt

# ThunderFlow should only emit events, not call domains directly
grep -r "alias Thunderline.Thunder" lib/thunderline/thunderflow/ --include="*.ex" | grep -v "ThunderFlow\|Event" > flow_violations.txt

# Check for direct Repo calls outside ThunderBlock
grep -r "Repo\." lib/thunderline/ --include="*.ex" | grep -v "thunderblock\|_test.exs" > repo_violations.txt
```

**Create Report:** `DOMAIN_BOUNDARY_VIOLATIONS.md`

```markdown
# Domain Boundary Violations

## Critical Issues

### ThunderBlock calling other domains ❌
[List violations from block_violations.txt]

### Direct Repo usage outside Block ❌
[List violations from repo_violations.txt]

### Circular dependencies ❌
[Any domains that depend on each other]

## Severity Assessment

- 🔴 Critical: Must fix before Cerebros integration
- 🟡 Warning: Should fix soon
- 🟢 Info: Nice to have

## Recommended Fixes

For each violation, suggest:
1. Which domain should own the logic
2. How to communicate (events vs direct calls)
3. Estimated effort (1-5 points)
```

### Task 1.2: Document Current Domain Interactions

**Create:** `DOMAIN_INTERACTION_MAP.md`

Use this template:
```markdown
# Domain Interaction Map

## ThunderBlock (Data Layer)
**Role:** Persistence, infrastructure
**Calls:** None (lowest layer)
**Called By:** All domains (for data access)
**Events Published:** None
**Events Consumed:** None

## ThunderFlow (Event Bus)
**Role:** Event routing, stream processing
**Calls:** None (orchestrator only)
**Called By:** All domains (to publish events)
**Events Published:** All event types
**Events Consumed:** All event types

## ThunderBolt (Compute)
**Role:** ML/AI, heavy compute
**Calls:** ThunderBlock (data), ThunderFlow (events)
**Called By:** ThunderCrown (orchestration)
**Events Published:** `ml.*`, `compute.*`
**Events Consumed:** `orchestration.*`

[Continue for each domain...]

## Dependency Graph

```mermaid
graph TD
    Crown[ThunderCrown]
    Bolt[ThunderBolt]
    Flow[ThunderFlow]
    Block[ThunderBlock]
    Gate[ThunderGate]
    Grid[ThunderGrid]
    Link[ThunderLink]
    
    Crown --> Flow
    Crown --> Block
    Bolt --> Flow
    Bolt --> Block
    Gate --> Flow
    Gate --> Block
    Grid --> Flow
    Grid --> Block
    Link --> Flow
    Link --> Block
    
    Flow --> Block
```

## Rules to Enforce

1. ✅ All domains can call ThunderBlock
2. ✅ All domains can call ThunderFlow
3. ❌ ThunderBlock never calls other domains
4. ❌ ThunderFlow never calls domains (event-driven only)
5. ❌ No circular dependencies between domains
6. ⚠️ Cross-domain calls should be rare (prefer events)
```

---

## 📋 Epic 2: Module Organization Cleanup (Priority: HIGH)

**Goal:** Every module has a clear home, no duplicates, no abandoned code

### Task 2.1: Find Orphaned/Abandoned Modules

**Search for red flags:**
```bash
# Find empty modules
find lib/ -name "*.ex" -type f -exec sh -c 'test $(wc -l < "$1") -lt 20' _ {} \; -print > small_modules.txt

# Find modules with no tests
for f in $(find lib/thunderline -name "*.ex" -type f); do
    base=$(basename "$f" .ex)
    testfile="test/thunderline/$(echo $f | sed 's|lib/thunderline/||' | sed 's|\.ex|_test.exs|')"
    if [ ! -f "$testfile" ]; then
        echo "$f -> NO TEST" >> modules_without_tests.txt
    fi
done

# Find TODO/FIXME comments
grep -r "TODO\|FIXME\|XXX\|HACK" lib/thunderline --include="*.ex" > todo_comments.txt
```

**Create Report:** `ORPHANED_CODE_REPORT.md`

```markdown
# Orphaned Code Report

## Empty/Stub Modules (< 20 lines)
[List from small_modules.txt]

**Decision:** 
- Keep if: Planning to implement soon
- Move to: `lib/thunderline/deprecated/` if old
- Delete if: Dead code, no plans

## Modules Without Tests
[List from modules_without_tests.txt]

**Priority for tests:**
1. 🔴 Critical path (authentication, data access)
2. 🟡 Important features (events, jobs)
3. 🟢 Nice to have (utilities, helpers)

## TODO/FIXME Comments
[Group by severity and age]

**Action Items:**
- Create issues for critical TODOs
- Delete resolved TODOs
- Add context to unclear TODOs
```

### Task 2.2: Standardize Module Naming

**Check naming consistency:**
```bash
# Find inconsistent naming patterns
find lib/thunderline -name "*.ex" | grep -i "cerebros" > cerebros_naming.txt
find lib/thunderline -name "*.ex" | grep -i "training" > training_naming.txt
find lib/thunderline -name "*.ex" | grep -i "ml\|machine" > ml_naming.txt
```

**Create Standards Doc:** `MODULE_NAMING_STANDARDS.md`

```markdown
# Module Naming Standards

## Domain Prefixes (Enforced)

All modules MUST use domain prefix:
- ✅ `Thunderline.ThunderBlock.*`
- ✅ `Thunderline.ThunderBolt.*`
- ✅ `Thunderline.ThunderCrown.*`
- ✅ `Thunderline.ThunderFlow.*`
- ✅ `Thunderline.ThunderGate.*`
- ✅ `Thunderline.ThunderGrid.*`
- ✅ `Thunderline.ThunderLink.*`

❌ Never:
- `Thunderline.ML.*` (use ThunderBolt)
- `Thunderline.Auth.*` (use ThunderGate)
- `Thunderline.Event.*` (use ThunderFlow)

## Submodule Patterns

### Resources (Ash)
- Pattern: `Domain.Resources.ResourceName`
- Example: `ThunderBlock.Resources.User`

### Actions (Business Logic)
- Pattern: `Domain.Actions.ActionName`
- Example: `ThunderBolt.Actions.TrainModel`

### Workers (Background Jobs)
- Pattern: `Domain.Workers.WorkerName`
- Example: `ThunderBolt.Workers.ModelTrainingWorker`

### Services (External Integration)
- Pattern: `Domain.Services.ServiceName`
- Example: `ThunderGate.Services.GithubAPI`

### Utilities (Helpers)
- Pattern: `Domain.Utils.UtilName`
- Example: `ThunderFlow.Utils.EventTransformer`

## Migration Plan

### Phase 1: Mark Deprecated (Week 1)
Add `@deprecated` to old modules:
```elixir
defmodule Thunderline.ML.Training do
  @deprecated "Use Thunderline.ThunderBolt.Actions.TrainModel instead"
  # ...
end
```

### Phase 2: Create Aliases (Week 2)
Add transition aliases:
```elixir
defmodule Thunderline.ML.Training do
  @moduledoc false
  defdelegate train(params), to: Thunderline.ThunderBolt.Actions.TrainModel
end
```

### Phase 3: Update Callers (Week 3-4)
Find and replace all references

### Phase 4: Delete Old (Week 5)
Remove deprecated modules
```

---

## 📋 Epic 3: CerebrosBridge Integration Prep (Priority: CRITICAL)

**Goal:** Get everything ready so senior team can drop in the Cerebros fix instantly

### Task 3.1: Document Current Bridge Architecture

**Read these files and understand the flow:**
```bash
lib/thunderline/thunderbolt/cerebros_bridge/
├── client.ex           # Main entry point
├── invoker.ex          # Subprocess execution
├── contracts.ex        # Data validation
├── translator.ex       # Format conversion
├── validator.ex        # Request/response validation
├── cache.ex           # ETS caching
├── persistence.ex     # State management
├── run_options.ex     # Configuration
└── run_worker.ex      # Oban job (BROKEN - one import)
```

**Create:** `CEREBROS_BRIDGE_ARCHITECTURE.md`

```markdown
# CerebrosBridge Architecture

## Overview
Bridge layer between Elixir (Thunderline) and Python (Cerebros service)

## Components

### Client (`client.ex`)
**Purpose:** Feature-gated facade for Cerebros execution

**Key Functions:**
- `enabled?/0` - Check if bridge is active
- `config/0` - Get bridge configuration
- `start_run/2` - Initiate NAS run
- `version/1` - Check Cerebros version

**Dependencies:**
- Feature flags (`:ml_nas`)
- Configuration (`:cerebros_bridge`)
- Event bus
- Cache, Contracts, Invoker, Translator

### Invoker (`invoker.ex`)
**Purpose:** Execute Cerebros calls as external subprocesses

**Features:**
- Retry logic with exponential backoff
- Timeout management
- Error classification
- Telemetry events

**Retry Strategy:**
```elixir
retry_count = 0..max_retries
delay = base_delay * (2 ^ retry_count)
max_delay = min(delay, max_delay_ms)
```

### RunWorker (`run_worker.ex`)
**Purpose:** Oban worker for async NAS runs

**Status:** ⚠️ BROKEN (Line 26 import)

**Fix Needed:**
```elixir
# BEFORE (BROKEN):
alias Thunderline.Thunderbolt.Cerebros.Telemetry

# AFTER (FIXED):
alias Cerebros.Telemetry
```

**Job Flow:**
1. Receive job args (run_id, spec, budget, etc.)
2. Validate inputs
3. Start run via Client
4. Record trials
5. Finalize run
6. Emit telemetry

## Data Flow

```
LiveView (Dashboard)
    ↓
CerebrosBridge.Client.start_run()
    ↓
Oban.insert(RunWorker.new())
    ↓
RunWorker.perform()
    ↓
Invoker.invoke() → [subprocess]
    ↓
Python Cerebros Service (port 8000)
    ↓
Results back through bridge
    ↓
Persistence layer
    ↓
Event emission
```

## Configuration

Required config in `config/dev.exs`:
```elixir
config :thunderline, :cerebros_bridge,
  enabled: System.get_env("CEREBROS_ENABLED") == "1",
  repo_path: "/home/mo/DEV/cerebros",
  script_path: "priv/bridge/cerebros_bridge.py",
  python_executable: "python3",
  timeout: 300_000,
  max_retries: 3,
  cache_ttl: 3600
```

## Dependencies

### Elixir Side:
- `Thunderline.ThunderBolt.CerebrosBridge.*` (this layer)
- `Cerebros` package (at `/home/mo/DEV/cerebros`) - NOT YET ADDED TO MIX.EXS
- `Thunderline.ThunderFlow.EventBus`
- `Oban` for async jobs

### Python Side:
- Cerebros Python service at `localhost:8000`
- Located at: `/home/mo/thunderline/` (lowercase)
- Start with: `./start_cerebros.sh`

## Integration Checklist

Before Cerebros integration can work:

- [ ] Fix broken import in `run_worker.ex:26`
- [ ] Add Cerebros to `mix.exs` dependencies
- [ ] Set `CEREBROS_ENABLED=1` environment variable
- [ ] Start Python Cerebros service (port 8000)
- [ ] Verify feature flag `:ml_nas` is enabled
- [ ] Test end-to-end: Dashboard → Worker → Python → Results

## Web Layer Integration Points

### Controllers Using Bridge:
- `ThunderlineWeb.CerebrosMetricsController`
- `ThunderlineWeb.CerebrosJobsController`
- `ThunderlineWeb.MLEventsController`

### LiveViews Using Bridge:
- `ThunderlineWeb.CerebrosLive` (main dashboard)
- `ThunderlineWeb.ThunderlineDashboardLive` (home dashboard)

### Routes:
```elixir
scope "/api/cerebros" do
  post "/jobs/:job_id/status", CerebrosJobsController, :update_status
  post "/jobs/:job_id/metrics", CerebrosJobsController, :update_metrics
  # ...
end
```

## Testing Strategy

1. **Unit Tests:** Each bridge module isolated
2. **Integration Tests:** Full flow with mock Python service
3. **E2E Tests:** Real Python service on port 8000
4. **Manual Tests:** Dashboard NAS launch button

## Known Issues

1. **Import Error:** `run_worker.ex:26` references old module path
2. **Missing Dependency:** Cerebros not in mix.exs
3. **Service Not Running:** Python service needs to be started
4. **Demo Functions:** `cerebros_live.ex` has 4 functions calling old Cerebros module directly

## Senior Team Fix Plan

1. ✅ One-line import fix (2 min)
2. ✅ Add dependency to mix.exs (5 min)
3. ✅ Handle demo functions (10 min)
4. ✅ Enable feature flag (2 min)
5. ✅ Test compilation (5 min)
6. ⚠️ Start Python service (TBD)
7. ✅ Test dashboard (10 min)

**Total:** ~30 minutes + Python service setup
```

### Task 3.2: Audit All Cerebros References

**Goal:** Find EVERY place Cerebros is mentioned so we know what to test after the fix

```bash
# Find all Cerebros mentions
grep -r "Cerebros\|cerebros\|CEREBROS" lib/thunderline --include="*.ex" > all_cerebros_refs.txt

# Separate by type
grep "alias.*Cerebros" all_cerebros_refs.txt > cerebros_aliases.txt
grep "defmodule.*Cerebros" all_cerebros_refs.txt > cerebros_modules.txt
grep "Cerebros\." all_cerebros_refs.txt | grep -v "alias\|defmodule" > cerebros_calls.txt
```

**Create:** `CEREBROS_REFERENCE_AUDIT.md`

```markdown
# Cerebros Reference Audit

## Summary
- Total references: [count from all_cerebros_refs.txt]
- Module definitions: [count from cerebros_modules.txt]
- Alias statements: [count from cerebros_aliases.txt]
- Direct calls: [count from cerebros_calls.txt]

## CerebrosBridge Modules (✅ Keep These)
These are the bridge layer - do not touch:
- `Thunderline.ThunderBolt.CerebrosBridge.Client`
- `Thunderline.ThunderBolt.CerebrosBridge.Invoker`
- [List all 9 bridge modules]

## Old Module References (❌ Need Updating)
These reference the OLD Cerebros location:
[List any references to `Thunderline.Thunderbolt.Cerebros.*` that aren't in bridge/]

## External Package References (✅ After Integration)
These will work once package is added:
[List references to just `Cerebros.*` without Thunderline prefix]

## Test Files
[List all test files that mention Cerebros]
**Status:** Need to update after integration

## Configuration References
[List config files mentioning Cerebros]

## Documentation References
[List .md files mentioning Cerebros]
**Status:** Update after integration works

## Action Plan

### Phase 1: Senior Team Fixes (1 hour)
- Fix broken import
- Add dependency
- Enable feature flag

### Phase 2: Rookie Team Tests (1-2 days)
After senior fix:
1. Test each controller endpoint manually
2. Test each LiveView page
3. Document what works vs broken
4. Create issues for remaining problems

### Phase 3: Documentation Update (1 day)
After everything works:
1. Update all docs to reflect new architecture
2. Add "How to use Cerebros" guide
3. Update troubleshooting section
```

---

## 📋 Epic 4: Test Infrastructure Setup (Priority: MEDIUM)

**Goal:** Make it EASY to write tests, establish patterns

### Task 4.1: Create Test Helpers

**Create:** `test/support/domain_test_helpers.ex`

```elixir
defmodule Thunderline.DomainTestHelpers do
  @moduledoc """
  Shared test helpers for all domain tests.
  Reduces boilerplate and establishes patterns.
  """

  @doc """
  Creates a test user with authentication token.
  """
  def create_test_user(attrs \\ %{}) do
    # Implementation
  end

  @doc """
  Creates test event with proper structure.
  """
  def create_test_event(type, payload, opts \\ []) do
    # Implementation
  end

  @doc """
  Asserts that an event was published.
  """
  def assert_event_published(event_type, timeout \\ 100) do
    # Implementation
  end

  @doc """
  Starts services needed for integration tests.
  """
  def start_test_services do
    # Start event bus, cache, etc.
  end
end
```

### Task 4.2: Document Testing Patterns

**Create:** `TEST_PATTERNS.md`

```markdown
# Testing Patterns & Standards

## Directory Structure

```
test/
├── support/
│   ├── domain_test_helpers.ex    # Shared helpers
│   ├── data_case.ex              # Database tests
│   └── conn_case.ex              # Controller tests
├── thunderline/
│   ├── thunderblock/             # Domain tests
│   │   ├── resources/            # Resource tests
│   │   ├── actions/              # Action tests
│   │   └── workers/              # Worker tests
│   └── thunderflow/
│       └── ...
└── thunderline_web/
    ├── controllers/              # Controller tests
    └── live/                     # LiveView tests
```

## Naming Conventions

- File: `my_module_test.exs`
- Module: `MyModuleTest`
- Test: `test "does something specific"`

## Test Categories

### Unit Tests (Fast, No DB)
```elixir
defmodule Thunderline.ThunderBolt.Utils.CalculatorTest do
  use ExUnit.Case, async: true
  
  alias Thunderline.ThunderBolt.Utils.Calculator
  
  describe "add/2" do
    test "adds two numbers" do
      assert Calculator.add(2, 3) == 5
    end
  end
end
```

### Resource Tests (With DB)
```elixir
defmodule Thunderline.ThunderBlock.Resources.UserTest do
  use Thunderline.DataCase, async: true
  
  alias Thunderline.ThunderBlock.Resources.User
  
  describe "create" do
    test "creates user with valid attrs" do
      attrs = %{email: "test@example.com", name: "Test"}
      assert {:ok, user} = User.create(attrs)
      assert user.email == "test@example.com"
    end
  end
end
```

### Controller Tests
```elixir
defmodule ThunderlineWeb.CerebrosJobsControllerTest do
  use ThunderlineWeb.ConnCase, async: true
  
  describe "POST /api/cerebros/jobs/:id/status" do
    test "updates job status", %{conn: conn} do
      # Setup
      job = create_test_job()
      
      # Execute
      conn = post(conn, "/api/cerebros/jobs/#{job.id}/status", 
        %{status: "completed"})
      
      # Assert
      assert json_response(conn, 200)
    end
  end
end
```

### LiveView Tests
```elixir
defmodule ThunderlineWeb.CerebrosLiveTest do
  use ThunderlineWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  
  describe "mount" do
    test "renders NAS form", %{conn: conn} do
      {:ok, view, html} = live(conn, "/cerebros")
      
      assert html =~ "Launch NAS Run"
      assert has_element?(view, "#nas-form")
    end
  end
end
```

### Integration Tests (Full Stack)
```elixir
defmodule Thunderline.Integration.CerebrosFlowTest do
  use Thunderline.DataCase, async: false
  
  import Thunderline.DomainTestHelpers
  
  setup do
    start_test_services()
    :ok
  end
  
  test "full NAS run lifecycle" do
    # 1. User submits form
    # 2. Event published
    # 3. Worker picks up
    # 4. Bridge calls Python
    # 5. Results saved
    # 6. Dashboard updates
  end
end
```

## Test Data Factories

Use helpers instead of raw attrs:
```elixir
# Bad
user = User.create!(%{
  email: "test#{System.unique_integer()}@example.com",
  name: "Test User",
  role: "admin",
  ...
})

# Good
user = create_test_user(role: "admin")
```

## Assertions

Be specific:
```elixir
# Bad
assert result

# Good
assert {:ok, %User{role: "admin"}} = result
```

## Test Coverage Goals

- 🔴 Critical: 100% (authentication, payments, data loss)
- 🟡 Important: 80% (features, business logic)
- 🟢 Nice: 60% (utilities, helpers)

## Running Tests

```bash
# All tests
mix test

# Specific file
mix test test/thunderline/thunderblock/resources/user_test.exs

# Specific test
mix test test/thunderline/thunderblock/resources/user_test.exs:42

# With coverage
mix test --cover

# Only failed
mix test --failed

# Watch mode (with mix_test_watch)
mix test.watch
```

## CI Requirements

All PRs must:
- ✅ Pass all tests
- ✅ No new warnings
- ✅ Coverage doesn't decrease
- ✅ Credo passes
- ✅ Dialyzer passes
```

---

## 📋 Epic 5: Configuration Cleanup (Priority: MEDIUM)

**Goal:** Single source of truth for all config

### Task 5.1: Audit Configuration Files

**Check these files:**
```bash
config/
├── config.exs        # Base config
├── dev.exs          # Development
├── test.exs         # Test
├── prod.exs         # Production
└── runtime.exs      # Runtime (for releases)
```

**Create:** `CONFIGURATION_AUDIT.md`

```markdown
# Configuration Audit

## Environment Variables Used

### Required (App Won't Start)
- `DATABASE_URL` - Postgres connection
- [List others]

### Feature Flags (Optional)
- `CEREBROS_ENABLED` - Enable ML features
- `RAG_ENABLED` - Enable semantic search
- `ENABLE_NDJSON` - Enable structured logging
- `ENABLE_UPS` - Enable power monitoring
- [List all from README]

### Service URLs (Optional)
- `CEREBROS_URL` - Python service (default: http://localhost:8000)
- `MLFLOW_URL` - MLflow tracking (default: http://localhost:5000)
- [List others]

### Secrets (Optional)
- `GITHUB_PERSONAL_ACCESS_TOKEN` - For MCP tools
- [List others]

## Configuration Consolidation

### Issues Found:
- [ ] Duplicate settings in multiple files
- [ ] Settings in code vs config files
- [ ] Unclear defaults
- [ ] Missing documentation

### Recommendations:
1. Move all feature flags to `config/config.exs`
2. Use runtime.exs for secrets only
3. Document every setting in README
4. Create .env.example template
```

### Task 5.2: Create .env.example Template

**Create:** `.env.example`

```bash
# ===========================================
# Thunderline Environment Configuration
# ===========================================
# Copy to .env and fill in your values
# DO NOT commit .env to git!

# --- Database (REQUIRED) ---
DATABASE_URL=ecto://postgres:postgres@localhost:5432/thunderline_dev

# --- Feature Flags (Optional) ---
CEREBROS_ENABLED=0              # Set to 1 to enable ML/NAS features
RAG_ENABLED=1                   # Set to 0 to disable semantic search
ENABLE_NDJSON=0                 # Set to 1 to enable structured event logs
ENABLE_UPS=0                    # Set to 1 to enable power monitoring
FEATURES_AI_CHAT_PANEL=0        # Set to 1 to enable experimental chat

# --- Service URLs (Optional) ---
CEREBROS_URL=http://localhost:8000    # Cerebros Python service
MLFLOW_URL=http://localhost:5000      # MLflow tracking server

# --- MCP Tools (Optional) ---
# GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxx  # For GitHub MCP integration

# --- Development (Optional) ---
# RETENTION_SWEEPER_CRON=0 * * * *     # Hourly retention sweep
# TL_ENABLE_REACTOR=false              # Use simple event processor
```

---

## 📊 Sprint Deliverables

By end of week, create PR with:

### Critical Deliverables (Must Have):
- [ ] `DOMAIN_BOUNDARY_VIOLATIONS.md` - All cross-domain issues
- [ ] `DOMAIN_INTERACTION_MAP.md` - How domains should talk
- [ ] `CEREBROS_BRIDGE_ARCHITECTURE.md` - Complete bridge docs
- [ ] `CEREBROS_REFERENCE_AUDIT.md` - Every mention of Cerebros
- [ ] `MODULE_NAMING_STANDARDS.md` - Enforced patterns

### Important Deliverables (Should Have):
- [ ] `ORPHANED_CODE_REPORT.md` - Dead code to delete
- [ ] `TEST_PATTERNS.md` - How to write tests
- [ ] `CONFIGURATION_AUDIT.md` - Config cleanup plan
- [ ] `.env.example` - Template for developers
- [ ] `test/support/domain_test_helpers.ex` - Test helpers

### Nice to Have:
- [ ] Migration scripts for renaming modules
- [ ] Credo custom checks for domain boundaries
- [ ] Test coverage report
- [ ] Performance benchmarks

---

## 🎯 Success Criteria

Sprint is successful if:

1. **We can identify ALL problems** (even if not fixed yet)
2. **We have a plan to fix each problem** (prioritized)
3. **Senior team can integrate Cerebros in < 1 hour**
4. **New devs can onboard using our docs**
5. **Tests are easy to write** (helpers + patterns)

---

## 💡 Pro Tips for This Sprint

### 1. Think Like an Architect
- Don't just document problems - propose solutions
- Consider trade-offs (speed vs safety, simple vs flexible)
- Think about future: will this scale to 10+ domains?

### 2. Use Automation
```bash
# Find duplicates automatically
find lib/ -name "*.ex" -exec md5sum {} \; | sort | uniq -d -w 32

# Count lines by domain
for d in lib/thunderline/*/; do
  echo -n "$(basename $d): "
  find $d -name "*.ex" -exec wc -l {} + | tail -1
done

# Find unused functions
mix xref graph --format stats
```

### 3. Ask "Why?" 5 Times
- Why do we have this pattern?
- Why is this module in this domain?
- Why are there two ways to do this?
- Keep asking until you understand the root cause

### 4. Document Decisions
When you find something weird, document:
- What it is
- Why it's weird
- Possible reasons it exists
- Recommendation (keep/change/delete)

---

## 🚀 Getting Started

1. **Create branch:**
   ```bash
   git checkout -b sprint2/codebase-consolidation
   ```

2. **Start with Epic 1** (Domain boundaries are most critical)

3. **Work in parallel if possible:**
   - One person on domain boundaries
   - One person on Cerebros audit
   - One person on test infrastructure

4. **Daily standup (async in observations file):**
   - What did I learn yesterday?
   - What am I tackling today?
   - Any blockers?

5. **Mid-week checkpoint:**
   - Show progress to senior team
   - Get feedback
   - Adjust priorities if needed

---

## 📝 Communication

### During Sprint:
Update `SPRINT_2_DAILY_LOG.md`:
```markdown
## Day 1 (Nov 1)
- Started Epic 1, Task 1.1
- Found 47 potential violations
- Question: Should ThunderFlow be allowed to call ThunderBlock directly?

## Day 2 (Nov 2)
- Completed domain boundary violations report
- Started Cerebros audit
- Blocker: Can't find all Python service locations
```

### End of Sprint:
Create `SPRINT_2_RETROSPECTIVE.md`:
```markdown
## What Went Well
- [List successes]

## What Was Hard
- [List challenges]

## What We Learned
- [Key insights]

## Recommendations for Next Sprint
- [Suggestions]
```

---

## ❓ Questions to Answer

As you work through this sprint:

1. **Architecture Questions:**
   - Is our domain structure optimal?
   - Should some domains be merged/split?
   - Are we over-engineering anything?

2. **Technical Debt Questions:**
   - What's the highest priority debt?
   - What can we safely ignore?
   - What will bite us later if not fixed?

3. **Process Questions:**
   - What tools would help us work faster?
   - What documentation is still missing?
   - How can we prevent new violations?

---

## 🎉 Remember

You're not just documenting - you're **designing the future architecture**. 

Your work this week will:
- Make Cerebros integration smooth
- Set standards for new features
- Prevent future technical debt
- Prove Elixir can dominate

**Let's show the Python/UI team what's up!** 💪⚡

Good luck! The senior team is counting on you. 🚀
