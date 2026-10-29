#!/bin/bash
# Creates the neutral demo workspace used by the chat, approvals and reminder tapes: a small
# Git repository at /home/netclaw/projects/website (shared with the daemon by
# screenshots/compose/projects.yml) declared as the workspace root, so shell calls run
# inside the repository and approval prompts offer "This repository". Idempotent.
# Run inside the capture container.
set -eu

repo="$HOME/projects/website"
mkdir -p "$repo"
cd "$repo"
if [ ! -d .git ]; then
  git init -q -b main .
  git config user.name alice
  git config user.email alice@example.com
  printf '# website\n\nStatic marketing site. Edit files under src/.\n' > AGENTS.md
  mkdir -p src
  printf '<h1>Hello</h1>\n' > src/index.html
  git add .
  git commit -q -m "Initial commit"
fi

# Declare the workspace root. The daemon restarts itself when netclaw.json changes.
cfg="$NETCLAW_HOME/config/netclaw.json"
if [ "$(jq -r '.Workspaces.Directory // ""' "$cfg")" != "$HOME/projects" ]; then
  jq --arg d "$HOME/projects" '.Workspaces = {Directory: $d}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  sleep 8
fi
