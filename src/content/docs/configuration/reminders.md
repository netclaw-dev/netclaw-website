---
title: "Reminders"
description: "Schedule recurring and one-time reminder prompts."
---

Reminders are autonomous agent sessions that fire on a schedule. You define what the agent should do, pick a schedule (once, interval, or cron), and optionally deliver results to Slack, Discord, or Mattermost. The daemon handles the rest.

The scheduling subsystem is enabled by default. For CLI commands that create and manage reminders, see [`netclaw reminder`](/cli/reminder/).

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
| `delivery.transport` | string | Channel | `"slack"`, `"discord"`, or `"mattermost"` |
| `delivery.address` | string | Channel | Target channel or user. Format depends on transport — see [In-session vs. out-of-session](#in-session-vs-out-of-session). |
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
| `Channel` | Agent posts results to a channel or DM via the generic `send_channel_message` tool | `transport` + `address`, with that channel configured |
| `CurrentSession` | Re-enters the originating conversation (a Slack/Discord thread, or a TUI/SignalR session) it was created in | Active session at creation; Slack, Discord, TUI, or SignalR only |

When `deliveryRequired` is `true` (the default) and delivery kind is `Channel`, the execution is marked **failed** if the agent doesn't post to the target channel. Each failed execution emits a `ReminderExecutionFailed` warning alert. After 5 consecutive failures, the reminder is auto-disabled and a `ReminderAutoDisabled` critical alert fires.

:::caution
Mattermost is the exception. Channel delivery posts correctly (the agent calls `send_channel_message`), but the daemon doesn't yet track that call as a named delivery the way it does for Slack and Discord — so `deliveryRequired: true` can mark a Mattermost channel reminder failed even after it posted. Set `deliveryRequired: false` for Mattermost channel reminders. (`CurrentSession` isn't an option here: `set_reminder` only accepts it for Slack, Discord, TUI, and SignalR sessions.)
:::

For `CurrentSession` delivery, the daemon waits up to 1 hour to confirm the reminder posted back to its originating session. If that session is gone, or delivery is never confirmed within the hour, the execution is marked failed.

To create a channel reminder, use `netclaw reminder create --delivery channel` or set `delivery.kind` to `"Channel"` in the JSON directly.

## In-session vs. out-of-session

The delivery kind decides whether a reminder talks back to a live conversation or starts a fresh one — usually the choice an agent is making when it schedules one for you.

**In-session (`CurrentSession`).** The reminder re-enters the conversation it was created in and replies there, like a deferred turn. "Remind me in this thread to follow up after lunch" is a `CurrentSession` reminder. It needs that session to still exist when it fires — if the thread is long gone, the delivery can't land. `set_reminder` accepts it only from Slack, Discord, TUI, and SignalR sessions (not Mattermost).

**Out-of-session (`Channel`).** The reminder runs on its own, with no originating conversation, and proactively posts to a target you name. "Every weekday at 9am, post a standup summary to #ops" is a `Channel` reminder. It depends on no live session, so it's the right choice for anything recurring or unattended.

For `Channel` delivery, the target format depends on the transport, and `set_reminder` validates it when the reminder is created:

| Transport | Channel target | User / DM target |
|-----------|----------------|------------------|
| `slack` | `#channel-name` or a `C…`/`G…` channel ID | `@username` or a `U…` user ID |
| `discord` | `channel:<channelId>` or `<#channelId>` | `dm:<userId>`, `@<userId>`, or `<@userId>` (delivers to that user's DM) |
| `mattermost` | `channel:<channelId>` | `@<userId>` (delivers to that user's DM) |

Discord DM delivery needs `AllowDirectMessages: true` and the target user in the channel's `AllowedUserIds` — the same [access controls](/channels/discord/#access-control) that gate live Discord chat. Mattermost and Discord IDs are ambiguous snowflakes on their own, so both transports require the `channel:` / `dm:` / `@` prefix — a bare ID is rejected with a disambiguation error.

## Runtime behavior

| Setting | Value | Configurable? |
|---------|-------|---------------|
| Execution timeout | 300 seconds | No |
| Max concurrent executions | 3 | No |
| History retention | 500 entries per reminder | No |
| Overflow handling | FIFO queue (unbounded) | — |

When all 3 slots are busy, incoming fires queue and run as slots open.

Recurring reminders get an automatic instruction appended: if the agent determines the reminder's purpose has been permanently fulfilled, it should call `cancel_reminder` to stop future fires.

If a run produces no session output for 20 minutes, the daemon concludes it as failed with `Reminder execution stalled: no session output for 00:20:00.` and releases the execution slot. This is a backstop against a wedged run holding its slot forever — a stall counts as a failure, so it feeds the failure counter and the visibility below.

## Failure visibility

A reminder that quietly stops working used to be invisible until someone went looking. Now failures surface two ways.

**On demand.** [`netclaw reminder status <id>`](/cli/reminder/#status) reports the failure streak, skipped-fire count, whether a run is in flight, and the last five outcomes — the fastest way to see whether a reminder is healthy.

**Pushed to the channel.** When a `Channel`-delivery reminder fails, netclaw posts a plain-language notice to that reminder's **destination channel** — the same place its results normally land, so the failure shows up where you're already looking:

```
Reminder "Daily Standup Summary" failed: send_channel_message: channel not found
```

The notices are bounded by the auto-disable threshold, so a broken reminder posts at most five times before it disables itself. On that fifth, threshold-hitting failure the message is the auto-disable notice instead — the plain failure notice is suppressed so the most important event isn't doubled:

```
Reminder "Daily Standup Summary" was automatically disabled after 5 consecutive failures. Last error: send_channel_message: channel not found
```

Two things are deliberately *not* posted to the channel:

- **Skipped (duplicate) fires** — a fire dropped because the previous run was still executing isn't a failure, so it's counted (visible in `reminder status`) but never posted.
- **`CurrentSession` and `None` failures** — these have no destination channel. They surface through the [operational alert sink](/observability/operational-alerts/) (`ReminderExecutionFailed`, `ReminderAutoDisabled`) and your [notification webhooks](/configuration/webhooks/#outbound-notification-webhooks) instead.

Channel delivery of a failure notice is fire-and-forget — if the channel itself is unreachable, netclaw logs it rather than blocking the reminder manager.

## Auto-disable and expiration

Two mechanisms stop reminders automatically.

### Consecutive failures

After 5 failed executions in a row, the reminder is disabled and a `ReminderAutoDisabled` critical alert fires via your [notification webhooks](/configuration/webhooks/#outbound-notification-webhooks). A single successful execution resets the failure counter. Check the streak any time with [`netclaw reminder status <id>`](/cli/reminder/#status), and see [Failure visibility](#failure-visibility) for how failures reach you before the reminder disables.

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

Start with `netclaw reminder status <id>` — the `Consecutive fails` count tells you how close it is to auto-disabling, and `Recent history` shows the actual error. For a channel reminder, the same error is also posted to its destination channel. The usual culprit is a missing Slack channel or an invalid delivery target: fix it, then `netclaw reminder enable <id>` if it already auto-disabled.

### Reminder runs but drops most fires

If `netclaw reminder status <id>` shows a climbing `Skipped (duplicate)` count, the reminder is scheduled more often than a run takes to finish, so each new fire is dropped while the previous run is still executing. Lengthen the interval or make the work faster.

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
