---
title: "Scripting Headless Sessions"
description: "Drive netclaw from scripts, evals, and other agents using headless mode."
---

`netclaw chat -p` sends a single prompt without opening the TUI. Add `--resume` for multi-turn conversations and `--json` for machine-readable output. The main use cases: evals (automated LLM behavior testing), having Claude Code or another agent talk to your netclaw instance, and scripted automation that doesn't need an interactive window.

Flag details are on the [`netclaw chat`](/cli/chat/) and [`netclaw sessions`](/cli/sessions/) reference pages — this guide is about combining them.

## Before you begin

- The netclaw daemon must be running (`netclaw status` to check, `netclaw init` if you haven't set up yet)
- Install [`jq`](https://jqlang.github.io/jq/download/) — most JSON examples on this page use it
- A working `~/.netclaw/config/netclaw.json` (created by `netclaw init`)

## Quick reference

```bash
# One-shot prompt, plain text response on stdout
netclaw chat -p "What time zone is the server in?"

# One-shot with structured JSON output
netclaw chat -p --json "Summarize today's alerts."

# Named session — state persists across calls
netclaw chat -p --resume ops/morning-check "Check system health."
netclaw chat -p --resume ops/morning-check "Anything unusual compared to yesterday?"

# JSON output with resume
netclaw chat -p --resume eval/recall-42 --json "What was my favorite color?"
```

## Multi-turn conversations

The daemon preserves conversation history between turns when you `--resume` the same session ID.

```bash
SESSION="eval/color-recall-$$"

# Turn 1: Plant a fact
netclaw chat -p --resume "$SESSION" \
  "Remember this: my favorite color is chartreuse. Just acknowledge."

# Turn 2: Distractor
netclaw chat -p --resume "$SESSION" \
  "What's the square root of 144?"

# Turn 3: Recall
response=$(netclaw chat -p --resume "$SESSION" \
  "What was my favorite color?")

echo "$response"  # Should mention chartreuse
```

The [`$$` suffix](https://www.gnu.org/software/bash/manual/html_node/Special-Parameters.html) (shell PID) prevents collisions across parallel runs.

## JSON output

`--json` wraps the response in a JSON object:

```bash
result=$(netclaw chat -p --json "Say hello.")
echo "$result" | jq .
```

```json
{
  "sessionId": "headless-a1b2c3d4",
  "response": "Hello! How can I help you today?",
  "toolCalls": [
    {
      "callId": "call-001",
      "toolName": "shell_execute",
      "argumentsJson": "{\"command\": \"echo hello\"}"
    }
  ],
  "usage": {
    "inputTokens": 1234,
    "outputTokens": 56,
    "totalTokens": 1290,
    "cachedInputTokens": 800,
    "reasoningTokens": 0,
    "promptMs": 45.2,
    "predictedPerSecond": 120.5
  },
  "ttftMs": 12.3,
  "totalMs": 456.7
}
```

`toolCalls` only shows up when the model actually called a tool. `promptMs` and `predictedPerSecond` come from llama.cpp — vLLM doesn't report them. `ttftMs` is time-to-first-token; `totalMs` is the full roundtrip.

The `sessionId` in the output is exactly what you'd pass to `--resume`:

```bash
# Get just the response text
netclaw chat -p --json "Summarize the logs." | jq -r '.response'

# Check if tools were called
netclaw chat -p --json "List files in /tmp" | jq '.toolCalls | length'

# Capture session ID for follow-ups
sid=$(netclaw chat -p --json "Start a new investigation." | jq -r '.sessionId')
netclaw chat -p --resume "$sid" "What did you find?"
```

## Writing assertions

A couple of helpers that make eval scripts easier to read:

```bash
assert_contains() {
  local label="$1" output="$2" pattern="$3"
  if echo "$output" | grep -qi "$pattern"; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label — expected '$pattern'" >&2
    return 1
  fi
}

assert_json_field() {
  local label="$1" output="$2" field="$3"
  if echo "$output" | jq -e "has(\"$field\")" > /dev/null 2>&1; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label — missing field '$field'" >&2
    return 1
  fi
}
```

In practice:

```bash
#!/bin/bash
set -euo pipefail
SESSION="eval/recall-$$"

turn1=$(netclaw chat -p --resume "$SESSION" \
  "My favorite color is chartreuse. Acknowledge.")
assert_contains "turn 1 acknowledged" "$turn1" "chartreuse"

turn2=$(netclaw chat -p --resume "$SESSION" \
  "What was my favorite color? One word only.")
assert_contains "turn 2 recalled" "$turn2" "chartreuse"

json_out=$(netclaw chat -p --json --resume "$SESSION" \
  "Say goodbye.")
assert_json_field "json has sessionId" "$json_out" "sessionId"
assert_json_field "json has response" "$json_out" "response"

echo "All assertions passed."
```

## Agent-to-agent workflows

If you're in a Claude Code, [Cursor](https://www.cursor.com/), or OpenCode session and need something from netclaw — its memory, a skill, tool access — shell out to `netclaw chat -p`:

```bash
# From Claude Code: ask netclaw to search its memory
netclaw chat -p "Search your memory for everything about the auth refactor."

# Multi-turn: establish context, then ask follow-ups
netclaw chat -p --resume agent/collab-$$ \
  "What do you know about the deployment process for the billing service?"
netclaw chat -p --resume agent/collab-$$ \
  "Write a runbook for it and save it to /tmp/billing-deploy-runbook.md"
```

`--json` makes it easier for the calling agent to parse what came back:

```bash
result=$(netclaw chat -p --json --resume agent/task-$$ \
  "Run the test suite and report results.")
echo "$result" | jq -r '.response'
```

## Unlocking tools for headless mode

There's nobody to click "Approve" in a script. [Approval gates](/architecture/security-model/#human-in-the-loop-as-a-layer-not-a-crutch) auto-deny gated tools in headless mode — the LLM gets a denial error and the script still exits 0 (the turn completed, the model just couldn't do what it wanted).

To let headless scripts use gated tools like `shell_execute`, set them to `Auto` in `~/.netclaw/config/netclaw.json`:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "DefaultMode": "Auto"
        }
      }
    }
  }
}
```

That auto-approves everything under the `Personal` [audience](/architecture/security-model/#audience-as-the-trust-primitive). If that's too broad, override individual tools instead:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "DefaultMode": "Approval",
          "ToolOverrides": {
            "shell_execute": "Auto"
          }
        }
      }
    }
  }
}
```

