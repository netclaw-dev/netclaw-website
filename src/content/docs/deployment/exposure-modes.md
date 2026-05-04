---
title: Exposure Modes
description: Configure how netclaw is exposed to the network — local, Tailscale Serve, Tailscale Funnel, or Cloudflare Tunnel.
---

Exposure mode controls how the daemon is reachable over the network. Most setups stay on local mode. You only need a tunnel mode when something external (GitHub webhooks, CI, a second machine) needs to reach the daemon.

## Before you begin

- Netclaw installed and initialized (`netclaw init`). See [Installation](/getting-started/installation/) if needed.
- For Tailscale modes: [`tailscaled` installed and running](https://tailscale.com/download).
- For Cloudflare Tunnel: [`cloudflared` installed and configured](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/).

## Modes

| Mode | Config value | Required process | Reachability | Risk |
|------|-------------|-----------------|-------------|------|
| **Local** | `local` | None | Loopback only | Lowest |
| **Tailscale Serve** | `tailscale-serve` | `tailscaled` | Your Tailscale network (called a [tailnet](https://tailscale.com/kb/1136/tailnet)), HTTPS | Low |
| **Tailscale Funnel** | `tailscale-funnel` | `tailscaled` | Public internet via Tailscale | High |
| **Cloudflare Tunnel** | `cloudflare-tunnel` | `cloudflared` | Public internet via Cloudflare | High |

The `netclaw init` wizard covers this at step 9:

![Exposure mode selection in the netclaw init wizard, with Local highlighted as the recommended option](/screenshots/output/init-09-exposure.png)

Options marked with a warning triangle expose the daemon to the public internet. Tailscale Serve is the recommended remote mode: tailnet-only access, no public exposure.

## Configuration

Set the mode in the `Daemon` section of `~/.netclaw/config/netclaw.json`.

### Local (default)

No `Daemon` section needed. The daemon binds to `127.0.0.1:5199` and is only reachable from the same machine.

```json
{}
```

### Tailscale Serve

```json
{
  "Daemon": {
    "ExposureMode": "tailscale-serve"
  }
}
```

Tailscale Serve creates an HTTPS endpoint on your tailnet that proxies to the daemon's local port. Only devices on your tailnet can reach it. Then run [`tailscale serve`](https://tailscale.com/kb/1242/tailscale-serve) to proxy your tailnet hostname to `127.0.0.1:5199`.

### Tailscale Funnel

```json
{
  "Daemon": {
    "ExposureMode": "tailscale-funnel"
  }
}
```

Funnel extends Serve to the public internet. Anyone with the URL can reach the daemon, though netclaw's device authentication still applies. Configure it with [`tailscale funnel`](https://tailscale.com/kb/1223/funnel). Only use Funnel when you need public internet access — Tailscale Serve covers everything else.

### Cloudflare Tunnel

```json
{
  "Daemon": {
    "ExposureMode": "cloudflare-tunnel"
  }
}
```

Routes traffic through Cloudflare's network to the daemon. Set up `cloudflared` with a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/) pointed at `127.0.0.1:5199`, and pair it with a [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) policy to restrict who can connect.

<!-- TODO: needs user input — What's the recommended Cloudflare Access policy configuration for netclaw? -->

### Full Daemon section

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `Host` | string | `127.0.0.1` | IP address the daemon binds to |
| `Port` | int | `5199` | TCP port |
| `ExposureMode` | string | `local` | `local`, `tailscale-serve`, `tailscale-funnel`, or `cloudflare-tunnel` |

```json
{
  "Daemon": {
    "Host": "127.0.0.1",
    "Port": 5199,
    "ExposureMode": "tailscale-serve"
  }
}
```

Case-insensitive — `tailscale-serve`, `TailscaleServe`, and `TAILSCALE-SERVE` all work.

**Docker users:** if you switch to a tunnel mode, update your container's port binding to match the `Host` and `Port` values here. See [Docker Deployment](/deployment/docker/) for details.

### Environment variables

Override any field with `NETCLAW_Daemon__` prefixed env vars:

```bash
NETCLAW_Daemon__ExposureMode=tailscale-serve
NETCLAW_Daemon__Host=127.0.0.1
NETCLAW_Daemon__Port=5199
```

Double underscores separate path segments, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider).

### Restart required

`Host`, `Port`, and `ExposureMode` require a daemon restart — they aren't hot-reloaded. Other config changes trigger an automatic restart; the daemon drains active sessions and restarts itself.

```bash
# systemd
systemctl --user restart netclaw

# Docker
docker restart netclaw
```

## Inbound webhooks

Tunnel modes make [inbound webhooks](/configuration/webhooks/) possible. External services like GitHub or CI systems can trigger autonomous runs via HTTP POST. The `netclaw init` wizard asks about this right after exposure mode selection:

![Inbound webhook toggle in the init wizard](/screenshots/output/init-09-webhooks.png)

They do nothing in local mode.

## Device pairing

Non-local modes require at least one paired device or an alternative remote authentication scheme. Without one, the daemon refuses to start — remote clients have no way to authenticate.

The init wizard handles this: it generates a bootstrap device token when you pick a tunnel mode, writing it to `~/.netclaw/config/devices.json` and `~/.netclaw/config/secrets.json`. For manual setup, pair a device before starting the daemon:

```bash
netclaw daemon pair
```

## Startup validation

If the mode requires `tailscaled` or `cloudflared` and that process isn't running, you'll see this in the daemon logs (`~/.netclaw/logs/daemon.log` or `journalctl --user -u netclaw` for systemd):

```
Daemon startup aborted: ExposureMode is 'tailscale-serve' but the required
tunnel process 'tailscaled' is not running. Start 'tailscaled' before starting
Netclaw, or set ExposureMode to 'local' in netclaw.json.
```

If no paired devices exist and no alternative auth scheme is configured:

```
Daemon startup aborted: ExposureMode is 'tailscale-serve' but no paired devices
exist and no alternative remote authentication scheme is configured. Pair a device
with 'netclaw daemon pair' or configure another remote auth scheme before starting
Netclaw.
```

Both are fatal. The daemon won't start until you fix the underlying issue.

## Troubleshooting

### Start here: `netclaw doctor`

Run [`netclaw doctor`](/cli/doctor/) first — it has a dedicated `exposure-mode` check.

![Netclaw doctor output showing health check diagnostics](/screenshots/output/doctor.png)

### Tunnel process not running

Startup aborted with "required tunnel process is not running."

Start the required process first:

```bash
# Tailscale modes
sudo systemctl start tailscaled

# Cloudflare Tunnel
sudo systemctl start cloudflared
```

Or switch to local mode if you don't need remote access:

```json
{
  "Daemon": {
    "ExposureMode": "local"
  }
}
```

### No paired devices

Startup aborted with "no paired devices exist and no alternative remote authentication scheme is configured."

Pair a device:

```bash
netclaw daemon pair
```

Or re-run the init wizard, which generates a bootstrap token automatically when you select a tunnel mode:

```bash
netclaw init
```

### Non-loopback bind in local mode

`netclaw doctor` reports a warning: "ExposureMode is 'local' but bind address is not loopback."

The daemon is reachable beyond localhost without tunnel protection. Either bind to loopback:

```json
{
  "Daemon": {
    "Host": "127.0.0.1"
  }
}
```

Or switch to the exposure mode that reflects how the daemon is actually reachable:

```json
{
  "Daemon": {
    "Host": "127.0.0.1",
    "ExposureMode": "tailscale-serve"
  }
}
```

<!-- TODO: needs user input — Should Host remain 127.0.0.1 for tunnel modes, or should it be 0.0.0.0? Tunnels typically terminate locally and proxy to loopback, but this should be confirmed. -->

## Related pages

- [Docker Deployment](/deployment/docker/) — containerized daemon with loopback port binding
- [systemd Service](/deployment/systemd/) — bare-metal Linux service management
- [Webhooks](/configuration/webhooks/) — inbound webhook route configuration
- [Models](/configuration/models/) — model slot configuration
- [`netclaw doctor`](/cli/doctor/) — built-in health check diagnostics

## Resources

- [Tailscale Serve documentation](https://tailscale.com/kb/1242/tailscale-serve) — set up HTTPS endpoints on your tailnet
- [Tailscale Funnel documentation](https://tailscale.com/kb/1223/funnel) — expose tailnet services to the public internet
- [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — route traffic through Cloudflare to your origin
- [Cloudflare Access documentation](https://developers.cloudflare.com/cloudflare-one/policies/access/) — identity-aware access policies for tunneled services
- [Tailscale download](https://tailscale.com/download) — install Tailscale on your platform
