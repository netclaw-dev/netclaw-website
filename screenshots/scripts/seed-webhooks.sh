#!/bin/bash
# Two neutral webhook routes for the webhooks tape. The secret is a throwaway demo value
# written to a temp file and read once by `set`. Run inside the capture container.
set -eu
cfg="$NETCLAW_HOME/config/netclaw.json"
if [ "$(jq -r '.Webhooks.Enabled // false' "$cfg")" != "true" ]; then
  jq '.Webhooks = {Enabled: true}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
  sleep 12
fi
secret="$(mktemp)"
printf 'demo-signing-secret' > "$secret"
netclaw webhooks set github-issues --prompt "Triage this issue: label it and summarize it in two sentences." \
  --secret-file "$secret" --audience personal >/dev/null
netclaw webhooks set deploy-notify --prompt "A deployment finished. Summarize the event payload in one line." \
  --secret-file "$secret" --audience personal >/dev/null
rm -f "$secret"
