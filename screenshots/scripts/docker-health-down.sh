#!/bin/bash
# Remove the container docker-health-up.sh started (found by its label, so a container that merely
# shares the name is left alone). Safe to run when there is nothing to remove.
set -u
ids="$(docker ps -aq --filter "label=netclaw-docs-capture=docker-health")"
if [ -n "$ids" ]; then
  # shellcheck disable=SC2086
  docker rm -fv $ids >/dev/null
fi
echo "docker-health: cleaned up"
