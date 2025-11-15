# Rookie Team: Documentation Audit & Codebase Sweep

**Mission:** Full documentation audit while we fix the Cerebros integration issues.

## 📋 Task Overview

You're doing a complete codebase sweep to:
1. Update all documentation to reflect current reality
2. Identify what's broken/outdated
3. Create a comprehensive system map
4. Document the Cerebros refactoring impact

**Timeline:** Take your time, be thorough. Quality over speed.

---

## 🎯 Task 1: Domain Catalog Audit (Priority: HIGH)

**File to Update:** `THUNDERLINE_DOMAIN_CATALOG.md`

### What to Do:

1. **Verify Each Domain Still Exists:**
   ```bash
   # Run this to see current domains:
   find lib/thunderline -name "*domain.ex" -type f
   ```

2. **For Each Domain, Document:**
   - Location: `lib/thunderline/<domain_name>/`
   - Resources: List all `.ex` files in domain
   - Status: ✅ Active, ⚠️ Partial, ❌ Broken
   - Notes: Any obvious issues

3. **Special Focus:**
   - **Thunderbolt Domain:** This is where Cerebros USED to live
   - Check for any references to `Thunderbolt.Cerebros.*`
   - Document what's still there vs moved to standalone package

**Example Entry:**
```markdown
### Thunderbolt Domain
- **Location:** `lib/thunderline/thunderbolt/`
- **Purpose:** ML/AI orchestration, VIM solver, automation
- **Status:** ⚠️ PARTIAL - Cerebros extracted to standalone package
- **Resources:**
  - ✅ `thunderbolt/resources/automata_run.ex`
  - ✅ `thunderbolt/vim/` (Virtual Ising Machine)
  - ❌ `thunderbolt/cerebros/` - MOVED to /home/mo/DEV/cerebros
- **Notes:** Need to update references to use new Cerebros package
```

---

## 🎯 Task 2: README Accuracy Check (Priority: HIGH)

**File to Update:** `README.md`

### What to Verify:

1. **Architecture Diagrams:**
   - Do they match current domain structure?
   - Is Cerebros shown correctly (now external)?
   - Mark sections as [OUTDATED] if wrong

2. **Installation Instructions:**
   - Try following them on a fresh clone
   - Note any missing steps
   - Document Python service setup (cerebros_service, mlflow)

3. **Environment Variables:**
   - List all `.env` vars actually used
   - Check which are required vs optional
   - Note any secrets needed for services

4. **Port Assignments:**
   - Phoenix: 5001 (confirmed)
   - MLflow: 5000 (verify if running)
   - Cerebros Python: 8000 (not currently running)
   - Any others?

**Add this section if missing:**
```markdown
## 🚨 Known Issues

### Cerebros Integration (In Progress)
- Cerebros has been extracted to standalone package at `/cerebros`
- Dashboard Cerebros features currently not working
- Need to add Cerebros as dependency in mix.exs
- Status: Being fixed by senior team
```

---

## 🎯 Task 3: Web Layer Inventory (Priority: CRITICAL)

**Mission:** Find ALL files that reference Cerebros/NAS

### What to Do:

1. **Search for Cerebros References:**
   ```bash
   cd /home/mo/DEV/Thunderline
   
   # Find all web files mentioning Cerebros
   grep -r "Cerebros" lib/thunderline_web/ --include="*.ex" --include="*.heex" > cerebros_web_references.txt
   
   # Find old module paths
   grep -r "Thunderbolt.Cerebros" lib/thunderline_web/ --include="*.ex" > cerebros_old_paths.txt
   
   # Find Training.Job references
   grep -r "Training.Job\|Training.Dataset" lib/ --include="*.ex" > training_refs.txt
   ```

2. **Create Inventory File:**

**File to Create:** `CEREBROS_WEB_INVENTORY.md`

```markdown
# Cerebros Web Layer Inventory

## Controllers

### ThunderlineWeb.CerebrosJobsController
- **Location:** `lib/thunderline_web/controllers/cerebros_jobs_controller.ex`
- **Status:** ❌ BROKEN
- **Issues:**
  - Line 15: References `Thunderline.Cerebros.Training.Job` (old path)
  - Line 34: References `Thunderline.Cerebros.Training.Dataset` (old path)
  - Functions failing: `update_status/2`, `update_metrics/2`, `add_checkpoint/2`
- **Fix Needed:** Update to use `Cerebros.Resources.TrainingJob`

## LiveViews

### [List each LiveView that mentions Cerebros]
- **Location:** 
- **Status:** 
- **Issues:**
- **Fix Needed:**

## Templates/Components

### [List each .heex file with Cerebros UI]
- **Location:**
- **Status:**
- **Issues:**

## Routes

### [Check router.ex for Cerebros routes]
- **Location:** `lib/thunderline_web/router.ex`
- **Routes Found:**
  ```elixir
  # Paste relevant route definitions
  ```
```

---

## 🎯 Task 4: Python Services Documentation (Priority: MEDIUM)

**File to Create:** `PYTHON_SERVICES.md`

