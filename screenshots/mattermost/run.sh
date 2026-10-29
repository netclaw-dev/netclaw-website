#!/bin/bash
# Regenerate the Mattermost screenshots, entirely in containers (Docker is the only
# prerequisite): Mattermost, the released netclaw daemon and Playwright share one
# compose network. Needs real inference so the bot can answer:
#
#   INFERENCE_BASE_URL=http://llm.example.internal:8080 INFERENCE_MODEL_ID=<id> \
#     ./screenshots/mattermost/run.sh
#
# Landing-page approval prompt (public/assets/approval-prompt.png) needs no model: set
# SCRIPTED_APPROVAL=1 and a scripted endpoint (scripted-llm.mjs) requests one demo-utilities http_fetch call
# (SCRIPTED_TOOL=shell for a shell_execute call instead);
# the run then captures the prompt with its buttons, framed by frame-approval.mjs, into OUT_DIR.
#
# (or put INFERENCE_UPSTREAM and INFERENCE_UPSTREAM_MODEL in screenshots/.env, gitignored). Other knobs:
#   COMPOSE_PROJECT_NAME  prefix for this run; "-mm" is appended (default netclaw-shots-mm)
#   NETCLAW_VERSION / NETCLAW_IMAGE   daemon image (default: src/version.json)
#   OUT_DIR               where PNGs go (default screenshots/output)
#   REPLY_TIMEOUT_SECONDS how long to wait for the bot's reply (default 300)
#
# Steps: compose up Mattermost -> bootstrap (admin, team, bot, channel, test user) ->
# start netclawd -> store the bot token as an encrypted secret and enable the Mattermost
# channel -> post an @netclaw message as the test user and wait for the reply ->
# Playwright captures -> tear everything down. Exits non-zero on any failure.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-netclaw-shots}-mm"
export COMPOSE_PROJECT_NAME
# shellcheck source=../lib.sh
. "$HERE/../lib.sh"

if [ -n "${SCRIPTED_APPROVAL:-}" ]; then
  export NC_INFERENCE_TYPE=openai-compatible NC_INFERENCE_ENDPOINT=http://scriptedllm:8080/v1 NC_INFERENCE_MODEL=demo-model
elif [ "$INFERENCE_MODE" = relay ]; then
  # This flow runs on its own compose network without the forwarder, and no frame shows the
  # daemon's configuration, so the daemon talks to the upstream directly.
  export NC_INFERENCE_ENDPOINT="$INFERENCE_UPSTREAM" NC_INFERENCE_MODEL="$INFERENCE_UPSTREAM_MODEL"
elif [ "$INFERENCE_MODE" != external ]; then
  echo "mattermost: set INFERENCE_UPSTREAM (or INFERENCE_BASE_URL and INFERENCE_MODEL_ID); the bot needs a real model to answer" >&2
  exit 2
fi

OUT_DIR="${OUT_DIR:-$SHOTS_DIR/output}"
mkdir -p "$OUT_DIR"
export CAPTURE_OUT_DIR="$(cd "$OUT_DIR" && pwd)"
BOOTSTRAP=".bootstrap.${COMPOSE_PROJECT_NAME}.json"

mm()  { docker compose -f "$HERE/docker-compose.mattermost.yml" "$@"; }
pw()  { mm run --rm --no-deps -T playwright "$@"; }
nc()  { mm exec -T -u netclaw netclawd netclaw "$@"; }

cleanup() {
  if [ -n "${KEEP_STACK:-}" ]; then echo "==> KEEP_STACK set: leaving project $COMPOSE_PROJECT_NAME running"; return; fi
  echo "==> Tearing down project $COMPOSE_PROJECT_NAME"
  mm --profile scripted --profile tools down -v --remove-orphans >/dev/null 2>&1 || true
  rm -f "$HERE/$BOOTSTRAP"
}
trap cleanup EXIT

echo "==> Bringing up Mattermost (${MATTERMOST_IMAGE:-mattermost/mattermost-preview:11.7.7}) and building the Playwright image ($PLAYWRIGHT_VERSION)"
mm up -d mattermost
mm build playwright
if [ -n "${SCRIPTED_APPROVAL:-}" ]; then
  export SCRIPTED_TOOL="${SCRIPTED_TOOL:-mcp}"   # mcp (default) or shell
  mm --profile scripted up -d --build scriptedllm mcp-demo
fi

echo "==> Bootstrapping Mattermost"
pw node /work/bootstrap.mjs http://mattermost:8065

BOT_TOKEN="$(pw node -p "require('/work/$BOOTSTRAP').bot.token")"
CHANNEL_ID="$(pw node -p "require('/work/$BOOTSTRAP').channel.id")"

