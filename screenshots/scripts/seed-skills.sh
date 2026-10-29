#!/bin/bash
# Stages the skills the skill-list and skill-sync captures show:
#   - two local skills in ~/.netclaw/skills (hello-greeter with a references/ file, flat-note)
#   - two skills and one subagent published to the stack's skill server (port 8090) with the
#     skillserver CLI, and the server added as the `corp-skills` feed in netclaw.json.
# Run inside the capture container. With `no-feed` as the first argument, only the local
# skills are created (nothing is published and no feed is configured).
set -eu

skills="$HOME/.netclaw/skills"
mkdir -p "$skills/hello-greeter/references" "$skills/flat-note"
cat > "$skills/hello-greeter/SKILL.md" <<'SKILL'
---
name: hello-greeter
description: Greet the user by name and mention one useful thing about their day.
metadata:
  version: 1.0.0
---

# Hello greeter

Greet the user by name. Read `references/greetings.md` for tone before you answer.
SKILL
cat > "$skills/hello-greeter/references/greetings.md" <<'REF'
Keep greetings to one sentence. Warm, never gushing.
REF
cat > "$skills/flat-note/SKILL.md" <<'SKILL'
---
name: flat-note
description: Capture a quick note as a single markdown bullet.
---

# Flat note

Write the note as one markdown bullet and confirm it back in a sentence.
SKILL

[ "${1:-}" = "no-feed" ] && exit 0

server=http://127.0.0.1:8090
export SKILLSERVER_API_KEY=demo-publish-key
src="$(mktemp -d)"
agents="$(mktemp -d)"
mkdir -p "$src/k8s-log-triage/references" "$src/incident-summary"
cat > "$src/k8s-log-triage/SKILL.md" <<'SKILL'
---
name: k8s-log-triage
description: Triage Kubernetes pod logs, group repeated errors and suggest the next check.
metadata:
  version: 0.2.0
---

# Kubernetes log triage

Read `references/patterns.md`, group the errors by pattern and propose one next check.
SKILL
cat > "$src/k8s-log-triage/references/patterns.md" <<'REF'
CrashLoopBackOff: check the previous container's logs first.
ImagePullBackOff: check the registry credentials and the tag.
REF
cat > "$src/incident-summary/SKILL.md" <<'SKILL'
---
name: incident-summary
description: Summarize an incident timeline in five bullets for a status update.
metadata:
  version: 1.1.0
---

# Incident summary

Turn the timeline into five bullets: impact, cause, fix, follow-ups, owner.
SKILL
cat > "$agents/release-notes-writer.md" <<'AGENT'
---
name: release-notes-writer
description: Draft release notes from a list of merged changes
modelRole: Compaction
timeoutSeconds: 90
---

You write short release notes. Group the changes by user impact and keep each line under 100 characters.
AGENT

skillserver publish-all "$src" --server-url "$server" >/dev/null 2>&1 || skillserver publish-all "$src" --server-url "$server"
skillserver publish-subagent "$agents/release-notes-writer.md" --version 1.0.0 --server-url "$server" >/dev/null
rm -rf "$src" "$agents"

cfg="$NETCLAW_HOME/config/netclaw.json"
jq '.SkillFeeds = {SyncIntervalMinutes: 60, Feeds: [{Name: "corp-skills", Url: "http://127.0.0.1:8090", Enabled: true, TimeoutSeconds: 30}]}' \
  "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
sleep 15
