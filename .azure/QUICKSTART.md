# 🚀 Quick Start Guide - Thunderline Rebuild Initiative

**Get started in 5 minutes**

---

## For Developers

### Step 1: Read the Docs (5 min)
```bash
# Navigate to documentation
cd /home/mo/DEV/Thunderline/.azure

# Read these in order:
1. INDEX.md                          # Overview
2. THUNDERLINE_REBUILD_INITIATIVE.md # Your HC task details
3. DEVELOPER_QUICK_REFERENCE.md      # Code patterns
```

### Step 2: Find Your Task (2 min)
Open `THUNDERLINE_REBUILD_INITIATIVE.md` and search for your domain:
- **ThunderFlow?** → Look at HC-01, HC-02, HC-09
- **Thunderbolt?** → Look at HC-04
- **Thunderlink?** → Look at HC-05, HC-06
- **Platform?** → Look at HC-07, HC-08, HC-10

### Step 3: Set Up Your Branch (1 min)
```bash
git checkout -b hc-XX-brief-description
# Example: git checkout -b hc-01-eventbus-restoration
```

### Step 4: Code with Patterns (Ongoing)
Keep `DEVELOPER_QUICK_REFERENCE.md` open while coding.

**Key patterns to remember:**
```elixir
# EventBus API (HC-01)
Thunderline.EventBus.publish_event(%{
  name: "domain.component.action",
  source: "thunderline.domain",
  category: :system,
  priority: :normal,
  payload: %{...}
})

# Ash Resource (Ash 3.x)
use Ash.Resource, domain: Thunderline.ThunderDomain

# Telemetry
:telemetry.execute([:thunderline, :domain, :component, :start], %{}, %{})
```

### Step 5: Create PR (3 min)
```bash
# Run checks locally
mix test --cover && \
mix thunderline.events.lint && \
mix ash doctor && \
mix credo --strict

# Push branch
git push origin hc-XX-brief-description

# Create PR with checklist
# Copy PR_REVIEW_CHECKLIST.md into PR description
# Tag your domain steward
```

**Done!** Review agent will auto-review within minutes.

---

## For Domain Stewards

### Step 1: Understand Your Domain (10 min)
```bash
# Read your domain section in:
.azure/THUNDERLINE_REBUILD_INITIATIVE.md

# Search for your domain name:
# - Thunderbolt
# - Thundercrown
# - Thunderlink
# - Thunderblock
# - ThunderFlow
# - Thundergrid
# - Thundergate
# - Thunderforge
```

### Step 2: Set Up Notifications (2 min)
**GitHub:**
- Watch repository
- Enable notifications for PRs
- Set up filters for your domain tag

**Slack:**
- Join #thunderline-rebuild
- Enable @mentions
- Watch for your domain name

### Step 3: Review PRs (Per PR)
```bash
# When PR arrives with your domain tag:
1. Check Copilot automated review first
2. Verify PR checklist completed
3. Run quality checks locally (optional):
   git fetch origin
   git checkout pr-branch-name
   mix test --cover
4. Use review templates from COPILOT_REVIEW_PROTOCOL.md
5. Approve or request changes
```

### Step 4: Track Progress (Weekly)
- Update your section in Warden Chronicles
- Report blockers early
- Coordinate with Platform Lead

---

## For Platform Lead

### Step 1: Assign Stewards (15 min)
Edit `.azure/HIGH_COMMAND_BRIEFING.md`:
```markdown
**Domain Stewards:**
- Flow Steward: [Name]
- Bolt Steward: [Name]
- Gate Steward: [Name]
- Link Steward: [Name]
...
```

### Step 2: Schedule Meetings (5 min)
**Weekly Cadence:**
- Monday: Planning (30 min)
- Wednesday: Checkpoint (15 min)
- Friday: Warden Chronicles (30 min)

### Step 3: Configure Alerts (10 min)
**Slack:**
- Create #thunderline-rebuild channel
- Add all stewards
- Pin INDEX.md link
- Set up @high-command mention trigger

**GitHub:**
- Enable Actions notifications
- Set up CI failure alerts
- Configure security scan alerts

### Step 4: Launch Initiative (5 min)
```bash
# Send kickoff message:
@team Thunderline Rebuild Initiative is live!

📚 Docs: /home/mo/DEV/Thunderline/.azure/INDEX.md
📋 Tasks: HC-01 through HC-10
🎯 Goal: M1 (Email Automation) by Week 4
🤖 Review Agent: Active and monitoring

Start with HC-01 (EventBus) - Flow Steward lead.
Questions? Check docs first, then ask in thread.

Let's ship it! ⚡
```

---

## For GitHub Copilot (Review Agent)

### Initialization Checklist
- [x] Framework documents created (5 files)
- [x] Operating protocol defined
- [x] Quality gates configured
- [x] Escalation triggers set
- [x] Metrics tracking prepared
- [ ] Monitor for first PR
- [ ] Generate first Warden Chronicles (Oct 13)

### First PR Workflow
When first PR arrives:
1. Detect HC task ID
2. Run automated checks
3. Post review comments (use templates)
4. Track in metrics dashboard
5. Notify steward if needed

