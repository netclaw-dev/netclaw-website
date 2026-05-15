#!/bin/bash
# Seeds a realistic tool-approvals.json for screenshot capture.
# Called by the approvals VHS tape before recording.
set -eu

NETCLAW_HOME="${NETCLAW_HOME:-$HOME/.netclaw}"
CONFIG_DIR="$NETCLAW_HOME/config"
APPROVALS_FILE="$CONFIG_DIR/tool-approvals.json"

mkdir -p "$CONFIG_DIR"

# Clean up any existing approvals and quarantine files
rm -f "$APPROVALS_FILE" "$APPROVALS_FILE.v1.bak" "$APPROVALS_FILE.invalid"

cat > "$APPROVALS_FILE" << 'SEED'
{
  "version": 2,
  "audiences": {
    "personal": {
      "shell_execute": [
        { "verb": "git push", "directory": null },
        { "verb": "git pull", "directory": null },
        { "verb": "git remote", "directory": "/home/user/repos/netclaw/" },
        { "verb": "docker compose", "directory": "/home/user/repos/netclaw/" },
        { "verb": "npm run", "directory": "/home/user/repos/netclaw-website/" },
        { "verb": "ls", "directory": null }
      ],
      "mcp:demo-utilities:write_file": [
        { "verb": "write_file", "directory": "/home/user/repos/netclaw/" }
      ]
    },
    "team": {
      "shell_execute": [
        { "verb": "git pull", "directory": null },
        { "verb": "git status", "directory": null }
      ]
    }
  }
}
SEED

echo "Seeded $APPROVALS_FILE"
