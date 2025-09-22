# Runbook: Enroll Clients (Runner)

Objective
Enroll edge/worker clients into a federation safely:
- Pull-only job acquisition (no inbound ports)
- mTLS channel for transport security
- Signed Job Manifests (JWS) for integrity/authorization
- Idempotent lease claims to prevent double work

Prerequisites
- Federation running or about to start (see start_federation.md)
- Client machines with:
  - Python 3.11 (or your packaged Runner)
  - Certificates/keys for mTLS (if enabled)
  - Access to dataset shard(s) indicated in the Manifest
- Runner CLI or script (planned: thunderline-runner flower-client)

1) Provision client identity and trust
- Issue short-lived client certificate (if using mTLS):
  - client.crt / client.key signed by org CA
  - ca.crt trusted by federation server / API endpoint
- Distribute JWS verification key or JWKS URL for Manifest signature validation

2) Obtain a signed Manifest (pull-only)
Patterns (choose one):
- Poll control-plane endpoint (secure HTTPS) for a lease:
  GET https://thunderline.example.com/api/federations/{id}/leases?client_id={client_uuid}
- If using a queue or mailbox, Runner consumes an addressable Manifest pointer then fetches the content from object storage (S3 presigned URL)
- For lab/demo: direct HTTP to the federation web with basic auth/mTLS (not for prod)

Successful response yields:
- Manifest (JWS compact or JSON with a “signature” field)
- Lease metadata: lease_id, expires_at, tokens_max/epochs_max

3) Validate the Manifest
- Verify JWS signature using org JWKS or embedded public key
- Check validity window (nbf/exp), federation_id, client_id match expectations
- Validate data URIs/hashes for dataset shards; refuse if sha256 mismatch

4) Claim the lease (idempotent)
- POST https://thunderline.example.com/api/federations/{id}/leases/{lease_id}/claim
  Body: {client_id, manifest_hash}
- Expected response: {status: "claimed"} or 409/422 with a reason if already claimed/expired
- Runner should retry with backoff on transient errors and abort on permanent ones

5) Launch Flower client
- Parameters (from Manifest):
  - server_address (e.g., federation service DNS/ClusterIP with port)
  - local training config (epochs, batch size, LR)
  - dataset shard path(s) or S3 presigned URLs
  - telemetry endpoint/token (optional)
- Example (pseudo Python):
  ```python
  import flwr as fl
  # prepare model/dataset per Manifest
  def client_fn(cid: str):
      # return a fl.client.NumPyClient or Client that implements fit/evaluate
      ...
  fl.client.start_client(server_address=manifest["server_address"], client=client_fn("edge-123"))
  ```

6) Report metrics and finalize
- Flower returns per-round updates; client logs local metrics (tokens/sec, loss, accuracy)
- On completion/interruption:
  - POST a heartbeat/final status to control plane (optional) to improve audit trail
  - Allow Runner to release the lease (if partial and resumable) or mark completed (if successful)

7) Power and performance probes (optional)
- Collect watts via:
  - NVIDIA: nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits
  - Intel RAPL: read /sys/class/powercap intel-rapl metrics
- Derive watts/token; attach to telemetry payload; subject to privacy/policy

8) Rotation and re-enrollment
- Certificates and tokens are short-lived; Runner refreshes before expiry
- If lease expires mid-run, Runner halts gracefully and requests a new lease

9) Troubleshooting
- 401/403 on Manifest fetch:
  - Verify mTLS/client cert validity, time sync, and CA trust
- 422 on claim:
  - Lease already claimed/expired; fetch a new Manifest
- Data download failures:
  - Check S3 endpoint/credentials; verify presigned URL expiry
- Training fails on device:
  - Fall back to smaller adapter/LoRA or reduced batch size (policy-driven)

Success criteria
- Client successfully claims a lease, trains, and submits updates across N rounds
- Control plane records join/claim events; telemetry shows client progress
- No duplicate work (idempotency holds); expired leases are reclaimed automatically

Notes
- The Runner CLI (thunderline-runner) should encapsulate: mTLS, JWS validation, lease claim/release, telemetry hooks, and graceful shutdown behavior.
- For air-gapped or mobile clients, consider a store-and-forward Manifest and results approach with strict TTLs.
