---
title: "netclaw status"
description: "Query daemon runtime status."
---

`netclaw status` queries the running daemon and prints overall health, connector states, the active model, persistence, telemetry counters, and whether an update is available. Run it when something feels off, or wire it into a health check script.

## Usage

```bash
netclaw status [options]
```

Requires a running daemon. If it's not up, start it with `netclaw daemon start` (or run [`netclaw init`](/cli/init/) which starts it for you).

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--format <text\|json>` | Output format | `text` |
| `--json` | Alias for `--format json` | — |

## Output

```bash
netclaw status
```

![netclaw status showing healthy daemon with connectors](/screenshots/output/status.png)

| Section | What it tells you |
|---------|-------------------|
| **overall** | `healthy` or `degraded` |
| **version** | Build version, commit hash, build timestamp |
| **daemon** | PID, uptime, endpoint URL |
| **persistence** | Storage provider (e.g., SQLite) |
| **memory** | Memory provider and status — returns `unavailable`, `healthy`, or `degraded` |
| **telemetry** | Enabled/disabled, [OpenTelemetry Protocol](https://opentelemetry.io/docs/specs/otlp/) (OTLP) endpoint if active |
| **counters** | Per-channel message stats: `recv`, `routed`, `dropped`, `replied`, `rejected`, `reply_failed` |
| **model** | Active model name, provider, context window, input/output modalities |
| **connectors** | Each connector's key, status, and enabled/disabled state |
| **update** | Whether a newer version is available |

### Overall status logic

`overall` reflects connector health:

- **healthy** — all enabled connectors are healthy
- **degraded** — any enabled connector is `disconnected`, `degraded`, `auth-required`, or `auth-failed`

### Connector statuses

Channel connectors (Slack, Discord) report: `healthy`, `degraded`, `disconnected`, `disabled`, `unknown`.

MCP connectors — keyed as `mcp:<server-name>` from your configured [MCP tool servers](/cli/mcp-tools/) — add: `auth-required` and `auth-failed`.

Disabled connectors still appear in the list with `(disabled)` so you can tell they're intentionally off, not broken.

If any connector shows `degraded` or worse, run [`netclaw doctor --fix`](/cli/doctor/) to auto-repair common issues. If that doesn't resolve it, check the specific connector's configuration.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Healthy |
| `2` | Degraded |
| `1` | Daemon unreachable or error response |

Exit code `2` for degraded (rather than `1`) lets scripts distinguish "something's wrong but running" from "down entirely":

```bash
netclaw status > /dev/null 2>&1
rc=$?
case $rc in
  0) echo "healthy" ;;
  2) echo "degraded — check connectors" ;;
  *) echo "down or unreachable" ;;
esac
```

Note: the [CLI overview](/cli/overview/) documents exit code `2` as "usage/argument error" for most commands. `status` is an exception — it uses `2` specifically for degraded health.

## JSON output

```bash
netclaw status --json
```

Returns the full status response as JSON.

The JSON includes fields not shown in text output — notably `reminders` (with `scheduledCount`, `activeExecutions`, `failedCount`). Also, the `version` text section maps to the `.build` key in JSON, so use `jq '.build'` rather than `jq '.version'`:

```bash
# Check overall health
netclaw status --json | jq -r '.overall'

# Get version info (note: `.build`, not `.version`)
netclaw status --json | jq '.build'

# List unhealthy connectors
netclaw status --json | jq '[.connectors[] | select(.enabled and .status != "healthy")]'
```

## When the daemon isn't running

If the daemon is unreachable, you'll see one of:

```
[FAIL] status: unable to reach daemon at http://127.0.0.1:5199: Connection refused
fix: run 'netclaw daemon start' and retry.
```

```
[FAIL] status: daemon returned 503 from http://127.0.0.1:5199
fix: run 'netclaw daemon status' and 'netclaw daemon start'.
```

The distinction:

| Command | What it checks | Daemon required |
|---------|---------------|-----------------|
| `netclaw daemon status` | PID file — is the process running? | No |
| `netclaw status` | Live health query — are connectors, model, persistence all working? | Yes |

If you're not sure the process is alive, start with `daemon status`. Once it's up, `status` gives the full picture.

## Daemon endpoint

`status` queries `http://127.0.0.1:5199/api/health/status` by default. Override with:

- `NETCLAW_DAEMON_ENDPOINT`
- `~/.netclaw/client/config.json`

## Related commands

- [`netclaw doctor`](/cli/doctor/) — Diagnostics with auto-repair (`--fix`)
- [`netclaw stats`](/cli/stats/) — Token usage, session counts, and memory metrics
- [`netclaw chat`](/cli/chat/) — Start a conversation (check status first if connections fail)
- [`netclaw init`](/cli/init/) — First-run setup that starts the daemon for you

## Resources

- [jq manual](https://jqlang.github.io/jq/manual/) — for wrangling `--json` output
- [OpenTelemetry collector docs](https://opentelemetry.io/docs/collector/) — if you're sending telemetry to an OTLP endpoint
