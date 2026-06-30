#!/bin/bash
# Orchestrates the screenshot capture pipeline.
# Brings up Docker Compose environment, runs VHS tapes, tears down.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAPES_DIR="$SCRIPT_DIR/tapes"
OUTPUT_DIR="$SCRIPT_DIR/output"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.screenshots.yml"

# Use a clean netclaw home for the init wizard so we get first-run screens
export NETCLAW_SCREENSHOT_HOME="$SCRIPT_DIR/.netclaw-screenshot-home"

mkdir -p "$OUTPUT_DIR"

NETCLAW_PORT="${NETCLAW_PORT:-5299}"

# Pin the daemon image to the version the docs are written against (src/version.json),
# unless the caller already set NETCLAW_VERSION or NETCLAW_IMAGE. Keeps screenshots
# in lockstep with the documented release.
if [ -z "${NETCLAW_VERSION:-}" ] && [ -f "$PROJECT_ROOT/src/version.json" ]; then
  NETCLAW_VERSION="$(node -e "process.stdout.write(require('$PROJECT_ROOT/src/version.json').documentedVersion)" 2>/dev/null || true)"
fi
export NETCLAW_VERSION
echo "==> Capturing against netclaw ${NETCLAW_IMAGE:-ghcr.io/netclaw-dev/netclaw:${NETCLAW_VERSION:-0.22.1}}"

echo "==> Starting screenshot environment (building images if needed)..."
docker compose -f "$COMPOSE_FILE" up -d --build --wait

echo "==> Waiting for netclawd health check on port $NETCLAW_PORT..."
for i in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:${NETCLAW_PORT}/api/health/ready" >/dev/null 2>&1; then
    echo "    netclawd is healthy."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "    ERROR: netclawd did not become healthy in time."
    docker compose -f "$COMPOSE_FILE" logs netclawd
    docker compose -f "$COMPOSE_FILE" down
    exit 1
  fi
  sleep 2
done

echo "==> Running VHS tapes..."
for tape in "$TAPES_DIR"/*.tape; do
  if [ -f "$tape" ]; then
    echo "    Running: $(basename "$tape")"
    vhs "$tape" || echo "    WARNING: $(basename "$tape") failed"
  fi
done

echo "==> Tearing down environment..."
docker compose -f "$COMPOSE_FILE" down

echo "==> Screenshots saved to: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.png 2>/dev/null || echo "    No PNG files generated."
