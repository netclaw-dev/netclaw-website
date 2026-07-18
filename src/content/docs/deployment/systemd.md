---
title: "systemd Service"
description: "Run Netclaw as a systemd service on Linux."
---

The netclaw daemon (`netclawd`) runs as a systemd user service — no `sudo`, no root, just your own account. One CLI command sets everything up.

## Why user-level systemd?

Netclaw is a personal agent. It operates on files in your home directory, signs in to services using your credentials, and connects to tools you've authorized. Running the daemon under your own user account matches the privilege envelope it actually needs.

Choosing `systemd --user` over `systemd --system` is **security-neutral relative to running the daemon directly from your shell**. The same files are reachable, the same credentials are accessible, the same network endpoints are in scope. systemd gives you auto-restart on crash, lingering across logout, and journal integration. None of those require elevated privileges.

The contrast that matters is user-level versus system-level. A system-level service would run as root, or force you to provision a dedicated `netclaw` user. Netclaw's threat model has no use for either. Root would put a personal agent in the same privilege class as the kernel; a dedicated service user would split your config and credentials across two filesystem owners for no benefit.

For stricter isolation, layer hardening directives onto the unit file: `ProtectHome=`, `NoNewPrivileges=true`, seccomp filters. Those add real sandboxing. User-level alone doesn't claim to.

## Before you begin

- Linux with systemd **236+** (Ubuntu 20.04+, Debian 11+, Fedora 36+, RHEL 8+, etc.) — check with `systemctl --version`
- `dbus-user-session` installed — required for `systemctl --user` on headless/minimal servers (e.g., `sudo apt install dbus-user-session` on Debian/Ubuntu, then re-login)
- Netclaw installed — see [Installation](/getting-started/installation/) if you don't have it yet
- An initialized `~/.netclaw` directory — run `netclaw init` first
- A configured provider and model — see [Models](/configuration/models/)

## Install the service

```bash
netclaw daemon install
```

This writes a unit file to `~/.config/systemd/user/netclaw.service`, enables it, and runs `loginctl enable-linger $USER` so the service survives logout.

Start it:

```bash
systemctl --user start netclaw
```

Verify:

```bash
netclaw status
```

![Netclaw status output showing a running daemon](/screenshots/output/status.png)

## The unit file

`netclaw daemon install` generates this at `~/.config/systemd/user/netclaw.service`:

```ini
[Unit]
Description=Netclaw Daemon
After=network.target

[Service]
Type=simple
ExecStart=/path/to/netclawd
ExecStop=/path/to/netclaw daemon stop
Restart=always
RestartSec=5
Environment=DOTNET_ENVIRONMENT=Production
Environment=PATH=/path/to/installdir:/home/you/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

[Install]
WantedBy=default.target
```

The `/path/to/` placeholders are resolved to actual binary locations by `netclaw daemon install` — the literal string never gets written. `ExecStop` uses the CLI's `daemon stop` command instead of a raw signal, which lets the daemon fire shutdown webhooks and drain active sessions before exiting. After `ExecStop` completes, systemd sends SIGTERM with a 10-second grace period. If the process is still alive after that, SIGKILL finishes it. In practice the daemon shuts down well within that window.

