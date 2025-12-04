# 📚 Thunderline Documentation

> **Last Reorganized:** December 4, 2025  
> **Total Documents:** 218 markdown files

This directory contains all Thunderline project documentation, organized by category.

---

## 📁 Directory Structure

```
docs/
├── README.md                    # This index
├── thunderline_handbook.md      # Main operational handbook
├── OKO_HANDBOOK.md              # OKO system handbook
│
├── hc-specs/                    # Active High Command specifications
│   ├── HC_ARCHITECTURE_SYNTHESIS.md     # Architecture synthesis
│   ├── HC_DELTA_14_18_QUAK_CEREBROS_SPEC.md  # QuAK + Cerebros spec
│   ├── HC_DELTA_IMPLEMENTATION_SPEC.md  # Delta implementation
│   ├── HC_TODO_SWEEP.md                 # Active HC todos
│   ├── THUNDERBIT_V1_API_CONTRACT.md    # Thunderbit API v1
│   ├── THUNDERBIT_BEHAVIOR_CONTRACT.md  # Thunderbit behavior
│   ├── UPPER_ONTOLOGY.md                # Ontology definitions
│   └── ...
│
├── architecture/                # System architecture docs
│   ├── THUNDERLINE_DOMAIN_CATALOG.md    # Domain inventory
│   ├── thunderline_domain_resource_guide.md
│   ├── domain_topdown.md                # C4 container view
│   ├── DOMAIN_ARCHITECTURE.md
│   ├── DOMAIN_ARCHITECTURE_REVIEW.md
│   ├── DOMAIN_ACTIVATION_FLOW.md
│   ├── ARCHITECTURE_DOMAIN_BOUNDARIES.md
│   ├── CEREBROS_BRIDGE_BOUNDARY.md
│   ├── PRISM_TOPOLOGY.md
│   ├── HORIZONTAL_RINGS.md
│   └── VERTICAL_EDGES.md
│
├── guides/                      # How-to guides & quickstarts
│   ├── CEREBROS_SETUP.md
│   ├── CEREBROS_MLFLOW_QUICKSTART.md
│   ├── CEREBROS_TESTING.md
│   ├── MAGIKA_QUICK_START.md
│   ├── NLP_QUICK_START.md
│   ├── TAK_PERSISTENCE_QUICKSTART.md
│   ├── DEPLOY_DEMO.md
│   ├── HOW_TO_AUDIT.md
│   ├── THUNDERHELM_SERVICES.md
│   └── ...
│
├── reference/                   # Specifications & standards
│   ├── EVENT_TAXONOMY.md        # Event naming & structure
│   ├── ERROR_CLASSES.md         # Error classification
│   ├── FEATURE_FLAGS.md         # Feature flag reference
│   ├── DEPENDENCY_MAP.md        # Dependency documentation
│   ├── QUICK_REFERENCE.md
│   ├── THUNDERDSL_SPECIFICATION.md
│   └── THUNDERVINE_GRAPHQL_API.md
│
├── ml-ai/                       # ML/AI pipeline documentation
│   ├── AI_ML_INTEGRATION_GUIDE.md
│   ├── ML_PIPELINE_EXECUTION_ROADMAP.md
│   ├── ONNX_INTEGRATION.md
│   ├── ONNX_ASHAI_INTEGRATION.md
│   ├── MAGIKA_SPACY_KERAS_INTEGRATION.md
│   ├── unified_persistent_model.md
│   ├── cerebros_nas_saga.md
│   └── ...
│
├── domain_docs/                 # Per-domain documentation
│   ├── thunderblock/
│   ├── thunderbolt/
│   ├── thundercrown/
│   ├── thunderflow/
│   ├── thundergate/
│   ├── thundergrid/
│   ├── thunderlink/
│   └── ...
│
├── historical/                  # Archived reports & audits
│   ├── hc-reports/              # High Command decision records
│   │   ├── HC-27_28_MIGRATION_PLAN.md
│   │   ├── HC-29_COMPLETION_REPORT.md
│   │   └── HC_EXECUTION_PLAN.md
│   │
│   ├── phase-reports/           # Phase completion reports
│   │   ├── PHASE_1_TICK_SYSTEM_COMPLETE.md
│   │   ├── PHASE_2_DOMAIN_ACTIVATION_COMPLETE.md
│   │   └── ...
│   │
│   └── audits/                  # Codebase audits & reviews
│       ├── CODEBASE_CLEANUP_REPORT.md
│       ├── ARCHITECTURE_REVIEW_SUMMARY.md
│       └── ...
│
└── Doc History/                 # Legacy/archived documentation
    ├── architecture/            # Historical architecture specs
    ├── planning/                # Historical planning docs
    ├── dip/                     # Design Intent Proposals
    └── ...
```

---

## 🎯 Quick Navigation

### Getting Started
- [Thunderline Handbook](thunderline_handbook.md) - Main operational guide
- [Cerebros Setup](guides/CEREBROS_SETUP.md) - ML system setup
- [Deploy Demo](guides/DEPLOY_DEMO.md) - Deployment guide

### High Command Specs (Active)
- [HC Architecture Synthesis](hc-specs/HC_ARCHITECTURE_SYNTHESIS.md) - System synthesis
- [QuAK + Cerebros Spec](hc-specs/HC_DELTA_14_18_QUAK_CEREBROS_SPEC.md) - Automata engine
- [Thunderbit API v1](hc-specs/THUNDERBIT_V1_API_CONTRACT.md) - API contract
- [Upper Ontology](hc-specs/UPPER_ONTOLOGY.md) - Ontology definitions

### Architecture
- [Domain Catalog](architecture/THUNDERLINE_DOMAIN_CATALOG.md) - All domains & resources
- [Domain Resource Guide](architecture/thunderline_domain_resource_guide.md) - Resource details
- [Architecture Review](architecture/DOMAIN_ARCHITECTURE_REVIEW.md) - Latest review
- [Domain Top-Down](architecture/domain_topdown.md) - C4 container view

### Reference
- [Event Taxonomy](reference/EVENT_TAXONOMY.md) - Event naming conventions
- [Error Classes](reference/ERROR_CLASSES.md) - Error handling patterns
- [Feature Flags](reference/FEATURE_FLAGS.md) - Configuration flags

### ML/AI
- [ML Pipeline Roadmap](ml-ai/ML_PIPELINE_EXECUTION_ROADMAP.md) - Implementation plan
- [ONNX Integration](ml-ai/ONNX_INTEGRATION.md) - Model inference
- [Magika Integration](guides/MAGIKA_QUICK_START.md) - File classification

---

## 📋 Root-Level Documents

These essential documents remain in the project root:

| File | Purpose |
|------|---------|
| `README.md` | Project overview & quick start |
| `AGENTS.md` | AI coding assistant instructions |
| `CONTRIBUTING.md` | Contribution guidelines |
| `CHANGELOG.md` | Version history |
| `License.md` | License information |
| `THUNDERLINE_MASTER_PLAYBOOK.md` | Strategic roadmap & HC matrix |
| `usage-rules.md` | Framework usage rules |
| `copilot-instructions.md` | GitHub Copilot config |

---

## 🗂️ Organization Principles

1. **HC specs** (active High Command documents) in `hc-specs/`
2. **Active docs** in topic-specific folders (`architecture/`, `guides/`, `reference/`, `ml-ai/`)
3. **Domain-specific docs** in `domain_docs/<domain>/`
4. **Historical/completed work** in `historical/` with subcategories
5. **Legacy archives** in `Doc History/` (preserved for reference)

---

*Documentation reorganized December 4, 2025*
