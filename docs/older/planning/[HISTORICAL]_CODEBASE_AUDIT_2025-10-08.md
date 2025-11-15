# Thunderline Codebase Audit - October 8, 2025

## Executive Summary

**Critical Findings:**
1. **Multiple Helm Deployments Running**: 3 separate Helm releases across 3 namespaces (cerebros, thunder, thunderline)
2. **Deprecated Services Still Active**: `thunder-stack` (automat0) deployment from September is still running
3. **Resource Duplication**: MLflow and Cerebros runners deployed multiple times across namespaces
4. **Dashboard Button Issue**: LiveView/JavaScript connection problems preventing user interaction

---

## Current Kubernetes State

### Helm Releases
```
NAME            NAMESPACE       STATUS      CHART                   INSTALLED
thunder         cerebros        deployed    thunder-stack-0.1.0     Sep 16, 2025
thunderline     thunderline     deployed    thunderhelm-0.2.0       Oct 4, 2025
thunderline     thunder         deployed    thunderhelm-0.2.0       Oct 1, 2025
traefik         kube-system     deployed    traefik-34.2.1          Sep 14, 2025
```

### Active Pods by Namespace

#### `cerebros` namespace:
- `mlflow-tracking-7b6b9ff9f7-qkczx` - MLflow server (Running)
- `thunder-automat0-757787d7bc-7rcm8` - Automat service (Running) **← SHOULD BE REMOVED**

#### `thunder` namespace:
- `thunderline-thunderhelm-mlflow-bd84cddbf-tvc2w` - MLflow (duplicate)
- `thunderline-thunderhelm-cerebros-*` - Cerebros (scaled to 0)
- `thunderline-thunderhelm-web-*` - Web pods (CrashLoopBackOff/ImagePullBackOff)
- `thunderline-thunderhelm-worker-*` - Worker pods (CrashLoopBackOff/ImagePullBackOff)

#### `thunderline` namespace:
- `thunderline-thunderhelm-cerebros-*` - Cerebros (scaled to 0)
- `thunderline-thunderhelm-mlflow-55fc8f8777-gpdhk` - MLflow (duplicate)
- `thunderline-thunderhelm-otelcol-*` - OpenTelemetry Collector
- `thunderline-thunderhelm-livebook-*` - Livebook (CrashLoopBackOff)
- `thunderline-thunderhelm-web-*` - Web (ImagePullBackOff)
- `thunderline-thunderhelm-worker-*` - Worker (ImagePullBackOff)

---

## Architecture Analysis

### What Should Be Running

**Primary Thunderline Services (Single Instance):**
1. **Web** (Phoenix LiveView) - Port 4000
   - Location: `lib/thunderline_web/`
   - Purpose: User-facing dashboard, API endpoints
   
2. **Worker** (Oban background jobs)
   - Location: `lib/thunderline/`
   - Purpose: Async processing, ML pipeline orchestration

3. **MLflow Tracking Server** (Single instance)
   - Purpose: ML experiment tracking and model registry
   - Current State: **3 instances running** (cerebros, thunder, thunderline namespaces)

4. **OpenTelemetry Collector** (Optional)
   - Purpose: Observability/telemetry aggregation
   - Current State: Running in thunderline namespace

### What Should NOT Be Running

**Deprecated Services:**
1. **thunder-automat0** (in cerebros namespace)
   - **Why It Exists**: Old proof-of-concept from September 2025
   - **Why It Should Go**: Functionality integrated into main Thunderline app
   - **Action Required**: Uninstall `thunder` Helm release from `cerebros` namespace

2. **cerebros-runner pods** (multiple deployments)
   - **Current State**: Scaled to 0 but still configured
   - **Issue**: Causing runaway processes consuming 700% CPU
   - **Action Required**: Remove or properly configure with resource limits

---

## Helm Chart Analysis

### Current Charts

1. **`thunder-stack-0.1.0`** (cerebros namespace)
   - **Status**: DEPRECATED - Remove immediately
   - **Contains**: automat0, cerebros-nlp-poc, mlflow-tracking
   - **Created**: September 16, 2025
   - **Command to Remove**: `helm uninstall thunder -n cerebros`

2. **`thunderhelm-0.2.0`** (thunder namespace)
   - **Status**: Partially working, has CrashLoopBackOff pods
   - **Created**: October 1, 2025
   - **Issues**: Web/Worker pods failing with ImagePullBackOff

