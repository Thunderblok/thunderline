# 📁 Proposed Documentation Structure and Consolidation Plan (2025-10-27)

## 🎯 Objective
Simplify the Thunderline documentation space by merging redundant audits, archiving outdated strategy docs, and clarifying canonical sources for future maintainers.

---

## 🧩 Consolidation Summary

| Type | Old Files | Action | Target |
|------|------------|--------|---------|
| **Audit & Status** | `CODEBASE_AUDIT_2025.md`, `CODEBASE_STATUS.md`, `CODEBASE_REVIEW_CHECKLIST.md` | 🔁 Merge into unified authoritative file | `CODEBASE_AUDIT_AND_STATUS.md` |
| **Methodologies** | `AUDIT_METHODOLOGY_COMPLETE.md`, `AUDIT_QUICK_REFERENCE.md` | ✅ Keep (active, referenced in HOW_TO_AUDIT.md) | ✔︎ |
| **Planning – Historical** | All under `/planning/[HISTORICAL]_CODEBASE_*` | 🗄️ Move to `/documentation/archive/` | Archive |
| **Phase Deliverables** | `phase2_event_schemas_complete.md`, `phase3_cerebros_bridge_complete.md`, `phase5_mlflow_foundation_complete.md` | 📦 Group into `/documentation/milestones/` | Consolidate |
| **Architecture Docs** | `/architecture/*`, `system_overview.mmd`, `unified_persistent_model.md`, `spectral_norm_*` | ✅ Retain under `/architecture/` | Core technical |
| **Feature/Policy Docs** | `FEATURE_FLAGS.md`, `DOMAIN_SECURITY_PATTERNS.md`, `ERROR_CLASSES.md`, `EVENT_TAXONOMY.md` | ✅ Keep — enforce CI linking | |
| **Subprojects** | `/docs/flower-power`, `/ash elixir`, `/dip` | 🚩 Move into `/integrations/` with index | Consolidate |
| **Outdated** | `GOOGLE_ERP_ROADMAP.md`, `OKO_HANDBOOK.md`, `TEAM_RENEGADE_REBUTTAL.md` | ❌ Mark deprecated, archive | |

---

## 📂 New Folder Hierarchy

```
documentation/
├── CORE_REFERENCE/
│   ├── CODEBASE_AUDIT_AND_STATUS.md
│   ├── HOW_TO_AUDIT.md
│   ├── AUDIT_QUICK_REFERENCE.md
│   ├── THUNDERLINE_DOMAIN_CATALOG.md
│   ├── DOMAIN_SECURITY_PATTERNS.md
│   ├── FEATURE_FLAGS.md
│   ├── EVENT_TAXONOMY.md
│   ├── ERROR_CLASSES.md
│
├── ARCHITECTURE/
│   ├── system_overview.mmd
│   ├── spectral_norm_architecture.md
│   ├── unified_persistent_model.md
│   ├── tpe_optimizer.md
│   └── honey_badger_consolidation_plan.md
│
├── MILESTONES/
│   ├── phase2_event_schemas_complete.md
│   ├── phase3_cerebros_bridge_complete.md
│   ├── phase5_mlflow_foundation_complete.md
│
├── INTEGRATIONS/
│   ├── dip/
│   ├── docs/flower-power/
│   ├── ash_elixir/
│
├── PLANNING/
│   ├── HC_EXECUTION_PLAN.md
│   ├── HIGH_COMMAND_BRIEFING.md
│   ├── THUNDERLINE_REBUILD_INITIATIVE.md
│   └── IMMEDIATE_ACTION_PLAN.md
│
├── ARCHIVE/
│   ├── [HISTORICAL]_CODEBASE_AUDIT_2025-10-08.md
│   ├── [HISTORICAL]_CODEBASE_REVIEW_OCT_12_2025.md
│   ├── README_NUMERICS.md
│   ├── GOOGLE_ERP_ROADMAP.md
│   ├── TEAM_RENEGADE_REBUTTAL.md
│
└── INDEX.md
```

---

## 🔧 Operations to Execute

1. **Merge Audit Suite:**
   - Combine `CODEBASE_AUDIT_2025.md`, `CODEBASE_STATUS.md`, and `CODEBASE_REVIEW_CHECKLIST.md` → new `CODEBASE_AUDIT_AND_STATUS.md`
   - Preserve executive summaries & checklists
   - Archive originals post-merge in `/archive/`

2. **Move Deprecated Docs:**
   - Relocate legacy handbooks and redundant planning notes to `/archive/`

3. **Rationalize TOC Index:**
   - Update `INDEX.md` to reflect only top-level and active references
   - Strip out duplicated content from `planning/*` folder

4. **Integrations Alignment:**
   - Reclassify subfolders (`dip/`, `ash elixir/`, `docs/flower-power/`) into `/INTEGRATIONS/`
   - Add cross-links for clarity in `INDEX.md`

5. **Add README to each top-level folder:**
   - One-paragraph scope note per directory describing what belongs there and edit guidelines

---

## ✅ Implementation Guidance

- **Timeline:** 2 commits max — first move, then merge into unified markdown  
- **Version Control:** Tag before restructure `v2025.10_doc_cleanup`
- **CI Enforcement:** Add doc-lint task verifying presence of canonical files only

---

## ⚡ Expected Result

- ~60% reduction in duplicated documentation  
- Clear separation between **active**, **historical**, and **reference** documents  
- Single authoritative audit + status overview for maintainability  
