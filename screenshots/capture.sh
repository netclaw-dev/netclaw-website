#!/bin/bash
# Record VHS tapes inside the capture container against a disposable released daemon.
# Docker is the only prerequisite; the host netclaw is never used.
#
#   ./screenshots/capture.sh            run every tape
#   ./screenshots/capture.sh status     run one tape (screenshots/tapes/status.tape)
#   ./screenshots/capture.sh status doctor
#
# Output goes to screenshots/output/ (override: OUT_DIR=/some/dir), owned by you.
# A tape starts from a clean ~/.netclaw. A tape whose first line comments contain
# `# stack: fresh` runs against the first-run state (no model config); `# stack: bare` is the
# same empty home plus the demo MCP server container, for tapes that seed their own config;
# all others run against the configured daemon. Exits non-zero if any tape fails; the stack is always
# torn down. Image, project name and inference settings: see stack.sh and README.md.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OUT_DIR="${OUT_DIR:-$SHOTS_DIR/output}"
mkdir -p "$OUT_DIR"
export CAPTURE_OUT_DIR="$(cd "$OUT_DIR" && pwd)"

tapes=("$@")
if [ "${#tapes[@]}" -eq 0 ]; then
  for f in "$SHOTS_DIR"/tapes/*.tape; do tapes+=("$(basename "$f" .tape)"); done
fi

cleanup() {
  echo "==> Tearing down project $COMPOSE_PROJECT_NAME"
  "$SHOTS_DIR/stack.sh" down >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Capturing against $NETCLAW_IMAGE ($INFERENCE_MODE inference), output $CAPTURE_OUT_DIR"

failed=()
for name in "${tapes[@]}"; do
  tape="$SHOTS_DIR/tapes/$name.tape"
  [ -f "$tape" ] || { echo "capture: no such tape: $name" >&2; exit 2; }
  state=configured
  if grep -qE '^#[[:space:]]*stack:[[:space:]]*fresh' "$tape"; then state=fresh; fi
  if grep -qE '^#[[:space:]]*stack:[[:space:]]*bare' "$tape"; then state=bare; fi

  # `# image: 0.27.0` runs this one tape against another release (update-check.tape needs an
  # install that is genuinely one version behind). `# host-docker: true` lets the tape drive the
  # host's Docker through its socket (docker-health.tape).
  image_version="$(sed -nE 's/^#[[:space:]]*image:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$tape" | head -1)"
  host_docker=""
  if grep -qE '^#[[:space:]]*host-docker:[[:space:]]*true' "$tape"; then host_docker=1; fi

  echo "==> $name: clean daemon ($state)"
  if ! (
    if [ -n "$image_version" ]; then
      unset NETCLAW_IMAGE
      export NETCLAW_VERSION="$image_version"
      # shellcheck source=lib.sh
      . "$SHOTS_DIR/lib.sh"
      echo "==> $name: this tape pins image $NETCLAW_IMAGE"
    fi
    if [ -n "$host_docker" ]; then export CAPTURE_HOST_DOCKER=1; fi
    # reset = wipe ~/.netclaw and (re)start the daemon; also creates the stack on first use.
    "$SHOTS_DIR/stack.sh" reset $([ "$state" != configured ] && echo "--$state") &&
      dc "$state" run --rm --no-deps -T --build capture "$name"
  ); then
    failed+=("$name")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "capture: FAILED tapes: ${failed[*]}" >&2
  exit 1
fi
echo "==> Done: ${tapes[*]}"
