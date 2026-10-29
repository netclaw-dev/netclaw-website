---
title: "Reminders"
description: "Schedule recurring and one-time agent sessions, and control where they run, who they run as and how they deliver results."
---

Reminders are autonomous agent sessions that fire on a schedule. You define what the agent should do, pick a schedule (once, interval, or cron), and optionally deliver the result to Slack, Discord, or Mattermost. The daemon handles the rest.

Nobody is in the chat when a reminder fires, so it can't answer an approval prompt. A tool call that would prompt is denied. To prepare a reminder for that, read [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/). For the commands that create and manage reminders, see [`netclaw reminder`](/cli/reminder/).

## Global configuration

The scheduling subsystem is on by default. Toggle it in `~/.netclaw/config/netclaw.json`:

```json
{
  "Scheduling": {
    "Enabled": true
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `true` | When `false`, reminders stop firing and the agent's reminder tools (`set_reminder`, `cancel_reminder`, `list_reminders`, `get_reminder_history`, `run_reminder`) are unregistered. |

Disabling doesn't delete existing reminders. Re-enable and they pick up where they left off. The daemon restarts itself when `netclaw.json` changes.

## Filesystem layout

Reminder data lives alongside other netclaw state:

```text
~/.netclaw/schedules/reminders/
├── daily-standup.json            # reminder definition
├── daily-standup.history.jsonl   # execution history (append-only)
├── infra-check.json
└── infra-check.history.jsonl
```

Each reminder gets a JSON definition and a JSONL history log. The filename is the reminder ID. History is capped at 500 entries per reminder, and the oldest entries are trimmed automatically. Each run also gets a session, with its log at `~/.netclaw/sessions/reminder_<id>_<fire time>-<hash>/logs/session.log`.

## Reminder definition schema

This is the stored format, and what `netclaw reminder validate` checks:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Kebab-case slug, up to 50 characters. `create` and `set_reminder` normalize whatever you pass. The prefix `restart-resume-` is reserved: both refuse it, and `netclaw reminder import` fails with HTTP 400 for a file that uses it |
| `title` | string | Yes | Human-readable name |
| `instructions` | string | Yes | Prompt for the agent session when the reminder fires |
| `schedule.type` | enum | Yes | `OneShot`, `Interval`, or `Cron` |
| `schedule.fireAtMs` | long | OneShot | Unix timestamp in milliseconds. Must be in the future |
| `schedule.intervalTicks` | long | Interval | .NET ticks (1 tick = 100 ns). `create` fills this in from `2h` and similar |
| `schedule.cronExpression` | string | Cron | 5-field cron expression, UTC unless it starts with `CRON_TZ=<zone> ` |
| `schedule.originalExpression` | string | No | What you typed, for display (`"6h"`, `"0 */6 * * *"`) |
| `delivery.kind` | enum | Yes | `CurrentSession`, `Channel`, or `None` |
| `delivery.transport` | string | Channel | `slack`, `discord`, or `mattermost` |
| `delivery.address` | string | Channel | Target channel or user. See [Reminder targets](#reminder-targets) |
| `delivery.sessionId` | string | CurrentSession | Filled in by the daemon from the creating session |
| `deliveryRequired` | bool | No | Default `true`. Fails the run if a `Channel` delivery doesn't happen. No effect for `CurrentSession` |
| `deliveryInstructions` | string | No | Guidance for what to put in the delivery message |
| `audience` | enum | Yes | `Personal`, `Team`, or `Public`. Decides which tools and files the run can use. See [Audience scoping](#audience-scoping) |
| `boundary` | string | Yes | Trust boundary: `boundary:personal`, `boundary:team`, `boundary:public` or `boundary:trusted-instance`. The daemon rejects one the audience doesn't allow, such as `boundary:personal` on a Team reminder |
| `enabled` | bool | No | Default `true` |
| `expiresAtMs` | long | No | Auto-disable after this time. Meant for recurring reminders |
| `createdBy`, `createdAtMs`, `updatedAtMs` | string, long | No | Bookkeeping. `create` and `set_reminder` both write `llm-tool` |
| `consecutiveFailures`, `terminalOutcome` | int, enum | No | Maintained by the daemon. See [Auto-disable](#auto-disable-and-expiration) |

A file without `audience` or `boundary` is rejected when the daemon loads it, and the reminder is never scheduled. `netclaw reminder validate` fails with `missing required properties including: 'boundary'`.

### Minimal definition

```json
{
  "id": "infra-check",
  "title": "Infrastructure health check",
  "instructions": "Run netclaw doctor and summarize any degraded services.",
  "schedule": {
    "type": "Interval",
    "intervalTicks": 216000000000,
    "originalExpression": "6h"
  },
  "delivery": {
    "kind": "None"
  },
  "audience": "Personal",
  "boundary": "boundary:personal"
}
```

### Channel delivery definition

```json
{
  "id": "daily-standup",
  "title": "Daily standup summary",
  "instructions": "Check yesterday's reminder history and git commits. Post a standup summary.",
  "schedule": {
    "type": "Cron",
    "cronExpression": "CRON_TZ=America/Chicago 0 9 * * MON-FRI",
    "originalExpression": "CRON_TZ=America/Chicago 0 9 * * MON-FRI"
  },
  "delivery": {
    "kind": "Channel",
    "transport": "slack",
    "address": "C12345678"
  },
  "deliveryRequired": true,
  "deliveryInstructions": "Post the summary to the standup channel. Keep it under 5 bullet points.",
  "audience": "Team",
  "boundary": "boundary:team"
}
```

Check a file with `netclaw reminder validate <file>`, then load it with [`netclaw reminder import`](/cli/reminder/#import). Or skip the file and use [`netclaw reminder create`](/cli/reminder/#create).

## Schedule types

| Type | Fires | Minimum | Format |
|------|-------|---------|--------|
| `OneShot` | Once, then stops | Any future time | Relative duration (`30m`, `2h`) or ISO 8601 timestamp |
| `Interval` | Repeats on a fixed duration | 60 seconds | Duration string (`2m`, `2h`, `1d`) |
| `Cron` | On a cron schedule | None | 5-field cron expression, UTC or `CRON_TZ=<zone>` |

An interval reminder fires its first run one interval after you create or re-enable it, not at a fixed wall-clock time.

### Time zones

Cron expressions run in UTC unless they start with `CRON_TZ=<IANA zone> `. The prefix makes the schedule follow that zone, including daylight saving changes:

```bash
netclaw reminder create standup cron "CRON_TZ=Europe/Brussels 0 9 * * MON-FRI" "Post the standup summary."
```

Use an IANA zone ID like `America/Chicago`. IDs with spaces (`Eastern Standard Time`) and unknown zones are rejected when you create, import or validate the reminder:

```text
[FAIL] Error: Invalid CRON_TZ prefix. Unknown time zone 'Eastern'. Use an IANA id such as America/Chicago.
```

## Reminder targets

Delivery decides whether a reminder talks back to a live conversation or starts a fresh one.

| Kind | What happens | Requirements |
|------|-------------|--------------|
| `None` | The agent runs silently. The result is recorded in history only | Nothing |
| `Channel` | The agent posts the result to a channel or DM with the `send_channel_message` tool | `transport` and `address`, with that channel configured |
| `CurrentSession` | The reminder re-enters the conversation it was created in and replies there | A live session at creation: Slack, Discord, Mattermost, TUI or SignalR |

**`CurrentSession`** is a deferred turn. "Remind me in this thread after lunch" is a `CurrentSession` reminder. The session has to still exist when it fires. The run ends as soon as the session accepts the fire, and netclaw doesn't wait for or retry the reply. If posting the reply then fails for good, the session logs an error and sends a `reminder.delivery.failed` warning alert. While an earlier fire of the same reminder is still queued in that session, the newer fire is dropped.

**`Channel`** needs no live session and proactively posts to a target you name. "Every weekday at 9am, post a standup summary to #ops" is a `Channel` reminder, and it's the right choice for anything recurring. The agent sets `delivery_kind` to `current_session`, `channel` or `none` when it calls `set_reminder`, and the CLI offers `none` and `channel`.

The target format depends on the transport. `set_reminder` and `create` check it when the reminder is created.

| Transport | Channel target | User or DM target |
|-----------|----------------|-------------------|
| `slack` | `#channel-name` or a `C...`/`G...` channel ID | `@username` or a `U...` user ID |
| `discord` | `channel:<channelId>` or `<#channelId>` | `dm:<userId>`, `@<userId>` or `<@userId>`, delivered to that user's DM |
| `mattermost` | `channel:<channelId>` | `@<userId>`, delivered to that user's DM |

