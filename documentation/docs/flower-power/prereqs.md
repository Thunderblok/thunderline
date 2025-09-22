# Prerequisites

Supported components and versions
- Kubernetes: v1.24+ (tested on 1.27–1.30)
- Helm: v3.10+
- Thunderline image: appVersion 2.1.x (Phoenix 1.8, Ash 3.x; OTP 26+; Elixir 1.18+)
- Python (for Flower server/clients): 3.10–3.12 (3.11 recommended)
- Node.js (for Thunderline asset pipeline): 18+ (only needed to build images)
- Postgres: 14+ (Thunderline DB)
- MinIO/S3: S3-compatible object store (for model artifacts/checkpoints)
- OTLP Collector (optional but recommended): for tracing/metrics export
- Prometheus + Grafana (optional but recommended): metrics and dashboards

Cluster requirements
- Namespace: thunder (examples assume this)
- Ingress controller (optional): nginx/traefik; configure web.ingress.* values
- StorageClass: default RWX/RWO for Postgres/MinIO (if used); Thunderline itself is stateless
- Resource sizing (initial guidance):
  - thunderline-web: 0.5–1 CPU, 512Mi–1Gi RAM
  - thunderline-worker: 1–2 CPU, 1–2Gi RAM
  - flower-federation (demo server): 0.5–1 CPU, 512Mi–1Gi RAM
  - GPU pool (optional): label/taint nodes for Flower clients that require CUDA
- Network policy (recommended): allow web <-> worker, worker -> Postgres/S3/OTLP; restrict federation server to cluster-only unless necessary

OS packages and tooling (if building images)
- Thunderline build:
  - Erlang/OTP 26+, Elixir 1.18+
  - Build tools: gcc, g++, make, git
  - Node.js 18+ (esbuild, tailwind) if building assets
- Flower build/runtime:
  - Python 3.11, pip, venv module
  - For CUDA clients: NVIDIA drivers + CUDA toolkit matching PyTorch wheels (if used)

External services (choose managed or self-hosted)
- Postgres: DATABASE_URL must be available to Thunderline web/worker
- MinIO/S3:
  - MINIO/S3 endpoint, access key, secret key, bucket (thunderline-artifacts default)
- OTLP collector:
  - Endpoint (e.g. http://otel-collector:4317), optional headers for auth
- Prometheus/Grafana:
  - Scrape ServiceMonitors (if used) or ingest metrics via sidecars/OTLP-to-Prom bridge

Security prerequisites
- TLS for ingress (if exposed)
- Cluster secret management policy (KMS/SealedSecrets/external secret stores)
- mTLS for Runner channel and short-lived client identities (docs/security.md)
- JWS signing keys for job manifests (docs/security.md) stored as Kubernetes Secrets

Images and registries
- Thunderline application image:
  - values.image.repository and values.image.tag must be set
  - Image should be a Phoenix release that binds to port 4000 (default)
- Flower federation image:
  - Demo uses python:3.11-slim + runtime pip install of flwr[simulation]
  - Production should use a hardened image with pinned dependencies and your strategy baked in

Access and permissions
- Kubernetes access: ability to create Deployments, Services, Secrets, ConfigMaps, Ingress (optional)
- ServiceAccount (created by chart) sufficient by default; tighten RBAC per org policy

Compatibility notes
- Thunderline requires Elixir >= 1.18 (mix project reflects that; ensures compatibility for Ash/Jido)
- If enabling GPU clients, pin Python/torch versions carefully and align CUDA
- Mnesia (used internally by Thunderline) stores data on ephemeral disk; primary persistence is Postgres

Next
- See configuration.md for environment variables and Helm values
- Then deploy with Helm using examples/values-dev.yaml or examples/values-federation-demo.yaml
