#!/bin/bash
# Pair one device, "alice-laptop", the way a second machine would: take a code from the daemon host
# and enter it on the device. The device side runs with its own NETCLAW_HOME, so the token and the
# endpoint land there and the daemon host's CLI configuration stays untouched.
set -eu

code="$(netclaw daemon pair | awk '/Pairing code/ {print $3}')"
mkdir -p /tmp/alice-laptop
printf '%s\nalice-laptop\n' "$code" | NETCLAW_HOME=/tmp/alice-laptop netclaw pair http://127.0.0.1:5199 >/dev/null
echo "seeded: paired device alice-laptop"