3. **`thunderhelm-0.2.0`** (thunderline namespace)
   - **Status**: Partially working, has CrashLoopBackOff pods
   - **Created**: October 4, 2025
   - **Issues**: Web/Worker/Livebook pods failing

### Recommended Helm Structure

**Single Deployment Strategy:**
```
Namespace: thunderline (primary)
├── thunderline-web (1-2 replicas)
├── thunderline-worker (1-2 replicas)
├── mlflow-tracking (1 replica)
├── otelcol (1 replica, optional)
└── postgres (or external)
```

---

## Service Integration Analysis

### Cerebros Integration Status

**Current State:**
- Cerebros runner deployed as separate pods
- Bridge code exists in: `lib/thunderline/thunderbolt/runners/cerebros_bridge.ex`
- Configuration: `config/*.exs` has CEREBROS_* env vars

**Integration Path:**
```elixir
# Already implemented in Thunderline:
Thunderline.Thunderbolt.Runners.CerebrosBridge
  ├── propose/2 - Trial proposal
  ├── train/2 - Training execution
  └── HTTP client using Req library
```

**Recommendation**: 
- Keep cerebros as optional sidecar OR
- Run cerebros_runner as Job-based execution (not always-on Deployment)

### Automat0 Integration Status

**Current State:**
- Running as separate service (`thunder-automat0`)
- No references found in main Thunderline codebase
- Appears to be standalone Python service

**Integration Path:**
- **Option 1**: Remove entirely if functionality not needed
- **Option 2**: Document what automat0 does and why it's needed
- **Option 3**: Integrate as Thunderline module if still required

---

## Dashboard Issues

### Button Clickability Problem

**Symptoms:**
- Create Room button not clickable
- All system control buttons unresponsive
- CSS/z-index appear correct

**Potential Root Causes:**
1. **LiveView Not Connecting**
   - Check WebSocket connection in browser console
   - Verify Phoenix PubSub is running

2. **JavaScript Hooks Not Loading**
   - Asset compilation may have failed
   - Check `assets/js/app.js` and hooks

3. **Browser State Issues**
   - Hard refresh needed (Ctrl+Shift+R)
   - Try incognito mode

**Code Locations:**
- Template: `lib/thunderline_web/live/dashboard_live.html.heex:549-556`
- Handler: `lib/thunderline_web/live/dashboard_live.ex:817-828`
- CSS: `assets/css/app.css:155-182`

---

## Dependency Tree

### Core Dependencies (from mix.exs)
```
Phoenix Framework
├── phoenix (~> 1.7.18)
├── phoenix_live_view (~> 1.0.5)
├── phoenix_html (~> 4.1)
└── phoenix_live_dashboard (~> 0.8)

Ash Framework
├── ash (~> 3.4)
├── ash_postgres (~> 2.4)
├── ash_authentication (~> 4.3)
├── ash_json_api (~> 1.4)
└── ash_graphql (~> 1.4)

ML/AI Stack
├── bumblebee (~> 0.6.0)
├── exla (~> 0.9.2)
├── axon (~> 0.7.0)
└── nx (~> 0.9.2)

Background Jobs
├── oban (~> 2.20)
└── ash_oban (~> 0.2)

Infrastructure
├── req (~> 0.5) - HTTP client
├── jason (~> 1.4) - JSON
└── telemetry (~> 1.2)
```

### Python Dependencies (Cerebros)
```python
# From cerebros_runner_poc.py
- tensorflow
- optuna
- mlflow
- numpy
- fastapi
- uvicorn
```

---

## Recommendations

### Immediate Actions (Priority 1)

1. **Clean Up Deprecated Services**
   ```bash
   # Remove old thunder-stack deployment
   helm uninstall thunder -n cerebros
   
   # Verify removal
   kubectl get pods -n cerebros
   ```

2. **Consolidate to Single Namespace**
   ```bash
   # Keep only thunderline namespace
   helm uninstall thunderline -n thunder
   
   # Fix image issues in thunderline namespace
   # Update values.yaml with correct image refs
   ```

3. **Fix Resource Limits**
   ```yaml
   # Add to values.yaml
   cerebrosRunner:
     enabled: true
     resources:
       requests:
         cpu: "1000m"
         memory: "2Gi"
       limits:
         cpu: "2000m"
         memory: "4Gi"
   ```

