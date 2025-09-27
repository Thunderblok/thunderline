#!/usr/bin/env python3
"""Minimal Cerebros bridge stub for Thunderline releases.

Reads bridge payloads from STDIN, determines the requested operation from the
`CEREBROS_BRIDGE_OP` environment variable, and optionally forwards the payload
to a remote runner service specified by `CEREBROS_REMOTE_URL`.

When no remote service is configured, the script simply echoes the payload back
with `status="ok"` so that Thunderline can proceed in demo mode.
"""

import json
import os
import sys
import urllib.error
import urllib.request


def post_json(url: str, payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:  # nosec: B310 demo only
        body = resp.read().decode("utf-8")
        if not body:
            return {"status": "ok"}
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return {"status": "ok", "raw": body}


def main() -> int:
    raw_input = sys.stdin.read()

    try:
        payload = json.loads(raw_input) if raw_input.strip() else {}
    except json.JSONDecodeError:
        payload = {}

    op = os.environ.get("CEREBROS_BRIDGE_OP", payload.get("op", "unknown"))
    body = payload.get("payload", {})

    remote_base = os.environ.get("CEREBROS_REMOTE_URL")

    if remote_base:
        endpoints = {
            "start_run": f"{remote_base.rstrip('/')}/bridge/start",
            "record_trial": f"{remote_base.rstrip('/')}/bridge/record",
            "finalize_run": f"{remote_base.rstrip('/')}/bridge/finalize",
        }
        url = endpoints.get(op, f"{remote_base.rstrip('/')}/bridge/ops")

        try:
            result = post_json(url, {"run_id": body.get("run_id"), **body})
        except urllib.error.URLError as exc:  # pragma: no cover - network failures
            result = {"status": "error", "reason": str(exc)}
    else:
        result = {"status": "ok", "op": op, "echo": body}

    sys.stdout.write(json.dumps(result))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
