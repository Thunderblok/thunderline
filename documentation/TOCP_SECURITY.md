# Thunderlink Transport Security Brief (formerly TOCP)

This document has moved. The canonical security battle plan for the consolidated transport layer now lives here:

- documentation/tocp/TOCP_SECURITY.md

Important notes for the transition period:
- The transport code is under `Thunderline.Thunderlink.Transport.*`. Legacy `Thunderline.TOCP.*` modules remain as thin shims.
- Telemetry prefix remains `[:tocp, *]` and metrics `tocp.*` to keep dashboards stable.
- Feature flags and simulator commands are unchanged: `:tocp`, `:tocp_presence_insecure`, `mix tocp.sim.run`.

Please maintain and review security posture updates in the canonical file above to avoid drift.
