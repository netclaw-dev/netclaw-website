---
title: "netclaw stats"
description: "View usage activity statistics."
---

`netclaw stats` tells you where your tokens are going, how many sessions are running, and whether memory is healthy. It also covers channel activity, webhook deliveries, and reminders. `--json` for scripts, `--tui` for a live dashboard.

## Usage

```bash
netclaw stats [options]
netclaw stats skills [options]
```

Requires a running daemon. If it's not up, start it with `netclaw daemon start` (or run [`netclaw init`](/cli/init/) which starts it for you).

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--days <N>` | Show trailing N-day daily breakdown | None (omits daily table) |
| `--all` | Show all-time daily breakdown | Off |
| `--tui` | Visual TUI dashboard | Off |
| `--json` | Alias for `--format json` | — |
| `--format <text\|json>` | Output format | `text` |

## Output

```bash
netclaw stats
```

![netclaw stats showing token usage, sessions, memory, channel activity, webhooks, and reminders](/screenshots/output/stats.png)

Without `--days` or `--all`, you get process-lifetime counters plus current snapshot data. No daily table.

| Section | What it shows |
|---------|---------------|
| **this process** | Token consumption (in/out), turns completed, [memories](/architecture/overview/) formed/recalled, [skills](/skills/overview/) loaded |
| **sessions** | Total, active, and all-time turn count |
| **memory** | Status (`healthy`, `degraded`, `unavailable`), anchor/document/record/edge counts, pending checkpoints |
| **skills** | Total available skill count |
| **\<channel\>** | Per-channel events (recv/routed/dropped) and replies (posted/rejected/failed) |
| **webhooks** | Route counts, delivery stats, rejection breakdown by HTTP status |
| **reminders** | Scheduled, active, and failed counts |

The "this process" counters live in the daemon process's memory and reset when the daemon restarts. Everything else (sessions, memory, daily breakdown) is persisted to SQLite and survives restarts.

If memory status shows `degraded` or `unavailable`, run [`netclaw doctor --fix`](/cli/doctor/) to fix common issues automatically.

### Daily breakdown

Add `--days` to see a per-day table of token usage and activity:

```bash
# Last 14 days
netclaw stats --days 14

# All time
netclaw stats --all
```

Columns: date, input/output tokens, turns, sessions, memories formed/recalled, skills loaded. When more than one day of data is returned, a totals row appears at the bottom.

## TUI dashboard

```bash
netclaw stats --tui
```

Opens a full-screen dashboard. `--tui` always shows an ASCII bar chart of daily token usage, defaulting to the last 7 days. Pass `--days N` to change the window:

```bash
netclaw stats --tui --days 30
```

The lower half of the dashboard shows the Daily Token Usage bar chart by default. Memory, per-channel, and Webhooks panels take its place when there's no daily breakdown data.

`Q`, `Escape`, or `Ctrl+C` to quit.

## Skill usage stats

`stats skills` shows per-skill load counts broken down by day and invocation method (e.g., `direct`, `auto`, `scheduled`):

```bash
# Last 7 days (default)
netclaw stats skills

# Last 30 days
netclaw stats skills --days 30

# All time
netclaw stats skills --all
```

Each day shows total loads, a method breakdown, and per-skill counts (top 15). `--tui` doesn't work with `stats skills`.

## JSON output

```bash
netclaw stats --json
```

```bash
# Total input tokens since daemon started
netclaw stats --json | jq '.tokens.inputTokensTotal'

# Daily token usage for the last 7 days
netclaw stats --days 7 --json | jq '.dailyBreakdown[] | {date, inputTokens, outputTokens}'

# Active session count
netclaw stats --json | jq '.sessions.activeSessions'

# Memory health status
netclaw stats --json | jq -r '.memory.status'
```

`stats skills --json` returns a separate shape with daily skill load breakdowns:

```bash
netclaw stats skills --json | jq '.daily[] | {date, totalLoads}'
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Daemon unreachable or error response |

## Daemon endpoint

`stats` queries `http://127.0.0.1:5199` by default. Override with:

- `NETCLAW_DAEMON_ENDPOINT` environment variable
- `~/.netclaw/client/config.json`

See [`netclaw status`](/cli/status/) for more on endpoint configuration.

## When the daemon isn't running

You'll see one of two errors:

**Connection refused** — the daemon process isn't running at all:

```
[FAIL] stats: unable to reach daemon at http://127.0.0.1:5199: Connection refused
       fix: run `netclaw daemon start` and retry.
```

**503 response** — the daemon is up but not ready (still starting, or something broke):

```
[FAIL] stats: daemon returned 503 from http://127.0.0.1:5199
       fix: run `netclaw daemon start` and retry.
```

For 503s, [`netclaw doctor --fix`](/cli/doctor/) can often sort out what's wrong without a restart.

## Related commands

- [`netclaw status`](/cli/status/) — live health check for daemon, connectors, and model
- [`netclaw doctor`](/cli/doctor/) — config diagnostics with `--fix` for auto-repair
- [`netclaw sessions`](/cli/sessions/) — if stats show unexpected session counts, dig into individual conversations here
- [`netclaw init`](/cli/init/) — first-run setup (starts the daemon for you)

## Resources

- [jq manual](https://jqlang.github.io/jq/manual/) — for wrangling `--json` output
- [SQLite documentation](https://www.sqlite.org/docs.html) — daily breakdown data is persisted here
