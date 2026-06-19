---
title: Exposure Modes
description: Configure how netclaw is exposed to the network — local, reverse proxy, Tailscale Serve, Tailscale Funnel, or Cloudflare Tunnel.
---

Exposure mode controls how the daemon is reachable over the network. Most setups use local mode. You only need a non-local mode when something external (GitHub webhooks, CI, a second machine, or a reverse proxy) needs to reach the daemon.

## Before you begin

- Netclaw installed and initialized (`netclaw init`). See [Installation](/getting-started/installation/) if needed.
- For reverse proxy: a working proxy already configured, a non-loopback internal IP for the daemon, and the proxy source IP or CIDR ready for `TrustedProxies`.
- For Tailscale modes: [`tailscaled` installed and running](https://tailscale.com/download).
- For Cloudflare Tunnel: [`cloudflared` installed and configured](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/).

## Modes

| Mode | Config value | Required process | Reachability | Risk |
|------|-------------|-----------------|-------------|------|
| **Local** | `local` | None | Loopback only | Lowest |
| **Reverse Proxy** | `reverse-proxy` | Your reverse proxy | Whatever the proxy exposes | Medium |
| **Tailscale Serve** | `tailscale-serve` | `tailscaled` | Your Tailscale network (called a [tailnet](https://tailscale.com/kb/1136/tailnet)), HTTPS | Low |
| **Tailscale Funnel** | `tailscale-funnel` | `tailscaled` | Public internet via Tailscale | High |
| **Cloudflare Tunnel** | `cloudflare-tunnel` | `cloudflared` | Public internet via Cloudflare | High |

Configure the exposure mode in `netclaw config`, or set it directly in `netclaw.json`.

<!-- TODO(screenshots): replace with config-exposure.png — capture via screenshots/tapes/config.tape after the stable release with netclaw-dev/netclaw#1368; tracked in epic #55 -->

Options marked with a warning triangle expose the daemon to the public internet. Tailscale Serve is the recommended remote mode: tailnet-only access, no public exposure.

:::caution
In every non-local mode (reverse proxy and the three tunnel modes), a loopback connection is **not** trusted as the local operator — the loopback peer is the proxy or tunnel forwarding remote traffic, not a same-host process. You must pair a device or authenticate remotely, even from the daemon's own host, and pairing codes can't be minted from a loopback connection. Only `local` mode auto-trusts loopback. (This closes the SEC-005 tunnel-loopback auth bypass.)
:::

### Reverse Proxy

```json
{
  "Daemon": {
    "Host": "10.0.0.5",
    "ExposureMode": "reverse-proxy",
    "TrustedProxies": ["10.0.0.10"]
  }
}
```

Use this when nginx, Caddy, Traefik, HAProxy, or another reverse proxy is the public edge.

In this mode:

- `Daemon.Host` must be a non-loopback internal address. `127.0.0.1`, `::1`, and `localhost` are rejected in `reverse-proxy` mode.
- `TrustedProxies` must list the proxy's source IP or CIDR. Forwarded headers are only honored from those peers.

If the proxy runs on the same machine, the final hop into netclaw still needs to target a non-loopback internal IP. A same-host reverse proxy is fine, but the final hop into netclaw still cannot use loopback.

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

If `cloudflared` runs outside the daemon's process namespace, set `Daemon.SkipTunnelProcessCheck` to `true` so startup validation skips the local process probe without skipping the rest of the auth checks.

<!-- TODO: needs user input — What's the recommended Cloudflare Access policy configuration for netclaw? -->

### Full Daemon section

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `Host` | string | `127.0.0.1` | IP address the daemon binds to |
| `Port` | int | `5199` | TCP port |
| `ExposureMode` | string | `local` | `local`, `reverse-proxy`, `tailscale-serve`, `tailscale-funnel`, or `cloudflare-tunnel` |
| `TrustedProxies` | string[] | `[]` | Required in `reverse-proxy`; literal IPs or CIDRs only |
| `SkipTunnelProcessCheck` | bool | `false` | Skip local tunnel process detection for sidecar or host-managed tunnel topologies |

```json
{
  "Daemon": {
    "Host": "127.0.0.1",
    "Port": 5199,
    "ExposureMode": "tailscale-serve"
  }
}
```

Case-insensitive — `reverse-proxy`, `ReverseProxy`, and `REVERSE-PROXY` all work, same as the tunnel modes.

**Docker users:** if you switch to a tunnel mode, update your container's port binding to match the `Host` and `Port` values here. See [Docker Deployment](/deployment/docker/) for details.

### Environment variables

Override any field with `NETCLAW_Daemon__` prefixed env vars:

```bash
NETCLAW_Daemon__ExposureMode=reverse-proxy
NETCLAW_Daemon__Host=10.0.0.5
NETCLAW_Daemon__Port=5199
NETCLAW_Daemon__TrustedProxies__0=10.0.0.10
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

Tunnel modes make [inbound webhooks](/configuration/webhooks/) possible. External services like GitHub or CI systems can trigger autonomous runs via HTTP POST.

They do nothing in local mode.

## Device pairing

Non-local modes require at least one paired device or an alternative remote authentication scheme. Without one, the daemon refuses to start because remote clients have no way to authenticate.

On fresh setup-owned installs, netclaw automatically creates a one-time bootstrap path for the first non-local start. Before the first successful non-local daemon start, it seeds one local paired device and matching local client token when no paired devices already exist. That covers the init wizard, first Docker boot, and manual setups that still use the daemon's local state directory.

After the first successful non-local start, that auto-seeding stops. Normal CLI use is paired-device auth from that point on.

If the daemon is already running and you need to add another device, pair from the daemon host:

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

In `reverse-proxy` mode, startup also fails if the daemon is still bound to loopback or if `TrustedProxies` is empty or malformed.

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

If this is a brand-new non-local install, check whether the daemon actually completed its first successful start. The one-shot bootstrap only happens before that first successful non-local startup.

If the daemon is already running, pair from the daemon host:

```bash
netclaw daemon pair
```

If the device store was lost after the first successful non-local start and the daemon will not start anymore, temporarily switch `Daemon.ExposureMode` to `local` or restore `devices.json` and `secrets.json` from backup. Then start the daemon, run `netclaw daemon pair`, and switch back.

You can also run `netclaw init` on an existing install — it shows an action menu with options to open the configuration editor, redo identity, or start over.

### Reverse proxy bound to loopback

Startup aborted because `Daemon.ExposureMode` is `reverse-proxy` but `Daemon.Host` is `127.0.0.1`, `::1`, or `localhost`.

Bind netclaw to a non-loopback internal IP and point the proxy at that address instead of loopback:

```json
{
  "Daemon": {
    "Host": "10.0.0.5",
    "ExposureMode": "reverse-proxy",
    "TrustedProxies": ["10.0.0.10"]
  }
}
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
- [nginx reverse proxy guide](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) — baseline reverse-proxy behavior and forwarding model
- [Cloudflare Tunnel service docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/local-management/as-a-service/) — service startup and lifecycle details for cloudflared
- [Tailscale download](https://tailscale.com/download) — install Tailscale on your platform
