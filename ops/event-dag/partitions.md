# Partitions & Backpressure Policy

- Partition keys by event type:
  - link/ui.command.* -> pac_id (stable ordering per PAC)
  - bolt/ml.* -> trial_id (isolate per trial)
  - gate.* -> realm_id (isolate per realm)

- Partition counts:
  - Dev: 4 partitions per processor by default
  - Prod: 32–128 depending on throughput; scale by lag SLO

- Backpressure:
  - Max lag SLO: 2s (interactive) / 60s (batch)
  - Drop policies: none for persistent categories; buffer+retry with exponential backoff
  - DLQ: per-stage topic with 7d retention; idempotent processors retry up to 10x

- Idempotency keys:
  - event.id + event.name + event.version

See taxonomy v1 in `ops/event-dag/event_taxonomy.yml` for the authoritative partition map.
