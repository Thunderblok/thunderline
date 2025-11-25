# Thunderhelm — Helm chart for Thunderline + ML/NAS demo stack

This chart deploys Thunderline’s control plane (web) and workers, and now ships optional building blocks for the Cerebros HPO/NAS demo loop: an MLflow tracking server, a lightweight Cerebros runner API, a Livebook workspace, and the prior Flower federation runtime.

Contents
- Deployments: web (Phoenix endpoint), worker (pipelines/Oban)
- Optional Deployments/Services: Flower federation server, Cerebros runner, MLflow tracker, Livebook workspace, OpenTelemetry collector
- Services: web ClusterIP plus optional services for each component
- Optional Ingress for web and Livebook
- ConfigMaps/Secrets for shared environment and secrets (global + component-specific)
- Optional PersistentVolumeClaims for MLflow and Livebook state
- ServiceAccount (optional)

Prerequisites
- Kubernetes v1.24+
- Helm v3.10+
- A Thunderline container image (set via values.image.repository/tag)
- External services (or equivalents):
  - Postgres (DATABASE_URL)
  - MinIO/S3-compatible object store (MINIO_* env)
  - Optional: OTLP collector (OTEL_EXPORTER_OTLP_ENDPOINT), Prometheus/Grafana

Quickstart
# Install into namespace "thunder"
helm install thunderline Thunderline/thunderhelm/deploy/chart -n thunder --create-namespace

# Set required secrets (example DEV values)
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  --set env.secrets.DATABASE_URL="ecto://postgres:postgres@postgres:5432/thunderline" \
  --set env.secrets.MINIO_ENDPOINT="http://minio:9000" \
  --set env.secrets.MINIO_ACCESS_KEY="minio" \
  --set env.secrets.MINIO_SECRET_KEY="minio123"

# Launch the full ML/NAS demo stack (Postgres/MinIO subcharts + Cerebros runner, MLflow, Livebook, OpenTelemetry collector)
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  -f Thunderline/thunderhelm/deploy/chart/examples/values-hpo-demo.yaml

# Enable optional Flower federation demo server
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  --set federation.enabled=true \
  --set federation.service.enabled=true

# Enable web ingress (edit hosts/TLS in values.yaml)
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  --set web.ingress.enabled=true

# Expose Livebook via ingress (password required when ingress is enabled)
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  --set livebook.enabled=true \
  --set livebook.secrets.password="<choose-a-strong-password>" \
  --set livebook.ingress.enabled=true \
  --set livebook.ingress.hosts[0].host=livebook.example.com \
  --set livebook.ingress.hosts[0].paths[0].path="/" \
  --set livebook.ingress.hosts[0].paths[0].pathType=Prefix

# Add cert-manager TLS for Livebook ingress
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  -f Thunderline/thunderhelm/deploy/chart/examples/values-livebook-tls.yaml

Structure
- Chart.yaml
- values.yaml
- templates/
  - _helpers.tpl: naming/labels helpers
  - configmap.yaml: non-secret env
  - secret.yaml: secret env (stringData)
  - serviceaccount.yaml
  - web-deployment.yaml, web-service.yaml, web-ingress.yaml
  - worker-deployment.yaml
  - cerebros-runner-{configmap,deployment,service}.yaml
  - mlflow-{deployment,service,pvc}.yaml
  - livebook-{secret,deployment,service,ingress,pvc}.yaml
  - federation-deployment.yaml, federation-service.yaml
   - opentelemetry-collector-{configmap,deployment,service}.yaml

Key values (partial)
image:
  repository: thunderline/app      # your image repo
  tag: "2.1.0"
  pullPolicy: IfNotPresent

env:
  MINIO_BUCKET: "thunderline-artifacts"
  SERVICE_NAME: "thunderline"
  LOG_LEVEL: "info"
  CEREBROS_ENABLED: "false"     # set to true to flip runtime config + ml_nas feature
  CEREBROS_MODE: "remote"          # default to remote runner
  CEREBROS_URL: ""                # auto-populated to http://<release>-cerebros:8088 if blank
  CEREBROS_REMOTE_URL: ""         # auto-populated, drives the bridge stub
  MLFLOW_TRACKING_URI: ""         # auto-populated to http://<release>-mlflow:5000 if blank
  FEATURES: ""                     # optional feature flags

