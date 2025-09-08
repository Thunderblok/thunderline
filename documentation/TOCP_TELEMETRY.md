# Thunderlink Transport Telemetry Specification (formerly TOCP)

This document has moved. The canonical telemetry spec for the consolidated transport layer now lives here:

- documentation/tocp/TOCP_TELEMETRY.md

Notes for readers during the transition:
- Telemetry prefix remains unchanged and should continue to use `[:tocp, *]` for compatibility with existing dashboards and exporters (metric names `tocp.*`).
- The code lives under `Thunderline.Thunderlink.Transport.*`; legacy `Thunderline.TOCP.*` modules remain as thin shims only.
- Simulator commands (`mix tocp.sim.run`, `mix tocp.dump.config`) and feature flags (`:tocp`, `:tocp_presence_insecure`) are unchanged.

If you are maintaining dashboards or alerts, please refer to the canonical spec above to avoid drift.
