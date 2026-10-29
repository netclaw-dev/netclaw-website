#!/bin/bash
# Start a release container for docker-health.tape through the host's Docker and wait until Docker
# reports it healthy, then give it the name the docs use. Runs inside the capture container, which
# has the host's docker socket for this tape only (compose/docker-host.yml).
#
# It never touches a container it didn't start: if something on the host is already called
# `netclaw`, it stops instead of removing it. The tape removes its own container afterwards by label
# (docker-health-down.sh).
set -eu

IMAGE="${NETCLAW_IMAGE:-ghcr.io/netclaw-dev/netclaw:0.28.2}"
TMP_NAME="${COMPOSE_PROJECT_NAME:-netclaw-shots}-docker-health"
LABEL="netclaw-docs-capture=docker-health"

if docker inspect netclaw >/dev/null 2>&1; then
  echo "docker-health: a container named 'netclaw' already exists on this host. Stop it or remove it first." >&2
  exit 1
fi

docker run -d --name "$TMP_NAME" --label "$LABEL" --stop-timeout 60 \
  -e NETCLAW_Daemon__DisableSelfUpdate=true "$IMAGE" >/dev/null

for _ in $(seq 1 60); do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$TMP_NAME")"
  if [ "$status" = healthy ]; then
    docker rename "$TMP_NAME" netclaw
    echo "container is healthy"
    exit 0
  fi
  sleep 2
done
echo "docker-health: container never became healthy" >&2
exit 1
