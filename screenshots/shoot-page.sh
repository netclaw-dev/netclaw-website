#!/bin/bash
# Screenshot a page of the locally built docs site (dist/) in the Playwright container.
#
#   npm run build
#   ./screenshots/shoot-page.sh cli/status            -> docs-logs/screenshots/cli-status.png
#   SCREENSHOT_OUT=/some/dir ./screenshots/shoot-page.sh cli/status
#   SCREENSHOT_BASE_URL=http://host.docker.internal:4321 ./screenshots/shoot-page.sh cli/status
#       (a dev server started with `npm run dev -- --host 0.0.0.0`)
#
# Runs scripts/screenshot-page.mjs with the same pinned Playwright image as the
# Mattermost capture. No host browser or host node needed beyond building the site.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "$#" -ge 1 ] || { echo "usage: shoot-page.sh <page-slug>   e.g. cli/status" >&2; exit 2; }

OUT="${SCREENSHOT_OUT:-$PROJECT_ROOT/docs-logs/screenshots}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

IMAGE="netclaw-docs-playwright:$PLAYWRIGHT_VERSION"
docker build -q -t "$IMAGE" --build-arg "PLAYWRIGHT_VERSION=$PLAYWRIGHT_VERSION" "$SHOTS_DIR/playwright" >/dev/null

env_args=(-e SCREENSHOT_OUT=/out)
[ -z "${SCREENSHOT_BASE_URL:-}" ] || env_args+=(-e "SCREENSHOT_BASE_URL=$SCREENSHOT_BASE_URL")

docker run --rm --user "$HOST_UID:$HOST_GID" --add-host host.docker.internal:host-gateway \
  "${env_args[@]}" -v "$PROJECT_ROOT:/site:ro" -v "$OUT:/out" \
  "$IMAGE" node /site/scripts/screenshot-page.mjs "$1" | sed "s#^/out#$OUT#"
