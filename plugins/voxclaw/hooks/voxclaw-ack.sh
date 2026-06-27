#!/usr/bin/env bash
# UserPromptSubmit hook. When the user sends a new message, notify VoxClaw
# that the previous response from this project has been acknowledged — no
# need to keep reading it aloud. All failure paths are silent.

set -euo pipefail

VOXCLAW_PORT="${VOXCLAW_PORT:-4140}"

payload="$(cat)"

printf '%s' "$payload" | python3 -c '
import json
import os
import sys
import urllib.request

port = sys.argv[1] if len(sys.argv) > 1 else "4140"

try:
    data = json.loads(sys.stdin.read() or "{}")
except json.JSONDecodeError:
    sys.exit(0)

project_id = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
if not project_id:
    sys.exit(0)

# session_id uniquely identifies this agent within the project, so acking a new
# prompt only stops THIS agent — not another agent sharing the same directory.
agent_id = data.get("session_id") or None

ack_url = f"http://localhost:{port}/ack"
payload = {"project_id": project_id}
if agent_id:
    payload["agent_id"] = agent_id
body = json.dumps(payload).encode()

req = urllib.request.Request(
    ack_url,
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    urllib.request.urlopen(req, timeout=1.0).read()
except Exception:
    pass
' "$VOXCLAW_PORT" || true

exit 0
