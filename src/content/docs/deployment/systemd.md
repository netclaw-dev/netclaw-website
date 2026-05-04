---
title: "systemd Service"
description: "Run Netclaw as a systemd service on Linux."
---

The netclaw daemon (`netclawd`) runs as a systemd user service on Linux. User-level, so no `sudo`, no root — it runs under your own account. One CLI command creates the unit file, enables the service, and sets up lingering so it survives logout.

## Before you begin

- Linux with systemd (Ubuntu 20.04+, Debian 11+, Fedora 36+, RHEL 8+, etc.)
- Netclaw installed — see [Installation](/getting-started/installation/) if you don't have it yet
- An initialized `~/.netclaw` directory — run `netclaw init` first
- A configured provider and model — see [Models](/configuration/models/)

## Install the service

```bash
netclaw daemon install
```

This does three things:

1. Writes a unit file to `~/.config/systemd/user/netclaw.service`
2. Runs `systemctl --user enable netclaw.service`
3. Runs `loginctl enable-linger $USER` so the service survives logout

Start it:

```bash
systemctl --user start netclaw
```

Verify:

```bash
netclaw status
```

![Netclaw status output showing a running daemon](/screenshots/output/status.png)

If the daemon is listening and reporting uptime, you're good.

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

[Install]
WantedBy=default.target
```

Paths get resolved from wherever the CLI is installed. `ExecStop` uses the CLI's `daemon stop` command instead of a raw signal, which lets the daemon fire shutdown webhooks and drain cleanly before exiting.

### Manual installation

If you prefer to create the service file yourself:

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
Restart=always
RestartSec=5
Environment=DOTNET_ENVIRONMENT=Production

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable netclaw.service
loginctl enable-linger $USER
systemctl --user start netclaw
```

Adjust `ExecStart` and `ExecStop` to wherever your binaries live. The `%h` specifier expands to your home directory.

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

Config lives at `~/.netclaw/config/netclaw.json`. Override the base directory with the `NETCLAW_HOME` environment variable.

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

Override with environment variables by adding them to the unit file:

```ini
[Service]
Environment=NETCLAW_Daemon__Host=127.0.0.1
Environment=NETCLAW_Daemon__Port=5200
```

After editing the unit file, reload and restart:

```bash
systemctl --user daemon-reload
systemctl --user restart netclaw
```

For remote access via Tailscale or Cloudflare Tunnel, see [Exposure Modes](/deployment/exposure-modes/).

### Config reload

A file watcher on `netclaw.json` picks up changes and triggers a graceful restart automatically. No manual restart needed for config changes.

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

To block systemd from reporting the service as "started" until the daemon is actually ready, add this to your `[Service]` section:

```ini
ExecStartPost=/bin/sh -c 'until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done'
```

For richer metrics and log export, see [OpenTelemetry](/observability/opentelemetry/).

## Logging

Logs go to `~/.netclaw/logs/daemon.log` as a rolling file. There's no systemd journal integration. Change the log level via `Logging:LogLevel:Default` in `netclaw.json`:

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

To follow the log in real time:

```bash
tail -f ~/.netclaw/logs/daemon.log
```

While `journalctl --user -u netclaw` will show stdout/stderr from the process, the structured application logs live in the file.

## Upgrading

Schema migrations are forward-only — there's no automatic rollback. Back up before upgrading.

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

This stops the service, disables it, removes the unit file, and runs `daemon-reload`. Your data in `~/.netclaw` stays untouched.

To remove manually:

```bash
systemctl --user stop netclaw
systemctl --user disable netclaw
rm ~/.config/systemd/user/netclaw.service
systemctl --user daemon-reload
```

## Troubleshooting

### Daemon stops after SSH disconnect

Lingering isn't enabled. Fix it with `loginctl enable-linger $USER` and verify with `ls /var/lib/systemd/linger/`.

### "Failed to connect to bus" when running systemctl

`XDG_RUNTIME_DIR` isn't set. Common when running `systemctl --user` from cron or a non-login shell. Export it manually:

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

Common causes: port conflict (another process on 5199), invalid config file, or missing provider configuration.

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

### Service fails on older systemd versions

User-level services require systemd 236+. Check with `systemctl --version`. On older systems, skip systemd and run `netclaw daemon start` directly — it detaches as a background process.

## Related pages

- [Docker Deployment](/deployment/docker/) — containerized alternative
- [Exposure Modes](/deployment/exposure-modes/) — remote access via Tailscale or Cloudflare Tunnel
- [Models](/configuration/models/) — model slot configuration
- [OpenTelemetry](/observability/opentelemetry/) — metrics and log export

## Resources

- [systemd user services documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) — full unit file reference
- [loginctl enable-linger](https://www.freedesktop.org/software/systemd/man/latest/loginctl.html) — why lingering matters for headless services
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention used by `NETCLAW_` env vars
