---
title: "Use the CLI from another machine"
description: "Pair a laptop, second server, or container with your netclaw daemon so its CLI can talk to the daemon over HTTPS."
---

Your netclaw daemon runs on one machine and you want `netclaw chat` and `netclaw status` on another. Pairing does it: generate a short-lived code on the daemon host, exchange it from the remote device, and the device gets a bearer token for every later request. Two commands, plus the one-time work of exposing the daemon over HTTPS.

| I want to | Do this |
|-----------|---------|
| Pair my first remote device | [Expose the daemon](#1-expose-the-daemon-over-https), then [pair](#2-generate-a-code-on-the-daemon-host) |
| Add another device later | `netclaw daemon pair` on the daemon host, then `netclaw pair <url>` on the device |
| Cut off a lost device | `netclaw daemon devices revoke <name>` on the daemon host |
| Re-pair after a 401 | Same as adding a device |

## Before you begin

- netclaw installed on both machines, and [`netclaw init`](/cli/init/) completed on the daemon host. The remote device needs only the `netclaw` binary. Pairing replaces init for client-only machines.
- An HTTPS URL that reaches the daemon (port 5199 behind it): a reverse proxy, Tailscale Serve, or a Cloudflare Tunnel. **`netclaw pair` refuses a plain `http://` URL for any non-loopback address**, so a bare `http://my-server:5199` doesn't work. [Exposure modes](/deployment/exposure-modes/) has the setup for each.
- The remote device trusts the certificate. A public certificate (Tailscale, Cloudflare, Let's Encrypt) needs nothing. For a private CA, install it in the device's trust store. .NET also honors `SSL_CERT_FILE`.

## 1. Expose the daemon over HTTPS

By default the daemon listens on loopback only, and pairing doesn't work in `local` mode. Set an exposure mode in `~/.netclaw/config/netclaw.json`:

```json
{
  "Daemon": {
    "ExposureMode": "tailscale-serve"
  }
}
```

| Mode | Config value | Requires | Who can reach it |
|------|-------------|----------|-----------------|
| Local | `local` | Nothing | Loopback only (default) |
| Reverse proxy | `reverse-proxy` | A proxy, a non-loopback `Daemon.Host`, and `TrustedProxies` | Whatever the proxy exposes |
| Tailscale Serve | `tailscale-serve` | `tailscaled` running | Your [tailnet](https://tailscale.com/kb/1136/tailnet) |
| Tailscale Funnel | `tailscale-funnel` | `tailscaled` running | The [public internet](https://tailscale.com/kb/1223/funnel) |
| Cloudflare Tunnel | `cloudflare-tunnel` | `cloudflared` running | The internet through [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) |

The daemon restarts itself when this changes in `netclaw.json`. If you set it through an environment variable, restart by hand. For a reverse proxy, the full config, the `Daemon.Host` rule, and the tunnel commands are in [Exposure modes](/deployment/exposure-modes/).

:::caution[Non-local modes need a paired device]
A non-local daemon won't start without at least one paired device, unless another remote auth scheme is configured. On a fresh install netclaw seeds one local bootstrap device (named `<hostname>-bootstrap`) before the first successful non-local start, so the daemon host's own CLI keeps working. After that first start, new devices need pairing.
:::

## 2. Generate a code on the daemon host

```bash
netclaw daemon pair
```

```
Pairing code:  56AJ-DPTU
Expires at:    02:50:53 (local time)

On the remote device, run:
  netclaw pair <https-address>

The daemon does not know its public address. The daemon is exposed through reverse-proxy, and http://127.0.0.1:5199 is reachable only from this machine.
Replace <https-address> with the HTTPS address this daemon is published at.
```

Codes last 5 minutes and work once. A new code replaces any earlier one. The alphabet leaves out `0`, `O`, `1`, `I`, and `L` so codes are hard to misread.

In a non-local mode the daemon can't know the address your proxy or tunnel publishes, so the command leaves a `<https-address>` placeholder. Substitute your HTTPS URL on the device. Only in `local` mode does it print a ready-made `netclaw pair http://127.0.0.1:5199` line, and pairing from another machine doesn't work there.

In Docker, run it through `docker exec`:

```bash
docker exec -u netclaw <container> netclaw daemon pair
```

The daemon logs that it generated a code but never the code, so `docker logs` can't recover one. Run the command again. Flags and subcommands are in [`netclaw daemon`](/cli/daemon/).

## 3. Pair the remote device

On the remote machine, with the URL your proxy or tunnel serves:

```bash
netclaw pair https://netclaw.example.com
```

```
Pairing code (XXXX-XXXX): 6S2F-YSJD
Device name [my-laptop]:
Paired successfully as 'my-laptop'.
Token stored in:     /home/netclaw/.netclaw/config/secrets.json
Endpoint saved in:   /home/netclaw/.netclaw/client/config.json

You can now use `netclaw chat`, `netclaw status`, etc. against https://netclaw.example.com.
```

The device name defaults to the hostname. Press Enter to accept it, or type another. The token goes to `secrets.json` and the endpoint to `client/config.json`.

Check it from the remote device:

```bash
netclaw status
```

You should get the daemon's status back, with the `endpoint:` line showing your HTTPS URL. Pair as many devices as you need.

We ran this flow with two containers of 0.28 on a private Docker network, with the daemon in `reverse-proxy` mode behind an nginx TLS proxy using a self-signed certificate that the client trusted through `SSL_CERT_FILE`. The client's `netclaw status` then reported `endpoint https://...` and `overall: healthy`.

## Manage paired devices

Run these on the daemon host:

```bash
netclaw daemon devices
netclaw daemon devices revoke <name>
```

```
Name                     Created                Last Used
my-server-bootstrap     2026-10-07 15:43       2026-10-07 15:46
my-laptop                2026-10-07 15:46       2026-10-07 15:46
```

`devices` prints `No paired devices.` when there are none. After `revoke`, the device gets a 401 on its next request. Revoke when a device is lost or retired, or when you want to reuse its name.

## How it works

- The daemon never stores a raw token. It keeps a salted SHA-256 hash in `~/.netclaw/config/devices.json` (permissions `600` on Linux), and the device keeps the raw token in its own `secrets.json`.
- In `local` mode, loopback connections work without a token, provided `Host` is `localhost` or a loopback IP and any `Origin` matches it. In every non-local mode, loopback isn't trusted either, because the loopback peer might be your proxy forwarding remote traffic.
- The exchange endpoint resists guessing three ways: 5 attempts per minute per IP, a block of 15 minutes after 10 failures in 15 minutes, and a 404 when no code is active. With 8 characters from a 32-character alphabet and a 5-minute life, guessing isn't practical.

The CLI finds the daemon in this order: the `NETCLAW_DAEMON_ENDPOINT` environment variable, `~/.netclaw/client/config.json` (written by `netclaw pair`), the daemon's own `Daemon.Host` and `Daemon.Port` from `netclaw.json`, then `http://127.0.0.1:5199`. A wildcard bind such as `0.0.0.0` is normalized to a connectable local address. Set the environment variable to switch between daemons without re-pairing.

## Troubleshooting

### A non-loopback daemon endpoint must use HTTPS

**Symptom:** `error: A non-loopback daemon endpoint must use HTTPS.`

**Cause:** You ran `netclaw pair http://host:5199`. The client only accepts plain HTTP for loopback addresses.

**Fix:** Pair through an HTTPS URL from your proxy or tunnel ([Exposure modes](/deployment/exposure-modes/)).

### Authentication failed

**Symptom:** `Authentication failed: the daemon rejected the bearer token. Run 'netclaw pair <endpoint>' to re-pair this device.` or `daemon returned 401`.

**Cause:** The device was revoked, or the daemon's device store was reset. On the daemon host in `local` mode, a request that names another host (or comes from a browser app on another local port) also gets a 401, and the daemon log shows `Refused loopback request: Host is not a loopback name`. Call `http://127.0.0.1:<port>` or `http://localhost:<port>`.

**Fix:** Run `netclaw daemon pair` on the daemon host, then `netclaw pair <endpoint>` on the device. If the device store was lost and a non-local daemon now fails to start, switch `Daemon.ExposureMode` to `local` temporarily, or restore `devices.json` and `secrets.json` from backup. Start the daemon, pair, and switch back.

### Pairing code invalid or expired

**Symptom:** `Pairing failed (401): Invalid, expired, or already-used pairing code.`

**Cause:** Codes live 5 minutes, work once, and a newer code replaces an older one.

**Fix:** Run `netclaw daemon pair` again and retry. A 404 means no code is active at all.

### Device name already exists

**Symptom:** `Pairing failed (409): A paired device named '<name>' already exists. Revoke it before pairing again.`

**Cause:** A paired device already has that name.

**Fix:** Pick a different name and reuse the same unexpired code, or revoke the old device with `netclaw daemon devices revoke <name>` first.

### Can't reach the daemon at all

**Symptom:** `Connection refused`, a timeout, or a TLS error.

**Cause:** Daemon down, exposure mode still `local`, a proxy or firewall in the way, or an untrusted certificate.

**Fix:** Check in order that the daemon is running, `Daemon.ExposureMode` isn't `local`, the HTTPS URL answers from the device, and port 5199 isn't blocked between proxy and daemon. For `reverse-proxy`, also confirm the daemon isn't bound to loopback and `TrustedProxies` includes the proxy's address. [`netclaw doctor`](/cli/doctor/) on the daemon host runs an exposure-mode check.

### Too many failed attempts

**Symptom:** Requests are refused for a while after several wrong codes.

**Cause:** The guard blocked your IP for 15 minutes.

**Fix:** Wait it out, or pair from a different IP.

## What's next

- [`netclaw chat`](/cli/chat/) - start talking to your agent from the paired device
- [`netclaw status`](/cli/status/) - daemon connectivity and endpoint

## Related pages

- [`netclaw daemon`](/cli/daemon/) - `pair`, `devices`, and the other daemon subcommands
- [Exposure modes](/deployment/exposure-modes/) - every `Daemon.ExposureMode` and its setup
- [`netclaw doctor`](/cli/doctor/) - exposure-mode and connectivity checks
- [`netclaw init`](/cli/init/) - the setup wizard, which handles bootstrap pairing

## Resources

- [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) - expose a local service to your tailnet
- [Tailscale Funnel](https://tailscale.com/kb/1223/funnel) - expose it to the public internet through Tailscale
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) - route traffic to the daemon through Cloudflare
- [Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) - a reverse proxy that handles TLS automatically
