#!/usr/bin/env bash
# Finish wiring netclaw after provision.sh: apply the IDs from .env, add the
# inference provider, set the channel audience, and store the bot token in
# netclaw's encrypted vault. Run it once.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .bot-token ] || { echo "Run ./provision.sh first." >&2; exit 1; }
set -a; . ./.env; set +a
: "${MM_CHANNEL_ID:?missing from .env}" "${INFERENCE_BASE_URL:?missing from .env}" "${INFERENCE_MODEL_ID:?missing from .env}"

nc() { docker compose exec -T netclaw netclaw "$@"; }

# Recreate netclaw so it picks up MM_CHANNEL_ID and MM_USER_ID from .env.
docker compose up -d --wait netclaw

nc provider add main openai-compatible --endpoint "$INFERENCE_BASE_URL"
nc model set main main "$INFERENCE_MODEL_ID"

# Personal posture (what `netclaw init` writes for one operator) and a personal
# audience for the private channel, so the agent can ask to run shell commands.
# Each command still needs your approval. Editing netclaw.json makes the daemon
# restart itself.
docker compose exec -T -e CH="$MM_CHANNEL_ID" netclaw sh -c '
  f=$HOME/.netclaw/config/netclaw.json
  jq --arg c "$CH" "
    .Security.DeploymentPosture = \"Personal\"
    | .Security.ShellExecutionMode = \"HostAllowed\"
    | .Security.StrictDefaults = true
    | .Tools.ShellMode = \"HostAllowed\"
    | .Mattermost.ChannelAudiences[\$c] = \"personal\"" "$f" > /tmp/netclaw.json
  cat /tmp/netclaw.json > "$f"; rm -f /tmp/netclaw.json'

# Token goes in over stdin, so it never appears in a process list or in .env.
docker compose exec -T netclaw sh -c 'netclaw secrets set Mattermost.BotToken "$(cat)"' < .bot-token

# Secrets changes need a restart.
docker compose restart netclaw
docker compose up -d --wait netclaw
nc status
