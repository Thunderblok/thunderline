# Configuration

This guide explains how to configure Thunderline, Flower federation, and supporting services via environment variables and Helm values (Thunderhelm).

Configuration surfaces
- Helm values (recommended on Kubernetes)
- Environment variables (projected via ConfigMap/Secret)
- Kubernetes objects (Ingress, Service, resources, node selectors)

Environment variables (Thunderline)
- DATABASE_URL
  - Example: ecto://postgres:postgres@postgres:5432/thunderline
  - Used by web and worker pods
- MINIO_ENDPOINT
  - Example: http://minio:9000 (S3-compatible endpoint)
- MINIO_ACCESS_KEY / MINIO_SECRET_KEY
- MINIO_BUCKET
  - Default: thunderline-artifacts
- OTEL_EXPORTER_OTLP_ENDPOINT (optional)
  - Example: http://otel-collector:4317
- OTEL_EXPORTER_OTLP_HEADERS (optional)
  - Example: authorization=Bearer <token>
- LOG_LEVEL
  - Default: info (set debug in dev)
- FEATURES (optional)
  - Comma-delimited feature gates (e.g., enable_ndjson,thundervine_lineage)
- ROLE
  - web or worker (set via values.web.env / values.worker.env)
- START_ENDPOINT / START_COMPUTE / START_OBAN
  - Strings “true”/“false” to toggle components per pod profile

Helm values (Thunderhelm)
- image
  - repository, tag, pullPolicy
- env (non-secrets)
  - MINIO_BUCKET, SERVICE_NAME, LOG_LEVEL, FEATURES
- env.secrets
  - DATABASE_URL, MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_HEADERS
- web
  - enabled, replicas
  - env: ROLE=web, START_ENDPOINT=true, START_COMPUTE=false, START_OBAN=true
  - service: enabled, type, port (default 4000)
  - ingress: enabled, className, hosts[], tls[]
- worker
  - enabled, replicas
  - env: ROLE=worker, START_ENDPOINT=false, START_COMPUTE=false, START_OBAN=true
- federation (Flower demo server)
  - enabled, replicas
  - image: repository, tag, pullPolicy (default python:3.11-slim for demo)
  - port (default 8081)
  - command/args (demo installs flwr[simulation] and starts FedAvg server)
  - service: enabled, type
- serviceAccount, rbac, imagePullSecrets
- probes (web/worker)
- Optional subcharts toggles (if you choose to add in future/fork):
  - postgresql.enabled, minio.enabled, opentelemetryCollector.enabled, kubePrometheusStack.enabled

Ingress (web)
- values.web.ingress.enabled=true
- values.web.ingress.className: nginx (for NGINX Ingress)
- values.web.ingress.hosts:
  - host: thunderline.example.com
    paths:
      - path: /
        pathType: Prefix
- values.web.ingress.tls:
  - secretName: thunderline-tls
    hosts:
      - thunderline.example.com

Resource requests/limits and scheduling
- Set per component:
  - values.web.resources
  - values.worker.resources
  - values.federation.resources
- Node selectors, tolerations, affinity:
  - values.web.nodeSelector/tolerations/affinity
  - values.worker.nodeSelector/tolerations/affinity
  - values.federation.nodeSelector/tolerations/affinity
- GPU pools (example):
  - values.federation.nodeSelector:
      accelerator: nvidia
  - values.federation.tolerations:
    - key: nvidia.com/gpu
      effect: NoSchedule
      operator: Exists

Secrets management
- Thunderhelm projects secrets into a Secret named <release>-secrets using values.env.secrets.*
- For production, prefer an external secrets manager (e.g., External Secrets, SealedSecrets, CSI/KMS) and template Secret names into values instead of raw values.

Port mapping
- Web service: values.web.service.port (default 4000)
- Federation (Flower) service: values.federation.port (default 8081)
- When using port-forward (no ingress):
  - kubectl -n thunder port-forward svc/<release>-web 4000:4000
  - kubectl -n thunder port-forward svc/<release>-federation 8081:8081

Profiles
- Web profile
  - ROLE=web; START_ENDPOINT=true; START_OBAN=true; START_COMPUTE=false
  - Exposes HTTP endpoint and runs Oban (configurable)
- Worker profile
  - ROLE=worker; START_ENDPOINT=false; START_OBAN=true
  - Runs event pipelines, telemetry, and background jobs
- Federation (demo)
  - Runs a Python Flower server; for production, replace with a hardened image and set command/args accordingly

Minimal example (values)
image:
  repository: ghcr.io/yourorg/thunderline
  tag: "2.1.0"

env:
  MINIO_BUCKET: "thunderline-artifacts"
  SERVICE_NAME: "thunderline"
  LOG_LEVEL: "info"
  FEATURES: ""

  secrets:
    DATABASE_URL: "ecto://postgres:postgres@postgres:5432/thunderline"
    MINIO_ENDPOINT: "http://minio:9000"
    MINIO_ACCESS_KEY: "minio"
    MINIO_SECRET_KEY: "minio123"
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4317"
  OTEL_EXPORTER_OTLP_HEADERS: ""

web:
  enabled: true
  replicas: 1
  service:
    enabled: true
    type: ClusterIP
    port: 4000
  ingress:
    enabled: false

worker:
  enabled: true
  replicas: 1

federation:
  enabled: false

Verification checklist
- helm template and helm lint pass
- Pods Ready: web, worker (and federation if enabled)
- Web responds on port 4000 (ingress or port-forward)
- DATABASE_URL connectivity OK (no CrashLoopBackOff)
- MinIO/S3 credentials valid; test writing/reading an object
- OTLP endpoint reachable (if configured); traces and metrics visible
