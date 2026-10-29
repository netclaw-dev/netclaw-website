---
title: "Back up, restore and move netclaw"
description: "Copy a netclaw data directory, restore it on the same or a different machine, and move between a host install and Docker."
---

Stop the daemon, copy the data directory without `models/`, `logs/` and `cache/`, and keep `keys/` next to `config/secrets.json`. The same copy restores a daemon, moves it to a new machine, or moves it between a host install and Docker, including to a different path.

## What to back up

| Back up | Why |
|---------|-----|
| `config/` | Settings, encrypted secrets, saved approvals, paired devices, webhook routes |
| `keys/` | The key ring that decrypts `secrets.json`. **Without it the secrets can't be read and the daemon won't start.** |
| `netclaw.db` | Conversation history, the session catalog, reminders, stats and memory |
| `sessions/` | Session workspaces, artifacts, saved tool output and logs |
| `identity/`, `skills/`, `agents/` | Your agent's instructions, skills and subagents |
| `schedules/`, `workspaces/` | Reminder files and project working copies |

Skip `models/` (downloaded again), `logs/`, `cache/`, `jobs/`, `runtime/`, `.bundle/` if you point the daemon's unpack directory into the volume, the `netclaw.pid` and `netclaw.lock` files, and `bin/` on a host install. [Data directory layout](/reference/data-directory/) says why for each.

Environment variables aren't in the directory. If you configure with `NETCLAW_*` variables, back up your compose file or run command too.

## Back up

Stop the daemon first. After a clean stop the database is a single consistent file, and the rest of the directory isn't changing under the copy.

### Docker named volume

```bash
docker stop netclaw

docker run --rm --entrypoint tar \
  -v netclaw-home:/data:ro \
  -v "$PWD:/backup" \
  ubuntu:24.04 czf /backup/netclaw-backup.tgz \
  --exclude=./models --exclude=./logs --exclude=./cache \
  --exclude=./jobs --exclude=./runtime --exclude=./.bundle \
  --exclude=./netclaw.lock --exclude=./netclaw.pid -C /data .

docker start netclaw
```

`--entrypoint tar` matters. Without it the netclaw image starts a daemon and treats `tar` as its arguments. The archive is owned by root and runs to roughly 100 KB for a small install.

### Docker bind mount or host install

For a bind mount, run `tar` on the host against the directory. For a host install, stop the daemon and confirm it is stopped before you copy anything. From 0.28, `netclaw daemon stop` uses the systemd unit when there is one. Before 0.28 it only sends a signal, and the unit's `Restart=always` brings the daemon back within seconds. So on 0.27.1 or older with a unit installed, run `systemctl --user stop netclaw` and check that `systemctl --user is-active netclaw` prints `inactive`. Without a unit, run `netclaw daemon stop` and check that `netclaw daemon status` says the daemon isn't running. `netclaw daemon stop` stops only the daemon of its own home. If it prints `Nothing was stopped. PID <pid> is not shown to serve <home>.`, check the PID. If it's a daemon of this home, stop it with the `kill <pid>` command the message names. If not, delete `netclaw.pid`. Then:

```bash
tar czf netclaw-backup.tgz -C ~ \
  --exclude=.netclaw/bin --exclude=.netclaw/models \
  --exclude=.netclaw/logs --exclude=.netclaw/cache --exclude=.netclaw/env \
  --exclude=.netclaw/jobs --exclude=.netclaw/runtime --exclude=.netclaw/.bundle \
  --exclude=.netclaw/netclaw.lock --exclude=.netclaw/netclaw.pid \
  .netclaw
netclaw daemon start
```

If you set `NETCLAW_HOME`, use that directory instead of `~/.netclaw`. Copy the `-wal` and `-shm` files with the database if a stopped daemon left them behind. Archiving the whole directory does that for you.

### Without stopping

Stopping is the simple option. To avoid downtime, copy the database with SQLite's own backup command and the rest of the directory afterward:

```bash
docker exec -u netclaw netclaw sqlite3 /home/netclaw/.netclaw/netclaw.db \
  ".backup '/tmp/netclaw-live-copy.db'"
docker cp netclaw:/tmp/netclaw-live-copy.db .
```

