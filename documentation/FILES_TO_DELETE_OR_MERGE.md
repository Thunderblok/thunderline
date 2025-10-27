# 🗑️ Proposed Deletions / Merges / Moves — Documentation Cleanup List (2025-10-27)

This file enumerates every document to be moved, merged, or removed per the consolidation plan.

---

## 🔁 **Merge Targets**

| Merge Into | Files to Merge | Reason |
|-------------|----------------|--------|
| `CODEBASE_AUDIT_AND_STATUS.md` | `CODEBASE_AUDIT_2025.md`, `CODEBASE_STATUS.md`, `CODEBASE_REVIEW_CHECKLIST.md` | Redundant coverage of audits, status summaries, and pre-release validation |
| `DOCUMENTATION_INDEX.md` | `INDEX.md`, `README_NUMERICS.md` | Streamline landing page; `README_NUMERICS.md` outdated |
| `HOW_TO_AUDIT.md` | `AUDIT_METHODOLOGY_COMPLETE.md`, `AUDIT_QUICK_REFERENCE.md` | Methodology and reference belong together for linear guidance |

---

## 📦 **Move to `/archive/`**

| File | Reason |
|------|---------|
| `planning/[HISTORICAL]_CODEBASE_AUDIT_2025-10-08.md` | Obsolete audit version |
| `planning/[HISTORICAL]_CODEBASE_REVIEW_OCT_12_2025.md` | Superseded by 2025 audit |
| `GOOGLE_ERP_ROADMAP.md` | Dead project route to third-party system |
| `TEAM_RENEGADE_REBUTTAL.md` | Non-technical internal memo |
| `OKO_HANDBOOK.md` | Replaced by EVENT_TAXONOMY + ERROR_CLASSES |
| `README_NUMERICS.md` | Legacy numeric types documentation |
| `LIVE_CHAT_CORRECTED_GAP_ANALYSIS.md` | Superseded by new dashboards |
| `phase2_event_schemas_complete.md`, `phase3_cerebros_bridge_complete.md`, `phase5_mlflow_foundation_complete.md` | Historical milestone records (moved under `/MILESTONES/`) |

---

## 📂 **Reorganize**

| New Path | Existing Source | Notes |
|-----------|-----------------|-------|
| `documentation/CORE_REFERENCE/` | `FEATURE_FLAGS.md`, `DOMAIN_SECURITY_PATTERNS.md`, `ERROR_CLASSES.md`, `EVENT_TAXONOMY.md` | Mark canonical references |
| `documentation/ARCHITECTURE/` | `spectral_norm_*`, `unified_persistent_model.md`, `tpe_optimizer.md` | Normalize engineering docs |
| `documentation/INTEGRATIONS/` | `ash elixir/`, `docs/flower-power/`, `dip/` | Prevent clutter |
| `documentation/ARCHIVE/` | All files marked deprecated | Auto-pruned from index |

---

## ⚠️ **Temporary Files to Monitor**

| File | Action | When |
|------|---------|------|
| `CODEBASE_AUDIT_AND_STATUS.md` | Final merge output validation | After next audit cycle |
| `PROPOSED_STRUCTURE_AND_CONSOLIDATION_PLAN.md` | Keep for governance reference | Until implementation complete |
| `FILES_TO_DELETE_OR_MERGE.md` | Delete after cleanup completes | After PR merged to main |

---

## 🧹 **Cleanup Verification Checklist**

- [ ] Archive folder structure created  
- [ ] Cross-links in `INDEX.md` updated  
- [ ] Historical files relocated correctly  
- [ ] Consolidation markdowns merged and deduplicated  
- [ ] Unreferenced files removed  
- [ ] Audit summary updated in `CODEBASE_AUDIT_AND_STATUS.md`  

---

Once completed, Thunderline documentation will contain **only authoritative, current, and indexed materials** — enabling maintainers to onboard rapidly without encountering outdated roadmaps or overlapping audits.