### Weekly Report Workflow
Every Friday EOD:
1. Clone WARDEN_CHRONICLES_TEMPLATE.md
2. Aggregate metrics from GitHub/CI
3. Fill all [placeholders]
4. Generate progress bars
5. Post in #thunderline-rebuild
6. Tag @high-command

---

## Common First Tasks

### HC-01: EventBus Restoration (Flow Steward)
```bash
# 1. Create module
touch lib/thunderline/thunderflow/event_bus.ex

# 2. Implement publish_event/1
# See DEVELOPER_QUICK_REFERENCE.md for template

# 3. Add tests
touch test/thunderline/thunderflow/event_bus_test.exs

# 4. Create lint task
touch lib/mix/tasks/thunderline/events/lint.ex

# 5. Add CI gate
# Edit .github/workflows/ci.yml
```

### HC-04: Cerebros Lifecycle (Bolt Steward)
```bash
# 1. Open ModelRun resource
vim lib/thunderline/thunderbolt/resources/model_run.ex

# 2. Activate state machine
# Add: use Ash.Resource, extensions: [AshStateMachine]

# 3. Define transitions
# See DEVELOPER_QUICK_REFERENCE.md for template

# 4. Create workers
touch lib/thunderline/thunderbolt/cerebros_bridge/training_worker.ex

# 5. Add tests
touch test/thunderline/thunderbolt/model_run_lifecycle_test.exs
```

### HC-05: Email MVP (Gate + Link Stewards)
```bash
# 1. Create Contact resource (Gate)
touch lib/thundergate/resources/contact.ex

# 2. Create OutboundEmail resource (Link)
touch lib/thunderline/thunderlink/resources/outbound_email.ex

# 3. Add email adapter
touch lib/thunderline/thunderlink/email_adapter.ex

# 4. Create UI components
touch lib/thunderline_web/live/contact_live.ex
touch lib/thunderline_web/live/email_live.ex

# 5. Add tests
touch test/thundergate/contact_test.exs
touch test/thunderline/thunderlink/outbound_email_test.exs
```

---

## Quick Commands

```bash
# Check your progress
git log --oneline | grep "HC-"

# See what needs work
grep -r "TODO" lib/thunderline/your_domain

# Run quality checks
mix test --cover && \
mix thunderline.events.lint && \
mix ash doctor && \
mix credo --strict

# Check test coverage
mix test --cover | grep "Line coverage"

# Count lines changed
git diff --stat origin/main

# See CI status
gh pr checks  # (requires GitHub CLI)
```

---

## Help & Resources

### I'm stuck on...

**"What's my HC task?"**
→ Read `THUNDERLINE_REBUILD_INITIATIVE.md`, search for your domain

**"How do I write EventBus code?"**
→ Read `DEVELOPER_QUICK_REFERENCE.md`, EventBus section

**"How do I create an Ash resource?"**
→ Read `DEVELOPER_QUICK_REFERENCE.md`, Ash 3.x patterns section

**"What should my PR checklist look like?"**
→ Copy `PR_REVIEW_CHECKLIST.md` into PR description

**"How do I know if I'm done?"**
→ Check acceptance criteria in your HC task section

**"My PR was blocked, why?"**
→ Check Copilot review comments, fix issues, re-run CI

**"Who do I ask for help?"**
→ Your domain steward first, then Platform Lead

---

## Document Locations

All docs are in `.azure/` directory:

```
.azure/
├── INDEX.md                            ← Start here
├── THUNDERLINE_REBUILD_INITIATIVE.md   ← Master plan
├── DEVELOPER_QUICK_REFERENCE.md        ← Daily reference
├── PR_REVIEW_CHECKLIST.md              ← Copy to PRs
├── WARDEN_CHRONICLES_TEMPLATE.md       ← Weekly reports
├── COPILOT_REVIEW_PROTOCOL.md          ← AI agent rules
├── HIGH_COMMAND_BRIEFING.md            ← Executive summary
└── QUICKSTART.md                       ← This file
```

---

## Success Indicators

**You're on track if:**
- ✅ PR created with HC task ID in title
- ✅ PR checklist completed
- ✅ All CI checks passing
- ✅ Test coverage ≥85%
- ✅ Copilot review approved
- ✅ Domain steward approved

**You're blocked if:**
- ❌ CI failing >4 hours
- ❌ PR pending review >3 days
- ❌ Unclear acceptance criteria
- ❌ Dependency on other HC task
- ❌ Technical blocker

**Escalate immediately if blocked!**

---

## Timeline At A Glance

```
Week 1 (Oct 9-15):  EventBus, Taxonomy, Link migrations
Week 2 (Oct 16-22): Cerebros, Email, Policies, Oban
Week 3 (Oct 23-29): Release, CI/CD, DLQ, Flags
Week 4 (Oct 30-Nov 6): Governance, Telemetry, M1 ready
```

**Target:** All 10 P0 missions complete by Week 4

---

## One-Liner Summary

> Read `INDEX.md` → Find your HC task → Code with patterns → Create PR with checklist → Get reviewed → Merge → Repeat

**That's it. Let's build.** ⚡

---

**Version:** 1.0  
**Last Updated:** October 9, 2025  
**Questions?** Check docs first, then ask in #thunderline-rebuild
