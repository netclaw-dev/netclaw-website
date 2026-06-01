---
title: "netclaw chat"
description: "Interactive chat and headless prompt mode."
---

Talk to your agent. `netclaw chat` opens a terminal UI for interactive conversations. `netclaw chat -p` sends a single prompt and exits — the scriptable version.

Both modes require a running daemon. If it's not up, start it with `netclaw daemon start` (or run [`netclaw init`](/cli/init/) which starts it for you). The CLI is a thin [SignalR](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction) client — rendering only. Inference, tool execution, and session state all live in the daemon.

## Usage

```bash
netclaw chat [options] [prompt]
```

## Options

| Flag | Alias | Description | Default |
|------|-------|-------------|---------|
| `--resume <id>` | `-r` | Resume an existing session by ID or name | New session |
| `--prompt` | `-p` | Headless mode — send a single prompt, stream output, exit | Interactive TUI |
| `--json` | — | Output structured JSON envelope (headless only) | Plain text |
| `--help` | `-h` | Print help and exit | — |

## Interactive TUI

```bash
netclaw chat
```

The TUI has three panels:

1. **Chat history** — scrollable, streams responses as they arrive
2. **Input** — text area that auto-sizes from 3 to 8 rows, keeps 100-message history
3. **Status bar** — keyboard hints, connection state, active model, token usage

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Send message |
| `Ctrl+Enter` | Insert newline |
| `PgUp` / `PgDn` / Mouse wheel | Scroll chat history |
| `Ctrl+Q` | Quit |
| `Escape` | Quit (ignored while generating) |

### Status bar

```
[key hints] | [connection status] | [model ID] | [usage]
```

Status bar color reflects connection state: green = Ready/Connected, yellow = Connecting/Generating, red = Disconnected/Failed.

Usage reads like `in=142 out=87 (12% ctx)` — input tokens, output tokens, percentage of the model's [context window](https://platform.openai.com/docs/concepts#context-window) used.

### Tool approval

When a tool needs approval, the input panel swaps the text area for a selection list:

| Option | Effect |
|--------|--------|
| **Once** | This invocation only |
| **This chat** | Session-scoped — resets when you quit |
| **Always here** | The command's verb, scoped to the current directory — persists to [`~/.netclaw/config/tool-approvals.json`](/cli/approvals/) |
| **Always anywhere** | The command's verb everywhere — a global grant in the same file. The broadest option; use it sparingly. |
| **Deny** | Block this invocation |

Arrow keys to select, `Enter` to confirm. netclaw shows fewer options when some don't apply (e.g. just **Once** and **Deny** for a command it can't cleanly parse).

### Reconnection

If the daemon disconnects, the status bar turns red and the TUI retries with backoff (1s, 2s, 5s, 10s). Anything you type while disconnected queues up and sends on reconnect.

### Session resume

```bash
netclaw chat --resume abc123
```

Recent messages replay as grayed-out history so you have context from where you left off. Find session IDs with [`netclaw sessions`](/cli/sessions/). You can use daemon-assigned IDs or pass your own human-readable name — `--resume daily-standup` creates a named session if it doesn't exist.

## Headless mode

```bash
netclaw chat -p "summarize today's alerts"
```

Sends one prompt, streams the response to stdout, exits when the turn completes (including any tool calls the agent makes along the way).

### Output format

| Prefix | Meaning |
|--------|---------|
| *(none)* | Streamed assistant text |
| `[tool:call] name(args)` | Tool invocation |
| `[tool:result] name → result` | Tool result |
| `[usage] in=N out=N total=N cached=N prompt_ms=N tok_s=N` | Token usage and timing |
| `[file] fileName → filePath` | File written by the agent |
| `[subagent:start] name (N tools)` | [Sub-agent](/architecture/overview/) spawned |
| `[subagent:done] name (success/failed, Xs)` | Sub-agent completed |
| `[compaction] N → M messages (keep=K, context=X/Y tokens)` | [Context compaction](/architecture/overview/) — the daemon summarized older messages to free up token space |

Errors go to stderr as `[error] message`. Thinking tokens are logged to `~/.netclaw/logs/` but not written to stdout.

### JSON output

```bash
netclaw chat -p --json "list running services"
```

Outputs a single JSON object to stdout. In JSON mode, the prefixed lines above are suppressed — you get one clean object:

```json
{
  "sessionId": "a1b2c3d4",
  "response": "Here are the running services...",
  "toolCalls": [
    {
      "callId": "call_01",
      "toolName": "shell_execute",
      "argumentsJson": "{\"command\":\"systemctl list-units\"}"
    }
  ],
  "usage": {
    "inputTokens": 1420,
    "outputTokens": 387,
    "totalTokens": 1807,
    "cachedInputTokens": 980,
    "reasoningTokens": 0,
    "promptMs": 142.3,
    "predictedPerSecond": 48.2
  },
  "ttftMs": 342.7,
  "totalMs": 2841.0
}
```

Null fields are omitted — if there are no tool calls, `toolCalls` won't appear. `ttftMs` is client-side time-to-first-token; `totalMs` is the full round-trip.

### Named sessions in headless mode

```bash
netclaw chat -p --resume daily-report "what happened since yesterday?"
```

Same `--resume` ID = same conversation, with full history carried forward.

```bash
# First turn: set context
netclaw chat -p --resume deploy-check "I'm about to deploy v2.3 to production"

# Second turn: ask a follow-up (same session, full history)
netclaw chat -p --resume deploy-check "run the pre-deploy checklist"
```

### Tool approval in headless mode

Approval-gated tools are **automatically denied** in headless mode. If your script needs a tool like shell execution, set its approval policy to `Auto` in your [tool configuration](/cli/mcp-tools/) beforehand.

## Examples

### Quick question

```bash
netclaw chat -p "what's the status of the postgres backup job?"
```

### Pipe output into other tools

```bash
netclaw chat -p --json "list all open incidents" | jq '.response'
```

### Scripted multi-turn session

```bash
SESSION="weekly-review-$(date +%Y%m%d)"

netclaw chat -p --resume "$SESSION" "pull this week's metrics from grafana"
netclaw chat -p --resume "$SESSION" "compare against last week and flag anomalies"
netclaw chat -p --resume "$SESSION" --json "write a summary for the team" | jq -r '.response' > report.md
```

## Related commands

- [`netclaw sessions`](/cli/sessions/) — Browse and resume previous chat sessions
- [`netclaw init`](/cli/init/) — First-run setup (configures the daemon that chat connects to)
- [`netclaw status`](/cli/status/) — Check daemon health before starting a chat
- [`netclaw mcp`](/cli/mcp-tools/) — Manage MCP tool servers and approval policies

## Resources

- [SignalR documentation](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction) — the real-time protocol between CLI and daemon
- [jq manual](https://jqlang.github.io/jq/manual/) — handy for wrangling `--json` output in scripts
