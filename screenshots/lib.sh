#!/bin/bash
# Shared helpers for stack.sh and capture.sh. Source it, don't run it.
#
# Resolves, in order: ./screenshots/.env (gitignored), then defaults.
#   COMPOSE_PROJECT_NAME  isolates containers, network and volumes (default netclaw-shots)
#   NETCLAW_VERSION       release tag; default = documentedVersion in src/version.json
#   NETCLAW_IMAGE         full image reference; wins over NETCLAW_VERSION
#   INFERENCE_BASE_URL    external OpenAI-compatible endpoint (unset = hermetic Ollama)
#   INFERENCE_MODEL_ID    model id served there (required with INFERENCE_BASE_URL)
#   OLLAMA_MODEL          hermetic model (default qwen2:0.5b)
#   INFERENCE_UPSTREAM    base URL of a real OpenAI-compatible server (relay mode). Adds the forwarder
#                         (compose/forwarder.yml) that answers to http://llm.example.internal:8081
#                         inside the stack and rewrites the upstream's model id to `demo-model` in
#                         every response, so tapes get real answers while neither the real hostname
#                         nor the real model name reaches netclaw.json or a screenshot. Needs
#                         INFERENCE_UPSTREAM_MODEL (the id the upstream really serves). Ollama stays
#                         available alongside it, for the tapes that need a reachable local provider.

SHOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SHOTS_DIR/.." && pwd)"
BASE_COMPOSE="$PROJECT_ROOT/docker-compose.screenshots.yml"

if [ -f "$SHOTS_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SHOTS_DIR/.env"
  set +a
fi

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-netclaw-shots}"
export COMPOSE_PROGRESS="${COMPOSE_PROGRESS:-quiet}"   # set COMPOSE_PROGRESS=plain to see build/pull output
# Compose project names must be lowercase alphanumerics, '-' or '_'.
case "$COMPOSE_PROJECT_NAME" in
  *[!a-z0-9_-]* | "") echo "COMPOSE_PROJECT_NAME must match [a-z0-9_-]+ (got '$COMPOSE_PROJECT_NAME')" >&2; exit 2 ;;
esac

# Version: one source of truth (src/version.json) unless overridden.
if [ -z "${NETCLAW_IMAGE:-}" ]; then
  if [ -z "${NETCLAW_VERSION:-}" ]; then
    NETCLAW_VERSION="$(sed -n 's/.*"documentedVersion": *"\([^"]*\)".*/\1/p' "$PROJECT_ROOT/src/version.json")"
    [ -n "$NETCLAW_VERSION" ] || { echo "could not read documentedVersion from src/version.json" >&2; exit 2; }
  fi
  NETCLAW_IMAGE="ghcr.io/netclaw-dev/netclaw:${NETCLAW_VERSION}"
fi
export NETCLAW_IMAGE
export NETCLAW_VERSION="${NETCLAW_IMAGE##*:}"
export NETCLAW_IMAGE_TAG="$(printf '%s' "$NETCLAW_VERSION" | tr -c 'A-Za-z0-9_.-' '_')"

# Inference: three modes.
#   relay     INFERENCE_UPSTREAM set: real answers through the forwarder, neutral hostname and model
#   external  INFERENCE_BASE_URL set: a real endpoint written into netclaw.json as is
#   hermetic  neither: Ollama with a tiny model, no external network use
if [ -n "${INFERENCE_UPSTREAM:-}" ]; then
  : "${INFERENCE_UPSTREAM_MODEL:?INFERENCE_UPSTREAM_MODEL is required with INFERENCE_UPSTREAM (the model id the upstream serves)}"
  INFERENCE_UPSTREAM_HOST="${INFERENCE_UPSTREAM#*://}"; INFERENCE_UPSTREAM_HOST="${INFERENCE_UPSTREAM_HOST%%/*}"
  INFERENCE_BASE_URL="${INFERENCE_BASE_URL:-http://llm.example.internal:8081}"
  INFERENCE_MODEL_ID="${INFERENCE_MODEL_ID:-demo-model}"
  INFERENCE_MODE=relay
  export INFERENCE_UPSTREAM INFERENCE_UPSTREAM_HOST INFERENCE_UPSTREAM_MODEL INFERENCE_MODEL_ID
  export NC_INFERENCE_TYPE=openai-compatible
  export NC_INFERENCE_ENDPOINT="$INFERENCE_BASE_URL"
  export NC_INFERENCE_MODEL="$INFERENCE_MODEL_ID"
elif [ -n "${INFERENCE_BASE_URL:-}" ]; then
  : "${INFERENCE_MODEL_ID:?INFERENCE_MODEL_ID is required when INFERENCE_BASE_URL is set}"
  INFERENCE_MODE=external
  export NC_INFERENCE_TYPE=openai-compatible
  export NC_INFERENCE_ENDPOINT="$INFERENCE_BASE_URL"
  export NC_INFERENCE_MODEL="$INFERENCE_MODEL_ID"
else
  INFERENCE_MODE=hermetic
  export NC_INFERENCE_TYPE=ollama
  export NC_INFERENCE_ENDPOINT=http://127.0.0.1:11434
  export NC_INFERENCE_MODEL="${OLLAMA_MODEL:-qwen2:0.5b}"
fi

# Playwright image/module version: the one locked in package-lock.json.
if [ -z "${PLAYWRIGHT_VERSION:-}" ]; then
  PLAYWRIGHT_VERSION="$(grep -A1 '"node_modules/playwright":' "$PROJECT_ROOT/package-lock.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"
fi
export PLAYWRIGHT_VERSION

export HOST_UID="${HOST_UID:-$(id -u)}"
export HOST_GID="${HOST_GID:-$(id -g)}"

# compose_files <configured|bare|fresh|all>
#   bare:       like configured (demo MCP server container up) but stack.sh does not seed any config
#   configured: daemon with a provider, model roles and the demo MCP server
#   fresh:      daemon with no model config at all (first-run state for `netclaw init`)
#   all:        every overlay, for commands (exec/logs/down) that must see every service
compose_files() {
  local state="$1"
  local files=(-f "$BASE_COMPOSE")
  if [ "$INFERENCE_MODE" != external ]; then files+=(-f "$SHOTS_DIR/compose/ollama.yml"); fi
  if [ "$INFERENCE_MODE" = relay ]; then files+=(-f "$SHOTS_DIR/compose/forwarder.yml"); fi
  if [ "$state" != fresh ]; then files+=(-f "$SHOTS_DIR/compose/configured.yml" -f "$SHOTS_DIR/compose/skillserver.yml"); fi
  files+=(-f "$SHOTS_DIR/compose/projects.yml")
  if [ -n "${CAPTURE_HOST_DOCKER:-}" ]; then files+=(-f "$SHOTS_DIR/compose/docker-host.yml"); fi
  printf '%s\0' "${files[@]}"
}

# dc <state> <docker compose args...>
dc() {
  local state="$1"; shift
  local files=()
  while IFS= read -r -d '' f; do files+=("$f"); done < <(compose_files "$state")
  docker compose "${files[@]}" "$@"
}

home_volume() { printf '%s_netclaw-home' "$COMPOSE_PROJECT_NAME"; }
