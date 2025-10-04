# Deploy (Kubernetes Prod/Stage)

This guide covers deploying Thunderline and the optional Flower federation runtime on a Kubernetes cluster using the Thunderhelm chart with production-minded settings.

Prerequisites
- Kubernetes v1.24+ and Helm v3.10+
- External Postgres and S3/MinIO
- Optional: OTLP collector, Prometheus, Grafana
- Thunderline container image published to your registry (Phoenix release, port 4000)
- A domain/ingress controller if exposing the web endpoint publicly

1) Prepare namespace and access
```bash
kubectl create namespace thunder || true
# Confirm you can create Deployments/Secrets/Ingress in this namespace
```

2) Choose a values baseline
Start from the dev examples and harden as needed:
- Thunderline/thunderhelm/deploy/chart/examples/values-dev.yaml
- Thunderline/thunderhelm/deploy/chart/examples/values-federation-demo.yaml (to enable Flower demo)

Recommended production overrides (create values-prod.yaml):
```yaml
image:
  repository: ghcr.io/YOURORG/thunderline
  tag: "2.1.0"
  pullPolicy: IfNotPresent

env:
  MINIO_BUCKET: "thunderline-artifacts"
  SERVICE_NAME: "thunderline"
  LOG_LEVEL: "info"
  FEATURES: ""  # e.g., "enable_ndjson"

  secrets:
    DATABASE_URL: "ecto://postgres:postgres@postgres:5432/thunderline"
    MINIO_ENDPOINT: "https://s3.YOURCLOUD"
    MINIO_ACCESS_KEY: "<set by Secret manager>"
    MINIO_SECRET_KEY: "<set by Secret manager>"
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector.observability:4317"
  OTEL_EXPORTER_OTLP_HEADERS: ""

web:
  replicas: 2
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: thunderline.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: thunderline-tls
        hosts: ["thunderline.example.com"]

worker:
  replicas: 2

# Federation (Flower) demo disabled by default in prod
federation:
  enabled: false

# Optional scheduling examples
web:
  resources:
    requests: {cpu: "500m", memory: "512Mi"}
    limits:   {cpu: "1",    memory: "1Gi"}

worker:
  resources:
    requests: {cpu: "1",  memory: "1Gi"}
    limits:   {cpu: "2",  memory: "2Gi"}
```

3) Install/upgrade with Helm
```bash
# Initial install
helm install thunderline Thunderline/thunderhelm/deploy/chart \
  -n thunder \
  -f values-prod.yaml

# Subsequent changes
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart \
  -n thunder \
  -f values-prod.yaml
```

4) Secrets management
Do NOT bake secrets into values files in production. Use your organization’s secret manager:
- External Secrets Operator: define ExternalSecret → manages Secret referenced by the chart
- SealedSecrets or CSI/KMS providers
- Reference existing Secret names via templated values (edit chart/values and templates if you prefer binding to existing Secrets instead of chart-managed)

Example ExternalSecret (pseudo):
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: thunderline-env
  namespace: thunder
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: corp-vault
    kind: ClusterSecretStore
  target:
    name: thunderline-secrets
  data:
    - secretKey: DATABASE_URL
      remoteRef: {key: thunderline/prod/DATABASE_URL}
    - secretKey: MINIO_ACCESS_KEY
      remoteRef: {key: thunderline/prod/MINIO_ACCESS_KEY}
    - secretKey: MINIO_SECRET_KEY
      remoteRef: {key: thunderline/prod/MINIO_SECRET_KEY}
```
Then adjust the chart (if desired) to use `thunderline-secrets` instead of chart-generated secrets.

5) Ingress and TLS
- Ensure DNS points to your ingress controller
- Provide a TLS secret (manually or via cert-manager)
- Verify:
```bash
kubectl get ingress -n thunder
curl -I https://thunderline.example.com
```

6) Enabling the federation server (controlled labs or POC)
- Production should use a hardened Flower image (no runtime pip install).
- Example override:
```yaml
federation:
  enabled: true
  image:
    repository: ghcr.io/YOURORG/flower-federation
    tag: "v0.1.0"
  port: 8081
  resources:
    requests: {cpu: "500m", memory: "512Mi"}
    limits:   {cpu: "1",    memory: "1Gi"}
  # Optional GPU pool
  nodeSelector:
    accelerator: nvidia
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Exists"
      effect: "NoSchedule"
```
- Apply:
```bash
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart \
  -n thunder \
  -f values-prod.yaml \
  --set federation.enabled=true
```

7) Scaling and resilience
- Increase web/worker replicas per load
- Add HPAs (HorizontalPodAutoscaler) out of chart or extend chart
- Prefer PDBs (PodDisruptionBudget) to maintain availability during node maintenance
- Set resource requests/limits to ensure fair scheduling

8) Observability
- Configure OTLP endpoint (env.secrets.OTEL_EXPORTER_OTLP_ENDPOINT)
- Confirm traces and metrics flow to your collector
- Import Grafana dashboards once provided (see observability.md)

9) Smoke tests
```bash
# general kube sanity
kubectl get deploy,po,svc,ing -n thunder

# web readiness
kubectl -n thunder rollout status deploy/thunderline-thunderhelm-web
curl -I https://thunderline.example.com

# worker running (Oban pipelines)
kubectl -n thunder logs deploy/thunderline-thunderhelm-worker | tail -n 200

# if federation enabled
kubectl -n thunder get svc | grep federation
kubectl -n thunder logs deploy/thunderline-thunderhelm-federation | tail -n 200
```

10) Rollbacks and upgrades
- Use Helm revision history:
```bash
helm history thunderline -n thunder
helm rollback thunderline <REVISION> -n thunder
```
- Prefer canary upgrades for the web component; worker upgrades should drain gracefully if you implement job draining semantics.

Checklist before go-live
- [ ] DATABASE_URL connectivity stable; migrations applied (no CrashLoopBackOff)
- [ ] MinIO/S3 credentials verified; artifact writes succeed
- [ ] Ingress + TLS valid; 200 OK on landing/health
- [ ] OTLP traces/metrics visible
- [ ] RBAC and ServiceAccounts comply with org policy
- [ ] Resource requests/limits tuned; nodes sized correctly
- [ ] (If federation) Hardened Flower image, pinned deps; network policy scoped; node selectors/tolerations correct

Next
- See runbooks/ for starting federations, enrolling clients, managing artifacts, and incident response.