### Document Each Python Service:

1. **MLflow Service:**
   - Location: `thunderhelm/mlflow/`
   - Purpose: Model tracking and registry
   - Port: 5000 (default)
   - How to start: `cd thunderhelm/mlflow && mlflow server ...`
   - Status: ❓ (check if running)

2. **Cerebros Python Service:**
   - Location: `thunderhelm/cerebros_service/`
   - Purpose: NAS solver backend
   - Port: 8000
   - How to start: `cd thunderhelm/cerebros_service && python app.py`
   - Status: ❌ Not running (confirmed)
   - Dependencies: Check `requirements.txt`

3. **Any Other Python Code:**
   - Check `python/` directory
   - Check `sidecar/` directory
   - Document what's there

**Template:**
```markdown
# Python Services

## Overview
Thunderline uses Python services for ML/AI tasks that need NumPy/PyTorch/etc.

## Services

### 1. MLflow Tracking Server
**Purpose:** Model experiment tracking and registry
**Location:** `thunderhelm/mlflow/`
**Port:** 5000
**Status:** ❓ Unknown (needs verification)

**Start Command:**
```bash
cd thunderhelm/mlflow
source ../../.venv/bin/activate
mlflow server --backend-store-uri sqlite:///mlflow.db --default-artifact-root ./mlruns --host 0.0.0.0 --port 5000
```

**Health Check:**
```bash
curl http://localhost:5000/health
```

[Continue for each service...]
```

---

## 🎯 Task 5: Dependency Tree Analysis (Priority: LOW)

**File to Create:** `DEPENDENCY_MAP.md`

### What to Document:

1. **Elixir Dependencies (from mix.exs):**
   - Group by category (Ash, Phoenix, Database, etc.)
   - Note version numbers
   - Mark critical vs optional

2. **Python Dependencies:**
   - Check all `requirements.txt` files
   - Check `pyproject.toml` if exists
   - List major packages (PyTorch, NumPy, etc.)

3. **JavaScript/Node:**
   - Check `assets/package.json`
   - List major packages (Tailwind, etc.)

---

## 🎯 Task 6: Test Coverage Report (Priority: LOW)

**File to Create:** `TEST_STATUS.md`

### What to Check:

```bash
# Find all test files
find test/ -name "*_test.exs" -type f > test_files_list.txt

# Count tests by domain
ls test/thunderline/*/  # See what domains have tests
```

**Document:**
- Which domains have good test coverage
- Which domains have NO tests
- Any obviously broken tests
- Cerebros tests that need updating

---

## 📊 Deliverables

When done, you should have:

- [ ] `THUNDERLINE_DOMAIN_CATALOG.md` - Updated and accurate
- [ ] `README.md` - Marked outdated sections, added known issues
- [ ] `CEREBROS_WEB_INVENTORY.md` - Complete list of broken files
- [ ] `PYTHON_SERVICES.md` - How to start/stop all Python services
- [ ] `DEPENDENCY_MAP.md` - What we depend on
- [ ] `TEST_STATUS.md` - Testing landscape
- [ ] `cerebros_web_references.txt` - Grep output
- [ ] `cerebros_old_paths.txt` - Grep output
- [ ] `training_refs.txt` - Grep output

---

## 🤔 Questions to Answer

As you go through the codebase, keep notes on:

1. **What looks abandoned?** (Empty directories, commented-out code)
2. **What's duplicated?** (Same logic in multiple places)
3. **What's confusing?** (Bad naming, unclear purpose)
4. **What's impressive?** (Cool patterns, good architecture)

Put these in a `ROOKIE_TEAM_OBSERVATIONS.md` file.

---

## 💡 Pro Tips

1. **Use `grep` extensively:**
   ```bash
   # Find module definitions
   grep -r "defmodule" lib/ --include="*.ex" | wc -l
   
   # Find all uses of a module
   grep -r "alias Thunderline.Thunderbolt.Cerebros" lib/
   ```

2. **Check git history for context:**
   ```bash
   # See recent changes to a file
   git log --oneline -- lib/thunderline_web/controllers/cerebros_jobs_controller.ex
   ```

3. **Ask questions in your observations file:**
   - "Why does Thunderbolt have two different NAS implementations?"
   - "What's the difference between Thunderflow and Thunderlink?"

4. **Don't fix anything yet** - Just document what you find

---

## 🚀 Getting Started

1. **Create a branch:**
   ```bash
   cd /home/mo/DEV/Thunderline
   git checkout -b docs/rookie-team-audit
   ```

2. **Start with Task 1** (Domain Catalog)

3. **Commit often:**
   ```bash
   git add THUNDERLINE_DOMAIN_CATALOG.md
   git commit -m "docs: update domain catalog with Cerebros extraction notes"
   ```

4. **When done, create all your files and ping us**

---

## ❓ Need Help?

If you get stuck:
- Document what you tried
- Note where you got confused
- Move to next task
- We'll review together

**Remember:** This is reconnaissance. You're gathering intel, not fixing things.

Good luck! 🎉
