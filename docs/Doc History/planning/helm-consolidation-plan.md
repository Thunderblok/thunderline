# Helm Consolidation Plan - Single Namespace Strategy

## Current State
```
thunderline (thunder namespace) - Revision 8, deployed Oct 1, 2025
  └── mlflow pod (Running)

thunderline (thunderline namespace) - Revision 2, deployed Oct 4, 2025
  ├── mlflow pod (Running) - DUPLICATE
  └── otelcol pod (Running)
```

## Target State
```
thunderline (thunderline namespace) - Single unified deployment
  ├── web (Phoenix LiveView)
  ├── worker (Oban)
  ├── mlflow (ML tracking)
  ├── otelcol (observability)
  ├── cerebros-runner (optional)
  ├── livebook (optional)
  ├── postgres (subchart)
  └── minio (subchart)
```

## Migration Steps

### Phase 1: Backup Current State
1. Export current values from both deployments
2. Document running pods and their configurations
3. Backup any persistent data (if applicable)

### Phase 2: Uninstall Duplicate Deployment
1. Remove `thunderline` from `thunder` namespace
2. Verify pods are terminating cleanly
3. Clean up any leftover PVCs

### Phase 3: Consolidate Configuration
1. Merge values from both deployments
2. Ensure no conflicts in resource names
3. Update image tags to latest working versions

### Phase 4: Deploy Unified Stack
1. Deploy to `thunderline` namespace with consolidated values
2. Verify all pods start successfully
3. Test connectivity between services

### Phase 5: Validation
1. Verify web endpoint is accessible
2. Test MLflow tracking
3. Confirm Oban workers processing jobs
4. Check telemetry flow to otelcol

## Execution Commands

### Backup Phase
```bash
# Already done above
helm get values thunderline -n thunderline > thunderline-namespace-values.yaml
helm get values thunderline -n thunder > thunder-namespace-values.yaml
```

### Uninstall Duplicate
```bash
# Remove from thunder namespace
helm uninstall thunderline -n thunder

# Verify removal
kubectl get pods -n thunder
```

### Deploy Consolidated
```bash
# Use the existing thunderline namespace deployment as base
# It already has more complete configuration (cerebros, livebook, etc.)
helm upgrade --install thunderline ./thunderhelm/deploy/chart \
  -n thunderline \
  -f /tmp/thunderline-current-values.yaml \
  --set web.enabled=true \
  --set web.replicas=1 \
  --set worker.enabled=true \
  --set worker.replicas=1
```

## Key Configuration

### Enabled Services
- ✅ PostgreSQL (subchart)
- ✅ MinIO (subchart)
- ✅ MLflow Tracking
- ✅ OpenTelemetry Collector
- ✅ Cerebros Runner
- ✅ Livebook
- ⚠️ Web (needs to be enabled)
- ⚠️ Worker (needs to be enabled)

### Resource Limits (to prevent runaway processes)
```yaml
cerebrosRunner:
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

web:
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

worker:
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
```

## Risks & Mitigation

### Risk: Data Loss
- **Mitigation**: Postgres and MinIO use PVCs, data persists across deployments

### Risk: Downtime
- **Mitigation**: This is a dev environment, acceptable downtime

### Risk: Configuration Conflicts
- **Mitigation**: Review merged values carefully before deployment

### Risk: Image Pull Failures
- **Mitigation**: Verify image tags exist or build locally

## Rollback Plan

If consolidation fails:
```bash
# Restore thunder namespace deployment
helm install thunderline ./thunderhelm/deploy/chart \
  -n thunder \
  -f thunder-namespace-values.yaml

# Or restore thunderline namespace
helm rollback thunderline -n thunderline
```

## Post-Migration Checklist

- [ ] All pods in Running state
- [ ] Web endpoint accessible at http://localhost:4000
- [ ] MLflow UI accessible
- [ ] Livebook accessible
- [ ] Dashboard buttons functional
- [ ] No memory leaks or runaway processes
- [ ] Telemetry flowing correctly
- [ ] Database migrations applied
