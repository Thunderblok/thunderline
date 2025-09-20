# SECURITY (unikernel prototype)

- Attack surface: single HTTP listener, no shell, read-only FS
- Syscalls: minimal set (network, time)
- Network: egress deny by default; allowlist MCP + Postgres (read-only)
- Auth: DID/JWT verification at edge; signed configs
