---
title: "Pairing Remote Devices"
description: "Pair remote CLI clients with your Netclaw daemon."
---

Your netclaw daemon runs on one machine but you want to use the CLI from another -- a laptop, a second server, a container you can't shell into. Pairing is a two-command handshake: generate a time-limited code on the daemon, exchange it from the remote device, and the client gets a bearer token for all future requests.

## Before You Begin

- Netclaw installed on both machines ([`netclaw init`](/cli/init/) completed on the daemon host). The remote device only needs the `netclaw` binary -- you don't need to run `netclaw init` on it. Pairing replaces init for client-only machines.
- The daemon's exposure mode set to something other than `local` -- remote pairing doesn't work over loopback. The default daemon port is **5199**; make sure your firewall allows it.
- Network connectivity between the two machines (same tailnet, tunnel, or direct)

## 1. Set an Exposure Mode

By default, the daemon only listens on loopback. You need to change this before any remote device can connect.

During `netclaw init`, Step 9 handles this:

![Network exposure mode selection during netclaw init](/screenshots/output/init-09-exposure.png)

| Mode | Config value | Requires | Who can reach it |
|------|-------------|----------|-----------------|
| Local | `local` | Nothing | Loopback only (default) |
| Tailscale Serve | `tailscale-serve` | `tailscaled` running | Same [tailnet](https://tailscale.com/kb/1136/tailnet) |
| Tailscale Funnel | `tailscale-funnel` | `tailscaled` running | [Public internet](https://tailscale.com/kb/1223/funnel) |
| Cloudflare Tunnel | `cloudflare-tunnel` | `cloudflared` running | Internet via [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) |

To change the mode after init, edit `~/.netclaw/config/netclaw.json`:

```json
{
  "Daemon": {
    "ExposureMode": "tailscale-serve"
  }
}
```

For tunnel setup details -- Tailscale Serve commands, Cloudflare Tunnel configuration, and how each mode binds the daemon -- see [Exposure Modes](/deployment/exposure-modes/).

Restart the daemon after changing exposure mode (`netclaw daemon stop && netclaw daemon start`, or `systemctl restart netclaw` if you're [using systemd](/deployment/systemd/)).

:::caution[Non-local modes require at least one paired device]
If you set a non-local exposure mode, the daemon requires at least one paired device at startup (unless another remote auth scheme is configured). This is a chicken-and-egg situation: you need to pair your first device while still in `local` mode, then switch. The `netclaw init` wizard handles this automatically -- manual setup requires pairing first from the daemon host.
:::

## 2. Generate a Pairing Code (Daemon Side)

On the machine running the daemon:

```bash
netclaw daemon pair
```

Output:

```
Pairing code:  ABCD-EF23
Expires at:    14:32:15 (local time)

On the remote device, run:
  netclaw pair http://my-server:5199
```

Codes expire after **5 minutes** and are single-use. Generating a new code replaces any previous one -- only one active at a time.

The character set (`23456789ABCDEFGHJKLMNPQRSTUVWXYZ`) deliberately excludes `0`/`O`/`1`/`I`/`L` to avoid misreads.

### Docker

If the daemon runs in a container, the pairing code is logged at `Information` level:

```bash
docker logs <container-name> | grep "Pairing code"
```

No need to exec into the container.

## 3. Pair the Remote Device (Client Side)

On the remote machine:

```bash
netclaw pair http://my-server:5199
```

For Tailscale and Cloudflare Tunnel modes, the endpoint URL differs -- check [Exposure Modes](/deployment/exposure-modes/) for the correct format for each mode.

The CLI prompts for two things:

```
Pairing code (XXXX-XXXX): ABCD-EF23
Device name [my-laptop]:
```

Device name defaults to the machine's hostname. Hit Enter to accept the default, or type a custom name.

On success:

- The CLI saves the bearer token to `~/.netclaw/config/secrets.json`
- The daemon endpoint is written to `~/.netclaw/client/config.json`
- `netclaw chat`, `netclaw status`, and all other remote commands work from here

If a device with the same name already exists on the daemon, the exchange returns HTTP 409. Revoke the old device first (see below).

There's no limit to how many devices you can pair -- add as many as you need.

## 4. Verify the Connection

From the newly paired device:

```bash
netclaw status
```

If you get system status back, pairing worked. The CLI attaches the bearer token automatically from here on.

## Managing Paired Devices

Run these from the daemon host.

### List devices

```bash
netclaw daemon devices
```

Shows Name, Created, and Last Used for each paired device. Prints `No paired devices.` if none exist.

### Revoke a device

```bash
netclaw daemon devices revoke <name>
```

After revocation, the device gets 401 on its next request. Use this when a device is lost, retired, or you need to re-pair with the same name.

## How Tokens Work

- Raw tokens never hit disk on the daemon side -- it stores a SHA256 hash with a per-device salt in `~/.netclaw/config/devices.json` (file permissions `600` on Linux)
- Clients keep the raw token in `~/.netclaw/config/secrets.json`
- Loopback connections skip bearer auth entirely -- if you're on the daemon host, you don't need to pair

### Endpoint Resolution

When the CLI connects, it checks these in order:

1. `NETCLAW_DAEMON_ENDPOINT` environment variable
2. `~/.netclaw/client/config.json` (written by `netclaw pair`)
3. Default: `http://127.0.0.1:5199`

Override with the env var when you need to switch between multiple daemons without re-pairing.

## Exchange Endpoint Security

The pairing endpoint has three layers of brute-force protection:

| Layer | Behavior |
|-------|----------|
| Rate limiter | 5 attempts/minute per IP |
| Fail2ban-style guard | 10 failures in 15 min blocks the IP for 15 min |
| No-code-pending gate | Returns 404 when no code is active |

With a 32-character alphabet, 8-character codes, 5-minute expiry, and 5 attempts/minute -- brute force isn't happening.

## Troubleshooting

### "Authentication failed: the daemon rejected the bearer token"

The token was revoked or the daemon's device store was reset. Re-pair:

```bash
netclaw pair <endpoint>
```

Run `netclaw daemon pair` on the daemon host to get a fresh code.

### Pairing code expired

Codes last 5 minutes. Generate a new one with `netclaw daemon pair` and try again.

### HTTP 409 — device name already exists

A device with that name is already paired. Either pick a different name during pairing, or revoke the existing one first:

```bash
netclaw daemon devices revoke <name>
```

### Can't connect to the daemon at all

Check the basics:

1. Is the daemon running? (`netclaw daemon start` on the host)
2. Is the exposure mode set to something other than `local`?
3. Can you reach the endpoint from the remote machine? (`curl http://my-server:5199/api/health/ready`)
4. Is a firewall blocking port 5199?

Run [`netclaw doctor`](/cli/doctor/) on the daemon host -- it includes exposure-mode health checks.

### IP blocked after too many failed attempts

Wait 15 minutes, or fix the issue from a different IP. The fail2ban guard auto-expires after 15 minutes.

## Next Steps

- [`netclaw chat`](/cli/chat/) -- start talking to your agent from the paired device
- [`netclaw status`](/cli/status/) -- check daemon connectivity and endpoint URL
- [`netclaw doctor`](/cli/doctor/) -- diagnose exposure mode and connectivity issues
- [Exposure Modes](/deployment/exposure-modes/) -- all `Daemon.ExposureMode` options and tunnel setup
- [`netclaw init`](/cli/init/) -- the setup wizard handles bootstrap pairing during non-local setup

## External Resources

- [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) -- expose local services to your tailnet
- [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) -- expose local services to the public internet via Tailscale
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) -- route traffic to your daemon through Cloudflare's network
- [Tailscale: What is a tailnet?](https://tailscale.com/kb/1136/tailnet) -- networking concepts for the Tailscale Serve mode
