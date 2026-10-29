#!/bin/bash
# ONE coherent demo install for every status-like capture: status, doctor, stats, sessions, model,
# provider, skill list, webhooks list, reminder list, the config dashboard and its sub-screens.
# Because they all start from this script, no two images disagree about what is installed.
#
#   providers   lab-llama (OpenAI-compatible, answered by the stack's forwarder), my-ollama
#               (the stack's local Ollama), my-deepseek (dummy key)
#   roles       main on lab-llama / demo-model, fallback and compaction on my-ollama / qwen2:0.5b
#   MCP         demo-utilities (the stack's demo server)
#   skills      two local, two from the corp-skills feed, one external source (claude-code)
#   webhooks    github-issues and deploy-notify
#   reminders   daily-uptime-check and weekly-report
#   workspaces  /home/netclaw/projects with website (a Git repo), notes and infra
#   search      DuckDuckGo, set the way the Search screen saves it
#
# Run inside the capture container against an empty ~/.netclaw (`# stack: bare`, which also brings
# up the demo MCP and skill servers). Prints "seeded: demo install" when done.
set -eu
here="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib-seed.sh
. "$here/lib-seed.sh"

netclaw provider add lab-llama openai-compatible --endpoint "${LAB_LLAMA_ENDPOINT:-http://llm.example.internal:8081}" >/dev/null
netclaw provider add my-ollama ollama --endpoint http://127.0.0.1:11434 >/dev/null
netclaw provider add my-deepseek deepseek --api-key sk-demo-0000 >/dev/null
netclaw model set main lab-llama "${ASSISTANT_MODEL_ID:-demo-model}" >/dev/null
netclaw model set fallback my-ollama qwen2:0.5b >/dev/null
netclaw model set compaction my-ollama qwen2:0.5b >/dev/null
netclaw mcp add --transport http demo-utilities http://127.0.0.1:8080/mcp >/dev/null

# The sections `netclaw init` writes for a Personal install, plus a Search backend.
json_set Security '{"DeploymentPosture": "Personal", "ShellExecutionMode": "HostAllowed", "StrictDefaults": true}'
json_set Tools '{"ShellMode": "HostAllowed"}'
json_set Identity '{"AgentName": "Netclaw", "CommunicationStyle": "Concise & casual", "UserTimezone": "Etc/UTC", "UserName": "alice"}'
json_set Search '{"Backend": "duckduckgo"}'
wait_daemon

# Workspaces: the website repository plus two plain folders for the picker.
bash "$here/seed-projects.sh"
mkdir -p "$HOME/projects/notes" "$HOME/projects/infra"
wait_daemon

# Skills: local skills, the corp-skills feed, one external source.
bash "$here/seed-skills.sh"
mkdir -p "$HOME/.claude/skills/release-notes"
cat > "$HOME/.claude/skills/release-notes/SKILL.md" <<'SKILL'
---
name: release-notes
description: Draft release notes from a list of merged pull requests.
---

Group the merged pull requests by area and write one sentence per change.
SKILL
netclaw skill source add claude-code --well-known claude-code >/dev/null
wait_daemon
netclaw skill sync >/dev/null

# Two inbound webhook routes.
netclaw webhooks set github-issues \
  --prompt "Triage the new GitHub issue and post a one-paragraph summary." \
  --secret demo-webhook-secret \
  --signature-header X-Hub-Signature-256 --signature-prefix "sha256=" \
  --events issues.opened,issues.closed --audience personal >/dev/null
netclaw webhooks set deploy-notify \
  --prompt "A deployment finished. Summarize the event payload in one line." \
  --secret demo-webhook-secret --audience personal >/dev/null
json_set Webhooks '{"Enabled": true}'
wait_daemon

# Two reminders.
bash "$here/seed-reminders.sh"

for i in $(seq 1 45); do
  if netclaw status 2>/dev/null | grep -q 'mcp:demo-utilities: healthy'; then
    echo "seeded: demo install"
    exit 0
  fi
  sleep 2
done
echo "seed: demo-utilities did not report healthy" >&2
exit 1