The `Environment=PATH=` directive is there because systemd `--user` services start with a sanitized default PATH that does not include `~/.local/bin` or any custom install directory. Without it, the agent's shell tool can't resolve `netclaw` (or other user-installed binaries) when it shells out from inside the daemon. The generated PATH puts your install directory first, then `~/.local/bin`, then the standard system path. If you upgrade from a Netclaw version that predates this directive, see the [Troubleshooting](#shell-tool-cant-find-netclaw-or-other-user-installed-binaries) section below.

### Manual installation

If you prefer to create the service file yourself, adjust the `ExecStart`, `ExecStop`, and `PATH` entries to point at wherever your binaries and user-bin directory actually live:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/netclaw.service << 'EOF'
[Unit]
Description=Netclaw Daemon
After=network.target

[Service]
Type=simple
ExecStart=/path/to/netclawd
ExecStop=/path/to/netclaw daemon stop
Restart=always
RestartSec=5
Environment=DOTNET_ENVIRONMENT=Production
Environment=PATH=/path/to/installdir:/home/you/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable netclaw.service
loginctl enable-linger $USER
systemctl --user start netclaw
```

The `%h` specifier (expands to your home directory) also works in ExecStart/ExecStop paths if you prefer relative-to-home references.

## Service management

| Action | Command |
|--------|---------|
| Start | `systemctl --user start netclaw` |
| Stop | `systemctl --user stop netclaw` |
| Restart | `systemctl --user restart netclaw` |
| Status | `systemctl --user status netclaw` |
| Logs (journal) | `journalctl --user -u netclaw` |
| Enable on boot | `systemctl --user enable netclaw` |
| Disable on boot | `systemctl --user disable netclaw` |

The CLI commands `netclaw daemon start`, `netclaw daemon stop`, and `netclaw daemon status` also work, regardless of whether systemd is managing the process.

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

Config lives at `~/.netclaw/config/netclaw.json`. To relocate the base directory, set `NETCLAW_HOME` — useful when you want data on a separate volume or need to run multiple instances with isolated state. Add it to the `[Service]` section of the unit file:

```ini
[Service]
Environment=NETCLAW_HOME=/data/netclaw
```

### Key paths

| Path | Contents |
|------|----------|
| `~/.netclaw/config/netclaw.json` | Daemon settings |
| `~/.netclaw/config/secrets.json` | Provider API keys and credentials |
| `~/.netclaw/netclaw.db` | SQLite database (sessions, stats) |
| `~/.netclaw/logs/daemon.log` | Rolling log file |
| `~/.netclaw/netclaw.pid` | PID file |
| `~/.netclaw/netclaw.lock` | Singleton lock (OS-backed exclusive lock) |

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

A file watcher on `netclaw.json` picks up changes and triggers a graceful drain-and-restart automatically. One exception: `Daemon.Host`, `Daemon.Port`, and `Daemon.ExposureMode` require a manual `systemctl --user restart netclaw` — the file watcher ignores these fields because changing the listener binding mid-flight isn't safe.

## Health checks

The daemon exposes two HTTP endpoints:

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /api/health/ready` | None | Returns `200 OK` when the daemon is ready |
| `GET /api/health/status` | Required | Detailed runtime status |

Smoke test:

```bash
curl -sf http://127.0.0.1:5199/api/health/ready && echo "OK"
```

To block systemd from reporting the service as "started" until the daemon is actually ready, add an `ExecStartPost` readiness gate to your `[Service]` section. This delays dependent services until netclaw is genuinely accepting connections:

```ini
ExecStartPost=/bin/sh -c 'until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done'
```

For richer metrics and log export, see [OpenTelemetry](/observability/opentelemetry/).

## Logging

Logs go to `~/.netclaw/logs/daemon.log` as a rolling file — `journalctl --user -u netclaw` captures stdout/stderr from the process, but the structured application logs live in the file. Change the log level via `Logging:LogLevel:Default` in `netclaw.json`:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
```

Valid levels: `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`.

Follow the log in real time:

```bash
tail -f ~/.netclaw/logs/daemon.log
```

## Upgrading

Schema migrations are forward-only with no automatic rollback, so back up before upgrading.

Model configuration is the one exception. On 0.25.0, the first model write converts `Models` to named definitions and roles and keeps a restorable snapshot — see [Migrating model configuration](/guides/migrating-model-config/), especially if your unit sets models through `NETCLAW_Models__*` variables.

Unlike the Docker deployment, bare-metal installs can self-update — the daemon periodically checks for new releases and applies them. After an update, the process exits and systemd's `Restart=always` brings it back on the new version. For manual upgrades:

```bash
# 1. Stop the daemon
systemctl --user stop netclaw

# 2. Back up the database
cp ~/.netclaw/netclaw.db ~/.netclaw/netclaw.db.bak.$(date +%s)

# 3. Replace binaries (method depends on how you installed)
#    For manual installs, download and extract the new release.
#    For package manager installs, update the package.

# 4. Start the daemon
systemctl --user start netclaw

# 5. Verify
until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done
echo "Daemon is ready"
```

To rollback: stop the daemon, restore the database backup, put the old binaries back, and start again.

## Uninstalling

```bash
netclaw daemon uninstall
```

Your data in `~/.netclaw` stays untouched.

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

![Netclaw doctor output showing health check diagnostics](/screenshots/output/doctor.png)

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
tail -20 ~/.netclaw/logs/daemon.log
```

Common causes: port conflict (another process on 5199), JSON syntax error in `netclaw.json`, or missing provider configuration.

### "Daemon already running" when starting

The lock file at `~/.netclaw/netclaw.lock` is held by another process — either a daemon is already running or a previous instance didn't exit cleanly. Check for it:

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

If your agent reports `command not found` when shelling out to `netclaw stats`, `gh`, or any other binary in `~/.local/bin`, the systemd unit's PATH is missing the directory where those binaries live. This was the default before the `Environment=PATH=` directive was baked into the install template, so older units don't have it at all.

Run `netclaw doctor` to confirm — the **Systemd Unit PATH** check will report a Warning if the unit lacks a PATH directive or doesn't include the daemon's install directory.

Refresh the unit file:

```bash
netclaw daemon uninstall
netclaw daemon install
systemctl --user restart netclaw
```

Verify the daemon picked up the new PATH:

```bash
cat /proc/$(pgrep -u "$USER" netclawd)/environ | tr '\0' '\n' | grep PATH
```

### Service fails on older systemd versions

User-level services require systemd 236+. Check with `systemctl --version`. On older systems, skip systemd and run `netclaw daemon start` directly — it detaches as a background process.

## Related pages

- [Docker Deployment](/deployment/docker/) — containerized alternative
- [Exposure Modes](/deployment/exposure-modes/) — remote access via Tailscale or Cloudflare Tunnel
- [Models](/configuration/models/) — model slot configuration
- [OpenTelemetry](/observability/opentelemetry/) — metrics and log export
- [`netclaw doctor`](/cli/doctor/) — built-in health check diagnostics

## Resources

- [systemd user services documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) — full unit file reference
- [systemd user services on ArchWiki](https://wiki.archlinux.org/title/Systemd/User) — best practical guide for user-level systemd
- [loginctl enable-linger](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) — why lingering matters for headless services
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention used by `NETCLAW_` env vars
