---
title: "systemd Service"
description: "Run the netclaw daemon as a systemd user service on Linux: install it, read its logs, update it and troubleshoot it."
---

The netclaw daemon (`netclawd`) runs as a systemd user service. No `sudo`, no root, just your own account. One CLI command sets everything up. Linux only: macOS and Windows have no background service, so see [Not on Linux](#not-on-linux).

## Why user-level systemd?

Netclaw is a personal agent. It operates on files in your home directory, signs in to services using your credentials, and connects to tools you've authorized. Running the daemon under your own user account matches the privilege envelope it actually needs.

Choosing `systemd --user` over `systemd --system` is security-neutral relative to running the daemon directly from your shell. The same files are reachable, the same credentials are accessible, the same network endpoints are in scope. systemd gives you auto-restart on crash, lingering across logout, and journal integration. None of those require elevated privileges.

The contrast that matters is user-level versus system-level. A system-level service would run as root, or force you to provision a dedicated `netclaw` user. Netclaw's threat model has no use for either. Root would put a personal agent in the same privilege class as the kernel. A dedicated service user would split your config and credentials across two filesystem owners for no benefit.

For stricter isolation, layer hardening directives onto the unit file: `ProtectHome=`, `NoNewPrivileges=true`, seccomp filters. Those add real sandboxing. User-level alone doesn't claim to.

## Before you begin

- Linux with systemd user services. These steps were run on Ubuntu 24.04 with systemd 255. Check yours with `systemctl --version`.
- `dbus-user-session` installed, which `systemctl --user` needs on headless and minimal servers (`sudo apt install dbus-user-session` on Debian and Ubuntu, then log in again)
- About 1 GiB of free memory. Local embeddings are on by default and download about 129 MB of models on first start. See [Memory and first start](/deployment/docker/#memory-and-first-start).
- Netclaw installed. See [Installation](/getting-started/installation/) if you don't have it yet.
- An initialized `~/.netclaw` directory. Run `netclaw init` first.
- A configured provider and model. See [Models](/configuration/models/).

## Install the service

```bash
netclaw daemon install
```

This writes a unit file to `~/.config/systemd/user/netclaw.service` and `~/.netclaw/config/daemon.env`, enables the unit, and runs `loginctl enable-linger $USER` so the service survives logout. It doesn't start the service. Start it:

```bash
systemctl --user start netclaw
```

If the command ends with `Service installed but linger failed: Could not enable linger: Access denied`, the unit is installed but your session can't enable lingering. The command exits `1`. Run `sudo loginctl enable-linger $USER`.

On a host without user systemd, such as a minimal container or a session with no `XDG_RUNTIME_DIR`, `install` writes nothing and exits `1`:

```text
Cannot install the service: systemd user services are not available on this host (Failed to connect to bus: No medium found). Run the daemon under a container supervisor, or start it with `netclaw daemon start` (it will not restart after a crash or reboot).
```

See [Failed to connect to bus](#failed-to-connect-to-bus-when-running-systemctl) for the fix.

Verify:

```bash
netclaw status
```

![netclaw status output: overall healthy, version 0.28.2, the active model, and connector lines for Discord, Mattermost, the demo-utilities MCP server, Slack and the TUI](/screenshots/output/status.png)

The `uptime` on the daemon line is how you tell a unit that restarted from one that never stopped.

## The unit file

`netclaw daemon install` generates this at `~/.config/systemd/user/netclaw.service`:

```ini
[Unit]
Description=Netclaw Daemon
After=network.target

[Service]
Type=simple
ExecStart=/home/you/.netclaw/bin/netclawd
ExecStop=/home/you/.netclaw/bin/netclaw daemon stop
TimeoutStopSec=60
Restart=always
RestartSec=5
Environment=DOTNET_ENVIRONMENT=Production
EnvironmentFile=-/home/you/.netclaw/config/daemon.env

[Install]
WantedBy=default.target
```

The binary paths are the real locations of `netclawd` and `netclaw`, resolved when you run `netclaw daemon install`. `ExecStop` uses the CLI's `daemon stop` command instead of a raw signal, which lets the daemon fire shutdown webhooks and drain active sessions before exiting. `TimeoutStopSec=60` gives that drain room: the daemon's graceful shutdown budget is 30 seconds, and `daemon stop` waits up to 45 before it force-kills. Existing installs pick up the 60-second value after you re-run `netclaw daemon install`.

`EnvironmentFile` points at `~/.netclaw/config/daemon.env`, which holds a `PATH=` line. systemd `--user` services start with a sanitized default PATH that does not include `~/.local/bin` or any custom install directory, so `netclaw daemon install` captures the PATH of the shell you ran it from and writes it there. Without it, the agent's shell tool can't resolve `netclaw` (or other user-installed binaries) when it shells out from inside the daemon. The leading `-` makes systemd tolerate a missing file. `netclaw daemon install` and `netclaw doctor --fix` replace only the first `PATH` line and keep every other line in the file as it was, so `daemon.env` is also where your own settings go (see [Configuration](#configuration)). If you upgrade from a Netclaw version that predates this, see the [Troubleshooting](#shell-tool-cant-find-netclaw-or-other-user-installed-binaries) section below.

### Manual installation

To write the service file yourself, point `ExecStart`, `ExecStop` and `PATH` at wherever your binaries and user-bin directory live. `%h` expands to your home directory:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/netclaw.service << 'EOF'
[Unit]
Description=Netclaw Daemon
After=network.target

[Service]
Type=simple
ExecStart=%h/.netclaw/bin/netclawd
ExecStop=%h/.netclaw/bin/netclaw daemon stop
TimeoutStopSec=60
Restart=always
RestartSec=5
Environment=DOTNET_ENVIRONMENT=Production
Environment=PATH=%h/.netclaw/bin:%h/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable netclaw.service
loginctl enable-linger $USER
systemctl --user start netclaw
```

## Service management

| Action | Command |
|--------|---------|
| Start | `systemctl --user start netclaw` |
| Stop | `systemctl --user stop netclaw` |
| Restart | `systemctl --user restart netclaw` |
| Status | `systemctl --user status netclaw` |
| Lifecycle events | `journalctl --user -u netclaw` |
| Daemon log | `tail -f ~/.netclaw/logs/daemon-*.log` |
| Enable on boot | `systemctl --user enable netclaw` |
| Disable on boot | `systemctl --user disable netclaw` |

`netclaw daemon status` works whoever started the daemon, as long as the PID in `netclaw.pid` is shown to serve this home. If it isn't, nothing is signalled. See [`Nothing was stopped`](#nothing-was-stopped-pid-is-not-shown-to-serve-the-home). `netclaw daemon stop` and `netclaw daemon start` use the unit when it is running this home's daemon, so they're interchangeable with `systemctl --user stop` and `start`, and a daemon stopped with `netclaw daemon stop` stays stopped. There's no `netclaw daemon restart`: use `systemctl --user restart netclaw`. See [`netclaw daemon`](/cli/daemon/).

### Lingering

systemd kills user services when you log out. [Lingering](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) prevents that by keeping your user slice alive.

```bash
# Check if lingering is enabled
ls /var/lib/systemd/linger/$USER

# Enable it (netclaw daemon install does this automatically)
loginctl enable-linger $USER
```

If your daemon stops every time you disconnect SSH, lingering isn't enabled.

## Configuration

Config lives at `~/.netclaw/config/netclaw.json`. To relocate the base directory, set `NETCLAW_HOME`. That helps when you want data on a separate volume or need to run multiple instances with isolated state. Put it in the new home's `daemon.env`, which `netclaw daemon install` and `netclaw doctor --fix` leave alone:

```bash
export NETCLAW_HOME=/data/netclaw
mkdir -p "$NETCLAW_HOME/config"
echo "NETCLAW_HOME=$NETCLAW_HOME" >> "$NETCLAW_HOME/config/daemon.env"
```

The file has to sit under the new home. With `NETCLAW_HOME` exported, `netclaw daemon install` reads and writes `<home>/config/daemon.env`, so a line left in `~/.netclaw/config/daemon.env` never reaches the unit and the daemon runs on `~/.netclaw`. Use an absolute path. Keep the same value exported in the shell where you run `netclaw`, because `netclaw daemon stop`, `start` and `status` refuse to act when the PID file's process isn't shown to serve the CLI's home. A value with `~`, `$HOME` or `%USERPROFILE%` gives the CLI no proof on Linux. If a line holds a credential, run `chmod 600` on `daemon.env`.

The install script honors `NETCLAW_HOME` too: config goes to `<home>/config`, and a fresh install puts `bin/` and `env` under it. `INSTALL_DIR` still wins, and an existing `~/.netclaw/bin` install is upgraded in place. `CONFIG_DIR` and `NETCLAW_CONFIG_DIR` no longer do anything.

### Key paths

| Path | Contents |
|------|----------|
| `~/.netclaw/config/netclaw.json` | Daemon settings |
| `~/.netclaw/config/secrets.json` | Provider API keys and credentials |
| `~/.netclaw/config/daemon.env` | The `PATH` the unit gives the daemon's shell tool, plus any settings of your own |
| `~/.netclaw/netclaw.db` | SQLite database: history, reminders, stats, memory |
| `~/.netclaw/logs/daemon-YYYY-MM-DD.log` | Daily log file, continued in `daemon-YYYY-MM-DD.1.log`, `.2.log` and so on at 10 MiB |
| `~/.netclaw/netclaw.pid` | PID file |
| `~/.netclaw/netclaw.lock` | Singleton lock (OS-backed exclusive lock) |

[Data directory layout](/reference/data-directory/) lists everything else.

### Network binding

Default binding is `127.0.0.1:5199`, loopback only.

```json
{
  "Daemon": {
    "Host": "127.0.0.1",
    "Port": 5199
  }
}
```

To bind a different address or port via environment variables, add them to the unit file:

```ini
[Service]
Environment=NETCLAW_Daemon__Host=127.0.0.1
Environment=NETCLAW_Daemon__Port=5200
```

Then reload and restart:

```bash
systemctl --user daemon-reload
systemctl --user restart netclaw
```

For remote access via Tailscale or Cloudflare Tunnel, see [Exposure Modes](/deployment/exposure-modes/).

### Config reload

A file watcher on `netclaw.json` picks up valid changes and triggers a graceful drain-and-restart automatically (tool loops stop at a safe point, and a running sub-agent parks and resumes, which can add about 18 seconds), including `Daemon.Host`, `Daemon.Port`, and `Daemon.ExposureMode`. It doesn't watch `secrets.json` or environment variables (including the unit file's `Environment=` lines), so run `systemctl --user restart netclaw` after changing those.

An invalid `Models` or provider section doesn't restart anything. The running daemon keeps its previous configuration, and [`netclaw status`](/cli/status/) reports `degraded` with `config on disk not applied: <reason>` until you fix the file. A daemon that restarts with that file exits `1` at startup with the same one-line reason, and systemd restarts it every five seconds.

## Health checks

The daemon exposes two HTTP endpoints:

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /api/health/ready` | None | Returns `200 OK` when the daemon is ready |
| `GET /api/health/status` | Required, except from loopback in `local` mode | Detailed runtime status. See [Health checks](/observability/health-checks/) |

Smoke test:

```bash
curl -sf http://127.0.0.1:5199/api/health/ready && echo "OK"
```

To block systemd from reporting the service as "started" until the daemon is actually ready, add an `ExecStartPost` readiness gate to your `[Service]` section. This delays dependent services until netclaw is genuinely accepting connections:

```ini
ExecStartPost=/bin/sh -c 'until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done'
TimeoutStartSec=300
```

`TimeoutStartSec` covers `ExecStartPost`, and its default is 90 seconds. The first start downloads about 130 MB of embedding models and can take longer than that. Without the longer timeout, systemd kills the unit and `Restart=always` loops.

For richer metrics and log export, see [OpenTelemetry](/observability/opentelemetry/).

## Logging

The daemon writes to `~/.netclaw/logs/daemon-YYYY-MM-DD.log`, one series per UTC day. At 10 MiB it continues in `daemon-YYYY-MM-DD.1.log`, then `.2.log`, and a restart appends to the first segment below the limit. The journal shows only what systemd sees: start, stop and the `ExecStop` output. The daemon deletes daily, numbered and crash logs older than 14 days (the newest three of each are always kept), starting 30 seconds after it starts and again every 12 hours. [Data retention](/configuration/data-retention/) covers the setting.

```bash
tail -f ~/.netclaw/logs/daemon-*.log
```

To see daemon logs in the journal too, turn on console logging in a drop-in:

```bash
mkdir -p ~/.config/systemd/user/netclaw.service.d
cat > ~/.config/systemd/user/netclaw.service.d/logging.conf << 'EOF'
[Service]
Environment=NETCLAW_Logging__Console__Enabled=true
EOF
systemctl --user daemon-reload
systemctl --user restart netclaw
journalctl --user -u netclaw -f
```

The default level is `Information`. Change it with `Logging:LogLevel:Default` in `netclaw.json`:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning"
    }
  }
}
```

Valid levels: `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`. Crash reports land in `logs/crash-*.log`, and [`netclaw doctor`](/cli/doctor/) flags recent ones.

## Updating

The daemon checks for a new release at startup and every 24 hours, logs a warning and raises an `update.available` [alert](/observability/operational-alerts/). It never downloads or applies one. You do that:

```bash
netclaw update --check
netclaw update
```

`netclaw update` stops the service with `systemctl --user`, swaps the two binaries, and starts it again, so the unit file doesn't change. See [`netclaw update`](/cli/update/).

[Back up first](/guides/backup-and-restore/) and read [Upgrade netclaw](/guides/upgrading/). Each release can migrate `netclaw.db`, and an older binary can't read everything a newer one wrote. To go back, stop the service and reinstall an older release over the binaries with the install script and `NETCLAW_VERSION`. That's only safe within the same minor series.

If you install by hand instead:

```bash
systemctl --user stop netclaw
curl -sSL https://releases.netclaw.dev/install.sh | NETCLAW_VERSION=0.28.2 bash
systemctl --user start netclaw
until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done
```

## Not on Linux

macOS and Windows have no background service. `netclaw daemon install` refuses with `Service installation is not yet supported on macOS` or `Service installation is currently Linux-only (systemd)`. On those systems start the daemon yourself with `netclaw daemon start`. It runs detached from the terminal and stops with `netclaw daemon stop`. If the daemon doesn't answer, `daemon stop` can't prove the PID is yours and refuses, printing the `kill <pid>` command to use (Task Manager on Windows). It doesn't start again after a reboot, so launch it from a login script if you want that. The macOS service request is tracked in [netclaw issue 1015](https://github.com/netclaw-dev/netclaw/issues/1015). The unit file above doesn't apply there.

## Uninstalling

```bash
netclaw daemon uninstall
```

This stops and disables the service and removes the unit file and `daemon.env`, including any settings of your own in it. To refresh the unit and keep those lines, run `netclaw daemon install` again instead. Your data in `~/.netclaw` stays untouched.

To remove manually:

```bash
systemctl --user stop netclaw
systemctl --user disable netclaw
rm ~/.config/systemd/user/netclaw.service
systemctl --user daemon-reload
```

## Troubleshooting

### Start here: `netclaw doctor`

Before diving into specific symptoms, run [`netclaw doctor`](/cli/doctor/). It checks provider connectivity, config validity, daemon health, and common misconfigurations in one pass.

![netclaw doctor output: 24 checks, all PASS, ending with doctor exit code: 0](/screenshots/output/doctor.png)

On a fresh install with no stored credentials, the usual lone warning is a missing `secrets.json`.

### Daemon stops after SSH disconnect

Lingering isn't enabled. Fix it with `loginctl enable-linger $USER` and verify with `ls /var/lib/systemd/linger/`.

### "Failed to connect to bus" when running systemctl

`XDG_RUNTIME_DIR` isn't set. Common when running `systemctl --user` from cron or a non-login shell. On headless servers, also make sure `dbus-user-session` is installed (`sudo apt install dbus-user-session`). Export the runtime dir manually:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
systemctl --user status netclaw
```

### Service starts but CLI can't connect

Check that the daemon is actually listening:

```bash
ss -tlnp | grep 5199
```

If nothing shows, check the daemon log:

```bash
ls -t ~/.netclaw/logs/daemon-*.log | head -1 | xargs tail -20
```

Common causes: port conflict (another process on 5199), JSON syntax error in `netclaw.json`, or missing provider configuration.

### "Daemon already running" when starting

The lock file at `~/.netclaw/netclaw.lock` is held by another process. Either a daemon is already running or a previous instance didn't exit cleanly. Check for it:

```bash
pgrep -a netclawd
```

If nothing shows, the lock file is stale. Remove it and restart:

```bash
systemctl --user stop netclaw
rm ~/.netclaw/netclaw.lock
systemctl --user start netclaw
```

### Shell tool can't find `netclaw` (or other user-installed binaries)

If your agent reports `command not found` when shelling out to `netclaw stats`, `gh`, or any other binary in `~/.local/bin`, the systemd unit's PATH is missing the directory where those binaries live. Older units were generated without a PATH source (an inline `Environment=PATH=` line, later the `EnvironmentFile`), so they don't have it at all.

Run `netclaw doctor` to confirm. The **Systemd Unit PATH** check will report a Warning if the unit lacks a PATH source or the PATH doesn't include the daemon's install directory.

Refresh the unit file:

```bash
netclaw daemon uninstall
netclaw daemon install
systemctl --user restart netclaw
```

`netclaw doctor --fix` replaces the `PATH` line in `daemon.env` and keeps your other lines, without rewriting the unit. Verify the daemon picked up the new PATH:

```bash
cat /proc/$(pgrep -u "$USER" netclawd)/environ | tr '\0' '\n' | grep PATH
```

### `Could not determine whether systemd owns the daemon lifecycle`

**Symptom:** `netclaw daemon stop` or `start` exits `1` and says the user session bus isn't reachable.

**Cause:** A unit is installed, but your shell has no `XDG_RUNTIME_DIR`, so the CLI can't ask systemd who owns the daemon. It refuses to guess, because a guess could leave `Restart=always` bringing the daemon straight back.

**Fix:** Run the command from a login session, or export `XDG_RUNTIME_DIR` as shown above. `systemctl --user` works from the same shell.

### `Nothing was stopped. PID is not shown to serve the home`

**Symptom:** `netclaw daemon stop`, `start` or `status` exits `1` with two lines on stderr, the first naming `PID <pid> is not shown to serve <home>`.

**Cause:** The CLI signals the PID in `netclaw.pid` only when it can show that process serves this home. The usual reasons are a stale PID file, or a different `NETCLAW_HOME` in your shell than in `daemon.env`. `daemon stop` only ever stops the daemon of its own home.

**Fix:** If no daemon of this home runs, delete `~/.netclaw/netclaw.pid`. If the PID is one of this home's daemons, check it, then `kill <pid>`. Never use `pkill netclawd`, which would also hit daemons of other homes.

### `Systemd Unit PATH` warning from `netclaw doctor`

**Cause:** `config/daemon.env` is missing, usually after restoring a backup onto the machine.

**Fix:** Run `netclaw doctor --fix`, then `systemctl --user restart netclaw`.

## Related pages

- [`netclaw daemon`](/cli/daemon/) - start, stop and install the daemon
- [`netclaw update`](/cli/update/) - install a new release
- [Upgrade netclaw](/guides/upgrading/) - what changes between releases
- [Run netclaw in Docker](/deployment/docker/) - the containerized alternative
- [Exposure modes](/deployment/exposure-modes/) - remote access via Tailscale or Cloudflare Tunnel

## Resources

- [systemd user services documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) - full unit file reference
- [systemd user services on ArchWiki](https://wiki.archlinux.org/title/Systemd/User) - best practical guide for user-level systemd
- [loginctl enable-linger](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) - why lingering matters for headless services
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) - the double-underscore nesting convention used by `NETCLAW_` env vars
