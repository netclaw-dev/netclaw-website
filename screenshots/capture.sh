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

echo "==> Starting screenshot environment..."
docker compose -f "$COMPOSE_FILE" up -d --wait

echo "==> Waiting for netclawd health check..."
for i in $(seq 1 60); do
  if curl -sf http://127.0.0.1:5199/api/health/ready >/dev/null 2>&1; then
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
