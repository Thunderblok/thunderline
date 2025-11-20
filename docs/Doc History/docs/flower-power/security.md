# Security

This guide codifies the security posture for federated training with Thunderline (control plane) and Flower (federation runtime). It focuses on transport security (mTLS), signed job manifests (JWS), multi‑tenant data governance (RLS), and privacy controls (DP/secure aggregation).

Threat model (abridged)
- Untrusted or semi‑trusted clients: Edge nodes may be intermittently connected, compromised, or resource‑constrained.
- Network eavesdropping/tampering: Control plane ↔ clients and S3/MinIO traffic must be protected.
- Multi‑tenancy: Strong tenant isolation and audit trails are required.
- Artifact integrity: Model checkpoints and deltas must be verifiable at rest and in motion.

Controls overview
- Transport
  - mTLS between Runner and control/federation endpoints (pull‑only paradigm)
  - TLS termination at ingress; TLS in‑cluster where required by policy
- Identity & AuthN/Z
  - Short‑lived client certificates or tokens; per‑tenant scoping
  - Ash actions enforce authorization; RLS protects data access
- Integrity
  - JWS‑signed Job Manifests; artifact sha256 lineage in Postgres
- Privacy
  - Optional Differential Privacy (DP) and Secure Aggregation (configurable per FederationSpec)
- Observability
  - Security‑relevant telemetry (joins, claims, failures) emitted as events and spans

mTLS (Runner channel)
- Clients authenticate with short‑lived certs issued by an org CA; Federation/Control plane validates client certs.
- Required materials on client:
  - client.crt / client.key (PEM), ca.crt (trusted CA/root)
- Example curl (for lease claim):
  ```bash
  curl --cert client.crt --key client.key --cacert ca.crt \
    https://thunderline.example.com/api/federations/<id>/leases/<lease_id>/claim
  ```
- Rotation
  - Certificates are short‑lived (hours or less); Runners fetch fresh credentials before expiry
  - Revoke/rotate CA keys per policy; propagate ca.crt to services

Signed Job Manifests (JWS)
- The Manifest is the source of truth for a client’s job: dataset shards, hyperparams, constraints, and telemetry endpoints.
- Control plane signs with a private key; clients verify with a public key or JWKS.
- Recommended format: JWS Compact (RFC 7515) or JWS JSON with “signature” field.
- Claims
  - iss (issuer), aud (expected audience), nbf/exp (validity window)
  - federation_id, client_id
  - manifest_hash (optional cross‑binding)
- Verification flow (Runner)
  1) Resolve JWKS (or cached public key)
  2) Verify signature and validity window
  3) Check federation_id/client_id binding
  4) Validate shard URIs/hashes (sha256) before training

Key management and rotation
- Store signing keys in a secure store (HSM/KMS or Kubernetes external secrets)
- JWKS endpoint or static JWK in Runner’s trust bundle
- Rotate signing keys regularly; publish overlapping keys (kid) to allow in‑flight manifests to complete
- Enforce short exp windows to reduce replay risk

Authorization and multi‑tenancy (Ash + RLS)
- All state changes occur via Ash actions with policy checks
- Resource scoping by tenant:
  - Federation, FLRound, ClientLease, ModelArtifact, MetricsRollup are RLS‑guarded
- Endpoints (RPC/GraphQL/REST) exposed per environment with least privilege; admin surfaces gated (e.g., AshAdmin disabled/locked in prod)

Privacy: Differential Privacy (DP)
- FederationSpec.privacy.dp.{enabled,epsilon,delta}
- DP applied at client side when enabled (Runner/Trainer plugin)
- Track cumulative privacy loss if multiple rounds/queries; enforce policy budget

Privacy: Secure Aggregation
- FederationSpec.privacy.secureAggregation.enabled
- Aggregate updates without revealing individual client contributions
- Strategy‑dependent: ensure your Flower strategy supports secure aggregation protocol

Artifact integrity and provenance
- All artifacts (checkpoints/adapters) are content‑addressed:
  - sha256 stored alongside URI and size_bytes in ModelArtifact
- Promotion requires re‑verifying hash before updating “latest” pointers
- Optional signed artifact manifests (detached signature) for downstream consumers

S3/MinIO security
- Use TLS endpoints; rotate access keys; restrict buckets with IAM policies
- Limit presigned URL validity windows for dataset shards and artifacts
- Encrypt at rest (server‑side encryption) per compliance

Ingress/TLS
- Terminate TLS at ingress; keep cluster‑internal TLS as required by policy
- Manage certificates with cert‑manager or your org’s PKI
- Enforce HSTS and modern cipher suites; disable weak protocols

Logging and PII
- Avoid logging sensitive data (keys, tokens)
- If power metrics or device info are considered sensitive, scrub or aggregate before egress
- Comply with data retention policies; implement log redaction where necessary

Security testing checklist
- [ ] mTLS handshake validated with invalid/expired client certs (denied)
- [ ] JWS verification fails on tampered/expired manifests (denied)
- [ ] RLS prevents cross‑tenant access to Federation rows/artifacts
- [ ] Artifact sha256 mismatch blocks promotion
- [ ] Presigned URLs expire and cannot be reused
- [ ] Key/cert rotation does not break in‑flight federations
- [ ] OTLP spans/metrics include security‑relevant events (join/claim/deny)

Incident response (see runbooks/incident_response.md)
- Leaked keys: rotate signing keys; revoke compromised certs; invalidate active leases
- Suspicious client: revoke cert, expire leases, quarantine datasets; reissue manifests to other clients
- Artifact tampering: block promotions; audit S3 access; restore from known‑good artifact by hash
