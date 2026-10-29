#!/bin/bash
# Seed for the channel audiences screen: enables a Mattermost adapter with three channels and a mix
# of audiences, pointed at the API fixture (mock-mattermost.py, which the tape starts first). The
# adapter can't actually connect, which only affects `netclaw status`, not the config screen.
set -eu
# shellcheck source=lib-seed.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-seed.sh"

netclaw secrets set Mattermost.BotToken demo-bot-token-0000 >/dev/null
json_set Mattermost '{
  "Enabled": true,
  "ServerUrl": "http://127.0.0.1:8065",
  "AllowDirectMessages": true,
  "AllowedChannelIds": ["c1a5s7i9s3t0a8n2t6b4o1t5k7", "c2o8p4s6r1o9o3m5d7e0m2o4k6", "c3l9u5n1c7h2t4a6b8l0e1d3k5"],
  "ChannelAudiences": {
    "c1a5s7i9s3t0a8n2t6b4o1t5k7": "Team",
    "c2o8p4s6r1o9o3m5d7e0m2o4k6": "Team",
    "c3l9u5n1c7h2t4a6b8l0e1d3k5": "Public"
  }
}'
sleep 5
echo "seeded: Mattermost adapter with three channels"
