# Use-Case Matrix (skeleton)

| Use Case | Value | Domains | Events | MVP | KPI | Risk |
|---|---|---|---|---|---|---|
| ThunderBolt: Federated NAS | Private model tuning | bolt,crown,flow | ml.run.*, audit.* | Minimal trial on toy data | time-to-first-run | dataset privacy |
| ThunderGate: DID-gated coops | Sovereign data | gate,crown | ui.command.*, audit.* | Simple vault read | auth latency | policy bypass |
| ThunderFlow: Knowledge refinery | Faster answers | flow,link | ui.command.message_send | Single embed->link->answer | p95 latency | vector drift |
