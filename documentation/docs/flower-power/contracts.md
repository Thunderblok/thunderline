# Contracts

This document defines the control-plane contracts between Thunderline (Ash/PG), the Flower federation runtime, and clients (Runner). It includes the FederationSpec, Ash resource surfaces, and the event taxonomy.

FederationSpec (YAML)
The single source of truth for a federation run. Thunderline stores it (verbatim) and materializes leases and manifests from it; the Flower server reads equivalent parameters to configure strategy and rounds.

Example
See examples/federation-spec.sample.yaml for a full sample. Key fields:

```yaml
apiVersion: thunderline.okocorp/v1
kind: FederationSpec
metadata:
  name: coop-chat-v2
  tenant: pac-ops
spec:
  modelRef:
    uri: s3://thunderline-artifacts/models/coop-chat-v2/base.pt
    sha256: "<hex>"
    format: torch
  strategy:
    name: fedavg            # fedavg | fedprox | custom
    params:
      clientFraction: 0.2   # fraction of clients per round
      minAvailable: 5       # min clients to start a round
      localEpochs: 1
      localBatchSize: 32
      learningRate: 5.0e-5
      proxMu: 0.0           # only for fedprox
  rounds:
    total: 10               # N rounds
    timeoutSeconds: 180     # round timeout budget (optional)
  privacy:
    dp:
      enabled: false
      epsilon: 3.0
      delta: 1.0e-5
    secureAggregation:
      enabled: false
  clientSelector:
    tenant: pac-ops
    tags: ["edge", "region-us-east"]
    embeddingQuery: ""      # reserved for pgvector selector
  datasetSpec:
    shards:
      - uri: s3://thunderline-artifacts/datasets/coop_chat_v2/shard-000.parquet
        sha256: "<hex>"
      - uri: s3://thunderline-artifacts/datasets/coop_chat_v2/shard-001.parquet
        sha256: "<hex>"
    schema: parquet
  artifacts:
    outputBucket: thunderline-artifacts
    prefix: "federations/coop-chat-v2"
  telemetry:
    otlp:
      enabled: true
      endpoint: "http://otel-collector:4317"
      headers: ""
  constraints:
    lease:
      maxEpochs: 1
      maxTokens: 1000000
      ttlSeconds: 1800
```

Validation rules (high level)
- spec.rounds.total ≥ 1
- strategy.name ∈ {fedavg, fedprox, custom}
- If privacy.dp.enabled=true → epsilon, delta must be set
- datasetSpec.shards[].uri required; sha256 strongly recommended
- artifacts.outputBucket required
- constraints.lease.ttlSeconds ≥ 60

Ash resources (proposed schema surfaces)
- Federation
  - id (UUID), name (string), tenant_id (string)
  - spec_yaml (text), status (enum: created|running|completed|failed)
  - created_by (string/UUID), started_at (utc), completed_at (utc)
  - actions:
    - create(name, tenant_id, spec_yaml)
    - start()
    - complete()
    - fail(reason)
- FLRound
  - id, federation_id (FK), round_num (int), status (enum)
  - metrics_json (map), started_at, completed_at
  - actions:
    - start(round_num)
    - complete(metrics_json)
- ClientLease
  - id, federation_id, client_id, manifest_uri (string)
  - lease_expires_at (utc), epochs_max (int), tokens_max (int), status (enum: issued|claimed|expired|released)
  - actions:
    - issue(client_id, manifest_uri, epochs_max, tokens_max, ttl)
    - claim(client_id)
    - release()
    - expire()
- ModelArtifact
  - id, federation_id, round_id (nullable), uri (string), sha256 (string), size_bytes (int), format (string), created_at
  - actions: record(uri, sha256, size_bytes, format)
- MetricsRollup
  - id, federation_id, round_id, aggregates_json (map), created_at
  - actions: record(aggregates_json)

Event taxonomy (outbox)
All state mutations emit an event (stored + published on bus). Suggested topic class: fl.*

- fl.federation.created
  - {federation_id, name, tenant_id}
- fl.federation.started
  - {federation_id, rounds_total}
- fl.federation.completed
  - {federation_id, rounds_total, artifact_uri, sha256}
- fl.federation.failed
  - {federation_id, reason}

- fl.client.lease_issued
  - {federation_id, client_id, lease_id, ttl_seconds}
- fl.client.joined
  - {federation_id, client_id, round_num}
- fl.client.dropped
  - {federation_id, client_id, reason}

- fl.round.started
  - {federation_id, round_num, client_fraction}
- fl.round.completed
  - {federation_id, round_num, metrics: {...}}

- fl.aggregate.completed
  - {federation_id, round_num, artifact_uri, sha256}

Manifests (per-client)
- Manifest captures job inputs the Runner needs:
  - modelRef (read-only), dataset shard(s), hyperparams (epochs, batch size, LR), constraints (max tokens/epochs), telemetry endpoint/token
  - Signed (JWS) by the control plane; Runner verifies signature and validity window before execution
- Delivery:
  - Pull-only: Runner polls/requests its manifest; no inbound ports on edge
- Idempotency:
  - Claiming a lease is idempotent; replays do not double-count work

Security considerations
- All Ash actions require authorization; RLS enforces tenant scoping
- Manifests signed with JWS; keys rotated regularly; short-lived validity windows
- Runner channel uses mTLS; short-lived identities for clients
- Optional DP/secure aggregation settings honored by clients and Flower strategy

Observability contract (labels and fields)
- Trace attributes: federation_id, round_num, client_id, tenant
- Metrics (Prom/OTLP):
  - fl_clients_joined_total{federation_id}
  - fl_rounds_completed_total{federation_id}
  - fl_aggregate_duration_seconds_bucket{federation_id}
  - fl_tokens_per_second{federation_id, client_id}
  - fl_power_watts{client_id} (optional)
  - fl_watts_per_token{client_id} (derived)
