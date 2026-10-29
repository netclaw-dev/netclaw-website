---
title: "netclaw update"
description: "Check for a newer netclaw release, install it, and switch between the stable and beta channels."
---

`netclaw update` downloads the newest release on your channel, verifies it, swaps the `netclaw` and `netclawd` binaries, and restarts the daemon if it was running. Run it on a host install. In Docker you pull a new image instead.

## Usage

```bash
netclaw update [options]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--check` | Report whether an update exists and install nothing | Off |
| `--force` | Skip the `Proceed with update? [y/N]` prompt | Off |
| `--channel <name>` | Switch the release channel, `stable` or `beta`, and save it to `netclaw.json`. With `--check` it previews the channel and saves nothing. | `stable` |

An unknown channel or flag prints the usage text and exits `1`. `--channel` with no value prints `--channel requires a value: stable or beta.`

## Examples

### Check, then install

```bash
netclaw update --check
netclaw update
```

```text
Update available: v0.28.0 → v0.28.2
Release notes: https://github.com/netclaw-dev/netclaw/releases/tag/0.28.2

  netclaw (linux-x64) - 70.2 MB
  netclawd (linux-x64) - 74.7 MB

Proceed with update? [y/N]: y
Downloading netclaw... verified.
Downloading netclawd... verified.
Stopping daemon... done.
Installing... done.
Restarting daemon... done.

Updated to v0.28.2.
```

![Terminal showing netclaw --version reporting 0.28.1, then netclaw update --check reporting that v0.28.2 is available with a release notes link](/screenshots/output/update-check.png)

The check alone, from a 0.28.1 install. It reports and changes nothing.

Add `--force` for scripts. When the daemon is already current, the command prints `Netclaw is up to date (v0.28.2).` and exits `0`.

### Move to the beta channel

```bash
netclaw update --channel beta
```

This saves `Daemon.UpdateChannel` to `netclaw.json`, then installs the newest build on that channel. Later checks follow it. `--channel stable` switches back. Beta resolves to the newest of the latest prerelease and the latest stable, so a stable release that supersedes a beta is still offered.

## What it changes

| Touched | Not touched |
|---------|-------------|
| The `netclaw` and `netclawd` binaries, in the directory of the running CLI (`~/.netclaw/bin` by default) | `~/.netclaw` data, `netclaw.json` and `secrets.json` |
| `Daemon.UpdateChannel` in `netclaw.json`, only when you pass `--channel` without `--check` | The systemd unit file and `daemon.env`. The unit keeps the same `ExecStart` path, which is why updates work in place. |

The command keeps the daemon's owner, using the same rule as [`netclaw daemon stop` and `start`](/cli/daemon/#under-systemd). When the systemd user unit is running this home's daemon, it stops and starts the daemon with `systemctl --user`. A daemon you started by hand, or one that belongs to a different `NETCLAW_HOME`, goes through `netclaw daemon stop` and `start`, which first prove the PID serves this home (see [Home check](/cli/daemon/#home-check)). On Linux that proof reads `/proc/<pid>/environ`. On macOS and Windows a daemon that doesn't answer with its home can't be proven. A 0.27.1 daemon is one, so stop it by hand before you update from 0.27.1. A daemon that wasn't running stays stopped.

It verifies the release manifest's signature and each archive's SHA-256 before it touches a binary. If the signature check fails, the command stops and says the manifest may have been tampered with. If swapping a binary fails, the previous binary is restored. After a successful update the old binaries are deleted, so there's nothing to roll back to. To go back, [install an older release](#pin-or-go-back-to-a-version).

The new daemon migrates `netclaw.db` forward when it starts, and the older one can't read everything the newer one writes. Take a [backup](/guides/backup-and-restore/) first, and read [Upgrade netclaw](/guides/upgrading/) for what changes between versions.

## Pin or go back to a version

`netclaw update` always installs the newest release on the channel. It has no `--version` flag. To pin an exact version or install an older one, run the install script with `NETCLAW_VERSION`. It replaces the binaries and leaves your data alone:

```bash
systemctl --user stop netclaw
curl -sSL https://releases.netclaw.dev/install.sh | NETCLAW_VERSION=0.28.0 bash
systemctl --user start netclaw
```

Going back past 0.27.0 isn't a supported path. See [Downgrading](/guides/upgrading/#downgrading).

## When the daemon says an update exists

The daemon checks at startup and every 24 hours. It logs a warning, raises an `update.available` [alert](/observability/operational-alerts/), and shows the state in [`netclaw status`](/cli/status/). It never downloads or installs anything. Most other `netclaw` commands also print a one-line `Update available` notice to stderr. [`netclaw doctor`](/cli/doctor/) reports it as a warning.

## Docker

The image sets `Daemon.DisableSelfUpdate=true`, so installing is refused:

```text
Update available: v0.28.0 → v0.28.2
Release notes: https://github.com/netclaw-dev/netclaw/releases/tag/0.28.2

Self-update is disabled (Daemon.DisableSelfUpdate=true).
Pull a newer container image to upgrade.
```

The command exits `1`. `--check` still works. Change the image tag, as described in [Run netclaw in Docker](/deployment/docker/#upgrading).

## Troubleshooting

### `Could not check for updates`

**Cause:** The release feed at `releases.netclaw.dev` isn't reachable from this machine, or it didn't answer in time. A timeout reads `Timed out after <n>s fetching manifest from <url>` (or `manifest signature`).

**Fix:** Check outbound HTTPS and any proxy. The daemon and the CLI both need it. The daemon's own check logs a warning (`Netclaw update check failed`) and keeps running.

### `Update aborted. Stop the daemon manually, fix service state, and retry.`

**Cause:** The daemon couldn't be stopped, for example because systemd reported an error, or because `netclaw daemon stop` refused with `Nothing was stopped. PID <n> is not shown to serve <home>.` The binaries weren't replaced.

**Fix:** Run `systemctl --user status netclaw` or `netclaw daemon status`, stop the daemon yourself, and run the update again.

### `Could not determine whether systemd owns the daemon lifecycle`

**Cause:** The systemd unit is installed but your shell has no user session bus (no `XDG_RUNTIME_DIR`), so the update can't tell whether the unit would restart the daemon behind its back. It stops before touching a binary.

**Fix:** Run the update from a login session, or export `XDG_RUNTIME_DIR=/run/user/$(id -u)`.

### `Update installed, but daemon restart failed`

**Cause:** The new binaries are in place but the daemon didn't come back up.

**Fix:** Start it with `systemctl --user start netclaw` or `netclaw daemon start`, and read the newest file in `logs/` for the reason. A config the new version rejects is the usual cause.

## Related pages

- [Upgrade netclaw](/guides/upgrading/) - back up, upgrade, verify and roll back, with what changed in each release
- [Back up, restore and move netclaw](/guides/backup-and-restore/) - what to copy before you update
- [Installation](/getting-started/installation/) - the install script and its options
- [`netclaw daemon`](/cli/daemon/) - start, stop and install the daemon
- [systemd service](/deployment/systemd/) - how a systemd-managed daemon is restarted

## Resources

- [netclaw releases on GitHub](https://github.com/netclaw-dev/netclaw/releases) - release notes for every version
- [systemctl reference](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html) - `--user` service control
