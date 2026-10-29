#!/bin/bash
# Runs inside the capture container. Arguments are tape names (without .tape).
# Each tape is recorded as the unprivileged `netclaw` user (same as the daemon), into a
# staging dir, then copied to /out owned by the invoking host user.
# Exits non-zero as soon as any tape fails or does not produce a file it declares.
set -uo pipefail

STAGE=/work/screenshots/output
OUT=/out
HOST_UID="${HOST_UID:-0}"
HOST_GID="${HOST_GID:-0}"

if [ "$#" -eq 0 ]; then
  echo "capture: no tapes given" >&2
  exit 2
fi

# Tapes marked `# host-docker: true` get the host's Docker socket (compose/docker-host.yml). The
# netclaw user needs the socket's group to use it.
if [ -S /var/run/docker.sock ]; then
  sock_gid="$(stat -c %g /var/run/docker.sock)"
  getent group "$sock_gid" >/dev/null || groupadd --gid "$sock_gid" dockerhost
  usermod -aG "$(getent group "$sock_gid" | cut -d: -f1)" netclaw
fi

for name in "$@"; do
  tape="/tapes/${name}.tape"
  if [ ! -f "$tape" ]; then
    echo "capture: no such tape: $name" >&2
    exit 2
  fi

  echo "==> Recording $name ($(netclaw --version))"
  rm -rf "${STAGE:?}"/*
  chown netclaw:netclaw "$STAGE"

  # VHS writes a Screenshot asynchronously, so one that is the LAST command in a tape is
  # lost when the recording ends. Run a copy with a trailing Sleep so any tape is safe.
  run_tape="/tmp/run-${name}.tape"
  { cat "$tape"; printf '\nSleep 1s\n'; } > "$run_tape"
  chmod 644 "$run_tape"

  if ! gosu netclaw vhs "$run_tape"; then
    echo "capture: FAILED: vhs exited non-zero for $name" >&2
    exit 1
  fi

  # Every Output/Screenshot path the tape declares must exist.
  missing=0
  while read -r path; do
    if [ ! -s "/work/$path" ]; then
      echo "capture: FAILED: $name did not produce $path" >&2
      missing=1
    fi
  done < <(sed -nE 's/^[[:space:]]*(Output|Screenshot)[[:space:]]+"?([^" ]+)"?.*$/\2/p' "$tape" | grep -v '^#')
  [ "$missing" -eq 0 ] || exit 1

  # Only stills are published. A tape needs an Output line for VHS to run; its GIF stays in staging.
  while IFS= read -r -d '' f; do
    install -m 0644 -o "$HOST_UID" -g "$HOST_GID" "$f" "$OUT/$(basename "$f")"
    echo "    wrote $(basename "$f")"
  done < <(find "$STAGE" -maxdepth 1 -type f -name '*.png' -print0)
done
