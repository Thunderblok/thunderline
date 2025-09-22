# Runbook: Artifacts and Promotion

Objective
Manage model artifacts produced by federations: verify integrity, store with lineage in S3/MinIO, and promote a candidate checkpoint/adapters to downstream consumers (e.g., PAC).

Prerequisites
- Thunderline web/worker running and connected to Postgres and S3/MinIO
- Federation completed or partially completed with an aggregate artifact
- Access to the bucket configured in values.env.MINIO_BUCKET (default thunderline-artifacts)

1) Artifact write and lineage (expected)
On federation completion (or at selected rounds), the Flower server writes an artifact:
- URI: s3://<bucket>/<prefix>/checkpoints/global-ROUND-<n>.<ext>
- Integrity: sha256 recorded
- Size: captured in bytes
Thunderline should record a ModelArtifact row with:
- federation_id, round_id (nullable), uri, sha256, size_bytes, format, created_at

2) Verify existence and hash
Use your S3/MinIO client or CLI:
```bash
mc ls minio/thunderline-artifacts/federations/coop-chat-v2/
mc stat minio/thunderline-artifacts/federations/coop-chat-v2/checkpoints/global-ROUND-10.pt
mc cat  minio/thunderline-artifacts/federations/coop-chat-v2/checkpoints/global-ROUND-10.pt | sha256sum
```
Compare the sha256 to the value stored in ModelArtifact.

3) Candidate selection
Selection heuristics may include:
- Best validation metric (accuracy, perplexity)
- Recency (latest stable round)
- Efficiency (watts/token, tokens/sec trends)
- Policy rules (minimum client coverage, fairness constraints)

4) Promotion (Ash action)
Expose an Ash action (example) to promote an artifact:
- Inputs: federation_id, artifact_uri, target_ref (e.g., “coop-chat-v2:prod”), metadata
- Steps:
  - Validate artifact exists and hash matches stored sha256
  - Update a “promotions” table/resource with provenance (who/when/why)
  - Optionally write a “latest” object/key to S3 (e.g., models/coop-chat-v2/latest.pt) pointing to the chosen artifact
  - Emit event: fl.artifact.promoted {federation_id, artifact_uri, target_ref, sha256}

Pseudo RPC payload:
```json
{
  "domain": "Thunderline.Thundercrown.Domain",
  "action": "promote_artifact",
  "params": {
    "federation_id": "UUID",
    "artifact_uri": "s3://thunderline-artifacts/federations/coop-chat-v2/checkpoints/global-ROUND-10.pt",
    "target_ref": "coop-chat-v2:prod",
    "reason": "best_val_acc",
    "metadata": {"val_acc": 0.913}
  }
}
```

5) Consumers (PAC or downstream services)
Consumers should read “latest” references or subscribe to fl.artifact.promoted events to update runtime models:
- Pull artifact from S3
- Verify sha256 again
- Hot-reload adapter/LoRA or full checkpoint based on your runtime

6) Rollback
If a promotion degrades performance:
- Promote the previous best artifact (idempotent promote to “latest”)
- Emit fl.artifact.promoted with the previous URI as the new target

7) Retention and housekeeping
- Retain all artifacts for audit per policy, or
- Apply lifecycle rules (keep N best and all round milestones, purge the rest)
- Ensure you never delete the artifact currently referenced by “latest” or by active deployments

8) Troubleshooting
- Artifact missing in S3:
  - Check federation server logs and S3 credentials; confirm bucket/prefix in FederationSpec.artifacts.*
- sha256 mismatch:
  - Recompute hash from S3 and compare with DB; if mismatch, block promotion and investigate integrity
- Consumers not updating:
  - Confirm event delivery and that consumers watch “latest” reference or listen to promotion events

Success criteria
- Artifact URI exists, sha256 matches, lineage recorded
- Promotion generates event and updates consumer-facing reference
- Consumers hot-reload with no downtime (per deployment strategy)
