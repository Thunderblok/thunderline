# Observability

This guide standardizes tracing and metrics for Thunderline + Flower, and provides a starter Grafana dashboard JSON.

Objectives
- End-to-end traces for federation lifecycle (start → rounds → aggregate → complete)
- Prometheus/OTLP metrics with stable names/labels
- Quick validation steps and troubleshooting

Stack
- OTLP Collector (receiver: grpc 4317/http 4318)
- Prometheus + Grafana (optional but recommended)
- Thunderline emits OTLP spans/metrics; federation (Flower) logs can be scraped or bridged

Configuration
- Thunderline env (set via Helm values):
  - OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
  - OTEL_EXPORTER_OTLP_HEADERS: (optional) authorization=Bearer <token>
- Labels/attributes (use consistently):
  - federation_id, round_num, client_id, tenant

Traces (span model)
- thunderline.federation.start
  - attrs: federation_id, tenant, rounds_total
- thunderline.round
  - attrs: federation_id, round_num, client_fraction, min_available
- thunderline.aggregate
  - attrs: federation_id, round_num
- thunderline.artifact.write
  - attrs: federation_id, round_num, artifact_uri, sha256
- thunderline.federation.complete
  - attrs: federation_id, rounds_total

Metrics (Prom/OTLP)
Counters
- fl_clients_joined_total{federation_id}
- fl_rounds_started_total{federation_id}
- fl_rounds_completed_total{federation_id}
- fl_aggregates_total{federation_id}
- fl_artifacts_written_total{federation_id}

Histograms/Summaries
- fl_aggregate_duration_seconds_bucket{federation_id}
- fl_round_duration_seconds_bucket{federation_id, round_num}

Gauges
- fl_tokens_per_second{federation_id, client_id}
- fl_power_watts{client_id} (optional; from runner probe)
- fl_watts_per_token{client_id} (derived)

Collector sanity checklist
- Port open and reachable from pods: curl -v http://otel-collector:4318/v1/metrics (HTTP mode) or check 4317 (gRPC)
- Spans appear in downstream (Tempo/Jaeger); metrics scraped/exported to Prometheus

Grafana starter dashboard
- See dashboards/flower-power.json for:
  - Join rate (fl_clients_joined_total)
  - Rounds completed over time (fl_rounds_completed_total)
  - Aggregate duration p50/p95
  - Tokens/sec (Top-N clients)
  - Optional watts/token (if runner reports power)

Validation steps
1) Deploy with OTLP endpoint set
2) Start a federation (dev or stage)
3) Confirm:
   - Spans exist with federation_id and round_num
   - Counts increment (rounds started/completed)
   - Aggregate duration histogram shows samples
4) If federation is disabled, skip Flower panels; only control-plane spans/metrics will appear

Troubleshooting
- No spans:
  - Check OTEL_EXPORTER_OTLP_ENDPOINT and headers
  - Confirm instrumentation not disabled (OTEL_DISABLED env not set to true)
- No metrics in Prometheus:
  - Ensure scrape config or OTLP → Prom bridge is working
  - Metric names/labels match the above catalog
- Missing federation_id labels:
  - Propagate labels in instrumentation binds for each span/metric update

Notes
- Derive watts/token in the collector or in application code if runner reports watts and total tokens.
- For multi-tenant clusters, add tenant label to all panels with templating for quick filtering.