Discord and Mattermost IDs look the same for channels and users, so both require the `channel:`, `dm:` or `@` prefix. A bare ID is rejected with a disambiguation error. Discord DM delivery needs `AllowDirectMessages: true` and the user in `AllowedUserIds`, the same [access controls](/channels/discord/#access-control) that gate live Discord chat.

When `deliveryRequired` is `true` (the default) and the delivery kind is `Channel`, the run fails if the agent doesn't call `send_channel_message`, or if the call returns an error. A failed run emits a `ReminderExecutionFailed` warning alert.

## Audience scoping

A reminder's `audience` is the audience its session runs as, which decides its tools, file access and approval policy exactly as in a chat of that audience. A reminder made by the agent inherits the audience of the chat that created it. A reminder made with the CLI is Personal. The agent can pass a lower audience to `set_reminder`, and can't pass a higher one than its own.

The reminder tools only see reminders at or below the caller's audience:

| Caller | Reminders it can list, run, cancel, read history for and update |
|--------|------------------------------------------------------------------|
| Personal chat | Personal, Team, Public |
| Team chat | Team, Public |
| Public chat | Public |
| CLI and HTTP API (operator) | All |

The run's tool access follows the deployment posture as well: under a `Team` posture, a reminder created for the `Personal` audience, for example from a Slack DM, runs with `Team` access. After an upgrade, `run_reminder` refuses such an older reminder and a narrower chat doesn't list it, so recreate it from a chat.

A reminder outside the caller's scope reads as `not found`, and `set_reminder` can't overwrite it. Personal and Team sessions get the reminder tools by default, and Public sessions don't. If you've stored an explicit `AllowedTools` list for Team, it replaces the default, so add `run_reminder` to it.

### Test a reminder with run_reminder

`run_reminder` carries out an existing reminder's exact prompt in the current chat, so a person can answer its approval prompts. Use it through the `/run-reminder <id>` slash command or `netclaw reminder run <id>`. It's the way to save the grants a scheduled run needs, and the [unattended runs guide](/guides/unattended-runs/#pre-approve-by-testing-the-reminder) shows it end to end.

- The chat must have the reminder's own audience. A Personal chat can't test a Team reminder, because the test would have wider permissions than the scheduled run. The tool says which audience to use.
- A CLI chat is Personal, narrowed to your [deployment posture](/security/security-model/#deployment-postures). On a Personal host `netclaw reminder run` only tests Personal reminders, so test a Team reminder from a Team channel.
- It refuses to run in a chat where nobody can answer prompts, such as a headless script.
- A one-shot that has already ended can't be tested: `run_reminder` answers `Reminder '<id>' ended (<outcome>) at <time>. A one-shot reminder deletes itself after it ends. Set it again with set_reminder to run it.` Test a one-shot before its fire time.
- A reminder reaches only the child runs of the session where it fires, so a test in another chat doesn't prove the scheduled run can start one.
- The steps are real. The test doesn't change the schedule or the history.

To watch a reminder fire inside the current conversation instead, ask the agent to call `set_reminder` with a short one-shot (`10s`) and `current_session` delivery.

## Runtime behavior

| Setting | Value | Configurable? |
|---------|-------|---------------|
| Execution timeout | 1 hour per attempt | No |
| Stall timeout | 20 minutes without session output | No |
| History retention | 500 entries per reminder | No |

Each reminder runs at most one occurrence at a time. If a fire arrives while the previous run is still going, netclaw skips it and counts it. There's no limit on how many different reminders run at once. 0.26.0 removed the old capacity gate that skipped reminders when the daemon was busy.

A run that produces no session output for 20 minutes concludes as failed with `Reminder execution stalled: no session output for 00:20:00.` and releases its slot. A stall counts as a failure.

A message from the operator or a trusted person during a reminder turn ends that turn after its current tool batch. The reminder records success and skips its remaining steps, though child runs the turn already started carry on. An open child approval request holds reminder fires for that session until the prompt closes. After downtime a reminder gets at most one catch-up fire.

Recurring reminders get an instruction appended: if the agent decides the reminder's purpose is permanently fulfilled, it should call `cancel_reminder`.

## Failure visibility

Failures surface two ways.

**On demand.** [`netclaw reminder status <id>`](/cli/reminder/#status) reports the failure streak, skipped-fire count, whether a run is in flight and the last five outcomes.

**Pushed to the channel.** When a `Channel` reminder fails, netclaw posts a plain-language notice to that reminder's destination channel, where its results normally land:

```text
Reminder "Daily standup summary" failed: send_channel_message: channel not found
```

A broken reminder posts at most five times before it disables itself. On the fifth, threshold-hitting failure the message is the auto-disable notice instead:

```text
Reminder "Daily standup summary" was automatically disabled after 5 consecutive failures. Last error: send_channel_message: channel not found
```

Two things aren't posted to the channel:

- **Skipped fires.** A fire dropped because the previous run was still going isn't a failure. It's counted in `reminder status` and never posted.
- **`CurrentSession` and `None` failures.** They have no destination channel, so they go out as [operational alerts](/observability/operational-alerts/) (`ReminderExecutionFailed`, `ReminderAutoDisabled`, and `reminder.delivery.failed` when a `CurrentSession` reply can't be posted) to the [alert destinations](/observability/operational-alerts/#configure-alert-destinations) you set up.

A failure to schedule the next occurrence emits `ReminderScheduleFailed`, counts toward auto-disable and raises the same notices. Posting a notice is fire-and-forget. If the channel is unreachable, netclaw logs it and carries on.

:::note
A tool call that is denied, whether nobody could approve it or the audience's policy forbids it, doesn't fail the run. The agent gets the denial, usually says so in its reply, and the run is recorded as `denied` in `history` and `status`. netclaw acknowledges it, doesn't retry it and doesn't count it toward auto-disable, because a retry would be denied the same way. It raises a `reminder.tool_denied` warning alert, once per distinct denial until the reminder's next `ok` run. The [unattended runs guide](/guides/unattended-runs/#troubleshooting) shows how to fix it.
:::

## Auto-disable and expiration

Two mechanisms stop reminders automatically.

### Consecutive failures

After 5 failed runs in a row, the reminder is disabled and a `ReminderAutoDisabled` critical alert fires, and `terminalOutcome` becomes `Failed`. A retry of a recurring occurrence that expires counts as one failure. `denied` runs don't count. A single success resets the counter. Fix the cause, then re-enable:

```bash
netclaw reminder enable <id>
```

Enabling clears the failure count and the terminal outcome, and reschedules from now.

### Expiration

Set `expiresAtMs` (or `--expires-in` on the CLI) to stop a recurring reminder after a deadline. It fires normally until then and disables on the next scheduled fire. `--expires-in` and `set_reminder` reject it on one-shot reminders.

## Agent tools

The agent manages reminders through five tools, all in the `scheduling` group:

| Tool | Description |
|------|-------------|
| `set_reminder` | Create or update (upsert) a reminder |
| `cancel_reminder` | Delete a one-shot, or disable a recurring reminder and keep its definition |
| `list_reminders` | List active or all reminders |
| `get_reminder_history` | Return execution history (default 20, max 100) |
| `run_reminder` | Return a reminder's exact prompt so the agent can run it in this chat |

These tools are registered only when `Scheduling.Enabled` is `true`, and each one is limited to the reminders its audience can see.

## One-shot cleanup

A one-shot reminder deletes itself when it ends, whether it was delivered, failed, was denied, was cancelled or expired. It leaves `netclaw reminder list` at once. netclaw keeps an end record with the outcome (`completed`, `failed`, `cancelled` or `expired`) and the run history for 12 days, then purges both. `netclaw reminder status` and `history` answer during that time. A one-shot whose run was `denied` ends as `failed`, and its end record keeps the denial text and the prompt, so you can set it again once the grant exists. A one-shot that fails is retried before it ends. A one-shot that comes due while the daemon is down is still delivered when it returns, for up to 7 days after its time. Past that, it expires.

At startup and every 12 hours, the daemon sweeps one-shots whose time has passed. It ends leftovers, finishes an end that a crash interrupted, and purges end records older than 12 days. A disabled one-shot whose time has passed ends as `cancelled`. Expired recurring reminders are disabled and kept. See [`netclaw reminder`](/cli/reminder/) for the CLI view.

## Troubleshooting

### Reminder runs show denied

**Symptom:** `reminder history` or `reminder status` shows `denied`, and the file wasn't written or the command didn't run.

**Cause:** The agent called a tool that needs approval, and nobody could answer. The call was denied, the agent said so, and the run finished without a failure count.

**Fix:** Follow the [unattended runs guide](/guides/unattended-runs/). The daemon log has `approval_required_unattended` with the session that made the call.

### Reminder fires but delivery fails

**Symptom:** `Consecutive fails` is climbing and `Recent history` shows a delivery error.

**Cause:** Usually a missing Slack channel or an invalid delivery target.

**Fix:** Run `netclaw reminder status <id>` for the actual error. A channel reminder also posts it to its destination channel. Fix the target, then `netclaw reminder enable <id>` if it already disabled itself.

### Skipped occurrences climbs

**Symptom:** `Skipped occurrences` goes up on every fire.

**Cause:** A run takes longer than the interval, so each new fire lands while the last run is still going.

**Fix:** Lengthen the schedule or shrink the work. The daemon log says `source=active` for this. `arrived too late to finish before its delivery deadline` means the scheduler delivered the fire too late to finish.

### Reminder doesn't fire

**Symptom:** Nothing at the scheduled time and `Skipped occurrences` is 0.

**Cause:** The daemon is down, scheduling is off, the reminder is disabled, or it was rejected on load.

**Fix:** Run `netclaw status`, check `Scheduling.Enabled`, and `netclaw reminder show <id>` to confirm `enabled` is `true`. A definition missing `audience` or `boundary` is rejected when loaded, so look for it in `netclaw reminder list`.

### Cron fires at the wrong hour

**Symptom:** A `0 9 * * *` reminder fires at 9:00 UTC.

**Cause:** Cron runs in UTC unless you say otherwise.

**Fix:** Add a prefix: `CRON_TZ=America/Chicago 0 9 * * *`.

## What's next

Run `netclaw reminder list` to confirm the reminder appears with the right schedule and next fire time. After it fires, `netclaw reminder history <id>` shows the session ID to pass to [`netclaw sessions`](/cli/sessions/). If it needs shell or file access, test it with `netclaw reminder run <id>` before the schedule does.

## Related pages

- [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/) - approve a reminder's tool calls ahead of time
- [`netclaw reminder`](/cli/reminder/) - CLI reference for every subcommand
- [How tool approvals work](/security/approvals/) - the model behind grants and unattended denial
- [Operational alerts](/observability/operational-alerts/) - `ReminderExecutionFailed`, `ReminderScheduleFailed` and `ReminderAutoDisabled`
- [Webhooks](/configuration/webhooks/) - the other kind of unattended session
- [Data retention](/configuration/data-retention/) - what the daemon deletes on its own, including ended one-shot reminders

## Resources

- [Crontab.guru](https://crontab.guru/) - visual editor for cron schedule expressions
- [Cron expression syntax (Wikipedia)](https://en.wikipedia.org/wiki/Cron#Cron_expression) - reference for the 5-field cron format
- [IANA time zone database (Wikipedia)](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) - zone IDs for `CRON_TZ=`
- [ISO 8601 (Wikipedia)](https://en.wikipedia.org/wiki/ISO_8601) - timestamp format for one-shot schedules
- [Locate your Slack channel ID](https://slack.com/help/articles/221769328-Locate-your-Slack-URL-or-ID) - find channel IDs for delivery targets