Precedence: `ToolOverrides[exact tool]` → `McpServerDefaults[server name]` → `DefaultMode`. The daemon picks up config changes automatically — no restart needed.

The hard-deny rules — command blocklists, path restrictions — still apply. `rm -rf /` is blocked even with `DefaultMode: "Auto"`. See the [security model](/architecture/security-model/#four-layers-not-one) for what's on those lists.

See also: [MCP Tool Permissions](/guides/mcp-tool-permissions/) for MCP-specific approval configuration.

## Timeouts

There's no built-in timeout flag. Wrap calls with `timeout`:

```bash
# 90-second deadline per prompt
timeout 90 netclaw chat -p "Analyze this codebase."

# Exit code 124 means timeout fired
if ! timeout 90 netclaw chat -p --resume "$SESSION" "$prompt"; then
  echo "Prompt timed out or failed" >&2
fi
```

For multi-turn scripts, you probably want a deadline on the whole thing too:

```bash
DEADLINE=$((SECONDS + 300))  # 5 minutes total

for prompt in "${PROMPTS[@]}"; do
  remaining=$((DEADLINE - SECONDS))
  if (( remaining <= 0 )); then
    echo "Overall deadline exceeded" >&2
    exit 1
  fi
  timeout "$remaining" netclaw chat -p --resume "$SESSION" "$prompt"
done
```

## Listing and filtering sessions

`netclaw sessions` works from scripts too:

```bash
# Plain text list
netclaw sessions --once

# JSON — filter to active sessions with jq
netclaw sessions --json | jq '[.[] | select(.Status == "active")]'

# Find a session by title pattern
netclaw sessions --json \
  | jq -r '.[] | select(.Title | test("billing"; "i")) | .PersistenceId'
```

Note: `netclaw sessions --json` uses PascalCase field names (`.Status`, `.Title`, `.PersistenceId`), while `netclaw chat -p --json` uses camelCase (`.sessionId`, `.response`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `NETCLAW_HOME` | Override config/data directory (default: `~/.netclaw`). Useful for isolated test environments. |
| `NETCLAW_DAEMON_ENDPOINT` | Override daemon URL (default: `http://127.0.0.1:5199`). Point scripts at a remote daemon. |

Isolate eval runs from your real config by setting `NETCLAW_HOME` to a temp directory:

```bash
EVAL_HOME=$(mktemp -d)
cp -r ~/.netclaw/identity "$EVAL_HOME/identity"
mkdir -p "$EVAL_HOME/config" "$EVAL_HOME/logs"

NETCLAW_HOME="$EVAL_HOME" netclaw chat -p "Run isolated test."

rm -rf "$EVAL_HOME"
```

Copy identity files so the daemon still authenticates — but config, logs, and session state stay isolated.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Prompt sent and response received |
| 1 | Runtime error — daemon unavailable, connection lost, missing prompt, or invalid flags |
| 2 | Unknown command |
| 124 | Timeout (from the `timeout` wrapper, not netclaw itself) |

## Related

- [`netclaw chat`](/cli/chat/) — full flag reference and TUI mode
- [`netclaw sessions`](/cli/sessions/) — browsing and managing sessions
- [`netclaw approvals`](/cli/approvals/) — managing persistent tool approvals
- [Security Model](/architecture/security-model/) — how approval gates work across channel types
- [Sessions & Input Model](/architecture/sessions/) — session lifecycle and recovery
- [Quickstart](/getting-started/quickstart/) — initial setup if you haven't run `netclaw init` yet

## Resources

- [jq manual](https://jqlang.github.io/jq/manual/) — JSON filtering for `--json` output
- [GNU coreutils `timeout`](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html) — deadline wrapper for headless calls
- [Bash special parameters](https://www.gnu.org/software/bash/manual/html_node/Special-Parameters.html) — `$$`, `$?`, and other variables used in scripting patterns