env.secrets:
  DATABASE_URL: ""                 # ecto://postgres:postgres@postgres:5432/thunderline
  MINIO_ENDPOINT: ""               # http://minio:9000
  MINIO_ACCESS_KEY: ""
  MINIO_SECRET_KEY: ""
  OTEL_EXPORTER_OTLP_ENDPOINT: ""  # http://otel-collector:4317
  OTEL_EXPORTER_OTLP_HEADERS: ""   # optional header string ("authorization=Bearer <token>")

web:
  enabled: true
  replicas: 1
  env:
    ROLE: "web"
    START_ENDPOINT: "true"
    START_COMPUTE: "false"
    START_OBAN: "true"
  service:
    enabled: true
    type: ClusterIP
    port: 4000
  ingress:
    enabled: false
    className: ""
    hosts:
      - host: thunderline.local
        paths:
          - path: /
            pathType: Prefix
    tls: []

worker:
  enabled: true
  replicas: 1
  env:
    ROLE: "worker"
    START_ENDPOINT: "false"
    START_COMPUTE: "false"
    START_OBAN: "true"

mlflow:
  enabled: false                   # enable to run an in-cluster MLflow tracker
  backendStoreUri: "sqlite:////data/mlflow.db"
  artifactRoot: "s3://thunderline-artifacts/mlflow"
  persistence:
    enabled: false                 # set true + storage class for durable metadata/artifacts

cerebrosRunner:
  enabled: false                   # enable to expose /propose + /train endpoints
  env:
    MLFLOW_EXPERIMENT_NAME: "thunderline-demo"

livebook:
  enabled: false                   # enable for interactive orchestration
  secrets:
    password: ""                 # MUST override in non-dev environments (required when ingress=true)
  persistence:
    enabled: false

  ingress:
    enabled: false               # set true to publish Livebook via Kubernetes ingress
    certManager:
      enabled: false             # flip to true to request cert-manager certificate
      clusterIssuer: "letsencrypt-prod"
      secretName: "livebook-tls" # secret used by the ingress TLS stanza

federation:
  enabled: false
  replicas: 1
  image:
    repository: python
    tag: "3.11-slim"
  port: 8081
  # Demo command installs flwr[simulation], the Thunderline Keras backend, and runs the Flower server app
  command: ["/bin/sh","-c"]
  args:
    - |
      pip install --no-cache-dir "flwr[simulation]" && \
      pip install --no-cache-dir -e /workspace/app/python && \
      flwr server-app cerebros.keras.flower_app:server_app --rest-server 0.0.0.0:8081
  service:
    enabled: true
    type: ClusterIP

opentelemetryCollector:
  enabled: false
  replicas: 1
  image:
    repository: otel/opentelemetry-collector-contrib
    tag: "0.106.0"
  service:
    type: ClusterIP
    grpcPort: 4317
    httpPort: 4318

Operational notes
- Provide DATABASE_URL and MinIO credentials via values.env.secrets.*
- For production, replace the demo federation container with a hardened image containing your strategy and pinned dependencies; set federation.image.* and override command/args accordingly.
- Configure imagePullSecrets, resources, affinity, and tolerations per your cluster standards.
- The web Deployment expects a Phoenix release that binds to the port declared in web.service.port (default 4000).
- The chart ships a stub Python script (`priv/cerebros_bridge_stub.py`) and wires `CEREBROS_SCRIPT` to it by default; set `env.CEREBROS_REMOTE_URL` to point the bridge at an external runner if you replace the included FastAPI service.
- When enabling `livebook.ingress`, provide `livebook.secrets.password` and configure TLS via `livebook.ingress.tls` and `livebook.ingress.certManager` (see `examples/values-livebook-tls.yaml`).
- When enabling the collector, update `env.secrets.OTEL_EXPORTER_OTLP_ENDPOINT` (or `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`) to point at the collector service and set any headers via `OTEL_EXPORTER_OTLP_HEADERS`.

Examples
See examples/ in this chart for:
- values-dev.yaml: simple dev config
- values-federation-demo.yaml: federation enabled for demo
- values-hpo-demo.yaml: full MLflow + Cerebros runner + Livebook stack
- values-otel.yaml: overlay for enabling the OpenTelemetry collector
- values-dashboard-run.yaml: dashboard-ready stack (Postgres + MinIO + MLflow + Cerebros)
- values-livebook-tls.yaml: overlay that enables Livebook ingress with cert-manager TLS

Lint and template
helm lint Thunderline/thunderhelm/deploy/chart
helm template thunderline Thunderline/thunderhelm/deploy/chart -n thunder

Uninstall
helm uninstall thunderline -n thunder
