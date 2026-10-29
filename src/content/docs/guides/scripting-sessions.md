---
title: "Scripting headless sessions"
description: "Drive netclaw from scripts, evals, and other agents with netclaw chat -p, including JSON output and multi-turn sessions."
---

`netclaw chat -p` sends a single prompt without opening the TUI. Add `--resume` for multi-turn conversations and `--json` for machine-readable output. The main use cases are evals (automated LLM behavior testing), having Claude Code or another agent talk to your netclaw instance, and scripted automation that doesn't need an interactive window.

Flag details are on the [`netclaw chat`](/cli/chat/) and [`netclaw sessions`](/cli/sessions/) reference pages. This guide is about combining them. A script can't answer approval prompts, so a call to a gated tool is denied. [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/) shows how to approve what a script needs.

## Before you begin

- The netclaw daemon must be running (`netclaw status` to check, `netclaw init` if you haven't set up yet)
- A `~/.netclaw/config/netclaw.json` file. `netclaw init` creates it
- Install [`jq`](https://jqlang.github.io/jq/download/), because most JSON examples on this page use it

:::caution
In Docker with configuration passed only as `NETCLAW_*` environment variables, there's no `netclaw.json`, and every `netclaw chat -p` call fails with `daemon not configured - please run netclaw init` and exit code 1. Either create the file (`docker exec -u netclaw <container> sh -c 'echo "{}" > ~/.netclaw/config/netclaw.json'` is enough, and the daemon keeps using your environment variables), or run the script with `NETCLAW_DAEMON_ENDPOINT=http://127.0.0.1:5199` set.
:::

## Quick reference

```bash
# One-shot prompt: the reply, then a [usage] line
netclaw chat -p "What time zone is the server in?"

# One-shot with structured JSON output
netclaw chat -p --json "Summarize today's alerts."

# Named session: state persists across calls
netclaw chat -p --resume ops/morning-check "Check system health."
netclaw chat -p --resume ops/morning-check "Anything unusual compared to yesterday?"

# JSON output with resume
netclaw chat -p --resume eval/recall-42 --json "What was my favorite color?"
```

## Plain output

Without `--json`, stdout carries the reply as it streams, plus lines that start with a bracketed tag:

```text
$ netclaw chat -p "Reply with exactly: hello"
hello
[usage] in=10483 out=2 total=10485 cached=0 prompt_ms=13920.145 tok_s=3.41
```

| Line | Meaning |
|------|---------|
| `[tool:call] <tool>(<arguments>)` | The model called a tool |
| `[tool:result] <tool> → <result>` | What the tool returned, including a denial |
| `[usage] in=... out=...` | Token counts and timings, printed at the end of every turn |
| `[subagent:start]`, `[subagent:done]`, `[compaction]`, `[file]` | Sub-agent, context compaction and attachment events |
| `[subagent:waiting] <n> open: <run ids>` | The run is waiting for child agents to finish |
| `[approval:waiting] <tool>: <text>`, `[approval:closed] <reason>` | An approval prompt this run saw, for example on a resumed session with an open child prompt |

Errors go to stderr as `[error] <message>` or `[headless:error] <message>`. A failed turn also writes `[turn:failed] category=<model|infra> kind=<Kind>`, and when child runs were still open, `[headless:open-runs] session=<id> runs=<ids>`. When a script parses the reply, use `--json` so none of these tags are mixed in.

## Check the exit code

`chat -p` exits `1` when the turn fails: the provider is unreachable, the request times out or the context overflows. Stdout can still hold the text the model streamed before it failed. Stderr gets one line that says why:

```text
[turn:failed] category=infra kind=ProviderFailure
```

`category` is `model` only when the model is to blame, such as a cut-off or thinking-only reply (`kind=ModelBehavior`). A provider outage or a timeout is `infra`, so an eval harness shouldn't score it against the model. With `--json` the envelope gains `errorCategory` and `errorKind`. Test the exit code:

```bash
if ! reply=$(netclaw chat -p "Summarize the alerts."); then
  echo "turn failed" >&2
  exit 1
fi
```

A turn that completes exits `0`, even when a tool call in it was denied. A turn that the loop guard ends after repeated refused calls also exits `0`, with no `[turn:failed]` line and possibly an empty `response`.

Exit `1` also covers SIGINT and SIGTERM (`kind=Cancelled`), a lost connection (`kind=ChannelFailure`, after `[headless:error] Lost the connection ...`), and a session stopped by a drained daemon restart. None of those write a JSON envelope.

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

`--json` wraps the response in a JSON object. A run with a sub-agent has several turns, so `response` is the last turn's text and `turnResponses` lists every turn:

```bash
result=$(netclaw chat -p --json "Use shell_execute to run exactly: echo hello. Then say done.")
echo "$result" | jq .
```

```json
{
  "sessionId": "signalr/3bc7665ec770475eac34c3fb0360b5f8",
  "response": "done",
  "toolCalls": [
    {
      "callId": "BT9cltvwvSccbHRais6tNqTWQGWa0vuv",
      "toolName": "shell_execute",
      "argumentsJson": "{\"Command\":\"echo hello\",\"_rationale\":\"Run the exact requested command.\"}"
    }
  ],
  "usage": {
    "inputTokens": 9646,
    "outputTokens": 2,
    "totalTokens": 9648,
    "cachedInputTokens": 0,
    "promptMs": 11575.806,
    "predictedPerSecond": 9.65
  },
  "turnResponses": [
    { "turnNumber": 1, "text": "done", "toolCalls": [ ... ], "usage": { ... } }
  ],
  "totalMs": 26464.9
}
```

`toolCalls` spans all turns, and `usage` sums the tokens across them. `promptMs` and `predictedPerSecond` come from the last turn that has usage.

`toolCalls` only shows up when the model actually called a tool, and it lists the calls without their results. A denied call looks the same as an allowed one, so check the reply or the plain-output `[tool:result]` line to see what happened. `promptMs` and `predictedPerSecond` come from llama.cpp, and vLLM doesn't report them. `totalMs` is the full roundtrip, and a `ttftMs` field (time to first token) shows up on some responses. `reasoningTokens` appears in `usage` only when the model reports reasoning.

The `sessionId` in the output is exactly what you'd pass to `--resume`. Without `--resume` it looks like `signalr/<32 hex characters>`, and with `--resume eval/recall-42` it's the name you passed:

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
    echo "  PASS $label"
  else
    echo "  FAIL $label: expected '$pattern'" >&2
    return 1
  fi
}

assert_json_field() {
  local label="$1" output="$2" field="$3"
  if echo "$output" | jq -e "has(\"$field\")" > /dev/null 2>&1; then
    echo "  PASS $label"
  else
    echo "  FAIL $label: missing field '$field'" >&2
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

If you're in a Claude Code, [Cursor](https://www.cursor.com/), or OpenCode session and need something from netclaw (its memory, a skill, tool access), shell out to `netclaw chat -p`:

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

## Let a script use shell and file tools

There's nobody to click "Approve" in a script. A call that would prompt is denied with `approval_required_unattended`, the model gets a denial error, and the script still exits 0 because the turn completed. In plain output it shows up as:

```text
[tool:call] shell_execute({"Command":"touch /tmp/unattended-demo.txt", ...})
[tool:result] shell_execute → Tool access denied: shell_execute needs approval, and nobody can answer a prompt in an unattended run. Save an "Always" grant for this call in a chat with the same audience (for example with /run-reminder), then run it again.
```

Approve what the script needs before you run it. The [unattended runs guide](/guides/unattended-runs/#scripts) covers the three ways to do it: save a grant with `netclaw approvals trust-verb`, answer the prompt once in a chat and choose an "Always" option, or set `shell_execute` to `Auto` for the Personal audience. A script's `-p` session runs as the Personal audience.

The hard-deny rules, such as command blocklists and protected paths, still apply. `rm -rf /` is blocked even with `shell_execute` set to `Auto`.

See also [MCP tool permissions](/guides/mcp-tool-permissions/) for MCP-specific approval configuration.

## Sub-agents

When the reply starts a sub-agent, `chat -p` stays open instead of exiting. Text mode prints `[subagent:waiting] 1 open: <run id>` after the turn. The child's result arrives as a notice in a later turn, and the run ends on the first turn that reports no open child run, or on a failed turn. Stdout holds the child's text only if the model reads `result.md` with `file_read`. A background shell job isn't a child run, so the script doesn't wait for it.

If the run fails or is stopped while a child is open, the CLI doesn't cancel the child. Resume the session with `netclaw chat --resume <id>`.

## Timeouts

There's no built-in timeout flag. Wrap calls with `timeout`. This matters more now: a `chat -p` that starts a child waits for it with no timer of its own, and an outside `timeout` is the only bound. It exits `124`, and stderr usually has `kind=Cancelled`.

```bash
# 90-second deadline per prompt
timeout 90 netclaw chat -p "Analyze this codebase."

# Exit code 124 means timeout fired
if ! timeout 90 netclaw chat -p --resume "$SESSION" "$prompt"; then
  echo "Prompt timed out or failed" >&2
fi
```

A short network drop fails the run with exit `1` (`kind=ChannelFailure`) after the prompt is sent, and the daemon may still run the prompt. Check the session with `netclaw chat --resume <id>` before you send it again.

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

# JSON: filter to active sessions with jq
netclaw sessions --json | jq '[.[] | select(.Status == "active")]'

# Find a session by title pattern
netclaw sessions --json \
  | jq -r '.[] | select((.Title // "") | test("billing"; "i")) | .SessionId'
```

`netclaw sessions --json` uses PascalCase field names (`.Status`, `.Title`, `.SessionId`), while `netclaw chat -p --json` uses camelCase (`.sessionId`, `.response`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `NETCLAW_HOME` | Override the base directory the CLI reads (default: `~/.netclaw`). It doesn't give you a separate daemon |
| `NETCLAW_DAEMON_ENDPOINT` | Override the daemon URL (default: `http://127.0.0.1:5199`). Point scripts at a daemon on another host, and skips the `daemon not configured` check when `netclaw.json` is missing. On the daemon's own machine use `http://127.0.0.1:<port>` or `http://localhost:<port>`. In `Local` exposure mode another host name or a browser app on another local port gets `401` |

`NETCLAW_HOME` changes where the CLI looks for its files, not which daemon it talks to. A CLI started with `NETCLAW_HOME` pointing at a temp directory still connects to the daemon on `127.0.0.1:5199`, with that daemon's real config, sessions and state. To isolate an eval run, give it its own daemon. In Docker that's a second container with its own volume, and you run the script inside it:

```bash
docker run -d --name eval-netclaw \
  -v eval-home:/home/netclaw/.netclaw \
  -e NETCLAW_Providers__local__Type=openai-compatible \
  -e NETCLAW_Providers__local__Endpoint=http://llm.example.internal:8080 \
  -e NETCLAW_Models__Definitions__main__Provider=local \
  -e NETCLAW_Models__Definitions__main__ModelId=<model id from /v1/models> \
  -e NETCLAW_Models__Roles__Main=main \
  ghcr.io/netclaw-dev/netclaw:0.28.2

# Environment-only config has no netclaw.json, so name the daemon explicitly
docker exec -u netclaw -e NETCLAW_DAEMON_ENDPOINT=http://127.0.0.1:5199 \
  eval-netclaw netclaw chat -p "Run isolated test."

docker rm -f eval-netclaw && docker volume rm eval-home
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | The turn completed |
| 1 | The turn failed, or a runtime error: daemon unavailable, connection lost, SIGINT or SIGTERM, missing prompt, `daemon not configured`, or invalid flags |
| 2 | Unknown command |
| 124 | Timeout (from the `timeout` wrapper, not netclaw itself) |

## Related pages

- [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/) - approve what a script's tool calls need
- [`netclaw chat`](/cli/chat/) - full flag reference and TUI mode
- [`netclaw sessions`](/cli/sessions/) - browsing and managing sessions
- [`netclaw approvals`](/cli/approvals/) - managing persistent tool approvals
- [Sessions & input model](/architecture/sessions/) - session lifecycle and recovery

## Resources

- [jq manual](https://jqlang.github.io/jq/manual/) - JSON filtering for `--json` output
- [GNU coreutils `timeout`](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html) - deadline wrapper for headless calls
- [Bash special parameters](https://www.gnu.org/software/bash/manual/html_node/Special-Parameters.html) - `$$`, `$?`, and other variables used in scripting patterns
