---
title: "netclaw reminder"
description: "Create, inspect and test reminders that run agent sessions once, on an interval, or on a cron schedule."
---

`netclaw reminder` manages scheduled agent sessions. A reminder fires on a schedule (once, on an interval, or via [cron](https://crontab.guru/)), runs a session with your instructions, and can post the result to a channel. Use `reminder run` to test one before the schedule does, because a scheduled run can't answer approval prompts. The [unattended runs guide](/guides/unattended-runs/) explains why and how to prepare.

Every subcommand except `validate` needs a running daemon. Without one you get `[FAIL] reminder <subcommand>: requires a running daemon.` and exit code 1. Start it with `netclaw daemon start`, or `docker restart <container>` in Docker.

## Usage

```bash
netclaw reminder <subcommand> [options]
```

## Subcommands

| Subcommand | Description |
|-----------|-------------|
| `list` | List reminders as a table, enabled or not. `--json` for scripts |
| `create` | Create or update a reminder |
| `ui` / `tui` | Interactive reminder builder |
| `show <id>` | Show a reminder's details |
| `history <id>` | Show execution history |
| `status <id>` | Show failures, skipped fires, next fire and recent runs |
| `run <id>` | Open a chat that tests the reminder now |
| `enable <id>` | Enable a reminder |
| `disable <id>` | Disable a reminder |
| `cancel <id>` | Delete a one-shot reminder, or disable a recurring one |
| `delete <id>` | Permanently delete a reminder and its history |
| `import <file>` | Import a reminder from a JSON file |
| `validate <file>` | Validate a reminder file offline, no daemon needed |

## Interactive TUI

```bash
netclaw reminder ui
```

The Reminder Builder walks you through six steps: title, schedule type, schedule value, instructions, delivery guidance, and review.

![Recording of the Reminder Builder: typing a title, choosing a cron schedule, entering instructions, reviewing, and the Reminder created screen](/screenshots/output/reminder.gif)

The recording runs about 19 seconds from step 1 to the "Reminder created" screen, which offers Create another or Quit.

Navigate with the arrow keys and Enter. Esc goes back a step and does nothing on the first step. Ctrl+Q quits from anywhere. Ctrl+Enter adds newlines in multi-line fields.

![Reminder Builder step 6 of 6, Review, showing the title daily-uptime-check, type cron, schedule 0 9 * * *, the instructions and delivery guidance, with Create reminder highlighted](/screenshots/output/reminder-builder-review.png)

The review step repeats everything you entered, so this is the last chance to go back with `Esc`.

## `list`

```bash
netclaw reminder list [--json]
```

Prints a table with one row per reminder: `id`, `status`, `failures`, `schedule`, `next_fire` and `title`. With none, it prints `No reminders.`

```text
id                  status    failures  schedule                                    next_fire             title
---------------------------------------------------------------------------------------------------------------
daily-uptime-check  enabled   0         runs daily at 09:00 UTC                     2026-10-30 09:00:00Z  daily-uptime-check
rec-demo            disabled  0         runs every 30m                              -                     rec-demo
weekly-report       enabled   0         runs every Monday at 09:00 America/Chicago  2026-11-02 15:00:00Z  Weekly report
```

![netclaw reminder list printing a table with two cron reminders, daily-uptime-check and weekly-report, each with its schedule in words and next fire time](/screenshots/output/reminder-list.png)

The schedule is spelled out in words, and `next_fire` is always UTC, even when the schedule names another zone, as `weekly-report` does with America/Chicago. `status` is `enabled`, `disabled`, or `failed` for a recurring reminder that gave up. A one-shot deletes itself when it ends, so it leaves the list the moment it runs, fails or is cancelled. Use [`status`](#status) or [`history`](#history) to see how it ended. An unknown option exits 1 with a usage line.

`--json` prints a JSON array of `id`, `title`, `enabled`, a readable `schedule`, `nextFire`, `expiresAt`, `audience`, `consecutiveFailures` and `terminalOutcome` for each reminder, which is what `list` printed before 0.28. With none, it prints `No active reminders.`

## `create`

```bash
netclaw reminder create <id> <scheduleType> <schedule> "<prompt>" [options]
```

| Positional | Description |
|-----------|-------------|
| `id` | Stable identifier. netclaw lowercases it, turns other characters into dashes and cuts it to 50 characters, so `Daily Standup` becomes `daily-standup` |
| `scheduleType` | `once`, `interval`, or `cron` |
| `schedule` | Duration, timestamp or cron expression (see [Schedule types](#schedule-types)) |
| `prompt` | What the agent should do when the reminder fires |

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--name <title>` | Human-readable title | Same as `id` |
| `--delivery <kind>` | `none` or `channel` | `none` |
| `--transport <transport>` | Channel transport: `slack`, `discord` or `mattermost` | - |
| `--address <target>` | Where to post: a channel name, `@user` or an ID. [Formats per transport](/configuration/reminders/#reminder-targets) | - |
| `--expires-in <duration>` | Auto-disable after this long, for recurring reminders (`24h`, `7d`) | - |

IDs that start with `restart-resume-` belong to the system, and `create` refuses them with `The reminder ID prefix 'restart-resume-' is reserved for the system.` If a reminder with that ID already exists, `create` updates it. A reminder created here runs with the Personal audience, because the CLI is the operator. To schedule one for a lower audience, ask the agent from a chat in that audience. Under a Team or Public [deployment posture](/security/security-model/#deployment-postures), tool access follows the posture's audience, so a Personal reminder can be refused by `run_reminder`. Create it again from a chat in the narrower audience. See [audience scoping](/configuration/reminders/#audience-scoping).

`--transport` only works for a channel you've configured. Without the channel, the command fails with `Unknown transport 'slack'. Available transports: [none].` Set the channel up in `netclaw config` first. The CLI can't set a `current_session` target. That one comes from the agent, inside the conversation it should reply in.

### Schedule types

| Type | What it does | Examples |
|------|-------------|----------|
| `once` | Fires one time, then deletes itself | `30m`, `2h`, or an [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601) timestamp like `2030-06-01T18:00:00Z` |
| `interval` | Repeats on a fixed duration | `2m`, `2h`, `1d` |
| `cron` | Fires on a [cron schedule](https://crontab.guru/): 5 fields, UTC unless you add a `CRON_TZ=` prefix | `0 */6 * * *`, `CRON_TZ=Europe/Brussels 0 9 * * MON-FRI` |

Intervals under 60 seconds are rejected (`Minimum interval is 60 seconds.`). Anything longer fires on every interval. A `once` reminder still delivers up to seven days late if the daemon was down at its fire time, and a recurring one gets at most one catch-up fire after downtime. The [configuration page](/configuration/reminders/#schedule-types) has the details.

A `CRON_TZ=` prefix takes an IANA zone ID without spaces, like `America/Chicago`. Windows names such as `Eastern Standard Time` and unknown zones are rejected:

```text
[FAIL] Error: Invalid CRON_TZ prefix. Unknown time zone 'Eastern'. Use an IANA id such as America/Chicago.
```

### Examples

#### Recurring cron reminder in your time zone

```bash
netclaw reminder create weekly-report cron "CRON_TZ=America/Chicago 0 9 * * MON" \
  "Summarize last week's merged pull requests and open incidents." \
  --name "Weekly report"
```

#### One-shot with Slack delivery

```bash
netclaw reminder create stir-trek-talk once 2h \
  "Remind me to head to the Stir Trek talk room" \
  --name "Head to Stir Trek talk room" \
  --delivery channel --transport slack --address "#general"
```

A one-shot reminder deletes itself when it ends, whether it ran, failed, was denied, was cancelled or expired. `create` says so in its reply. Re-creating a reminder with the same ID starts a fresh one.

#### Cron health check every six hours

```bash
netclaw reminder create infra-check cron "0 */6 * * *" \
  "Run netclaw doctor and summarize any degraded services."
```

## `show`

```bash
netclaw reminder show <id>
```

Prints a summary of the reminder: schedule in words, next fire, instructions, delivery fields, `audience`, `consecutiveFailures` and `terminalOutcome`. This is a view for reading, not the stored definition, so it's not what `import` expects. The stored file is `~/.netclaw/schedules/reminders/<id>.json`.

For a one-shot that has ended, `show` exits 1, because its definition is gone:

```text
[FAIL] Reminder 'once-demo' ended (cancelled) at 2026-10-29 15:19:02Z and its definition was deleted. Its history stays readable until 2026-11-10 15:19:02Z: netclaw reminder history once-demo
```

## `history`

```bash
netclaw reminder history <id> [--last N]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--last <N>` | Number of history records to return | `20` |

Output is a table with the columns `fired_at`, `status` (`ok`, `denied` or `failed`), `duration_ms` and `session_id`. Use the session ID to see what the agent did with [`netclaw sessions`](/cli/sessions/).

```text
fired_at                   status    duration_ms   session_id
-------------------------------------------------------------------------------
2026-10-14 04:18:00Z       denied    25847         reminder/disk-note/1791951480000
2026-10-14 04:24:00Z       ok        25754         reminder/disk-note/1791951840000
```

A run is `denied` when a tool call was [denied because nobody could approve it](/guides/unattended-runs/#what-an-unattended-run-can-do), or because the audience's policy forbids the tool or path. For a recurring reminder, a denial isn't a failure. netclaw doesn't retry the run or count it toward auto-disable, and it raises a `reminder.tool_denied` alert once per distinct denial until the next `ok` run. Save the grant the call needs, and the next run goes through. A one-shot has no next run, so a denial ends it as `failed`. Its end record keeps the denial text and the prompt, and you set the reminder again once the grant exists. A run is `ok` when the session finished and nothing was denied, even if the agent couldn't do its job otherwise.

## `status`

```bash
netclaw reminder status <id>
```

The first command to run when a reminder misbehaves. Where `history` lists raw runs, `status` shows whether it's enabled, whether a run is in flight, when it fires next, how close it is to auto-disabling, and its last five outcomes.

```text
$ netclaw reminder status disk-note
Reminder:            disk-note
Enabled:             True
Executing now:       False
Next fire:           Wednesday, October 7 at 3:27 PM Coordinated Universal Time (2026-10-07 15:27:00Z)
Consecutive fails:   0
Skipped occurrences: 0
Terminal outcome:    none
Recent history (newest first):
  2026-10-07 15:24:00Z  ok
```

| Field | Meaning |
|-------|---------|
| `Enabled` | Whether the reminder is active. Flips to `False` on its own after 5 consecutive failures, never after `denied` runs. |
| `Executing now` | A run is in flight right now. |
| `Next fire` | Next scheduled time, or `not scheduled` when disabled. |
| `Consecutive fails` | Current failure streak. Auto-disables at 5, and one success resets it to 0. |
| `Skipped occurrences` | Fires dropped because the previous run was still going, or because the scheduler delivered one too late to finish. Counted since daemon start. |
| `Terminal outcome` | `none` while the reminder can still run. `Failed` after a recurring reminder gave up. |
| `Ended` | For a one-shot that has ended: the outcome (`completed`, `failed`, `cancelled` or `expired`), when, and until when its history stays. Replaces `Terminal outcome`. |
| `Last error`, `Prompt` | A `failed` one-shot also prints these, so you can set it again. `Prompt` appears only here, not in `show`. |
| `Occurrence status`, `Occurrence attempts`, `Next retry`, `Last failure` | Shown for a one-shot that has a pending occurrence, including retries after a failure. |
| `Recent history` | The five most recent runs, newest first, with the error for `failed` and `denied` ones. |

A one-shot deletes itself when it ends, but `status` and `history` keep answering for 12 days. `status` then shows `Enabled: False`, `Next fire: not scheduled` and the `Ended:` line instead of `Terminal outcome:`:

```text
Ended:               cancelled at 2026-10-29 15:19:02Z (history stays until 2026-11-10 15:19:02Z)
```

An unknown ID exits non-zero with `Reminder '<id>' not found`.

A climbing `Skipped occurrences` count means the reminder is scheduled more often than a run takes to finish. See [troubleshooting](/configuration/reminders/#troubleshooting).

## `run`

```bash
netclaw reminder run <id>
```

Opens a normal chat with `/run-reminder <id>` as the first message. The agent loads the `run-reminder` skill, warns that the test does real work and asks you to confirm. Answer yes, and it carries out the reminder's exact prompt in that chat and asks you to approve each gated call, so you can save "Always" grants that the scheduled run will use. Nothing is recorded in the reminder's history, and the schedule doesn't change.

The steps are real. A reminder that deletes files deletes them, and one that posts to a channel posts there.

A test only runs in a chat with the reminder's own audience. A CLI chat is Personal, narrowed to your [deployment posture](/security/security-model/#deployment-postures), so on a Personal host `reminder run` tests Personal reminders and on a Team host it tests Team ones. For a reminder at another audience, run `/run-reminder <id>` in a channel with that audience instead. If the reminder is a one-shot that already ended, the agent says so and tells you to set it again. The [unattended runs guide](/guides/unattended-runs/#pre-approve-by-testing-the-reminder) shows the whole flow with real output.

![Netclaw chat TUI during a reminder test run, with an approval prompt for touch /tmp/disk-note.txt and five options with Always here highlighted](/screenshots/output/reminder-run-approval.png)

The prompt has five options because the command doesn't run inside a Git repository, so **This repository** isn't offered.

Any other form (`reminder run` with no ID, or extra arguments) prints `Usage: netclaw reminder run <id>` and exits 1. `run` doesn't print a result block or take `--json`. The result is the chat itself.

## `enable` / `disable`

```bash
netclaw reminder enable <id>
netclaw reminder disable <id>
```

Disabled reminders keep their definition and history and stop firing. Enabling one resets its schedule, so an interval reminder fires one interval after you enable it. An ended one-shot can't be enabled. `enable`, `disable` and `show` fail with the same `ended ... its definition was deleted` message, and you create the reminder again instead.

## `cancel` vs `delete`

```bash
netclaw reminder cancel <id>
netclaw reminder delete <id>
```

`cancel` on a recurring reminder disables it and keeps the definition and history, so you can re-enable it later:

```text
Reminder 'rec-demo' cancelled (disabled).
```

On a one-shot, `cancel` deletes the reminder and writes an end record with the outcome `cancelled`:

```text
Reminder 'once-demo' cancelled and deleted.
```

Cancelling a one-shot that already ended prints `Reminder '<id>' already ended (<outcome> at <time>). Nothing changed.` and exits 0. `delete` removes everything, history included.

## `import`

```bash
netclaw reminder import <file> [--replace|--upsert]
```

Imports a reminder from a definition file. The format is the stored file's, documented in [the definition schema](/configuration/reminders/#reminder-definition-schema), so a file copied from `~/.netclaw/schedules/reminders/` on another install imports as it is.

| Mode | Description |
|------|-------------|
| _(default)_ | Create only. Fails if the reminder already exists |
| `--upsert` | Create or update |
| `--replace` | Replace the existing reminder entirely |

A successful import prints `Imported reminder '<id>'.` IDs that start with `restart-resume-` are reserved, so an export that contains one fails with `The reminder ID prefix 'restart-resume-' is reserved for the system.` Remove that entry from the file first. The default mode refuses an existing ID with `[FAIL] Reminder '<id>' already exists.` Use `--upsert` to update it.

## `validate`

```bash
netclaw reminder validate <file>
```

Checks a definition file offline, without a daemon:

```text
$ netclaw reminder validate daily-standup.json
Reminder definition is valid: daily-standup
```

It requires `id`, `title`, `instructions`, `delivery`, `audience` and `boundary`, plus the schedule field for the type:

- `OneShot` needs `fireAtMs`
- `Interval` needs `intervalTicks`
- `Cron` needs a valid `cronExpression` ([5 fields](https://en.wikipedia.org/wiki/Cron#Cron_expression), optionally with `CRON_TZ=`)

A file without `boundary` fails with `JSON deserialization ... was missing required properties including: 'boundary'`, and an unknown time zone fails with `Invalid CRON_TZ prefix. Unknown time zone 'Nope/Zone'. Use an IANA id such as America/Chicago.` `validate` doesn't check that `boundary` suits the `audience`. The daemon does that when it saves.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Reminder not found, validation error, daemon unreachable, or another failure |

## What's next

Run [`netclaw reminder list`](#list) to confirm your reminder appears with the right schedule. After it fires, [`netclaw reminder status <id>`](#status) tells you whether it's healthy, and [`history`](#history) gives you the session ID to pass to [`netclaw sessions`](/cli/sessions/). If the reminder needs shell or file access, [test it with `run`](#run) before the schedule does.

## Related pages

- [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/) - why a scheduled run is denied and how to approve it ahead of time
- [Reminders configuration](/configuration/reminders/) - definition schema, schedules, delivery targets and audience scoping
- [`netclaw sessions`](/cli/sessions/) - inspect what happened during a reminder session
- [`netclaw approvals`](/cli/approvals/) - list, add and revoke saved grants
- [`netclaw status`](/cli/status/) - confirm the daemon is running

## Resources

- [Crontab.guru](https://crontab.guru/) - visual editor for cron schedule expressions
- [Cron expression syntax (Wikipedia)](https://en.wikipedia.org/wiki/Cron#Cron_expression) - reference for the 5-field cron format
- [IANA time zone database (Wikipedia)](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) - zone IDs for `CRON_TZ=`
- [ISO 8601 (Wikipedia)](https://en.wikipedia.org/wiki/ISO_8601) - timestamp format for one-shot schedules
