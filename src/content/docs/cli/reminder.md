---
title: "netclaw reminder"
description: "Schedule autonomous agent sessions that fire once, on an interval, or via cron."
---

`netclaw reminder` schedules autonomous agent sessions. A reminder fires on a schedule (once, on an interval, or via [cron](https://crontab.guru/)), runs a session with your instructions, and optionally delivers results to a Slack channel.

All subcommands except `validate` require the daemon to be running. Start it with `netclaw daemon start` or [`netclaw init`](/cli/init/).

## Usage

```bash
netclaw reminder <subcommand> [options]
```

## Subcommands

| Subcommand | Description |
|-----------|-------------|
| `list` | List all active reminders |
| `create` | Create or update a reminder |
| `ui` / `tui` | Interactive reminder builder |
| `show <id>` | Show reminder details |
| `history <id>` | Show execution history |
| `enable <id>` | Enable a reminder |
| `disable <id>` | Disable a reminder |
| `cancel <id>` | Cancel (soft delete — disables, keeps definition) |
| `delete <id>` | Permanently delete a reminder and its history |
| `import <file>` | Import a reminder from a JSON file |
| `validate <file>` | Validate a reminder file offline (no daemon needed) |

## Interactive TUI

```bash
netclaw reminder ui
```

The Reminder Builder walks you through six steps: title, schedule type, schedule value, instructions, delivery guidance, and review.

![The netclaw reminder TUI builder walking through the creation flow](/screenshots/output/reminder.gif)

Navigate with arrow keys and Enter. Esc goes back a step (or quits on the first step). Ctrl+Q quits from anywhere. Ctrl+Enter adds newlines in multi-line fields.

## `list`

```bash
netclaw reminder list
```

![netclaw reminder list showing two reminders — a recurring cron reminder and a one-shot reminder](/screenshots/output/reminder-list.png)

## `create`

```bash
netclaw reminder create <id> <scheduleType> <schedule> "<prompt>" [options]
```

| Positional | Description |
|-----------|-------------|
| `id` | Stable identifier, kebab-case slug (e.g. `daily-standup`) |
| `scheduleType` | `once`, `interval`, or `cron` |
| `schedule` | Duration or cron expression (see [Schedule types](#schedule-types)) |
| `prompt` | Instructions for what netclaw should do when the reminder fires |

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--name <title>` | Human-readable title | Same as `id` |
| `--delivery <kind>` | `none` or `channel` | `none` |
| `--transport <transport>` | Transport for channel delivery (e.g. `slack`) | — |
| `--address <target>` | Target for channel delivery (`#channel`, `@user`, or ID) | — |
| `--expires-in <duration>` | Auto-disable after duration (e.g. `24h`, `7d`) | — |

If a reminder with the given ID already exists, it gets updated (upsert).

Channel delivery requires [Slack to be configured](/cli/init/) in netclaw. Without it, the reminder runs but has nowhere to post results.

### Schedule types

| Type | What it does | Examples |
|------|-------------|----------|
| `once` | Fires one time, then auto-disables | `30m`, `2h`, or an [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601) timestamp like `2026-06-01T18:00:00Z` |
| `interval` | Repeats on a fixed duration | `15m`, `2h`, `1d` |
| `cron` | Fires on a [cron schedule](https://crontab.guru/) (5-field, UTC) | `0 */6 * * *`, `0 9 * * MON-FRI` |

### Examples

#### Recurring cron reminder

```bash
netclaw reminder create akka-nuget-daily cron "0 15 * * MON-FRI" \
  "Check Akka.NET NuGet download counts. Compare to yesterday and flag anything unusual." \
  --name "Akka NuGet Daily Downloads Report"
```

#### One-shot with Slack delivery

```bash
netclaw reminder create stir-trek-talk once "2026-05-01T18:45:00Z" \
  "Remind me to head to the Stir Trek talk room" \
  --name "Head to Stir Trek talk room" \
  --delivery channel --transport slack --address "#general"
```

#### Interval health check

```bash
netclaw reminder create infra-check interval "6h" \
  "Run netclaw doctor and summarize any degraded services."
```

## `show`

```bash
netclaw reminder show <id>
```

Shows the full JSON definition for a reminder — the same format `import` expects.

## `history`

```bash
netclaw reminder history <id> [--last N]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--last <N>` | Number of history records to return | `20` |

Output is a table with columns: `fired_at`, `status` (`ok`/`failed`), `duration_ms`, and `session_id`. Use the session ID to dig into what the agent did with [`netclaw sessions`](/cli/sessions/).

## `enable` / `disable`

```bash
netclaw reminder enable <id>
netclaw reminder disable <id>
```

Disabled reminders keep their definition and history — they just stop firing.

## `cancel` vs `delete`

```bash
netclaw reminder cancel <id>
netclaw reminder delete <id>
```

`cancel` disables a reminder but leaves the definition and history intact, so you can re-enable it later. `delete` removes everything permanently.

## `import`

```bash
netclaw reminder import <file> [--replace|--upsert]
```

Imports a reminder from a JSON file. The file format matches `show` output — grab a reminder's JSON, edit it, and import it back.

| Mode | Description |
|------|-------------|
| _(default)_ | Create only — fails if the reminder already exists |
| `--upsert` | Create or update |
| `--replace` | Replace the existing reminder entirely |

The file is validated before import. Run `validate` first to check for errors without hitting the daemon.

## `validate`

```bash
netclaw reminder validate <file>
```

Checks a reminder JSON file for schema errors offline. Schedule-type-specific rules:

- `once` reminders need a `fireAtMs` timestamp
- `interval` reminders need `intervalTicks`
- `cron` reminders need a valid `cronExpression` (standard [5-field format](https://en.wikipedia.org/wiki/Cron#Cron_expression))

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Reminder not found, validation error, daemon unreachable, or other failure |

## What's next

Run [`netclaw reminder list`](#list) to confirm your reminder appears with the right schedule and next fire time. After it fires, [`netclaw reminder history <id>`](#history) shows whether it succeeded. Grab the session ID from the history output and pass it to [`netclaw sessions`](/cli/sessions/) to see the full run.

## Related commands

- [`netclaw status`](/cli/status/) — confirms daemon is running before using reminders
- [`netclaw sessions`](/cli/sessions/) — inspect what happened during a reminder session
- [`netclaw stats`](/cli/stats/) — usage statistics including reminder execution counts
- [`netclaw doctor`](/cli/doctor/) — health checks for the daemon and its subsystems

## Resources

- [Crontab.guru](https://crontab.guru/) — visual editor for cron schedule expressions
- [Cron expression syntax (Wikipedia)](https://en.wikipedia.org/wiki/Cron#Cron_expression) — reference for the standard 5-field cron format
- [ISO 8601 (Wikipedia)](https://en.wikipedia.org/wiki/ISO_8601) — timestamp format for one-shot reminder schedules
