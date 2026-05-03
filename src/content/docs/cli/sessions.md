---
title: "netclaw sessions"
description: "Browse and resume chat sessions."
---

Pick up where you left off. `netclaw sessions` opens a terminal UI (TUI) listing your recent sessions — scroll, hit Enter, and you're back in the conversation. For scripts, `--once` and `--json` dump session data to stdout instead.

Requires a running daemon. If it's not up, start it with `netclaw daemon start` (or run [`netclaw init`](/cli/init/) which starts it for you).

This command only lists sessions — there's no delete or cleanup here. Session lifecycle is managed by the daemon's retention policy.

## Usage

```bash
netclaw sessions [options]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--once` | List sessions to stdout and exit (no TUI) | TUI mode |
| `--json` | Output as JSON array (implies `--once`) | Plain text |

## TUI mode

```bash
netclaw sessions
```

Full-screen session browser. Each entry shows:

```
[cli] Deploy troubleshooting (8 turns, 23m ago)
[slack] Weekly standup recap (3 turns, 2h ago)
[cli] Config migration (12 turns, 1d ago)
```

The channel tag (`cli`, `slack`, etc.) shows where the session originated. The daemon returns up to 50 of your most recent sessions.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `↑` / `K` | Move selection up |
| `↓` / `J` | Move selection down |
| `Enter` | Resume selected session (opens chat) |
| `N` | Start a new [`netclaw chat`](/cli/chat/) session |
| `Ctrl+Q` | Quit |
| `Escape` | Quit |

Enter drops you straight into [`netclaw chat`](/cli/chat/) with that session's full history loaded. When no sessions exist, you'll see "No sessions found. Press Enter to start a new chat."

## Single-shot mode

### Plain text output

```bash
netclaw sessions --once
```

Lists all sessions to stdout, one per line:

```
a1b2c3d4  Deploy troubleshooting  [active]  turns=8  last=2026-05-03 14:22
e5f6g7h8  Weekly standup recap    [inactive]  turns=3  last=2026-05-03 11:45
```

**Active** means the session is held in memory and responds instantly. **Inactive** means it's persisted to disk — resuming one replays its history, which takes a moment.

The session ID in the first column is what you pass to [`netclaw chat --resume`](/cli/chat/#session-resume):

```bash
netclaw sessions --once | head -1 | awk '{print $1}' | xargs netclaw chat --resume
```

### JSON output

```bash
netclaw sessions --json
```

Outputs a JSON array of session objects:

```json
[
  {
    "persistenceId": "session-a1b2c3d4",
    "channel": "cli",
    "title": "Deploy troubleshooting",
    "status": "active",
    "turnCount": 8,
    "createdAt": 1746268800000,
    "lastActivity": 1746282120000,
    "logPath": "/home/user/.netclaw/logs/sessions/a1b2c3d4"
  }
]
```

#### JSON fields

| Field | Type | Description |
|-------|------|-------------|
| `persistenceId` | string | Full internal persistence ID (prefixed with `session-`) |
| `channel` | string | Origin channel (`cli`, `slack`, `discord`, etc.) |
| `title` | string? | Auto-generated or null for untitled sessions |
| `description` | string? | Session description, if set |
| `status` | string | `active` (in memory) or `inactive` (persisted to disk) |
| `turnCount` | int | Number of completed conversation turns |
| `createdAt` | long | Creation time (Unix milliseconds) |
| `lastActivity` | long | Last activity time (Unix milliseconds) |
| `logPath` | string? | Path to per-session log directory |
| `lastInputTokens` | long? | Input tokens from the last recorded turn |

Note that `sessionId` is not included in the JSON — it's computed at runtime. To derive the short ID from `persistenceId`, strip the `session-` prefix:

```bash
# Requires jq
netclaw sessions --json | jq -r '.[0].persistenceId | ltrimstr("session-")'
```

Active sessions have their [actor](https://getakka.net/articles/concepts/actors.html) materialized in memory — they respond without any startup cost. Inactive sessions are persisted to disk and fully recoverable; resuming one replays its history, which takes a moment depending on the number of turns.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Sessions listed successfully |
| `1` | Daemon unavailable or request failed |

In TUI mode, a failed daemon connection shows "Failed to connect to daemon. Is it running?" In `--once` mode, the error looks different:

```
[FAIL] sessions: unable to reach daemon at <endpoint>: <message>
run 'netclaw daemon start' and retry.
```

## Examples

### Find sessions with many turns

```bash
# Requires jq
netclaw sessions --json | jq '[.[] | select(.turnCount > 10)] | sort_by(-.lastActivity)'
```

### Resume the most recently active session

```bash
# Requires jq — derives session ID by stripping the "session-" prefix
netclaw chat --resume "$(netclaw sessions --json | jq -r '.[0].persistenceId | ltrimstr("session-")')"
```

## Related commands

- [`netclaw chat`](/cli/chat/) — Pass `--resume <id>` to jump straight into a specific session
- [`netclaw chat -p`](/cli/chat/#headless-mode) — Headless mode with `--resume` for scripted multi-turn conversations
- [`netclaw status`](/cli/status/) — Check daemon health if sessions can't connect
- [`netclaw stats`](/cli/stats/) — Token usage and session count metrics

## Resources

- [jq manual](https://jqlang.github.io/jq/manual/) — filter and transform `--json` output
- [Akka.NET persistence](https://getakka.net/articles/persistence/architecture.html) — how session state survives daemon restarts
