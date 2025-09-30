# START HERE — Thunderline NAS + Flower Keras Smoke-Test Playbook

Use this checklist to spin up the full Thunderline + Cerebros NAS stack, verify the cluster, and launch a run from the dashboard. Each section lists the exact steps and the files or commands to reference.

---

## 1. Prerequisites
- **Source validation (local workstation):**
  - `mix thunderline.ml.prepare` – confirm base Cerebros bridge readiness.
  - `mix thunderline.ml.validate --require-enabled` – ensure validator passes with the bridge feature flag on.
- **Credentials:**
  - Docker registry access for the Thunderline release image (`image.repository` / `image.tag`).
  - Kubernetes cluster credentials (`kubectl` configured for the target context).
- **Helm:** version 3.10+ available locally.
- **Flower runtime image:**
  - Ensure the Flower superexec image you plan to deploy includes the `flwr` runtime and this repository's `python/cerebros/keras` package. The new client/server wiring lives in `cerebros.keras.flower_app` and removes the PyTorch requirement.
  - If you are packaging a custom superexec image, copy the repo into `/workspace/app` and set the entry point to `flwr client-app cerebros.keras.flower_app:client_app` (see Section 5).
  - Required environment variables are documented below; at a minimum set `CEREBROS_MODEL_NAME=simple_cnn` and `CEREBROS_DATASET_NAME=mnist` for CPU demos.

---

## 2. Deploy the Helm stack
1. Change into the repo root: `cd /home/mo/DEV/Thunderline` (or your clone path).
2. Make sure the Thunderline release image is available to the cluster:
   - If you publish to a registry, override the chart defaults:
     ```sh
     helm upgrade --install thunderline thunderhelm/deploy/chart \
       -n thunder --create-namespace \
       -f thunderhelm/deploy/chart/examples/values-dashboard-run.yaml \
       --set image.repository=ghcr.io/<your-org>/thunderline \
       --set image.tag=<release-tag>
     ```
   - For local K3s/Kubernetes without registry access, build and load the image directly:
     ```sh
     docker build -t thunderline/app:2.1.0 .
     docker save thunderline/app:2.1.0 | sudo k3s ctr images import -
     ```
     (Replace the import command with the equivalent for your runtime, e.g. `crictl`.)
3. Apply the pre-baked dashboard NAS overlay:
   ```sh
   helm upgrade --install thunderline thunderhelm/deploy/chart \
     -n thunder --create-namespace \
     -f thunderhelm/deploy/chart/examples/values-dashboard-run.yaml
   ```
   - This overlay enables Postgres, MinIO, MLflow, and the Cerebros runner.
   - Feature flags `ml_nas`, `cerebros_bridge`, and `ai_chat_panel` are turned on via chart values.
   - To attach a Flower control plane, merge in the federation example values:
     ```sh
     helm upgrade --install thunderline thunderhelm/deploy/chart \
       -n thunder --create-namespace \
       -f thunderhelm/deploy/chart/examples/values-dashboard-run.yaml \
       -f thunderhelm/deploy/chart/examples/values-federation-demo.yaml \
       --set thunderFederation.image.repository=ghcr.io/<your-org>/flower-superexec \
       --set thunderFederation.image.tag=<tag>
     ```
     Update the example command to point at your hardened Flower superexec image that bundles the Keras backend module.

---

## 3. Verify the cluster
- Watch pod rollout: `kubectl get pods -n thunder -w` (use `sudo` if your kubeconfig lives under `/etc/rancher/k3s/`) until all pods are `Running` and `Ready`.
- Confirm auxiliary services:
  - `kubectl get svc thunderline-postgresql -n thunder`
  - `kubectl get svc thunderline-minio -n thunder`
  - `kubectl get svc thunderline-mlflow -n thunder`
  - `kubectl get svc thunderline-cerebros -n thunder`
