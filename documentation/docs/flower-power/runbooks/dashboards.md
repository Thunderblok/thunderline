# Runbook: Dashboards

Objective
Import and use the standard “Flower Power” Grafana dashboard to monitor federated training runs across tenants and federations.

Prerequisites
- Prometheus scraping your metrics (or OTLP → Prom bridge in place)
- Grafana reachable and a data source configured for Prometheus
- Dashboard JSON available at Thunderline/docs/flower-power/dashboards/flower-power.json

1) Import the dashboard
- In Grafana → Dashboards → Import → Upload JSON file
- Select: Thunderline/docs/flower-power/dashboards/flower-power.json
- Choose your Prometheus data source → Import

2) Dashboard variables
- federation_id: populated from label_values(fl_rounds_completed_total, federation_id)
- tenant: multi-select from label_values(fl_rounds_completed_total, tenant)

3) Panels overview
- Clients Joined (total)
- Rounds Completed (total)
- Rounds Completed Over Time (rate)
- Aggregate Duration p95
- Tokens per Second (Top 10 Clients)
- Watts per Token (if runner reports power)

4) Validation
- Start a federation and verify:
  - Rounds Completed increases; rate shows activity
  - Aggregate p95 displays non-zero values during rounds
  - Tokens/sec shows top clients (if client metrics are pushed)
- If federation disabled, control-plane metrics still show (events/rounds) depending on instrumentation

5) Customization tips
- Add panels: round p50, client join/drop rate, per-tenant breakdowns
- Add exemplars from traces (if your stack supports exemplar correlation)
- Add alert rules: e.g., “no rounds completed for X minutes” or “aggregate p95 > Y sec”

6) Troubleshooting
- Empty variables:
  - Ensure metrics flow and labels exist (federation_id, tenant)
- No data in panels:
  - Validate Prometheus target; check scrape errors
  - Confirm metric names match observability.md catalog
- Wrong time window:
  - Use a larger range (Last 6 hours/24 hours) during slow activity

7) Versioning / drift
- Keep the JSON under version control; changes should be PR-reviewed
- Consider provisioning this dashboard via Grafana provisioning for reproducible environments
