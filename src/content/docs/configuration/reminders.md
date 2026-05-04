---
title: "Reminders"
description: "Schedule recurring and one-time reminder prompts."
---

Reminders are autonomous agent sessions that fire on a schedule. You define what the agent should do, pick a schedule (once, interval, or cron), and optionally send results to Slack. The daemon handles the rest.

The scheduling subsystem is enabled by default. For CLI commands that create and manage reminders, see [`netclaw reminder`](/cli/reminder/).

## Before you begin

- The daemon must be running — start it with `netclaw daemon start` or [`netclaw init`](/cli/init/)
- For channel delivery, [Slack must be configured](/cli/init/) in your netclaw setup

## Global configuration

Toggle the scheduling subsystem in `~/.netclaw/config/netclaw.json`:

```json
{
  "Scheduling": {
    "Enabled": true
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `true` | When `false`, all reminder scheduling stops and the LLM tools (`set_reminder`, `cancel_reminder`, `list_reminders`, `get_reminder_history`) are unregistered. |

Disabling doesn't delete existing reminders — it just stops them from firing. Re-enable and they pick up where they left off.

## Filesystem layout

Reminder data lives alongside other netclaw state:

```
~/.netclaw/schedules/reminders/
├── daily-standup.json            # reminder definition
├── daily-standup.history.jsonl   # execution history (append-only)
├── infra-check.json
└── infra-check.history.jsonl
```

Each reminder gets two files: a JSON definition and a JSONL history log. The filename is the reminder ID (URL-encoded if it contains special characters). History is capped at 500 entries per reminder — oldest entries are trimmed automatically.

## Reminder definition schema

This is the JSON format used by `netclaw reminder show`, `import`, and `validate`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Kebab-case slug, max 50 characters |
| `title` | string | Yes | Human-readable name |
| `instructions` | string | Yes | Prompt for the agent session when the reminder fires |
| `schedule.type` | enum | Yes | `OneShot`, `Interval`, or `Cron` |
| `schedule.fireAtMs` | long | OneShot | Unix timestamp in milliseconds. Validated at import time. |
| `schedule.intervalTicks` | long | Interval | .NET Ticks (1 tick = 100ns). Auto-populated by the CLI from duration strings — you don't set this manually. |
| `schedule.cronExpression` | string | Cron | Standard 5-field cron expression (UTC) |
| `schedule.originalExpression` | string | No | Original human input (e.g. `"6h"`, `"0 */6 * * *"`) |
| `delivery.kind` | enum | Yes | `CurrentSession`, `Channel`, or `None` |
| `delivery.transport` | string | Channel | `"slack"` |
| `delivery.address` | string | Channel | Slack channel ID or user ID |
| `delivery.sessionId` | string | CurrentSession | Auto-populated by the daemon from the creating session context |
| `deliveryRequired` | bool | No | Default `true`. Marks execution failed if delivery doesn't happen. |
| `deliveryInstructions` | string | No | Guidance for what to include in the delivery message |
| `audience` | enum | No | `Personal`, `Team`, or `Public`. Inherited from the creating session. Controls which tools the reminder session can access — see [MCP Servers](/configuration/mcp-servers/). |
| `enabled` | bool | No | Default `true` |
| `expiresAtMs` | long | No | Auto-disable after this timestamp. Not valid on OneShot reminders. |
| `createdBy` | string | No | `"llm-tool"`, `"cli"`, `"system"` |
| `createdAtMs` | long | No | Unix ms creation timestamp |
| `updatedAtMs` | long | No | Unix ms last-update timestamp |

### Minimal definition

```json
{
  "id": "infra-check",
  "title": "Infrastructure Health Check",
  "instructions": "Run netclaw doctor and summarize any degraded services.",
  "schedule": {
    "type": "Interval",
    "intervalTicks": 216000000000,
    "originalExpression": "6h"
  },
  "delivery": {
    "kind": "None"
  }
}
```

### Channel delivery definition

```json
{
  "id": "daily-standup",
  "title": "Daily Standup Summary",
  "instructions": "Check yesterday's reminder history and git commits. Post a standup summary.",
  "schedule": {
    "type": "Cron",
    "cronExpression": "0 9 * * MON-FRI",
    "originalExpression": "0 9 * * MON-FRI"
  },
  "delivery": {
    "kind": "Channel",
    "transport": "slack",
    "address": "C12345678"
  },
  "deliveryRequired": true,
  "deliveryInstructions": "Post the summary to the standup channel. Keep it under 5 bullet points.",
  "audience": "Team"
}
```

To load a definition from a file: `netclaw reminder validate <file>` to check for errors, then `netclaw reminder import <file>` to register it with the daemon.

## Schedule types

| Type | Fires | Minimum | Format |
|------|-------|---------|--------|
| `OneShot` | Once, then auto-disables | 60 seconds from now | Relative duration (`30m`, `2h`) or ISO 8601 timestamp |
| `Interval` | Repeats on a fixed duration | 60 seconds | Duration string (`15m`, `6h`, `1d`) |
| `Cron` | On a cron schedule | N/A | 5-field cron expression, UTC |

The 60-second minimum is enforced for all schedule types. Cron expressions are always evaluated in UTC.

Interval reminders fire their first execution one interval after creation (or after being re-enabled) — not at a fixed wall-clock time. Imported definitions with an explicit `fireAtMs` will use that timestamp for the first fire instead.

For more detail on creating reminders with each schedule type, see [`netclaw reminder create`](/cli/reminder/#create).

## Delivery modes

| Kind | What happens | Requirements |
|------|-------------|--------------|
| `None` | Agent runs silently. Results recorded in history only. | Nothing |
| `Channel` | Agent posts results to a Slack channel via `send_slack_message` (called automatically by the agent) | `transport` + `address` + [Slack configured](/cli/init/) |
| `CurrentSession` | Re-enters the originating conversation (Slack thread, TUI, etc.) | Active session context at creation time |

When `deliveryRequired` is `true` (the default) and delivery kind is `Channel`, the execution is marked **failed** if the agent doesn't post to the target channel. Each failed execution emits a `ReminderExecutionFailed` warning alert. After 5 consecutive failures, the reminder is auto-disabled and a `ReminderAutoDisabled` critical alert fires.

For `CurrentSession` delivery, if the originating session is no longer active, delivery times out after 300 seconds and the execution is marked failed.

For Slack delivery, use `netclaw reminder create --delivery channel` or set `delivery.kind` to `"Channel"` in the JSON directly.

## Runtime behavior

| Setting | Value | Configurable? |
|---------|-------|---------------|
| Execution timeout | 300 seconds | No |
| Max concurrent executions | 3 | No |
| History retention | 500 entries per reminder | No |
| Overflow handling | FIFO queue (unbounded) | — |

When all 3 slots are busy, incoming fires queue and run as slots open.

Recurring reminders get an automatic instruction appended: if the agent determines the reminder's purpose has been permanently fulfilled, it should call `cancel_reminder` to stop future fires.

## Auto-disable and expiration

Two mechanisms stop reminders automatically.

### Consecutive failures

After 5 failed executions in a row, the reminder is disabled and a `ReminderAutoDisabled` critical alert fires via your [notification webhooks](/configuration/webhooks/#outbound-notification-webhooks). A single successful execution resets the failure counter.

Fix the underlying issue (usually a missing Slack channel or invalid delivery target), then re-enable:

```bash
netclaw reminder enable <id>
```

### Expiration

Set `expiresAtMs` (or `--expires-in` on the CLI) to auto-disable a recurring reminder after a deadline. The reminder fires normally until the expiration time, then disables on the next scheduled fire. Not applicable to one-shot reminders.

## LLM tools

The agent manages reminders through four tools, all requiring the `scheduling` grant (grants control which LLM tools are available — see [MCP Servers](/configuration/mcp-servers/) for grant configuration):

| Tool | Description |
|------|-------------|
| `set_reminder` | Create or update (upsert) a reminder |
| `cancel_reminder` | Disable a reminder (definition preserved) |
| `list_reminders` | List active or all reminders |
| `get_reminder_history` | Return execution history (default 20, max 100) |

These tools are only registered when `Scheduling.Enabled` is `true`.

## Stale one-shot cleanup

On daemon startup, the reconciliation process permanently deletes any one-shot reminder that already fired — the only time a definition disappears without an explicit `delete` command. Expired recurring reminders are disabled (not deleted) during reconciliation.

## Troubleshooting

### Reminder fires but delivery fails

Verify that Slack is still configured and the target channel exists. Run `netclaw reminder history <id>` — if you see repeated `failed` statuses, the auto-disable countdown is ticking. Fix the channel, then `netclaw reminder enable <id>`.

### Reminder doesn't fire

First verify the daemon is running (`netclaw status`). Then check `Scheduling.Enabled` in your config and run `netclaw reminder show <id>` to confirm `enabled` is `true`.

### Cron fires at unexpected times

Cron expressions are evaluated in UTC, not local time. A `0 9 * * *` schedule fires at 9:00 UTC. Adjust your expression for your timezone offset.

## What's next

Run `netclaw reminder list` to confirm your reminder appears with the right schedule and next fire time. After it fires, `netclaw reminder history <id>` shows whether it succeeded — grab the session ID from that output and pass it to [`netclaw sessions`](/cli/sessions/) to see the full execution log.

## Related pages

- [`netclaw reminder`](/cli/reminder/) — CLI reference for all reminder subcommands
- [Webhooks](/configuration/webhooks/) — outbound alerts including `ReminderAutoDisabled`
- [Operational Alerts](/observability/operational-alerts/) — full alert type reference including `ReminderExecutionFailed` and `ReminderAutoDisabled`
- [`netclaw sessions`](/cli/sessions/) — inspect what happened during a reminder execution
- [`netclaw doctor`](/cli/doctor/) — validates daemon subsystems including scheduling

## Resources

- [Crontab.guru](https://crontab.guru/) — visual editor for cron schedule expressions
- [Cron expression syntax (Wikipedia)](https://en.wikipedia.org/wiki/Cron#Cron_expression) — reference for the standard 5-field cron format
- [ISO 8601 (Wikipedia)](https://en.wikipedia.org/wiki/ISO_8601) — timestamp format for one-shot schedules
- [Locate your Slack channel ID](https://slack.com/help/articles/221769328-Locate-your-Slack-URL-or-ID) — find channel IDs for delivery targets
- [Slack App Permissions](https://api.slack.com/scopes) — required scopes for channel delivery
