# Cerebros Web Layer Inventory

## Controllers

### ThunderlineWeb.CerebrosMetricsController
- **Location:** `lib/thunderline_web/controllers/cerebros_metrics_controller.ex`
- **Status:** ⚠️ DEPRECATED
- **Issues:**
  - References `Thunderline.Thunderbolt.Cerebros.*` and `CerebrosBridge.Client`
  - Relies on old Thunderbolt Cerebros integration modules
- **Fix Needed:** Replace with `Cerebros.Resources.TrainingMetrics` and update bridge to `Cerebros.Bridge.Client`

### ThunderlineWeb.CerebrosJobsController
- **Location:** `lib/thunderline_web/controllers/cerebros_jobs_controller.ex`
- **Status:** ❌ BROKEN
- **Issues:**
  - Aliases `Thunderline.Cerebros.Training.{Job, Dataset}` which are outdated
- **Fix Needed:** Update to `Cerebros.Resources.{TrainingJob, TrainingDataset}`

### ThunderlineWeb.CerebrosJobsJSON
- **Location:** `lib/thunderline_web/controllers/cerebros_jobs_json.ex`
- **Status:** ✅ Fine
- **Notes:** Only renders JSON, no internal logic referencing old modules

### ThunderlineWeb.MLEventsController
- **Location:** `lib/thunderline_web/controllers/ml_events_controller.ex`
- **Status:** ⚠️ DEPRECATED
- **Issues:** Mentions Cerebros pipelines in comments and docstrings
- **Fix Needed:** Verify if replaced by unified training event bus; update module references

### ThunderlineWeb.ServiceRegistryController
- **Location:** `lib/thunderline_web/controllers/service_registry_controller.ex`
- **Status:** ✅ Fine
- **Notes:** Contains static references to “Cerebros Service #1” label; not functional linkage


## LiveViews

### ThunderlineWeb.CerebrosLive
- **Location:** `lib/thunderline_web/live/cerebros_live.ex`
- **Status:** ⚠️ DEPRECATED
- **Issues:**
  - Uses `Thunderline.Thunderbolt.CerebrosBridge` and validates via `CerebrosBridge.enabled?/0`
  - Multiple UI messages tied to disabled Cerebros integration
- **Fix Needed:** Migrate to `Cerebros.Web.CerebrosLive` or integrate new MLFlow dashboards

### ThunderlineWeb.ThunderlineDashboardLive
- **Location:** `lib/thunderline_web/live/thunderline_dashboard_live.ex`
- **Status:** ⚠️ DEPRECATED
- **Issues:**
  - Contains `Thunderline.Thunderbolt.Cerebros.*` and `CerebrosBridge` aliases
  - Dependent on feature flag `ml_nas`
- **Fix Needed:** Replace aliases with `Cerebros.Diagnostics` and updated analytical bridge modules


## Templates / Components

- **No direct `.heex` files found** referencing Cerebros explicitly beyond inclusions in LiveViews.
- Components like `layouts` or shared dashboards load data through LiveView assigns.


## Routes

### Extracted from `lib/thunderline_web/router.ex`

#### Cerebros Routes
```elixir
# Cerebros & Raincatcher (drift lab) interface
live "/cerebros", CerebrosLive, :index
get "/cerebros/metrics", CerebrosMetricsController, :show
# Cerebros Job Coordination API
get "/jobs/poll", CerebrosJobsController, :poll
patch "/jobs/:id/status", CerebrosJobsController, :update_status
patch "/jobs/:id/metrics", CerebrosJobsController, :update_metrics
post "/jobs/:id/checkpoints", CerebrosJobsController, :add_checkpoint
get "/datasets/:id/corpus", CerebrosJobsController, :get_corpus
```
- **Status:** ⚠️ DEPRECATED
- **Issues:** Routes point to deprecated/broken controllers
- **Fix Needed:** Redirect to `/training/jobs`, `/training/metrics`, or renamed endpoints within new Cerebros service layer.


## Summary

| Category       | Total | Active | Deprecated | Broken |
|----------------|--------|---------|-------------|---------|
| Controllers    | 5      | 2       | 2           | 1       |
| LiveViews      | 2      | 0       | 2           | 0       |
| Templates      | 1      | 1       | 0           | 0       |
| Routes         | 1      | 0       | 1           | 0       |
| **TOTAL**      | **9**  | **3**   | **5**       | **1**   |


### Legacy Path Analysis

All `Thunderline.Thunderbolt.Cerebros.*` paths are deprecated.
Primary replacements include:
- `Cerebros.Resources.TrainingJob`
- `Cerebros.Resources.TrainingDataset`
- `Cerebros.Bridge.Client`
- `Cerebros.Diagnostics.Metrics`


### Outstanding Items
- Validate whether any Phoenix contexts or Oban workers still depend on legacy Cerebros bridge.
- Synchronize web and backend module replacements in next cerebros_bridge rollout.
