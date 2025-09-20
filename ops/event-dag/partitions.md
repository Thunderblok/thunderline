# Partitions & Backpressure Policy

- Partition keys by event type:
  - link/ui.command.* -> channel_id (stable ordering per channel)
  - bolt/ml.run.* -> trial_id (isolate per trial)
  - crown/audit.* -> actor_id (coalesce actor streams)

- Partition counts:
  - Dev: 4 partitions per processor by default
  - Prod: 32–128 depending on throughput; scale by lag SLO

- Backpressure:
  - Max lag SLO: 2s (interactive) / 60s (batch)
  - Drop policies: none for persistent categories; buffer+retry with exponential backoff
  - DLQ: per-stage topic with 7d retention; idempotent processors retry up to 10x

- Idempotency keys:
  - event.id + event.name + event.version
