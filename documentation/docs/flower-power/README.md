# Flower Power: Distributed Training with Thunderline + Flower (+ Cerebros/Automat0)

This doc set describes how to deploy and operate a federated training platform:
- Control plane: Thunderline (Phoenix + Ash + Postgres)
- Federation runtime: Flower (server + clients)
- Optional executors: Automat0 microservices and Cerebros training pipelines
- Artifact plane: MinIO/S3 for model checkpoints and logs
- Observability: OTLP collector, Prometheus, Grafana

Goals
- One-click dev demo on Kubernetes using Thunderhelm
- Contract-first integration (FederationSpec) with lineage and audit in Postgres (Ash)
- Production-ready guidance: security (mTLS/JWS), observability, SLOs, and rollout playbooks

Quickstart (Kubernetes)
1) Build/publish your Thunderline image (or use an existing one) and set image repo/tag in Helm values.
2) Install Thunderhelm:
   - Dev defaults:
     helm install thunderline Thunderline/thunderhelm/deploy/chart -n thunder --create-namespace -f Thunderline/thunderhelm/deploy/chart/examples/values-dev.yaml
   - Federation demo (enables a demo Flower server):
     helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart -n thunder -f Thunderline/thunderhelm/deploy/chart/examples/values-federation-demo.yaml
3) Port-forward web (if no ingress):
   kubectl -n thunder port-forward svc/thunderline-thunderhelm-web 4000:4000
   Open http://localhost:4000
4) Verify pods and logs:
   kubectl get pods -n thunder
   kubectl logs deploy/thunderline-thunderhelm-web -n thunder

Document map
- architecture.md — planes, sequence diagrams, topology
- prereqs.md — versions, cluster requirements, GPU/CPU, OS packages
- configuration.md — environment, secrets, Helm values, feature flags
- contracts.md — FederationSpec schema; Ash resources; event taxonomy; examples
- deploy-dev.md — dev path with Helm + optional compose for dependencies
- deploy-k8s.md — production Helm guide: ingress/TLS, node selectors, resources, HPA
- runbooks/
  - start_federation.md — create FederationSpec, start/monitor rounds
  - enroll_clients.md — runner bootstrap, mTLS, JWS manifest validation, idempotency
  - artifacts_and_promotion.md — checkpoints to MinIO/S3, lineage, promotion
  - dashboards.md — OTLP spans, Prom metrics, Grafana panels
  - incident_response.md — common failures and mitigations
- observability.md — OTLP config, metrics catalog, Grafana JSON
- security.md — mTLS, signed manifests, tenant isolation (RLS), DP/secure aggregation
- roadmap.md — strategies (FedAvg/FedProx/custom), pgvector selector, watts/token probes

Acceptance (MVP)
- Start Federation → K clients join → N rounds complete
- Aggregated checkpoint stored in MinIO with sha256 lineage in PG
- OTLP traces + Prom metrics visible; SLOs recorded (round p95, join rate, tokens/sec)

Next
Proceed to architecture.md to understand core planes and flows.
