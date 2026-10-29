#!/bin/bash
# Helpers for the seed-*.sh scripts. Source it. These run inside the capture container as the
# `netclaw` user, which shares the daemon's network namespace and ~/.netclaw volume, so the
# plain `netclaw` CLI talks to the daemon exactly as a user's shell would. The capture image has
# python3 but no jq.

NC_CONFIG="${HOME}/.netclaw/config/netclaw.json"

# wait_daemon: block until `netclaw status` reports a healthy daemon. The daemon restarts
# itself in-process after every netclaw.json change, so call this after each write.
wait_daemon() {
  local i
  sleep 3
  for i in $(seq 1 60); do
    if netclaw status 2>/dev/null | grep -q '^overall: healthy'; then return 0; fi
    sleep 2
  done
  echo "seed: daemon did not become healthy" >&2
  return 1
}

# json_set <section> <json>: merge a JSON object into one top-level section of netclaw.json
# (replacing the keys it names, keeping the rest of the section).
json_set() {
  python3 - "$NC_CONFIG" "$1" "$2" <<'PY'
import json, sys
path, section, patch = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
with open(path) as f:
    cfg = json.load(f)
cfg.setdefault(section, {}).update(patch)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
}
