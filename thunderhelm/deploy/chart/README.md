# Thunderhelm — Helm chart for Thunderline + optional Flower federation

This chart deploys Thunderline’s control plane (web) and workers, with an optional Python-based Flower federation runtime for federated learning demos and experiments.

Contents
- Deployments: web (Phoenix endpoint), worker (pipelines/Oban), optional federation (Flower server)
- Services: web ClusterIP, optional federation ClusterIP
- Optional Ingress for web
- ConfigMap/Secret for shared environment and secrets
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

# Enable optional Flower federation demo server
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  --set federation.enabled=true \
  --set federation.service.enabled=true

# Enable web ingress (edit hosts/TLS in values.yaml)
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder \
  --set web.ingress.enabled=true

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
  - federation-deployment.yaml, federation-service.yaml

Key values (partial)
image:
  repository: thunderline/app      # your image repo
  tag: "2.1.0"
  pullPolicy: IfNotPresent

env:
  MINIO_BUCKET: "thunderline-artifacts"
  SERVICE_NAME: "thunderline"
  LOG_LEVEL: "info"
  FEATURES: ""                     # optional feature flags

env.secrets:
  DATABASE_URL: ""                 # ecto://postgres:postgres@postgres:5432/thunderline
  MINIO_ENDPOINT: ""               # http://minio:9000
  MINIO_ACCESS_KEY: ""
  MINIO_SECRET_KEY: ""
  OTEL_EXPORTER_OTLP_ENDPOINT: ""  # http://otel-collector:4317
  OTEL_HEADERS: ""                 # optional

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

federation:
  enabled: false
  replicas: 1
  image:
    repository: python
    tag: "3.11-slim"
  port: 8081
  # Demo command installs flwr[simulation] and runs a basic FedAvg server
  command: ["/bin/sh","-c"]
  args:
    - |
      pip install --no-cache-dir "flwr[simulation]" && \
      python - <<'PY'
      from flwr.server import ServerApp, start_server
      from flwr.server.strategy import FedAvg
      def app() -> ServerApp:
          return ServerApp(FedAvg())
      if __name__ == "__main__":
          start_server(server_app=app(), server_address="0.0.0.0:8081")
      PY
  service:
    enabled: true
    type: ClusterIP

Operational notes
- Provide DATABASE_URL and MinIO credentials via values.env.secrets.*
- For production, replace the demo federation container with a hardened image containing your strategy and pinned dependencies; set federation.image.* and override command/args accordingly.
- Configure imagePullSecrets, resources, affinity, and tolerations per your cluster standards.
- The web Deployment expects a Phoenix release that binds to the port declared in web.service.port (default 4000).

Examples
See examples/ in this chart for:
- values-dev.yaml: simple dev config
- values-federation-demo.yaml: federation enabled for demo

Lint and template
helm lint Thunderline/thunderhelm/deploy/chart
helm template thunderline Thunderline/thunderhelm/deploy/chart -n thunder

Uninstall
helm uninstall thunderline -n thunder
