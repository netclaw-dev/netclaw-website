---
title: "Data retention"
description: "How long netclaw keeps daemon and crash logs, what it never deletes, and how to change the limit."
---

The daemon deletes its own old log files so the logs directory doesn't grow forever. Only daemon and crash logs qualify, including the numbered segments the daemon log rolls into: session logs and session data are never pruned. The limit is `Retention.Logs.Days`, 14 days by default. Change it when you want a longer audit trail or a smaller disk footprint.

## What gets deleted

| Deleted | Never deleted |
|---------|---------------|
| `daemon-yyyy-MM-dd.log`, `daemon-yyyy-MM-dd.N.log` and `crash-*.log` files in `~/.netclaw/logs/` whose date is more than `Retention.Logs.Days` days ago | Session logs and session data, including everything in subfolders such as `logs/sessions/` |
| | The newest 3 daemon log files and the newest 3 crash logs, however old. Segments count as files, so three segments of one day can be the three kept |
| | Any other file in `logs/`, such as `notes.log` or a compressed `daemon-2026-01-09.log.gz`. Only the exact names above match, so a zero-padded `daemon-2026-01-09.01.log` is left alone |

The daemon log rolls over when it reaches 10 MiB: the next lines go to `daemon-yyyy-MM-dd.1.log`, then `.2.log`, and so on. A new UTC date starts the series again. Retention prunes the segments by the date in their names, like the first file of the day.

The age comes from the date in the file name, in UTC. Today's log is never old enough to qualify. The newest-three rule means a wrong system clock can't wipe your whole history.

## When it runs

The daemon runs the clean-up 30 seconds after it starts, then every 12 hours. A change to `Retention.Logs.Days` restarts the daemon like any `netclaw.json` change, so the new limit takes effect on that restart's first run. Setting `0` keeps the logs forever and the clean-up deletes nothing.

## Change the limit

```bash
netclaw config retention                 # show the current value
netclaw config retention --logs-days 30  # keep 30 days
netclaw config retention --logs-days 0   # keep forever
```

The same screen is in `netclaw config` under **Data Retention**: type the number and press `Enter`. To write the key yourself:

```json
{
  "Retention": {
    "Logs": { "Days": 30 }
  }
}
```

The environment variable `NETCLAW_Retention__Logs__Days=30` works too and wins over `netclaw.json`. `netclaw config retention` warns when one is set. Environment changes need a [manual daemon restart](/cli/daemon/).

| Field | Type | Default | Allowed values |
|-------|------|---------|----------------|
| `Retention.Logs.Days` | integer | `14` | `0` to `36500`. `0` keeps logs forever. |

[`netclaw config`](/cli/config/#netclaw-config-retention) rejects anything outside that range and writes nothing. In a hand-edited file, a value that isn't an integer falls back to 14 days and the daemon logs a warning at startup. The daemon still starts. A negative number keeps everything, like `0`.

## Confirm it ran

When the clean-up deletes something, the daemon log says so:

```text
02:45:44.817 [INF] Netclaw.Daemon.Services.DataRetentionActor: Retention: deleted 7 expired daemon and crash log file(s) older than 14 days.
```

A run that finds nothing to delete writes nothing. A file it can't delete (a read-only volume, say) logs `Retention: could not delete N expired daemon and crash log file(s); will retry at the next run.` and the daemon keeps going. A bad stored value shows up as:

```text
[WRN] Netclaw.Startup: Configuration warning: Retention:Logs:Days value 'soon' is not an integer; using the default of 14 days.
```

Look in `~/.netclaw/logs/daemon-<date>.log`, or `docker exec <container> sh -c 'grep Retention ~/.netclaw/logs/daemon-*.log'` in Docker.

## Retention elsewhere

Completed one-shot [reminders](/configuration/reminders/) are removed after 12 days.

## Related pages

- [`netclaw config`](/cli/config/): the Data Retention screen and `config retention`
- [Configuration reference](/configuration/reference/): every key, including `Retention.Logs.Days`
- [Data directory layout](/reference/data-directory/): where logs and sessions live
- [Docker](/deployment/docker/): keep the home volume's logs in check
- [Back up, restore and move netclaw](/guides/backup-and-restore/): what to copy before logs age out

## Resources

- [.NET configuration providers](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration): how `NETCLAW_` environment variables map to JSON keys
- [Docker logs and volumes](https://docs.docker.com/engine/storage/volumes/): where a container's home volume lives
