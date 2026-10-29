---
title: "Upgrade netclaw"
description: "Back up, upgrade a host, systemd or Docker install, verify it, roll back, and see what changed in 0.25 through 0.28, including the 0.27.1 to 0.28 upgrade."
---

Back up the data directory, upgrade, check `netclaw status` and `netclaw doctor`, and keep the backup until you trust the new version. Upgrades are forward-only. The new daemon migrates `netclaw.db` on its first start, so rolling back means restoring the backup, not just switching the binary. Coming from 0.27.1? Read [Upgrade from 0.27.1 to 0.28](#upgrade-from-0271-to-028) first.

| Install | Upgrade with |
|---------|--------------|
| Host, started by hand | `netclaw update` |
| systemd user service | `netclaw update`. It stops and starts the service for you. |
| Docker | Change the image tag, then `docker compose up -d` or recreate the container |

## Before you upgrade

1. [Back up](/guides/backup-and-restore/) the data directory, `keys/` included.
2. Read [what changed](#what-changed-by-release) for every release between yours and the target.
3. Upgrade while idle. Pick a moment when nobody is mid-conversation and no sub-agent or reminder run is working. `netclaw sessions` can't tell you: `[active]` means a session is loaded in memory, idle or not.
4. If you narrowed any `Tools` list, check it. From 0.27.1 a configured list replaces the defaults. See [0.27.1](#0271).
5. Check memory. From 0.27.0 the daemon wants 1 GiB and downloads about 129 MB on first start. See [0.27.0](#0270).
6. Upgrade the CLI and the daemon together. A newer `netclaw` can't chat with an older daemon. See [0.28](#028).

## Upgrade

### Host or systemd

```bash
netclaw update --check
netclaw update
```

See [`netclaw update`](/cli/update/). To pin a version, run the install script with `NETCLAW_VERSION=<version>`.

### Docker

```bash
docker compose pull          # or change the tag in the compose file first
docker compose up -d
```

Pin an exact tag such as `0.28.2`. `latest` moves on every stable release. Wait for `healthy`:

```bash
docker inspect --format '{{.State.Health.Status}}' netclaw
```

## Verify

```bash
netclaw --version
netclaw status
netclaw doctor
```

`netclaw status` should say `overall: healthy` and show the new version. `netclaw doctor` lists what the new version dislikes in your config, and `netclaw doctor --fix --dry-run` previews the repairs. Then resume one old session with `netclaw chat -p --resume <id> "..."` and read the newest daemon log for warnings. From 0.28.2 a log can have numbered segments, so pick the newest by time, not by name: `ls -t ~/.netclaw/logs/daemon-*.log | head -1`.

## Roll back

Switching the binary back isn't enough, because the database may already be migrated and newer sessions may not replay. Restore the full backup you took before the upgrade, into an emptied directory or a new volume, and start the old version on it. Don't start anything with the new version in between, and never unpack the backup over a directory that 0.28 has used.

1. Stop the daemon. `netclaw daemon stop` stops only the daemon of its own home. If it prints `Nothing was stopped. PID <pid> is not shown to serve <home>.`, check whether that PID is a daemon of this home. If it is, stop it with the `kill <pid>` command the message prints. If it isn't, delete `netclaw.pid`.
2. Restore the data directory into a fresh place, as below.
3. Start the old version and verify.

You lose everything since the backup: new sessions, memories and reminders. If you only took a copy of `netclaw.db`, see [Roll back to 0.27.1](#roll-back-to-0271) for the smaller procedure.

### Docker

Restore into a volume with a new name and leave the upgraded one for inspection. `docker volume create` on a name that exists succeeds without complaint, so a reused name would put the archive on top of the upgraded data. Use the image tag you backed up from. Here that is `0.27.1`:

```bash
docker stop -t 60 netclaw
docker volume create netclaw-home-0.27.1

docker run --rm --entrypoint tar \
  -v netclaw-home-0.27.1:/data \
  -v "$PWD:/backup:ro" \
  ubuntu:24.04 xzpf /backup/netclaw-backup.tgz -C /data

docker rm netclaw
docker run -d --name netclaw --stop-timeout 60 \
  -v netclaw-home-0.27.1:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw:0.27.1
```

Add the ports, environment variables and limits from your original `docker run`, or point your Compose file at the new volume and the old tag. The new volume holds no `cache/`, so there's no restart manifest to delete, and a backup taken after a clean stop carries no `-wal` or `-shm` files from the upgraded database. Wait for `healthy`, then run `netclaw status`, `netclaw reminder list` and `netclaw sessions --once` to see the old state back.

### Host or systemd

`bin/` isn't in the backup, so put the old binaries back first and leave the daemon stopped. Reinstall with `NETCLAW_VERSION=<old version>` and the install script. The install script doesn't start the daemon. Stop the daemon with `systemctl --user stop netclaw` or `netclaw daemon stop`. Then move the upgraded data aside, unpack the backup into the emptied directory and start:

```bash
f=~/netclaw-0.28-failed-$(date +%s) && mkdir "$f" && cd ~/.netclaw &&
for d in $(ls -A); do
  case "$d" in bin|models|logs|env) ;; *) mv "$d" "$f"/ ;; esac
done

tar xzpf /path/to/netclaw-backup.tgz -C ~
netclaw --version        # the old version
netclaw doctor --fix
netclaw daemon start     # or: systemctl --user start netclaw
```

Run `netclaw --version` before anything else, so you know the old CLI answers. The loop moves everything except `bin/`, `models/`, `logs/` and `env`, so nothing 0.28 touched stays under the restored folders. That takes the `cache/restart-manifest.json`, the `restart-resume-*` reminder files and every `netclaw.db*` file with it. The timestamp keeps a second attempt from colliding with the first. If you set `NETCLAW_HOME`, use that directory instead of `~/.netclaw`.

### Downgrading

Don't point an older binary at a data directory a newer one has used. In a test with 0.27.1 data:

- 0.26.0 started, and resumed a simple 0.27.1 session. It wrote that session's log to the old `logs/sessions/<id>/` path, while the 0.27 folder under `sessions/` stayed behind, so the session's files split in two.
- 0.26.0 failed to resume a session that 0.27.1 had touched mid-turn. The daemon logged `Persistence failure when replaying events` with `Unknown manifest 'ia-v1'`, and `netclaw chat --resume` hung until killed.

The release notes say the same: a binary older than 0.27.0 can't resume a session that has a versioned storage binding. If you must go back, restore the pre-upgrade backup. After running 0.28 or later, also delete `cache/restart-manifest.json` before you start 0.27.1. See [Upgrade from 0.27.1 to 0.28](#upgrade-from-0271-to-028).

## Upgrade from 0.27.1 to 0.28

0.28 changes how sub-agents, reminders and restarts are stored, and the database change goes one way. Do these in order. We ran every step below in Docker: a 0.27.1 container with a home volume, one chat session and one reminder, then 0.28.2 on the same volume.

:::caution
After the upgrade, never start 0.27.1 or older on the database. 0.27.1 reads the new child notice rows wrongly, replays a notice as user input and can deliver a child result twice. It also can't read parked child runs, drain parks or `ContinuationAuthorized` records. To go back, use the backup from step 3.
:::

### 1. Check the security posture

0.28 denies `shell_execute` when the config has no `Security.DeploymentPosture`. A missing key falls back to the strict Public posture, where 0.27.1 asked for approval. `netclaw init` writes the key, so this hits hand-written and very old configs. Run `netclaw doctor` on the 0.27.1 install first:

```text
[FAIL] Security Policy: Security section is missing; strict fallback defaults are active (Public posture, shell disabled).
       fix: Add a Security section with DeploymentPosture or run `netclaw init` again.
```

Add the section before you upgrade. This is the Personal posture that `init` writes, which keeps the shell available:

```json
"Security": {
  "DeploymentPosture": "Personal",
  "ShellExecutionMode": "HostAllowed",
  "StrictDefaults": true
},
"Tools": { "ShellMode": "HostAllowed" }
```

Pick `Team` or `Public` if that's who talks to this install. See [Hardening](/security/hardening/). If you skip this step, 0.28.2 starts and the same doctor failure shows up. A shell call then returns `Tool access denied: tool_not_allowed_for_audience_profile`.

### 2. Check for reminder files and old keys

- A reminder import file with an ID that starts with `restart-resume-` fails. The prefix is reserved for the system. `netclaw reminder validate` still passes such a file, but `netclaw reminder import` prints `[FAIL] The reminder ID prefix 'restart-resume-' is reserved for the system.` and exits `1`. Remove those entries from exported files.
- Find every `ToolOverrides` or `McpServerDefaults` key that contains a `:`, such as `file_write:control-plane`. On 0.27.1 and older such a key set the whole tool to `Auto`. On 0.28 the key is ignored and the tool uses the audience default, so it can prompt again. See [Reduce or turn off approval prompts](/guides/reduce-approval-prompts/#stop-prompts-for-one-mcp-server-or-tool).
- To keep every old log, set `Retention.Logs.Days` to `0` before you upgrade. See [numbered daemon logs](#028) below.

### 3. Stop the daemon and back up the database

Wait until no turn is running and no sub-agent works. 0.27.1 keeps an active child, and any message waiting behind it, only in memory. A stop loses them and 0.28 can't recover them.

The database runs in WAL mode, so a copy of `netclaw.db` alone can miss recent writes. After a clean stop SQLite folds them in, and the `-wal` and `-shm` files are usually gone or empty. Copy `netclaw.db*` anyway so the copy is complete either way. Give the stop time to finish.

On a host install, stop the daemon the way your install is run, and confirm it is stopped before you copy anything. The 0.27.1 `netclaw daemon stop` only sends a signal and doesn't know about the systemd unit, whose `Restart=always` brings the daemon back about five seconds later. A copy then catches a running database.

```bash
# with a systemd unit installed
systemctl --user stop netclaw
systemctl --user is-active netclaw     # must print: inactive

# without a unit
netclaw daemon stop
netclaw daemon status                  # must say the daemon isn't running

mkdir ~/.netclaw/pre-0.28 && cp ~/.netclaw/netclaw.db* ~/.netclaw/pre-0.28/
```

In Docker, stop the container instead. The entrypoint restarts a daemon that exits, so `netclaw daemon stop` inside the container is undone within seconds. Copy the files from the volume with a throwaway container that runs as the netclaw user (UID 1654), using your own volume name:

```bash
docker stop -t 60 netclaw
docker run --rm --user 1654:1654 --entrypoint sh -v netclaw-home:/data \
  ghcr.io/netclaw-dev/netclaw:0.27.1 \
  -c 'mkdir /data/pre-0.28 && cp /data/netclaw.db* /data/pre-0.28/'
```

This copy is the database only. Take a full [backup](/guides/backup-and-restore/) too, because `keys/` and `config/` aren't in it, and the full backup is what the [Roll back](#roll-back) procedure restores. Take it now, while the daemon is still stopped. Run the commands in [Back up](/guides/backup-and-restore/#back-up) and skip their last line (`docker start netclaw` or `netclaw daemon start`). If 0.27.1 starts again before the upgrade, the copies no longer match it.

### 4. Upgrade

Host installs use `netclaw update`. In Docker, step 3 only stopped the old container, so its name is still taken. Remove it, then start the new tag on the same volume with the flags you used before (ports, environment variables, limits). Or change the tag in your Compose file and run `docker compose up -d`:

```bash
docker rm netclaw
docker run -d --name netclaw --stop-timeout 60 \
  -v netclaw-home:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw:0.28.2
```

Starting without `docker rm` fails with a name-conflict error. The container reported `healthy` in about 20 seconds. This release adds no SQL migration, but the new daemon reads the volume as 0.28 data from here on. The reminder and the old session were still there:

```bash
docker exec netclaw netclaw status
docker exec netclaw netclaw doctor
docker exec netclaw netclaw reminder list
docker exec netclaw netclaw sessions --once
```

```text
overall: healthy
version: 0.28.2 (commit 7419d84, built 2026-10-29T00:10:12Z)
daemon: PID 33, uptime 0m 19s, endpoint http://127.0.0.1:5199
```

### 5. Delete leftover trace files

Releases up to 0.27.1 wrote every keystroke of `netclaw init`, `provider`, `model`, `reminder ui`, `mcp tools`, `approvals` and `config` to `netclaw-<command>-trace.log` in the temp directory, API keys and tokens included. Opening `netclaw provider` on 0.27.1 left `/tmp/netclaw-provider-trace.log` behind. 0.28 writes no trace files and never deletes the old ones. Delete them:

```bash
rm -f /tmp/netclaw-*-trace.log                  # Linux
rm -f "${TMPDIR:-/tmp}"/netclaw-*-trace.log     # macOS
```

On Windows, run `del %TEMP%\netclaw-*-trace.log` in `cmd`. We didn't run the macOS and Windows forms.

If other people could read that temp directory, rotate the secrets you typed. See [GHSA-mh95-h6p6-c9j3](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-mh95-h6p6-c9j3). In a container the files live in the container's own `/tmp`, so a recreated container drops them.

While you're cleaning up, check the OAuth token expiry. If `netclaw doctor` says `netclaw.json has the retired key Providers.<name>.OAuthTokenExpiry`, run `netclaw doctor --fix --yes`. It removes the key from `netclaw.json`, writes `netclaw.json.retired-oauth-expiry.bak` and copies the date into `secrets.json` for a provider that has a token there. The daemon logs a startup warning until you do. If the daemon stops at startup with an error that names `Providers:<name>`, run `netclaw provider` and sign in again.

### 6. Call the daemon by a loopback name

In `Local` exposure mode the daemon accepts a request only when `Host` is `localhost` or a loopback IP (`127.0.0.1`, `[::1]`) and any `Origin` is `http://` plus the same host. Anything else gets `401` on the authenticated endpoints, and the daemon log shows `Refused loopback request: Host is not a loopback name`. We saw it with `curl -H "Host: netclaw.example.internal" http://127.0.0.1:5199/api/reminders`. The health endpoint still answers. Point scripts at `http://127.0.0.1:<port>` or `http://localhost:<port>`. A browser app on another local port (`http://localhost:3000`) needs a [paired device](/guides/pairing-remote-devices/).

### Roll back to 0.27.1

This is the smaller procedure for when you only have the database copy from step 3. Stop the new daemon, put the copy back with its `-wal` and `-shm` files handled the same way, remove the restart manifest, and start 0.27.1. In Docker:

```bash
docker stop -t 60 netclaw
docker run --rm --user 1654:1654 --entrypoint sh -v netclaw-home:/data \
  ghcr.io/netclaw-dev/netclaw:0.27.1 \
  -c 'cd /data && rm -f netclaw.db netclaw.db-wal netclaw.db-shm \
      && cp pre-0.28/netclaw.db* . \
      && rm -f cache/restart-manifest.json schedules/reminders/restart-resume-*.json \
      && if [ -f config/secrets.json ]; then \
           jq "del(.Providers[]?.OAuthTokenExpiry)" config/secrets.json > /tmp/secrets.json \
           && cat /tmp/secrets.json > config/secrets.json; fi'
docker rm netclaw
docker run -d --name netclaw --stop-timeout 60 \
  -v netclaw-home:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw:0.27.1
```

The helper also removes three things 0.28 left behind:

- `restart-manifest.json` is the 0.28 restart record.
- A `restart-resume-*.json` reminder file under `schedules/reminders/` is one 0.28 wrote after a restart. 0.27.1 would load it and deliver it to a session as a user message.
- If 0.28 ran with an OAuth provider, `config/secrets.json` holds `Providers.<name>.OAuthTokenExpiry` as plain text. 0.27.1 would encrypt it on its next write to the file and then fail to read it as a date. The `jq` line removes it and does nothing when the key is absent.

Run the helper as `--user 1654:1654`, not root. A `netclaw.db` owned by root makes the 0.27.1 daemon crash at startup with `SQLite Error 8: attempt to write a readonly database`, because the entrypoint only fixes ownership when the top-level directory is wrong.

On a host, stop the daemon (`systemctl --user stop netclaw` or `netclaw daemon stop`), put the old binaries back, and run this before you start them. It needs `jq`:

```bash
cd ~/.netclaw
rm -f netclaw.db netclaw.db-wal netclaw.db-shm
cp pre-0.28/netclaw.db* .
rm -f cache/restart-manifest.json schedules/reminders/restart-resume-*.json
if [ -f config/secrets.json ]; then
  jq 'del(.Providers[]?.OAuthTokenExpiry)' config/secrets.json > secrets.tmp \
    && cat secrets.tmp > config/secrets.json && rm secrets.tmp
fi
```

We ran the Docker form: 0.27.1 reported `healthy` with the pre-upgrade reminders in place. A database-only restore leaves everything else as 0.28 left it. A reminder file that 0.28 wrote under `schedules/` was still listed after the rollback, and so would be new session folders and config changes. Use the [full rollback](#roll-back) when that matters. Two more things to know:

- A restore loses the journal records the 0.28 daemon wrote after the backup.
- The backup has to predate the first 0.28 start, beta builds included.

## What changed by release

Each row says what you'll see, then what to do.

### 0.25

| Change | What you'll see | What to do |
|--------|-----------------|------------|
| Models are named definitions plus roles (`Models.Definitions`, `Models.Roles`) | A config with inline `Models.Main` still runs. `netclaw doctor` fails the schema check with `Required properties ["Definitions","Roles"] are not present`. The first model write converts the file. | Follow [Migrating model configuration](/guides/migrating-model-config/). Don't mix both shapes: a config with legacy `Main` and the new keys crashes the daemon at startup. |
| The systemd unit gets its `PATH` from `config/daemon.env` | An old unit has no `PATH` source, and `netclaw doctor` warns `Systemd Unit PATH`. | Run `netclaw daemon install`, or `netclaw doctor --fix`, then restart the service. |
| `netclaw daemon stop` drains sessions within a bounded time | A stop with a turn in flight waits instead of hanging | Nothing. Raise your Docker stop timeout to 60 seconds. |
| Sub-agents fail closed when an approval is needed and nobody is there | An unattended subagent that used to proceed now stops | Grant the approval it needs. See [Reduce or turn off approval prompts](/guides/reduce-approval-prompts/). |
| STDIO MCP server arguments are no longer rewritten | The server gets exactly the arguments you configured | Remove workarounds that depended on the rewrite. |

### 0.26

| Change | What you'll see | What to do |
|--------|-----------------|------------|
| Per-channel thread mention gating (`MentionRequiredInThreadByChannel`) | Your existing config is unchanged, and a channel with no entry still replies to thread follow-ups without a mention. Only a channel you add in the `netclaw config` channels screen at the Team or Public tier starts with the rule on. There the bot ignores thread follow-ups unless it's mentioned, then backfills the thread. | To turn it off for a channel, set it to `false` in `Slack`, `Discord` or `Mattermost.MentionRequiredInThreadByChannel`, keyed by channel ID. |
| New default tool lists for Public and Team audiences | Public gets `file_read`, `file_list`, `file_search`, `tool_output_read`, `attach_file`. Team adds more. Audiences with no configured list pick this up. | Nothing, unless you relied on a tool that's no longer default. See [0.27.1](#0271) for lists you configured. |
| `netclaw skill list` needs a running daemon | The command fails when the daemon is down | Start the daemon first. |
| Reminders defer at capacity and failed one-shots are retried | Fewer silently skipped runs. Finished one-shots and background jobs are pruned, jobs after 24 hours. | Nothing. |
| Native PowerShell on Windows | The shell tool uses `pwsh` 7.6, or Windows PowerShell 5.1 as a fallback | Nothing. |

### 0.27.0

| Change | What you'll see | What to do |
|--------|-----------------|------------|
| Local embeddings on by default | A first start downloads two models (about 129 MB) from Hugging Face into `models/`. Idle memory is about 480 MB, against about 235 MB with embeddings off. A 512 MiB container limit is OOM-killed, and 768 MiB is stable. | Allow 1 GiB. To turn it off, set `Memory.Embeddings.Enabled` to `false`, or `NETCLAW_Memory__Embeddings__Enabled=false`. See [Memory and embeddings](/configuration/memory/). |
| Existing memories get embedded | In the upgrade test the daemon logged `memory_embedding_gap_repair_complete embedded=1` by itself on first start. | Run `netclaw memory backfill-embeddings` once if you have a large memory. See [`netclaw memory`](/cli/memory/). |
| Unified, versioned session storage | New sessions get a folder under `sessions/<name>-<hash>/`. Old sessions keep their paths. The database gets a `session_storage_bindings` table. | Nothing to migrate. See [Data directory layout](/reference/data-directory/#session-storage). Restoring to a different path needs [a fix](/guides/backup-and-restore/#move-to-a-different-path). |
| An older binary can't resume newer sessions | See [Downgrading](#downgrading) | Don't downgrade. |
| System skills ship inside the daemon | `skills/.system/` is rebuilt from the binary at each start | Don't edit `.system/`. Put your own skills elsewhere in `skills/`. |
| MCP OAuth client secrets belong in `secrets.json` | An `OAuthClientSecret` in `netclaw.json` fails `netclaw doctor`'s schema check. The daemon still starts. There's no autofix. | Remove it from the file and re-add the server with `netclaw mcp add --client-id <id> --client-secret <secret>`. |

### 0.27.1

| Change | What you'll see | What to do |
|--------|-----------------|------------|
| Configured `Tools` lists replace the defaults | A list that used to add to the defaults now is the whole list. `"Team": { "AllowedTools": ["file_read", "file_list"] }` gave 15 Team tools before and 2 now. Covers audience `AllowedTools`, file roots, `GlobalReadRoots`, attachment categories and `WebFetch.HttpAllowList`. | Check every `Tools` list in `netclaw.json`, `secrets.json` and `NETCLAW_*` variables. To add one entry, write the full list. |
| `netclaw doctor` checks tool lists | A Public or Team list without `tool_output_read` warns. A list that exactly copies a shipped default is reported. | Add `tool_output_read`. For a copied default, `netclaw doctor --fix` backs up `netclaw.json` as `netclaw.json.legacy-tool-defaults.bak` and deletes the key. |
| Exact older default lists map to today's | The daemon applies today's default and logs a startup warning. A Public list from 0.8 to 0.19 loses `file_write`. Edited lists apply as written and miss `file_search` and `tool_output_read`. | Add the missing tools by hand to an edited list. |
| Malformed lists stop startup | A scalar where a list belongs, an unknown attachment category, or an empty `NETCLAW_*` variable beside a file list. The container restart-loops. | Fix the key the error names. Set a list in one place only. |
| `netclaw init` writes the posture, not `Tools.AudienceProfiles` | New installs have `Security.DeploymentPosture`, `ShellExecutionMode`, `StrictDefaults` and `Tools.ShellMode`. The daemon derives the profiles. | Nothing. Old files keep working. |
| Only a kill of the netclaw daemon is hard-denied | `kill`, `pkill` and `killall` now prompt and can be granted | Review grants you rely on. See [Security model](/security/security-model/). |
| Graceful stop is bounded to 30 seconds | Sessions interrupted by a stop can resume | Set Docker's stop timeout to 60 seconds. |
| Reminder tools are scoped to the caller's audience | A Public or Team chat can't see Personal reminders | Nothing. |

### 0.28

0.28.0 shipped on 25 October. 0.28.1 and 0.28.2 are patch releases on the same database format. The rows below cover the 0.27.1 to 0.28 move. Each row says what you'll see, then what to do. The steps are in [Upgrade from 0.27.1 to 0.28](#upgrade-from-0271-to-028).

| Change | What you'll see | What to do |
|--------|-----------------|------------|
| `netclaw daemon stop` stops only its own home's daemon | The CLI sends no signal until it proves the PID serves this home. Linux reads the proof from `/proc`. On macOS and Windows it can't prove the home of a 0.27.1 daemon, so `netclaw update` from 0.27.1 and `daemon stop` refuse and print `Nothing was stopped. PID <pid> is not shown to serve <home>.` | Check that the PID is a daemon of this home, then run the `kill <pid>` command the message prints (Task Manager on Windows) and run the command again. If it isn't, delete `netclaw.pid`. Retrying without either doesn't help |
| `netclaw daemon status` exits `1` when the daemon isn't running or `/api/health/ready` doesn't answer (it used to exit `0` after printing a message). The Docker `HEALTHCHECK` is now `netclaw daemon status` | A container with a custom `Daemon.Port` stays `healthy`. On 0.27.1 it turned `unhealthy` because the check was `curl` against port `5199` | Drop any `healthcheck:` override you added for a custom port. Scripts that read the exit code now see failures |
| `netclaw daemon stop` and `start` go through the systemd unit when it runs this home's daemon | `netclaw daemon stop` leaves the daemon stopped. On 0.27.1 `Restart=always` brought it back five seconds later. With a unit installed and no user session bus, both exit `1` with `Could not determine whether systemd owns the daemon lifecycle` | Use `netclaw daemon stop` and `start` freely on a service install. Run them from a login session. `netclaw update` follows the same rule |
| `netclaw daemon install` checks `systemctl --user` first | On a host with no user session bus it writes nothing, prints `Cannot install the service: systemd user services are not available on this host` and exits `1` | Install `dbus-user-session` or export `XDG_RUNTIME_DIR` |
| `netclaw daemon pair` prints an address only in `local` mode | In a proxy or tunnel mode the last line reads `netclaw pair <https-address>` with a note, not the bind address | Substitute your HTTPS URL. See [Pairing remote devices](/guides/pairing-remote-devices/) |
| `netclaw chat -p` exits `1` when the turn fails | A provider that can't be reached, a timeout or a context overflow gave exit `0` with an `[error]` line on 0.27.1. Stdout can still hold partial text | Scripts that treated every exit as success now see failures |
| The chat client and the daemon must match | A new `netclaw` against a 0.27.1 daemon fails `chat -p` with `The daemon has unsupported text admission version 0. Upgrade the daemon.` and exits `1`. A 0.27.1 CLI against a newer daemon still chats. A chat message can now be up to 512 KB (it was 32 KB), and the daemon confirms the input after it saves it | Upgrade both. `netclaw update` replaces both binaries |
| `netclaw reminder list` prints a table | Columns `id`, `status`, `failures`, `schedule`, `next_fire` and `title`. An empty list prints `No reminders.` | Use `netclaw reminder list --json` in scripts. It prints the same JSON as before, and `No active reminders.` when empty |
| Agent tools can't reach credential locations | `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.azure`, `~/.config/gh`, `~/.config/gcloud`, `~/.docker/config.json`, `~/.netrc` and `~/.git-credentials` are denied to file tools and to shell commands that name them. `cat ~/.ssh/id_rsa` returns `Tool access denied: shell_references_protected_path`, where 0.27.1 printed the file. No approval or override changes that | Commands that use the credentials without reading them, such as `ssh host`, `git push` and `aws s3 ls`, still work |
| The daemon rotates and prunes its logs | `daemon-YYYY-MM-DD.log` stops at 10 MiB and continues in `daemon-YYYY-MM-DD.1.log`, `.2.log` and so on. A restart appends to the first segment under the limit, and a new UTC date starts a new series. The daemon removes daemon and crash logs older than 14 days, judged by the date in the file name, and always keeps the newest three of each. It checks 30 seconds after start and every 12 hours. Session logs and session folders are untouched | To keep more, set `Retention.Logs.Days` (`0` keeps everything) before you upgrade. Pick the newest log by time, not by name, because `daemon-2026-10-28.1.log` sorts before `daemon-2026-10-28.log`. See [Data retention](/configuration/data-retention/) |
| Invalid `Models` or provider config stops startup with one line | The daemon exits `1` with `error: Models:Roles:Main references unknown definition ...` on stderr and in the log, with no stack trace and no crash log. A running daemon refuses a bad edit, keeps its previous configuration, and `netclaw status` shows `degraded` with `config on disk not applied: <reason>`. `netclaw doctor` reports `Invalid model configuration:` | Fix the `Models` section the message names. See [Health checks](/observability/health-checks/#overall-status) |
| `netclaw doctor --fix` backs up before it removes keys | It writes `netclaw.json.removed-keys.bak` (numbered if one exists) and prints `Backed up the original to ...`. It never touches `Models` or a credential | Nothing. Keep the backup until you've checked the result |
| Moved or restored data directories keep their sessions | A session's stored folder is mapped onto the current data directory, with one warning in the daemon log. The `sqlite3` path rewrite is no longer needed | Remove that step from your restore runbook. See [Move to a different path](/guides/backup-and-restore/#move-to-a-different-path) |
| `Session.IdleTimeout` defaults to 1 hour (it was 30 minutes) | An idle session stays in memory twice as long before the daemon saves a snapshot and unloads it. `0` disables unloading | Set the value yourself if you relied on 30 minutes |
| OTLP over HTTP/protobuf posts to `v1/logs` and `v1/metrics` | `Telemetry:Otlp:Endpoint` is a base URL. A full signal URL is reduced to its base. gRPC is unchanged. There is still no tracing exporter | With `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, use `http://collector:4318`. See [OpenTelemetry](/observability/opentelemetry/) |
| Large tool results keep their tail | The model sees the last 12,000 characters of a result (2,000 for `shell_execute`) and reads the rest with `tool_output_read`. The full output is saved under the session's `workspace/tool-calls/` | Nothing. See [Data directory layout](/reference/data-directory/#session-storage) |
| The restart manifest names enums | `cache/restart-manifest.json`, which carries reminders across a coordinated restart, now stores reminder enums as names. 0.27.1 can't read that file | Before you move a data directory back to 0.27.1, delete `cache/restart-manifest.json` |
| A broken `netclaw.json` or `secrets.json` gives one line | An empty, cut-off or duplicate-key file used to crash every command with exit `134` and a `crash-*.log`. Now each prints `Couldn't read netclaw.json: <reason>` and exits `1`. `netclaw doctor` shows `[FAIL] Config Load`. `netclaw update` still runs. With a daemon running, `netclaw daemon status` prints `The local daemon address is unknown. No readiness probe was sent. Repair the local configuration and retry.` and exits `1`, and the CLI sends no local control traffic to a guessed address | Fix the file. See [`Couldn't read netclaw.json`](/troubleshooting/common-problems/#couldnt-read-netclawjson) |
| MCP server and provider names match without regard to case | `netclaw mcp add Git` when `git` exists updates `git` and prints the stored name. On 0.27.1 it wrote a second key and every command failed with `A duplicate key ... was found`. `provider add`, `remove`, `rename` and `model set` do the same | If a hand-edited file holds two keys that differ only by case, remove one |
| `provider add` rejects an endpoint without a scheme | `llm.example.internal:8080` prints `Error: Endpoint '...' is not an absolute http or https URL.` and writes nothing. `model list` also applies `NETCLAW_Models__*` variables from your shell and says so | Write `http://` or `https://` in front of the host |
| Provider endpoints work with or without `/v1` | `http://host:8080` and `http://host:8080/v1` both work. On 0.27.1 the `/v1` form worked for chat but discovery and the probe asked `/v1/v1/models` and got a 404 | Keep whichever you have. See [Self-hosted providers](/configuration/self-hosted-providers/#endpoint-url) |
| `mcp add` and `mcp remove` handle grants | `mcp add` on an existing server updates its connection and keeps its grants, approval modes and enabled state. `mcp remove` clears its tokens, grants, overrides and saved approvals. In the permissions screen, `E` and `A` ask before they grant every tool | Re-add a removed server and grant its tools again. See [`netclaw mcp`](/cli/mcp-tools/) |
| Sessions unload on a different rule | A Slack, Discord or Mattermost subscriber no longer keeps a session in memory, and a session with a running background job waits for the job before it unloads | Nothing. A later message wakes the session as before |
| Memory uses the Main model and re-embeds edits | Curation calls the Main model, not Compaction. An edited memory is embedded again at once. `backfill-embeddings` does nothing when `Memory:Embeddings:Enabled` is `false` | Check that Main can handle curation calls. See [Memory](/architecture/memory-model/) |
| Model backups are numbered | The first migration to named definitions writes `netclaw.json.legacy-models.bak`. A later one writes `.legacy-models.2.bak` instead of overwriting | Nothing. See [Migrate your model config](/guides/migrating-model-config/) |
| Time zones and chat startup | Without `tzdata`, `netclaw init` rejects every zone except `UTC` (`Unknown time zone '<zone>'`), and a bad `CRON_TZ=` prefix reads `Invalid CRON_TZ prefix.` A fresh `netclaw chat` prints no session line and creates no session until you send a message | Install `tzdata` in minimal images |
| Sub-agents run in the background | `spawn_agent` returns a run ID at once and the result arrives as a notice in a later turn, which the parent reads from `result.md`. A child that waits for consent parks and survives a restart. A graceful restart with an active child can take about 18 seconds longer, still inside the 30 second budget. A profile's `timeoutSeconds` is ignored with one warning, and a child waits 600 seconds for a silent stream. A Mattermost binding with no `CallbackUrl` refuses child consent requests | Nothing for most installs. Keep the 60 second Docker stop timeout. Give Mattermost a `CallbackUrl` if children need approvals |
| `netclaw chat -p` waits for child agents | When the reply starts a sub-agent, `chat -p` stays open and prints `[subagent:waiting] N open: <run ids>` until a turn reports no open child run | A script that starts a child waits for it, so wrap the call in `timeout`. See [Scripting sessions](/guides/scripting-sessions/) |
| A person's message ends an automation turn | During a reminder, background job, webhook or approval-notice turn, a message from the operator or a trusted person ends the turn after its current tool batch. The reminder records success and skips its remaining steps | Nothing. Expect it when you chat while a reminder runs |
| A denied call stops the turn | After you deny a call, the assistant stops, says what it wanted to do and asks how to continue. It doesn't retry or look for another way in that turn | Nothing |
| `Session.MaxToolIterationsPerTurn` no longer limits a turn | The key still binds, with a default of 60, and nothing reads it. A repeated identical call is refused with a nudge. At repeat 6 the turn ends quietly with the model's text and no error | Don't rely on the key. See [The turn ended with no error](/troubleshooting/common-problems/#the-turn-ended-with-no-error) |
| Reminders changed | Interval reminders under 61 minutes fire again (broken since 0.26.0). A one-shot deletes its own definition when it ends, so `reminder list` no longer shows it. A small end record and its run history stay 12 days, readable with `netclaw reminder status <id>` and `history <id>`. A one-shot has a 7 day delivery window. A `current_session` reminder ends when the session admits the fire, and a failed post sends a `reminder.delivery.failed` alert. A denied run is recorded as `denied`, and a denied one-shot ends as failed. `reminder import` rejects `restart-resume-` IDs | Look for `denied` in `netclaw reminder history <id>`. See [Reminders](/configuration/reminders/) |
| A reminder from before the upgrade can keep a wider audience | Under a posture narrower than the reminder's audience (Team posture with Slack DMs, for example) a reminder can carry the Personal audience. `run_reminder` then refuses it | Create it again from a chat |
| The loopback `Host` and `Origin` check | See [step 6](#6-call-the-daemon-by-a-loopback-name) above | Use `http://127.0.0.1:<port>` or `http://localhost:<port>` |
| No `Security.DeploymentPosture` means no shell | See [step 1](#1-check-the-security-posture) above | Set the posture, then run `netclaw doctor` |
| `ToolOverrides` and `McpServerDefaults` keys | A key with a `:` is ignored and logged at startup, and `netclaw doctor` reports it as an error. Key matching ignores case, and when two keys differ only by case the stricter mode wins. A key with no value is ignored | Rename the key to `tool_name` or `server/tool`, or delete it. `doctor --fix` doesn't change these keys |
| `OAuthTokenExpiry` moved to `secrets.json` | A provider refresh no longer rewrites `netclaw.json` and restarts the daemon. An old key still works until the first refresh and logs a startup warning | `netclaw doctor --fix --yes`. See [step 5](#5-delete-leftover-trace-files) |
| TUI commands no longer write a trace file | `netclaw-<command>-trace.log` files from older releases stay in the temp directory with whatever you typed | Delete them. See [step 5](#5-delete-leftover-trace-files) |
| A SQLite `Default Timeout` of 0 or less stops startup | The journal write timeout is now `Default Timeout` plus 10 seconds, 40 seconds by default | Remove the setting or use a positive value |
| Personal file reads reach as far as writes | `file_read`, `file_list`, `file_search` and `attach_file` on the Personal audience reach at least as far as the write profile, unattended runs included. The private temp folder is `/tmp/netclaw-<uid>/<key>/p`. `netclaw doctor` warns when a profile writes wider than it reads | Nothing |
| Provider OAuth sign-in needs a current daemon | A new CLI against an older daemon shows an upgrade message during provider OAuth sign-in | Upgrade both |
| Tool calls are logged again, with redaction | An Info line `Invoking tool [<name>] (call=<id>) args=... rationale=...` per call. Strings over 256 characters become a length and hash, and `session.log` redacts arguments the same way. An approval request, a policy denial or a correction request no longer writes an Error entry | Nothing. Update log alerts that matched on those errors |
| 0.28.1: every role fails over to the Fallback model | Compaction and child agents on the Compaction role now use the Fallback model. A cut-off child reply keeps its text in `artifacts/truncated-output.md`, and `result.md` names it | Nothing |
| 0.28.2: cost can rise | With no `MaxOutputTokens` set, a hosted API gets an output limit of 32000 tokens, capped to the model maximum and its context window. Anthropic replies are no longer cut at 1024 tokens. A self-hosted server gets 32000 clamped to its context window only when the window is known, otherwise no limit field. New `netclaw model set --max-output-tokens`, `--clear-max-output-tokens`, `--thinking <off|low|medium|high|max>` and `--clear-thinking` | Set `--max-output-tokens` for a lower cap. An `openai-compatible` provider needs `Providers:<name>:VendorOptions:ThinkingDialect` before it can send a thinking level, and a hand-edited level the dialect can't send fails startup and `doctor`. See [Models](/configuration/models/) |
| 0.28.2: a failing turn stops sooner | The loop guard also counts failed calls with no success between them: a nudge at 4, a stronger one at 6, and the turn ends at 8. `netclaw doctor --json` writes only JSON to stdout | Nothing. Parse the stdout of `doctor --json` as is |

The daemon, CLI, config, log and provider rows were run on a build from the `dev` branch before 0.28.0. The sub-agent, reminder, security, telemetry, 0.28.1 and 0.28.2 rows come from the 0.28.2 source and release notes, and we didn't run each one.

### Removed or rejected settings

| Setting | Removed in | What happens | Fix |
|---------|-----------|--------------|-----|
| `Tools.ShellTimeoutSeconds` | 0.24.0 | The daemon runs. `netclaw doctor` fails the schema check. | `netclaw doctor --fix` removes it. |
| `SkillSync.DisableSystemSkillSync` | 0.27.0 | Same | `netclaw doctor --fix` removes it. |
| `Persistence` section | 0.27.0 | The daemon aborts with `Persistence configuration is not supported. Netclaw always uses its single SQLite database.` | Delete the section. `doctor --fix` can't. |
| `OAuthClientSecret` in `netclaw.json` | 0.27.0 | Schema failure in `doctor`, daemon runs | Move it to `secrets.json` as above. |

0.27.0 added a `worktree_dir` to the session context and nothing more. There is no worktree tool to migrate from.

## Tested upgrades

### 0.25.4 to 0.27.1 in Docker

A 0.25.4 container with a bind-mounted data directory had a legacy `Models.Main`, `Tools.ShellTimeoutSeconds`, `SkillSync.DisableSystemSkillSync`, a narrowed Team list, a secret, a reminder, a memory, a session and a saved grant. Starting the 0.27.1 image on the same directory:

- The container was `healthy` in about ten seconds with no fatal log line.
- The log showed `Applying SQLite migration 6: 006_session_storage_bindings.sql`, then downloaded both models and embedded the existing memory.
- `tool-approvals.json` converted from version 2 to 3, and a byte-identical `tool-approvals.json.v2.bak` appeared next to it. Don't run a 0.25 or 0.26 daemon against the version 3 file.
- The old session kept its `logs/sessions/<id>/session.log` path. A new session got a folder under `sessions/`.
- The legacy model shape and the removed keys didn't stop the daemon. `netclaw doctor` failed the schema check for all three and warned that the Team list lacked `tool_output_read`. `netclaw doctor --fix --dry-run` planned to convert the models and remove the two keys.
- The secret, reminder, memory and session were all intact.

### 0.27.1 to 0.28.2 in Docker

A 0.27.1 container with a named volume, a cron reminder, one chat session and a config with no `Security` section. We stopped it, copied `netclaw.db`, and started 0.28.2 on the volume with embeddings off.

- The container was `healthy` in about 20 seconds. `netclaw status` reported `0.28.2`, and the reminder and session were intact.
- `netclaw doctor` failed `Security Policy` and `Tool Audience Profiles` on both versions. On 0.28.2 a shell call returned `Tool access denied: tool_not_allowed_for_audience_profile`.
- After adding the `Security` section the daemon restarted itself and `doctor` showed only the missing `secrets.json` warning.
- `netclaw doctor` named a retired `OAuthTokenExpiry` key, and `doctor --fix --yes` removed it and wrote `netclaw.json.retired-oauth-expiry.bak`.
- `netclaw reminder import` refused a `restart-resume-` ID.
- A request with `Host: netclaw.example.internal` got `401` on `/api/reminders`.
- Restoring the pre-upgrade `netclaw.db` into a copy of the volume and starting 0.27.1 gave a `healthy` daemon with the reminder and session.

We didn't run a host install, a numbered daemon log (they start at 10 MiB), a sub-agent, or the macOS and Windows stop refusal.

## Troubleshooting

### The daemon won't start after an upgrade

**Symptom:** The container restart-loops, or `systemctl --user status netclaw` shows it restarting.

**Cause:** The new version rejects something in your config. An invalid `Models` or provider section prints one `error:` line and exits `1` with no crash log.

**Fix:** Read the first lines of `docker logs`, the newest daemon log (`ls -t ~/.netclaw/logs/daemon-*.log | head -1`), or the newest `logs/crash-*.log`. Common causes are in the [Docker troubleshooting table](/deployment/docker/#container-is-unhealthy-and-docker-logs-shows-aborted-core-dumped). If you can't fix it quickly, [roll back](#roll-back).

### Scheduled reminders or background jobs stopped running

**Cause:** Records written by a daemon older than the trust-context hardening are rejected at load. The daemon logs which file and keeps it on disk.

**Fix:** Recreate the reminder, or add explicit `audience` and `boundary` fields to the JSON and restart. `netclaw doctor` has no fix for this.

### The agent can't run shell commands any more

**Cause:** The config has no `Security.DeploymentPosture`, so 0.28 uses the Public posture with the shell off. Calls return `Tool access denied: tool_not_allowed_for_audience_profile`.

**Fix:** Add the `Security` section from [step 1](#1-check-the-security-posture) and run `netclaw doctor`.

### A script or browser app gets 401 from the daemon

**Cause:** The request names a host other than `localhost` or a loopback IP, or carries a different `Origin`. See [step 6](#6-call-the-daemon-by-a-loopback-name).

### The bot stopped answering in threads

**Cause:** A channel added in the `netclaw config` channels screen at the Team or Public tier starts with `MentionRequiredInThreadByChannel` set to `true`. Upgrading alone doesn't turn it on. See [0.26](#026).

### Memory use doubled

**Cause:** Embeddings in 0.27.0. See [0.27.0](#0270).

## Related pages

- [Back up, restore and move netclaw](/guides/backup-and-restore/) - the backup to take first
- [`netclaw update`](/cli/update/) - what the update command does
- [Migrating model configuration](/guides/migrating-model-config/) - the 0.25 model shape
- [Data directory layout](/reference/data-directory/) - the 0.27 session layout
- [Run netclaw in Docker](/deployment/docker/) - tags, stop timeouts and memory limits

## Resources

- [netclaw releases on GitHub](https://github.com/netclaw-dev/netclaw/releases) - full release notes for every version
- [Semantic Versioning](https://semver.org/) - how to read the version numbers
- [Docker image tags](https://docs.docker.com/reference/cli/docker/image/tag/) - pinning by tag or digest
- [GHSA-mh95-h6p6-c9j3](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-mh95-h6p6-c9j3) - the TUI trace file that step 5 deletes
