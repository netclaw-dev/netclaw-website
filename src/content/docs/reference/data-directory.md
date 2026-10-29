---
title: "Data directory layout"
description: "Every folder and file under ~/.netclaw: what it holds, whether you can delete it, and whether it belongs in a backup."
---

Netclaw keeps everything it owns under one directory: `~/.netclaw`, or `$NETCLAW_HOME` if you set it. In the Docker image that's `/home/netclaw/.netclaw`. Use this page to find a file, decide what's safe to delete, and know what to copy in a [backup](/guides/backup-and-restore/).

## Top level

This is the layout after a first start with a few sessions, one reminder and one secret:

```text
~/.netclaw/
├── config/
│   ├── netclaw.json
│   ├── secrets.json
│   ├── tool-approvals.json
│   ├── devices.json
│   ├── webhooks/
│   └── daemon.env
├── keys/
├── identity/
├── skills/
├── agents/
├── sessions/
├── schedules/reminders/
├── jobs/
├── workspaces/
├── netclaw.db
├── models/
├── logs/
├── client/
├── cache/
├── runtime/
├── bin/
├── projects/
├── environment/
├── netclaw.pid
└── netclaw.lock
```

| Path | Holds | Back up | Safe to delete |
|------|-------|---------|----------------|
| `config/` | Settings, secrets and access state. See [config/](#config) | Yes | No |
| `keys/` | The key ring that decrypts `secrets.json`, one `key-<guid>.xml` per key | **Yes, always** | No. Without it every stored secret is unreadable, and a daemon with stored secrets fails at startup. |
| `netclaw.db` | One SQLite database: conversation history, the session catalog, durable reminders, usage stats, memory and session storage bindings | Yes | No |
| `netclaw.db-wal`, `netclaw.db-shm` | SQLite write-ahead log and shared memory, present while the daemon runs and sometimes after it stops | With the database | Not while the daemon runs |
| `identity/` | `SOUL.md`, `AGENTS.md` and `TOOLING.md` plus their `soul/`, `agents/` and `tooling/` folders. Your agent's personality and standing instructions | Yes, except `tooling/shadow/` | `tooling/shadow/` only. It's regenerated at startup. |
| `skills/` | Your own skills. `.system/` is managed by the daemon and `.server-feeds/` holds synced feed skills | Yes, except `.system/` and `.server-feeds/` | `.system/` and `.server-feeds/` come back at the next start |
| `agents/` | Sub-agent definitions you wrote. `.server-feeds/` holds synced ones | Yes, except `.server-feeds/` | `.server-feeds/` re-syncs |
| `sessions/` | One folder per session created since 0.27.0. See [Session storage](#session-storage) | Yes | Only for sessions you've finished with |
| `schedules/reminders/` | One JSON file per [reminder](/configuration/reminders/) | Yes | Deleting a file deletes the reminder |
| `jobs/` | Background shell jobs: `<id>.json` and `<id>/output.log` | No | Yes, when no job is running. Finished jobs are pruned after 24 hours anyway. |
| `workspaces/` | Project workspaces, usually git repositories with an `AGENTS.md`. Moves if you set `Workspaces.Directory` | Yes | No. It holds your working copies. |
| `models/` | Downloaded ONNX models for memory, about 129 MB | No | Yes. The daemon downloads them again at the next start. |
| `logs/` | Daemon, crash and session logs. See [Logs](#logs) | No | Yes, once you've read what you need |
| `client/` | `config.json`, the daemon endpoint this machine is paired to | Only on a paired client | Yes. You'd pair again. |
| `cache/` | Restart bookkeeping such as `restart-manifest.json` | No | Yes, with the daemon stopped |
| `runtime/` | The daemon's working directory. Empty in normal use | No | Yes |
| `bin/` | The `netclaw` and `netclawd` binaries on a host install. Empty in Docker | No | No on a host. A full reset from `netclaw init` keeps it. |
| `.bundle/` | Only if you set `DOTNET_BUNDLE_EXTRACT_BASE_DIR` into the data directory: the daemon's unpacked native libraries, about 43 MB. The [Docker](/deployment/docker/#hardened-profile) hardened profile uses a tmpfs instead | No | Yes, with the daemon stopped. It's rebuilt at the next start. |
| `projects/`, `environment/` | Created at startup, empty on a fresh install | No | Yes |
| `netclaw.pid`, `netclaw.lock` | Process id and the singleton lock that stops a second daemon | No | Only a stale pair, with no daemon running |
| `env` | Host installs only: the shell snippet that puts `netclaw` on your `PATH` | No | Not unless you uninstall |

## config/

| File | Holds | Back up |
|------|-------|---------|
| `netclaw.json` | All settings. Edits restart the daemon after it drains sessions. See [`netclaw config`](/cli/config/) | Yes |
| `secrets.json` | Credentials, encrypted with the key ring in `keys/`. Written by [`netclaw secrets set`](/cli/secrets/). One exception: `Providers.<name>.OAuthTokenExpiry` is plain text | Yes, with `keys/` |
| `tool-approvals.json` | Saved "Always" approvals. Also `.lock` and, after an upgrade from an older format, `.v2.bak` | Yes |
| `netclaw.json.removed-keys.bak`, `netclaw.json.legacy-tool-defaults.bak`, `netclaw.json.retired-oauth-expiry.bak` | Copies of `netclaw.json` that [`netclaw doctor --fix`](/cli/doctor/) writes before it removes keys or moves a retired `OAuthTokenExpiry` to `secrets.json`. A second backup of the same kind gets a number: `.removed-keys.2.bak` | Optional |
| `devices.json` | Paired devices as salted token hashes | Yes, or you pair again |
| `bootstrap-state.json` | First-start bookkeeping for non-local [exposure modes](/deployment/exposure-modes/) | Yes |
| `hard-deny-overrides.json` | Optional operator hard-deny overrides. Absent unless you made one | Yes, if present |
| `webhooks/` | One file per inbound [webhook](/configuration/webhooks/) route | Yes |
| `daemon.env` | systemd only: the `PATH` captured by `netclaw daemon install`. `install` and `netclaw doctor --fix` change only the `PATH` line and keep every other line, such as `NETCLAW_HOME=...`, as it is | Yes, if you added lines |

`netclaw.json` can hold only part of your configuration. Variables named `NETCLAW_*` override it and don't appear in any file, so keep a copy of how you set them.

## Session storage

Conversation history doesn't live in `sessions/`. It's in `netclaw.db`. A session folder holds the files a session produces: its working files, attachments, outputs, scratch space and logs.

Since 0.27.0 every new session gets one folder, the session storage envelope, named `<session-name>-<stable-hash>`. Netclaw records the folder's absolute path in the database when the session first starts. When the session opens again, the daemon maps that path onto the current data directory, so a moved or restored home keeps working.

```text
sessions/<session-name>-<stable-hash>/
├── workspace/
│   └── tool-calls/
├── attachment-staging/
├── artifacts/
├── worktrees/
├── logs/
│   └── session.log
└── subagents/
    └── <run-id>/
        ├── task.md
        ├── result.md
        ├── artifacts/
        └── logs/
            └── session.log
```

Netclaw creates each directory the first time something needs it, so most sessions show only a few of them. A session that never wrote a file has just `logs/`.

| Folder | What it's for |
|--------|---------------|
| `workspace/` | The session workspace and the base for relative file paths. A new session's default working directory. Netclaw creates it the first time a shell call or a saved tool result needs it, and refuses to if the folder or the session folder above it is a link |
| `workspace/tool-calls/` | The full output of a tool call that was too big to keep in the conversation, one `<SHA-256 of the call id>.log` file per call. The model gets the last part of the output inline (the last 12,000 characters, or 2,000 for `shell_execute`) and reads the rest with `tool_output_read`. If the file can't be written, the truncation note says the output wasn't kept |
| `attachment-staging/` | Untrusted bytes from an inbound attachment, before the content scanner admits them. Accepted files move to `workspace/inbox/` |
| `artifacts/` | Outputs the session, or you, should keep, such as files it attaches to a reply |
| Temp folder | Scratch space for the session's own commands. Netclaw sets `TMPDIR`, `TMP` and `TEMP` to it for every process it launches, and it's safe to lose. On Linux and macOS it lives outside the data directory, in `/tmp/netclaw-<uid>/<key>/p` (`/private/tmp/...` on macOS), where `<key>` is the first 16 hex characters of the SHA-256 of the session folder's path and a child run uses `.../<key>/c<8 hex>`. Netclaw creates the folders with mode 0700 and refuses a shell launch or file write when the owner, the mode or a link is wrong. On Windows it stays inside the session folder, in `tmp/parent/` and `subagents/<run-id>/tmp/` |
| `worktrees/` | The preferred place for `git worktree add`. After Git creates one, the agent points the session at it with `set_working_directory` |
| `logs/session.log` | The raw activity log of the parent run |
| `subagents/<run-id>/` | The same layout for each child run, kept under the parent so one folder holds a whole session. `task.md` holds what the parent asked and `result.md` what the child returned, which the parent reads with `file_read`. A child reply cut off at its output limit leaves the full text in `artifacts/truncated-output.md`, and `result.md` names it |

Being inside the envelope doesn't grant access. Audience restrictions, file-operation permissions, shell approval, protected-file rules and attachment validation all apply to these folders as they do anywhere else. See [Security model](/security/security-model/).

### Existing sessions keep their old paths

Sessions that started before 0.27.0 have no binding. They keep the workspace and log paths they always had, for example `logs/sessions/<session-id>/session.log`. Netclaw doesn't move, rename or migrate their files, and an upgrade doesn't change where an old session resumes. A restart or a config change doesn't change the layout of an existing session either.

To check after an upgrade, resume an old session and confirm its `LogPath` in `netclaw sessions --once --json` is unchanged, then start a new one and see that its path is under `sessions/`.

### Find things

| I want | Do this |
|--------|---------|
| A session's log | Run `netclaw sessions --once --json` and read `LogPath` |
| A subagent's log | Use the exact `LogPath` the `spawn_agent` result returns. Don't search the logs folder |
| A file a session kept | Look in that session's `artifacts/` |
| To clear scratch space | Delete the temp folder, `/tmp/netclaw-<uid>/` on Linux and macOS. Nothing depends on it. On Windows, delete `tmp/` in the session folder |

### Moving the directory

The database stores each session's folder as an absolute path, but the daemon re-roots it. If you restore a backup to a different location, such as from Docker's `/home/netclaw/.netclaw` to `/home/you/.netclaw`, a session opens in `sessions/<name>-<hash>` under the new home and the daemon logs one warning naming the old and new path. [Back up, restore and move netclaw](/guides/backup-and-restore/#move-to-a-different-path) has the tested walkthrough, and the one thing it needs on top.

### Downgrading

A binary older than 0.27.0 doesn't know about storage bindings. It resumes a session by its old rules, so its files end up in a different place than the 0.27 envelope, and it can't replay some events a newer daemon wrote. Don't downgrade a data directory that has run 0.27 sessions. See [Upgrade netclaw](/guides/upgrading/#downgrading).

## Logs

| File | Written by | Holds |
|------|------------|-------|
| `logs/daemon-YYYY-MM-DD.log` | The daemon | One file per UTC day, appended to. At 10 MiB the daemon starts `daemon-YYYY-MM-DD.1.log`, then `.2.log`, and so on, and the next UTC day starts over. Level `Information` by default. Change it with `Logging:LogLevel:Default`. Deleted after 14 days |
| `logs/crash-YYYYMMDD-HHMMSS.log` | The daemon | A fatal startup or runtime exception. [`netclaw doctor`](/cli/doctor/) reports recent ones. Deleted after 14 days |
| `logs/signalr-<id>.log` | `netclaw chat -p` | The transcript of a headless run |
| `logs/sessions/<session-id>/session.log` | The daemon | The raw log of a session that started before 0.27.0 |
| `sessions/<name>-<hash>/logs/session.log` | The daemon | The raw log of a newer session. Subagent logs sit under `subagents/` |

The daemon deletes `daemon-*.log` files, numbered segments included, and `crash-*.log` files older than `Retention:Logs:Days` (default 14), about 30 seconds after it starts and then every 12 hours. The date comes from the file name, the newest three of each kind always stay, and `0` keeps everything. Nothing else is touched: `signalr-*.log`, everything under `logs/sessions/` and every session folder under `sessions/` stay until you delete them. [Data retention](/configuration/data-retention/) explains the setting. Releases before 0.28.0 delete nothing, so prune those files yourself. Under systemd, `journalctl --user -u netclaw` shows only start and stop lines unless you set `NETCLAW_Logging__Console__Enabled=true`, which also makes `docker logs` show the daemon's output.

Background shell jobs write to `jobs/<id>/output.log`, rotating once to `output.1.log` at about 5 MB. The agent gets the exact path in the job result.

## Related pages

- [Back up, restore and move netclaw](/guides/backup-and-restore/) - copy this directory and prove the copy works
- [Upgrade netclaw](/guides/upgrading/) - what changes in this layout between releases
- [Run netclaw in Docker](/deployment/docker/) - the volume this directory lives in
- [Secrets](/security/secrets/) - how `secrets.json` and `keys/` work together
- [Data retention](/configuration/data-retention/) - what the daemon deletes and what it keeps
- [Sessions](/architecture/sessions/) - how a session runs

## Resources

- [SQLite write-ahead logging](https://www.sqlite.org/wal.html) - why `netclaw.db-wal` appears
- [SQLite backup API](https://www.sqlite.org/backup.html) - the safe way to copy a live database
- [ASP.NET Core Data Protection key management](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/configuration/default-settings) - the key ring format behind `keys/`
