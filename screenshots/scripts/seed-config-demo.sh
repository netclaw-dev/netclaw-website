#!/bin/bash
# Seed for the `netclaw config` tape, on top of a completed `netclaw init` (Personal): a
# projects folder for the workspaces picker, one inbound webhook route, and the Claude Code
# skills folder as an external skill source. Neutral names throughout.
set -eu
# shellcheck source=lib-seed.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-seed.sh"

mkdir -p "$HOME/projects/website" "$HOME/projects/notes" "$HOME/projects/infra"
json_set Workspaces '{"Directory": "/home/netclaw/projects"}'
wait_daemon

netclaw webhooks set github-issues \
  --prompt "Triage the new GitHub issue and post a one-paragraph summary." \
  --secret demo-webhook-secret \
  --signature-header X-Hub-Signature-256 --signature-prefix "sha256=" \
  --events issues.opened,issues.closed >/dev/null
json_set Webhooks '{"Enabled": true}'
wait_daemon

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
echo "seeded: workspaces, webhook route github-issues, skill source claude-code"