- Inspect logs for the application pods:
  - `kubectl logs -f deploy/thunderline-web -n thunder`
  - `kubectl logs -f deploy/thunderline-worker -n thunder`
  - Verify the boot logs mention `CEREBROS_ENABLED=true` and the `ml_nas` feature flag.

---

## 4. Expose the dashboard and helpers
- **Dashboard (Phoenix web):**
  - `kubectl port-forward svc/thunderline-web -n thunder 4000:4000`
  - Browse to `http://localhost:4000` and sign in.
- **MLflow (optional):**
  - `kubectl port-forward svc/thunderline-mlflow -n thunder 5000:5000`
  - Visit `http://localhost:5000` to watch experiment metrics.
- **MinIO console (optional):**
  - `kubectl port-forward svc/thunderline-minio -n thunder 9000:9000`
  - Use the credentials defined in the values file (`minio` / `minio123`).

---

## 5. Launch the NAS run from the dashboard
1. Navigate to the Cerebros / NAS panel in the Phoenix dashboard.
2. Fill in or accept the default spec (the chart included `Validator.default_spec/0`).
3. Trigger the run – the dashboard enqueues `Thunderline.Thunderbolt.CerebrosBridge.RunWorker`.
4. Monitor the worker logs: `kubectl logs -f deploy/thunderline-worker -n thunder`.
   - Expect to see `RunWorker` emit `run_started`, trial reports, and finalize telemetry.

---

## 6. Launch the Flower Keras federation (optional)
- **Server (inside the SuperExec image or locally):**
  ```sh
  flwr server-app cerebros.keras.flower_app:server_app \
    --insecure-allow-loopback \
    --rest-server 0.0.0.0:8081
  ```
  Environment variables:
  - `FLOWER_NUM_ROUNDS` – number of rounds (default `3`).
  - `FLOWER_FRACTION_FIT` / `FLOWER_FRACTION_EVAL` / `FLOWER_MIN_AVAILABLE` – FedAvg tunables.
- **Clients (one per SuperExec or local process):**
  ```sh
  flwr client-app cerebros.keras.flower_app:client_app \
    --rest-server <server-host>:8081
  ```
  Recommended configuration variables:
  - `CEREBROS_MODEL_NAME` – `simple_cnn`, `mlp`, etc.
  - `CEREBROS_DATASET_NAME` – `mnist`, `fashion_mnist`, or `cifar10`.
  - `CEREBROS_DATASET_CFG` – JSON string for additional dataset arguments (`{"limit": 1000}` for smoke tests).
  - `CEREBROS_TRAIN_PARAMETERS` / `CEREBROS_TRAIN_OVERRIDES` – JSON specs fed into `resolve_training_config`.
  - `FLOWER_PARTITION_ID`, `FLOWER_NUM_PARTITIONS` – split the dataset across clients.
  - `CEREBROS_USE_MIXED_PRECISION` – set to `true` for GPU clients.
  Metrics emitted by the client aggregate to the server via weighted averaging.

Once the Flower round completes, run `kubectl logs -f deploy/thunderline-worker -n thunder` to confirm the bridge consumed the aggregated weights if you are integrating the control plane.

---

## 7. Monitor telemetry & artifacts
- **MLflow UI:** check trial metrics, parameters, and artifacts for the run ID.
- **MinIO bucket:** confirm bridge payloads and artifacts land under `thunderline-artifacts/`.
- **Phoenix dashboard:** watch real-time status updates and ensure the run transitions to `succeeded` (or inspect errors if the status differs).

---

## 8. Clean up (optional)
- Remove the release: `helm uninstall thunderline -n thunder`.
- Delete the namespace if no longer needed: `kubectl delete ns thunder`.
- Clear any local port-forward sessions.

---

## References
- Helm chart documentation: `thunderhelm/deploy/chart/README.md`
- Flower federation quickstart: `ops/federation/flower/README.md`
- Cerebros Keras backend & Flower wiring: `python/cerebros/keras/`
- Mix validators: `mix thunderline.ml.prepare`, `mix thunderline.ml.validate`

Keep this playbook updated as dependencies or feature flags change.
