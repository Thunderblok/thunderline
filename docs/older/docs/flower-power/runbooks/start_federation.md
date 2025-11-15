# Runbook: Start a Federation

Objective
Start a federated training run using Thunderline as control plane and Flower as the federation runtime. Ensures all state transitions are recorded in Postgres (Ash), artifacts land in S3/MinIO, and telemetry flows to OTLP/Prom.

Prerequisites
- Thunderline deployed (web + worker) via Thunderhelm
- Optional federation (Flower) server running or enabled in Helm
- Postgres reachable; MinIO/S3 credentials valid
- FederationSpec YAML prepared (see ../examples/federation-spec.sample.yaml)

1) Prepare FederationSpec
- Copy the sample and edit fields:
  - spec.modelRef.uri/sha256
  - spec.rounds.total
  - spec.strategy.* (fedavg/fedprox/custom)
  - spec.datasetSpec.shards[].uri/sha256
  - spec.artifacts.outputBucket/prefix
- Store it local or in object storage. Example local path:
  Thunderline/docs/flower-power/examples/federation-spec.sample.yaml

2) Ensure services are healthy
- Pods:
  kubectl get pods -n thunder
- Logs:
  kubectl logs deploy/thunderline-thunderhelm-web -n thunder | tail -n 200
  kubectl logs deploy/thunderline-thunderhelm-worker -n thunder | tail -n 200
- Optional federation:
  kubectl logs deploy/thunderline-thunderhelm-federation -n thunder | tail -n 200

3) Start the federation (HTTP RPC path)
If you’ve exposed an Ash RPC or controller endpoint (e.g., /rpc/run) that calls a start action:

Example pseudo request (adjust domain/action names to match your implementation):
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

Expected result:
- Federation row created (status=running)
- FLRound row created for round=1 (status=started)
- Events emitted: fl.federation.started, fl.round.started

4) Alternative: console/eval helper
If you provide a helper function (example only):
kubectl exec -it deploy/thunderline-thunderhelm-worker -n thunder -- \
  bin/thunderline eval 'Thunderline.FederationHelpers.start!("coop-chat-v2-demo","pac-ops", File.read!("priv/specs/coop-chat-v2.yaml"))'

5) Monitor progress
- Rounds/Events (logs):
  kubectl logs deploy/thunderline-thunderhelm-worker -n thunder | sed -n "/fl\\./p" | tail -n +1
- OTLP traces/metrics:
  Verify your collector and Grafana dashboards (see ../observability.md)
- Federation service (Flower):
  kubectl get svc -n thunder | grep federation
  kubectl -n thunder port-forward svc/thunderline-thunderhelm-federation 8081:8081

6) Completion and artifacts
- Expected events:
  - fl.round.completed (for each round)
  - fl.aggregate.completed
  - fl.federation.completed
- Artifact:
  - Global checkpoint written to MinIO/S3 (spec.artifacts.*)
  - ModelArtifact row recorded (uri, sha256, size)

7) Pause/stop (optional)
If you expose Ash actions to pause/stop:
- Pause: emits fl.federation.paused and halts round advancement
- Stop/Fail: sets status to completed/failed; emits corresponding events

8) Troubleshooting
- web/worker CrashLoopBackOff:
  - Check DATABASE_URL, Postgres reachability, migrations
- No artifacts:
  - Validate MINIO_* env and bucket permissions; test a simple object write
- No clients join:
  - For a demo, ensure federation (Flower) server is running
  - For real edge: verify Runner can pull manifest (mTLS), lease validity, and network policies
- Rounds hang/time out:
  - Increase spec.rounds.timeoutSeconds
  - Lower clientFraction or minAvailable
  - Inspect federation logs for connectivity or strategy issues

Success criteria
- K clients join, N rounds complete
- Checkpoint stored in S3 with sha256 recorded
- OTLP traces and Prom metrics visible; SLOs met (see ../observability.md)

Rollback
- If necessary, mark federation as failed via an Ash action; retain lineage and events
- Helm rollback affects deployments only; federations in DB remain for audit
