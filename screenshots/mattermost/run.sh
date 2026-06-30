#!/bin/bash
# Orchestrates the Mattermost screenshot capture end to end:
#   1. brings up the Mattermost container
#   2. bootstraps it (admin/team/bot/token/channel/test user) -> .bootstrap.json
#   3. starts the pinned netclaw daemon against it, with inference pointed at
#      an OpenAI-compatible endpoint (spark2 by default)
#   4. posts an @netclaw message as the test user so the bot replies
#   5. drives Playwright (capture.mjs) to shoot the System Console + live thread
#   6. tears everything down
#
# The daemon uses `--network host` so its loopback control plane is reachable
# from the host, and Mattermost is reached at http://localhost:8065.
#
# Overridable env:
#   NETCLAW_IMAGE      default ghcr.io/netclaw-dev/netclaw:0.22.1
#   SPARK_ENDPOINT     OpenAI-compatible inference endpoint (default spark2)
#   SPARK_MODEL_ID     model id served there (matches the local netclaw instance)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

NETCLAW_IMAGE="${NETCLAW_IMAGE:-ghcr.io/netclaw-dev/netclaw:0.22.1}"
SPARK_ENDPOINT="${SPARK_ENDPOINT:-https://spark2.testlab.petabridge.net}"
SPARK_MODEL_ID="${SPARK_MODEL_ID:-Qwen/Qwen3.6-35B-A3B-FP8}"
SERVER="http://localhost:8065"

cleanup() {
  echo "==> Tearing down"
  docker rm -f netclaw-mm-shot >/dev/null 2>&1 || true
  docker compose -f docker-compose.mattermost.yml down -v >/dev/null 2>&1 || true
  rm -f .bootstrap.json
}
trap cleanup EXIT

echo "==> Bringing up Mattermost"
docker compose -f docker-compose.mattermost.yml up -d

echo "==> Bootstrapping Mattermost"
node bootstrap.mjs "$SERVER"

BOT_TOKEN="$(node -e "process.stdout.write(require('./.bootstrap.json').bot.token)")"
CHANNEL_ID="$(node -e "process.stdout.write(require('./.bootstrap.json').channel.id)")"

echo "==> Starting netclaw ($NETCLAW_IMAGE) against Mattermost + $SPARK_ENDPOINT"
docker rm -f netclaw-mm-shot >/dev/null 2>&1 || true
docker run -d --name netclaw-mm-shot --network host \
  -e NETCLAW_Daemon__Host=127.0.0.1 -e NETCLAW_Daemon__Port=5299 \
  -e NETCLAW_Daemon__ExposureMode=local -e NETCLAW_Daemon__DisableSelfUpdate=true \
  -e NETCLAW_Session__TurnLlmTimeoutSeconds=600 \
  -e NETCLAW_Session__FirstTokenTimeoutSeconds=600 \
  -e NETCLAW_Session__PrefillTimeoutSeconds=600 \
  -e NETCLAW_Mattermost__Enabled=true \
  -e NETCLAW_Mattermost__ServerUrl="$SERVER" \
  -e NETCLAW_Mattermost__BotToken="$BOT_TOKEN" \
  -e NETCLAW_Mattermost__DefaultChannelId="$CHANNEL_ID" \
  -e NETCLAW_Mattermost__MentionOnly=true \
  -e "NETCLAW_Mattermost__ChannelAudiences__${CHANNEL_ID}=team" \
  -e NETCLAW_Providers__spark__Type=openai-compatible \
  -e NETCLAW_Providers__spark__Endpoint="$SPARK_ENDPOINT" \
  -e NETCLAW_Models__Main__Provider=spark -e NETCLAW_Models__Main__ModelId="$SPARK_MODEL_ID" \
  -e NETCLAW_Models__Fallback__Provider=spark -e NETCLAW_Models__Fallback__ModelId="$SPARK_MODEL_ID" \
  -e NETCLAW_Models__Compaction__Provider=spark -e NETCLAW_Models__Compaction__ModelId="$SPARK_MODEL_ID" \
  "$NETCLAW_IMAGE"

echo "==> Waiting for daemon health"
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:5299/api/health/ready >/dev/null 2>&1 && break
  sleep 2
done

echo "==> Posting an @netclaw message as the test user"
TOKEN="$(curl -s -i -X POST "$SERVER/api/v4/users/login" -H 'Content-Type: application/json' \
  -d '{"login_id":"testuser","password":"TestUser1234!"}' | grep -i '^token:' | awk '{print $2}' | tr -d '\r')"
curl -s -X POST "$SERVER/api/v4/posts" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"channel_id\":\"$CHANNEL_ID\",\"message\":\"@netclaw hey! In one sentence, what are you and what can you help with?\"}" >/dev/null
echo "    posted; waiting for the bot to reply"
sleep 25

echo "==> Capturing screenshots (Playwright)"
node capture.mjs

echo "==> Done. Shots written to ../output/mattermost-*.png"