### Short-term Actions (Priority 2)

4. **Document Service Purpose**
   - Create `SERVICES.md` explaining each service
   - Document integration points
   - Add architecture diagram

5. **Fix Dashboard Buttons**
   - Test LiveView connection
   - Verify asset compilation
   - Check browser console for errors

6. **Optimize Memory Usage**
   - Disable CA streaming (already done)
   - Reduce telemetry intervals (already done)
   - Add proper resource requests/limits

### Long-term Actions (Priority 3)

7. **Service Consolidation Strategy**
   - Decide: Cerebros as sidecar vs Job-based execution
   - Document: When to use external Cerebros runner
   - Implement: Resource quotas and limits

8. **CI/CD Pipeline**
   - Automated Helm chart testing
   - Image versioning strategy
   - Rollback procedures

9. **Monitoring & Alerts**
   - Resource usage alerts
   - Pod restart alerts
   - Dashboard health checks

---

## File Structure Analysis

### Key Configuration Files

```
/home/mo/DEV/Thunderline/
├── config/
│   ├── config.exs         - Main config
│   ├── runtime.exs        - Runtime env vars
│   ├── dev.exs            - Dev overrides
│   └── prod.exs           - Prod overrides
│
├── thunderhelm/
│   └── deploy/chart/
│       ├── values.yaml                    - Default Helm values
│       ├── examples/
│       │   ├── values-dev.yaml           - Dev config
│       │   ├── values-hpo-demo.yaml      - ML demo
│       │   └── values-federation-demo.yaml - Flower demo
│       └── templates/                     - K8s manifests
│
├── lib/thunderline_web/
│   ├── live/
│   │   └── dashboard_live.ex              - Main dashboard
│   └── components/
│       └── layouts.ex                     - App layouts
│
└── lib/thunderline/
    ├── thunderbolt/                       - ML/Training
    ├── thunderblock/                      - Persistence
    ├── thunderflow/                       - Events
    ├── thundergate/                       - Auth
    └── thundergrid/                       - Distributed compute
```

### Missing/Needed Documentation

1. **ARCHITECTURE.md** - High-level system design
2. **SERVICES.md** - What each service does
3. **DEPLOYMENT.md** - How to deploy properly
4. **TROUBLESHOOTING.md** - Common issues and fixes

---

## Action Plan

### Phase 1: Immediate Cleanup (Today)
- [ ] Uninstall `thunder` from `cerebros` namespace
- [ ] Scale down duplicate MLflow instances
- [ ] Document why automat0 existed
- [ ] Fix kubectl permissions for VSCode

### Phase 2: Consolidation (This Week)
- [ ] Choose single namespace (`thunderline`)
- [ ] Fix image pull issues
- [ ] Configure proper resource limits
- [ ] Test dashboard functionality

### Phase 3: Documentation (This Week)
- [ ] Create ARCHITECTURE.md
- [ ] Create SERVICES.md
- [ ] Update README with current state
- [ ] Document deployment process

### Phase 4: Optimization (Next Week)
- [ ] Implement resource quotas
- [ ] Set up monitoring/alerts
- [ ] Create CI/CD pipeline
- [ ] Load testing

---

## Questions to Answer

1. **Why was automat0 created?** 
   - What functionality does it provide?
   - Can it be removed or must it be integrated?

2. **Why 3 namespaces?**
   - What's the intended separation of concerns?
   - Should we consolidate to one?

3. **Image Pull Issues**
   - Are images built and pushed to registry?
   - What's the correct image tag/repository?

4. **Cerebros Runner Strategy**
   - Always-on deployment vs Job-based execution?
   - Resource limits to prevent runaway processes?

5. **Dashboard Button Issue**
   - Is this a LiveView connection problem?
   - JavaScript hook issue?
   - CSS/z-index problem?

---

## Next Steps

**Immediate** (Next 30 minutes):
1. Uninstall deprecated thunder-stack deployment
2. Check what automat0 actually does
3. Fix dashboard button issue

**Today:**
1. Consolidate to single namespace
2. Fix image pull problems
3. Document current architecture

**This Week:**
1. Implement resource limits
2. Create missing documentation
3. Test end-to-end functionality