echo "==> Starting netclawd ($NETCLAW_IMAGE), models via NETCLAW_Models__Definitions/Roles env"
mm up -d --wait netclawd
mm up -d callbackfwd

echo "==> Storing the bot token as an encrypted secret and enabling the Mattermost channel"
nc secrets set Mattermost.BotToken "$BOT_TOKEN" >/dev/null
# The scripted approval run needs shell_execute, which the "team" audience doesn't get.
AUDIENCE="${CHANNEL_AUDIENCE:-$([ -n "${SCRIPTED_APPROVAL:-}" ] && echo personal || echo team)}"
mm exec -T -u netclaw -e SERVER=http://mattermost:8065 -e CH="$CHANNEL_ID" -e AUD="$AUDIENCE" netclawd sh -c '
  f=/home/netclaw/.netclaw/config/netclaw.json
  [ -f "$f" ] || echo "{}" > "$f"
  jq --arg s "$SERVER" --arg c "$CH" ".configVersion = 1
    | .Security = {DeploymentPosture: \"Personal\", ShellExecutionMode: \"HostAllowed\", StrictDefaults: true}
    | .Mattermost = {Enabled: true, ServerUrl: \$s, CallbackUrl: \"http://netclawd:5299/api/mattermost/actions\", DefaultChannelId: \$c, MentionOnly: true, ChannelAudiences: {(\$c): \$a}}" --arg a "$AUD" \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"'

echo "==> Waiting for the Mattermost channel to connect"
connected=0
for _ in $(seq 1 45); do
  if mm exec -T -u netclaw netclawd sh -c 'cat /home/netclaw/.netclaw/logs/daemon-*.log' 2>/dev/null \
      | grep -i 'mattermost' | grep -iE 'connected|started' | tail -n 3 | grep -q .; then connected=1; break; fi
  sleep 2
done
if [ "$connected" -ne 1 ]; then
  echo "mattermost: netclawd never reported a Mattermost connection" >&2
  mm exec -T -u netclaw netclawd sh -c 'grep -i mattermost /home/netclaw/.netclaw/logs/daemon-*.log | tail -n 20' >&2 || true
  exit 1
fi
mm exec -T -u netclaw netclawd sh -c 'grep -i mattermost /home/netclaw/.netclaw/logs/daemon-*.log | tail -n 5'

if [ -n "${SCRIPTED_APPROVAL:-}" ] && [ "$SCRIPTED_TOOL" = mcp ]; then
  echo "==> Registering the demo MCP server and gating its tools behind approval"
  nc mcp add --transport http demo-utilities http://mcp-demo:8080/mcp >/dev/null
  mm exec -T -u netclaw netclawd sh -c '
    f=/home/netclaw/.netclaw/config/netclaw.json
    jq ".Tools.AudienceProfiles.Personal.ApprovalPolicy.McpServerDefaults[\"demo-utilities\"] = \"Approval\"" "$f" > "$f.tmp" && mv "$f.tmp" "$f"'
  sleep 12   # the daemon restarts itself when netclaw.json changes
  for _ in $(seq 1 30); do nc status 2>/dev/null | grep -q 'mcp:demo-utilities: healthy' && break; sleep 2; done
fi
if [ -n "${SCRIPTED_APPROVAL:-}" ]; then
  # A Git repository for the shell call to run in, so the prompt looks like real project work.
  mm exec -T -u netclaw netclawd sh -c '
    mkdir -p ~/projects/website && cd ~/projects/website && git init -q -b main . \
      && git config user.name alice && git config user.email alice@example.com \
      && echo "# website" > README.md && git add . && git commit -q -m "Initial commit" \
      && git remote add origin git@example.com:acme/website.git'
  echo "==> Capturing the approval prompt"
  pw node /work/approval.mjs || {
    echo "==> approval capture failed; scripted endpoint and daemon logs follow" >&2
    mm logs --tail 20 scriptedllm >&2 || true
    mm exec -T -u netclaw netclawd sh -c 'tail -n 40 /home/netclaw/.netclaw/logs/daemon-*.log' >&2 || true
    exit 1
  }
  echo "==> Done. approval-prompt.png written to $CAPTURE_OUT_DIR"
  exit 0
fi

echo "==> Posting an @netclaw message and waiting for the reply"
pw node /work/post-message.mjs

echo "==> Capturing screenshots (Playwright)"
pw node /work/capture.mjs

echo "==> Done. Shots written to $CAPTURE_OUT_DIR/mattermost-*.png"
