#!/bin/bash
# Bring up a disposable Netclaw daemon (the released image) for verifying commands and
# for tape recordings. Docker is the only prerequisite. Never uses a host netclaw.
#
#   ./screenshots/stack.sh up [--fresh|--bare]  start the stack and wait until the daemon is healthy
#   ./screenshots/stack.sh reset [--fresh|--bare]  wipe ~/.netclaw and restart the daemon (inference cache is kept)
#   ./screenshots/stack.sh exec <cmd...>    run a command in the daemon container as the netclaw user
#   ./screenshots/stack.sh daemon-log [N]   last N lines (default 200) of the daemon's log file
#   ./screenshots/stack.sh logs [args]      docker compose logs for the stack (container stdout)
#   ./screenshots/stack.sh ps               list the stack's containers
#   ./screenshots/stack.sh down             remove containers, network and volumes
#
# States:
#   configured (default)  provider, model roles and the demo MCP server are added with the real
#                         CLI (provider add / model set / mcp add), as a user would after init
#   --fresh               no model config and an empty ~/.netclaw: first-run state for `netclaw init`
#   --bare                empty ~/.netclaw like --fresh, but the demo MCP server container is up; the
#                         tape seeds its own config (see screenshots/scripts/seed-*.sh)
#
# Examples:
#   COMPOSE_PROJECT_NAME=dr04 ./screenshots/stack.sh up
#   COMPOSE_PROJECT_NAME=dr04 ./screenshots/stack.sh exec netclaw doctor
#   COMPOSE_PROJECT_NAME=dr04 ./screenshots/stack.sh down
#
# Image: NETCLAW_VERSION=0.27.1 (default: src/version.json) or NETCLAW_IMAGE=<ref>.
# Inference: hermetic Ollama by default; set INFERENCE_BASE_URL + INFERENCE_MODEL_ID
# (env or screenshots/.env) to use an external OpenAI-compatible endpoint.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

state=configured
cmd="${1:-}"; [ "$#" -gt 0 ] && shift
if [ "${1:-}" = "--fresh" ]; then state=fresh; shift; fi
if [ "${1:-}" = "--bare" ]; then state=bare; shift; fi

wait_healthy() {
  local cid status i
  cid="$(dc "$state" ps -q netclawd)"
  for i in $(seq 1 90); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)"
    if [ "$status" = healthy ]; then
      echo "==> netclawd is healthy ($NETCLAW_IMAGE, project $COMPOSE_PROJECT_NAME, state $state, inference $INFERENCE_MODE)"
      return 0
    fi
    sleep 2
  done
  echo "stack: netclawd did not become healthy" >&2
  dc "$state" logs --tail 80 netclawd >&2 || true
  return 1
}

# Run the CLI in the daemon container as the netclaw user (no TTY).
nc() { dc all exec -T -u netclaw netclawd netclaw "$@"; }

# Initialize a configured daemon the way a user would, with the real CLI. The daemon
# restarts itself in-process after each config write, so wait for MCP to connect.
seed() {
  local i
  nc provider add inference "$NC_INFERENCE_TYPE" --endpoint "$NC_INFERENCE_ENDPOINT" >/dev/null
  for role in main fallback compaction; do
    nc model set "$role" inference "$NC_INFERENCE_MODEL" >/dev/null
  done
  nc mcp add --transport http demo-utilities http://127.0.0.1:8080/mcp >/dev/null
  # `netclaw init` also writes the Security section (no CLI command for it); add what the
  # wizard writes for the Personal posture so `netclaw doctor` passes the Security Policy check.
  dc all exec -T -u netclaw netclawd sh -c '
    f=/home/netclaw/.netclaw/config/netclaw.json
    jq ".Security = {DeploymentPosture: \"Personal\", ShellExecutionMode: \"HostAllowed\", StrictDefaults: true}" "$f" > "$f.tmp" && mv "$f.tmp" "$f"'
  for i in $(seq 1 45); do
    if nc status 2>/dev/null | grep -q 'mcp:demo-utilities: healthy'; then
      echo "==> seeded: provider inference ($NC_INFERENCE_TYPE), model $NC_INFERENCE_MODEL, MCP demo-utilities"
      return 0
    fi
    sleep 2
  done
  echo "stack: daemon did not report demo-utilities healthy after seeding" >&2
  nc status >&2 || true
  return 1
}

bring_up() {
  dc "$state" up -d --build --remove-orphans
  wait_healthy
  if [ "$state" = configured ]; then seed; fi
}

case "$cmd" in
  up)
    echo "==> Starting $NETCLAW_IMAGE as project $COMPOSE_PROJECT_NAME ($state, $INFERENCE_MODE inference)"
    bring_up
    ;;
  reset)
    dc all rm -sf netclawd >/dev/null
    docker volume rm "$(home_volume)" >/dev/null 2>&1 || true
    bring_up
    ;;
  daemon-log) dc all exec -T -u netclaw netclawd sh -c 'tail -n "${1:-200}" /home/netclaw/.netclaw/logs/daemon-*.log' _ "$@" ;;
  exec)
    [ "$#" -gt 0 ] || { echo "usage: stack.sh exec <command...>" >&2; exit 2; }
    tty_flag=(); [ -t 0 ] || tty_flag=(-T)
    dc all exec "${tty_flag[@]}" -u netclaw netclawd "$@"
    ;;
  logs) dc all logs "$@" ;;
  ps)   dc all ps "$@" ;;
  down) dc all down -v --remove-orphans ;;
  *)
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
