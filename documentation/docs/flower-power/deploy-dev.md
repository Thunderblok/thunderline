# Deploy (Dev)

This guide gets a developer cluster running Thunderline (web + worker) and an optional Flower (federation) demo server using the Thunderhelm chart.

Prereqs
- Kubernetes v1.24+ and Helm v3.10+
- External Postgres, MinIO/S3, and (optionally) an OTLP collector (dev examples assume service DNS names: postgres, minio, otel-collector)
- A Thunderline container image that runs a Phoenix release and listens on port 4000

1) Namespace and values
Create/use a dev namespace (examples use thunder):
```bash
kubectl create namespace thunder || true
```

Use the provided dev values file (ClusterIP, no ingress, federation disabled):
- Thunderline/thunderhelm/deploy/chart/examples/values-dev.yaml

2) Install Thunderline (web + worker)
```bash
helm install thunderline Thunderline/thunderhelm/deploy/chart \
  -n thunder \
  -f Thunderline/thunderhelm/deploy/chart/examples/values-dev.yaml
```

Update secrets (if you didn’t already set them in values-dev.yaml):
```bash
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart \
  -n thunder \
  --set env.secrets.DATABASE_URL="ecto://postgres:postgres@postgres:5432/thunderline" \
  --set env.secrets.MINIO_ENDPOINT="http://minio:9000" \
  --set env.secrets.MINIO_ACCESS_KEY="minio" \
  --set env.secrets.MINIO_SECRET_KEY="minio123"
```

3) Verify pods and logs
```bash
kubectl get pods -n thunder
kubectl logs deploy/thunderline-thunderhelm-web -n thunder | tail -n +1
kubectl logs deploy/thunderline-thunderhelm-worker -n thunder | tail -n +1
```

4) Port-forward web (no ingress in dev example)
```bash
kubectl -n thunder port-forward svc/thunderline-thunderhelm-web 4000:4000
# Open http://localhost:4000
```

5) Optional: Enable the Flower demo server
Enable the demo Flower server (python:3.11-slim; installs flwr[simulation] at container start):
```bash
helm upgrade --install thunderline Thunderline/thunderhelm/deploy/chart \
  -n thunder \
  -f Thunderline/thunderhelm/deploy/chart/examples/values-federation-demo.yaml
```

Check the federation service and logs:
```bash
kubectl get svc -n thunder | grep federation
kubectl -n thunder port-forward svc/thunderline-thunderhelm-federation 8081:8081
kubectl logs deploy/thunderline-thunderhelm-federation -n thunder | tail -n +1
```

6) Sanity checks
- Web: ensure 200 OK on / or health endpoint (values.web.probes.web.liveness.path)
- DB: pods should not CrashLoop; if they do, confirm DATABASE_URL and network reachability
- Artifacts: verify MinIO/S3 credentials by running a simple object write/read from app code or via a one-off job (optional)
- OTLP: if configured, ensure traces/metrics appear in your collector/observability stack

7) Start a federation (dev paths)
You have two options (depending on what surfaces you’ve implemented):
- RPC HTTP (Ash Typescript RPC):
  - The default config in Thunderline/config/config.exs sets run_endpoint to /rpc/run
  - Example (pseudo) curl to call a “start_federation” action:
    ```bash
    curl -X POST http://localhost:4000/rpc/run \
      -H 'content-type: application/json' \
      -d '{
        "domain": "Thunderline.Thundercrown.Domain",
        "action": "start_federation",
        "params": {
          "name": "coop-chat-v2-demo",
          "tenant_id": "pac-ops",
          "spec_yaml": "'"$(cat Thunderline/docs/flower-power/examples/federation-spec.sample.yaml | sed "s/\"/\\\\\"/g")"'"
        }
      }'
    ```
  - Note: the exact domain/action names depend on your implementation. Use this as a template.

- Console eval inside the web/worker pod (if you expose a helper):
  ```bash
  # Example: calling a helper module you write (not yet implemented)
  kubectl exec -it deploy/thunderline-thunderhelm-worker -n thunder -- \
    bin/thunderline eval 'Thunderline.FederationHelpers.start!("coop-chat-v2-demo", "pac-ops", File.read!("priv/specs/coop-chat-v2.yaml"))'
  ```

8) Cleanup
```bash
helm uninstall thunderline -n thunder
kubectl delete namespace thunder
```

Notes and tips
- Migrations: Thunderline supervises a MigrationRunner; your DB will be created/migrated at startup if properly configured.
- Federation demo server is for simulation only; production should use a hardened image with pinned dependencies and your strategy baked in.
- If you use different service names (e.g., external Postgres), adjust DATABASE_URL and related env accordingly.
- For local testing without Kubernetes, you can run Postgres/MinIO and Thunderline locally, then run the Flower server via python -m venv + pip install flwr[simulation]. See deploy-dev alternatives in future docs.
