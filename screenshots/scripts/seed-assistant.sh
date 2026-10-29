#!/bin/bash
# Seed for the tapes that need a working assistant (status, doctor, stats, sessions, chat): one
# OpenAI-compatible provider answered by the stack's forwarder (INFERENCE_UPSTREAM, see
# compose/forwarder.yml), all three model roles on it, and the demo MCP server.
#
# The model ID is the neutral name the forwarder presents (demo-model). It rewrites the upstream's
# real model id to that name in responses, and llama.cpp serves whatever model it has loaded
# regardless of the name in the request, so the real name never reaches netclaw.json or the screen.
#
# Also writes the Security and Identity sections `netclaw init` writes (Personal posture), so the
# config is complete and `netclaw doctor` has no failures. Needs an empty ~/.netclaw
# (`# stack: bare`, which brings up the demo MCP server container).
set -eu
# shellcheck source=lib-seed.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-seed.sh"

MODEL_ID="${ASSISTANT_MODEL_ID:-demo-model}"

netclaw provider add lab-llama openai-compatible --endpoint "${LAB_LLAMA_ENDPOINT:-http://llm.example.internal:8081}" >/dev/null
for role in main fallback compaction; do
  netclaw model set "$role" lab-llama "$MODEL_ID" >/dev/null
done
netclaw mcp add --transport http demo-utilities http://127.0.0.1:8080/mcp >/dev/null

json_set Security '{"DeploymentPosture": "Personal", "ShellExecutionMode": "HostAllowed", "StrictDefaults": true}'
json_set Tools '{"ShellMode": "HostAllowed"}'
json_set Identity '{"AgentName": "Netclaw", "CommunicationStyle": "Concise & casual", "UserTimezone": "Etc/UTC", "UserName": "alice"}'

for i in $(seq 1 45); do
  if netclaw status 2>/dev/null | grep -q 'mcp:demo-utilities: healthy'; then
    echo "seeded: provider lab-llama, model $MODEL_ID, MCP demo-utilities"
    exit 0
  fi
  sleep 2
done
echo "seed: demo-utilities did not report healthy" >&2
exit 1
