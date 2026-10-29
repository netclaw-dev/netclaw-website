#!/bin/bash
# Seed for the provider and model manager tapes: three providers with neutral names and all three
# model roles assigned, written with the real CLI the way a user would after init.
#
#   my-ollama    ollama             the stack's local Ollama (reachable)
#   lab-llama    openai-compatible  http://llm.example.internal:8081, answered by the stack's
#                                   forwarder (compose/forwarder.yml) when INFERENCE_UPSTREAM is set,
#                                   unreachable otherwise
#   my-deepseek  deepseek           a dummy key, so the provider can't authenticate
#
# Also writes the Security and Identity sections `netclaw init` writes, so the config is complete.
# Needs an empty ~/.netclaw (`# stack: fresh` or `# stack: bare`).
set -eu
# shellcheck source=lib-seed.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-seed.sh"

netclaw provider add my-ollama ollama --endpoint http://127.0.0.1:11434 >/dev/null
netclaw provider add lab-llama openai-compatible --endpoint "${LAB_LLAMA_ENDPOINT:-http://llm.example.internal:8081}" >/dev/null
netclaw provider add my-deepseek deepseek --api-key sk-demo-0000 >/dev/null

# The OpenAI-compatible type label is long enough to push the model manager's columns out of line,
# so lab-llama stays out of the role table.
netclaw model set main my-deepseek deepseek-chat >/dev/null
netclaw model set fallback my-ollama qwen2:0.5b >/dev/null
netclaw model set compaction my-ollama qwen2:0.5b >/dev/null

json_set Security '{"DeploymentPosture": "Personal", "ShellExecutionMode": "HostAllowed", "StrictDefaults": true}'
json_set Tools '{"ShellMode": "HostAllowed"}'
json_set Identity '{"AgentName": "Netclaw", "CommunicationStyle": "Concise & casual", "UserTimezone": "Etc/UTC", "UserName": "alice"}'
wait_daemon
echo "seeded: providers my-ollama, lab-llama, my-deepseek; roles main (my-deepseek), fallback and compaction (my-ollama)"