The result is a consistent snapshot, even while the daemon writes. Archive the rest of the directory with `--exclude=./netclaw.db*`, and restore the snapshot as `netclaw.db`. Don't copy `netclaw.db` itself on a live daemon. It runs in WAL mode, so the file alone can miss recent writes. The other files aren't snapshotted together, so a session that changes mid-copy can be a few turns ahead of the database.

## Restore

### Docker

Create a volume, unpack the archive into it as root so ownership survives, and start a container with the same flags as before. The volume has to be new and empty. `docker volume create` on a name that exists succeeds silently, and the archive would land on top of whatever is in it. To restore over a broken install, use a new name as below, and `docker rm` the old container first. Or remove the container and then the volume with `docker volume rm`. On a new machine there's no old container, so skip the `docker rm`. Replace `<version>` with the image version you backed up from:

```bash
docker volume create netclaw-home-restored

docker run --rm --entrypoint tar \
  -v netclaw-home-restored:/data \
  -v "$PWD:/backup:ro" \
  ubuntu:24.04 xzpf /backup/netclaw-backup.tgz -C /data

docker rm netclaw
docker run -d --name netclaw --stop-timeout 60 \
  -v netclaw-home-restored:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw:<version>
```

Use the same image version you backed up from, or a newer one, and never an older one. To go back after an upgrade, follow [Roll back](/guides/upgrading/#roll-back). The entrypoint repairs ownership on start, so an archive made on another machine works too.

### Host

Stop the daemon, unpack, start it. Leave `bin/` alone so you keep your installed binaries. Restore with the same version you backed up from, or a newer one. `doctor --fix` and `daemon start` run whatever `netclaw` is installed, so after an upgrade that went wrong, put the old binaries back first. See [Roll back](/guides/upgrading/#roll-back).

Unpack into an empty data directory. `tar` doesn't delete files that the archive lacks, so on a directory that is already in use, move its contents aside first, as the block below does.

```bash
netclaw daemon stop

# only if ~/.netclaw already holds data: move it aside first
f=~/netclaw-old-$(date +%s) && mkdir "$f" && cd ~/.netclaw &&
for d in $(ls -A); do
  case "$d" in bin|models|logs|env) ;; *) mv "$d" "$f"/ ;; esac
done

tar xzpf netclaw-backup.tgz -C ~
netclaw doctor --fix
netclaw daemon start
```

`netclaw doctor --fix` rebuilds `config/daemon.env`, the file that gives the service's shell tool your `PATH`. The backup includes the file, but its `PATH` belongs to the old machine, so `--fix` refreshes it from yours. If it's stale or missing, `netclaw doctor` warns `Systemd Unit PATH` and the agent's shell can't find tools in `~/.netclaw/bin` or `~/.local/bin`.

### Check it worked

```bash
netclaw status                  # overall: healthy
netclaw sessions --once         # your sessions are listed
netclaw reminder list           # your reminders are back
netclaw doctor                  # "Secrets JSON ... All N value(s) are encrypted"
```

Then resume a session with `netclaw chat -p --resume <id> "..."` and confirm it continues the conversation. A daemon that starts and stays up has decrypted `secrets.json`. If the key ring is missing it doesn't start.

## Move to another machine

Restore the same archive on the new machine as above. Do these first:

- Install the same netclaw version, or a newer one. A directory that 0.28 has opened can't go back to 0.27.1 or older. To keep a way back, copy `netclaw.db` before the first 0.28 start, as in [Upgrade from 0.27.1 to 0.28](/guides/upgrading/#upgrade-from-0271-to-028).
- Stop the daemon on the old machine so two daemons never use the same Slack, Discord or Mattermost bot at once.
- Re-check anything tied to the old machine: `Daemon.Host`, exposure mode and paired devices, tunnel agents, and file paths in `netclaw.json` such as `Workspaces.Directory`.

### Move to a different path

Restore a backup somewhere else, such as a host install at `/home/you/.netclaw` into Docker's `/home/netclaw/.netclaw`, and sessions keep working. The database stores each session's folder as an absolute path from the old machine. When the daemon opens a session it takes the last two segments of that path, `sessions/<name>-<hash>`, and looks under the current data directory instead. It logs one warning per session and carries on:

```text
[WRN] Netclaw.Daemon.Gateway.SqliteSessionStorageResolver: Session signalr/9dba417b... was stored at /home/you/.netclaw/sessions/signalr_9dba...-d0fde89e6b81e439; using /home/netclaw/.netclaw/sessions/signalr_9dba...-d0fde89e6b81e439 under the current data directory
```

We moved a host install at `/home/you/.netclaw` into a Docker volume, and a second data directory from `/srv/olduser/.netclaw` into Docker. Both listed their sessions, resumed them with `netclaw chat -p --resume`, replayed the history, and ran new turns, including one that called the shell and saved its output under the restored session folder. The stored `envelope_root` in `netclaw.db` stays as it was, and `sessions.log_path` updates the next time a session runs. Nothing reads either value back, so there's nothing to edit. The path mapping accepts both `/` and `\` separators, so a move from Docker back to a host install, or from Windows to Linux, takes the same route. We didn't run those two.

If `sessions/` wasn't in the backup, the warning ends with `(that folder does not exist yet, so the session starts with an empty workspace)`. The conversation is intact because it lives in `netclaw.db`, but the session's files are gone.

:::note[On 0.27.1]
0.27.1 doesn't re-root. Resuming a moved session logs `UnauthorizedAccessException: Access to the path '/home/you' is denied`, and a session that needs its folder can hang. With the daemon stopped, rewrite the two stored paths before you start it, replacing the first path with where the backup came from and the second with where you restored it:

```bash
docker run --rm --entrypoint sqlite3 \
  -v netclaw-home:/data \
  ghcr.io/netclaw-dev/netclaw:0.27.1 /data/netclaw.db "
update session_storage_bindings
  set envelope_root = replace(envelope_root, '/home/you/.netclaw', '/home/netclaw/.netclaw');
update sessions
  set log_path = replace(log_path, '/home/you/.netclaw', '/home/netclaw/.netclaw');"
```

On a host install, run `sqlite3 ~/.netclaw/netclaw.db` with the same two statements. Upgrading to a later build makes the rewrite unnecessary.
:::

### From a host install into Docker

Back up the host as shown, then unpack it into a new volume, dropping the leading `.netclaw/` folder:

```bash
docker run --rm --entrypoint tar \
  -v netclaw-home:/data -v "$PWD:/backup:ro" \
  ubuntu:24.04 xzpf /backup/netclaw-backup.tgz -C /data --strip-components=1
```

Start the container. The files arrive owned by your host user ID and the entrypoint changes them to 1654 on the first start. Move host-only settings across by hand: `NETCLAW_*` variables from your unit file belong in the compose file, and a `Daemon.ExposureMode` other than `local` needs the steps in [Run netclaw in Docker](/deployment/docker/#reaching-the-daemon).

## Troubleshooting

### The container is unhealthy after a restore

**Symptom:** `docker logs` shows `Failed to convert configuration value 'ENC:...' ... The key {...} was not found in the key ring`, then restarts with a growing delay.

**Cause:** `secrets.json` came back without `keys/`. A fresh key was created, and it can't decrypt secrets written under the old one.

**Fix:** Stop the container and unpack `keys/` from the backup into the volume. The new key file can stay. Start the container again. If you've lost the keys, delete `config/secrets.json` and set each secret again with [`netclaw secrets set`](/cli/secrets/).

### `Access to the path ... is denied` on resume

**Cause:** You're on 0.27.1, which doesn't re-root a moved session's stored path. See [Move to a different path](#move-to-a-different-path).

### The restored host has no `netclaw` command

**Cause:** The archive didn't include `bin/`, by design, and this is a new machine.

**Fix:** Install netclaw first with the [install script](/getting-started/installation/), then restore. Don't unpack a Docker backup over `bin/`.

## Related pages

- [Data directory layout](/reference/data-directory/) - what each folder holds and whether it belongs in a backup
- [Upgrade netclaw](/guides/upgrading/) - take this backup before you upgrade
- [Run netclaw in Docker](/deployment/docker/) - volumes, bind mounts and ownership
- [Secrets](/security/secrets/) - how `secrets.json` and `keys/` work together
- [systemd service](/deployment/systemd/) - stop and start a service-managed daemon

## Resources

- [SQLite online backup](https://www.sqlite.org/backup.html) - the `.backup` command used for a live copy
- [SQLite write-ahead logging](https://www.sqlite.org/wal.html) - why a live database file can't be copied alone
- [GNU tar manual](https://www.gnu.org/software/tar/manual/tar.html) - `-p`, `--exclude` and `--strip-components`
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/) - back up, restore and migrate volumes
