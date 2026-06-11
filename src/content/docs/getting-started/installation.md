---
title: "Installation"
description: "Install Netclaw on your system."
---

Netclaw has two components: a **CLI** (`netclaw`) and a **daemon** (`netclawd`). The CLI is a thin client — all inference, tool execution, and session state live in the daemon. Install both on the same machine to get started; for remote setups, see [Pairing Remote Devices](/guides/pairing-remote-devices/).

## Linux (recommended)

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash
```

Installs both CLI and daemon to `~/.netclaw/bin` and adds it to your PATH. Supports x86_64 and ARM64.

```bash
# CLI only
curl -sSL https://releases.netclaw.dev/install.sh | bash -s -- cli

# Daemon only
curl -sSL https://releases.netclaw.dev/install.sh | bash -s -- daemon

# Pin a version
NETCLAW_VERSION=0.1.0 curl -sSL https://releases.netclaw.dev/install.sh | bash

# Custom install directory
INSTALL_DIR=/opt/netclaw curl -sSL https://releases.netclaw.dev/install.sh | bash
```

## Windows

```powershell
iwr -useb https://releases.netclaw.dev/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\netclaw`. To install a specific component or version:

```powershell
$script = Join-Path $env:TEMP "netclaw-install.ps1"
iwr -useb https://releases.netclaw.dev/install.ps1 -OutFile $script
& $script -Component cli           # CLI only
& $script -Component daemon        # Daemon only
& $script -Version 0.1.0           # Pinned version
```

## Docker

Run the daemon as a container — useful for servers, homelab setups, or if you don't want to install anything on the host.

```bash
docker run -d \
  --name netclaw \
  -v netclaw-home:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw
```

| Setting | Value |
|---------|-------|
| Image | `ghcr.io/netclaw-dev/netclaw` |
| Architectures | `linux/amd64`, `linux/arm64` |
| Runs as | non-root user `netclaw` (UID 1654) |
| Port | 5199 (loopback inside the container) |
| Volume | `/home/netclaw/.netclaw` (config, identity, sessions, logs) |

The image runs as the non-root `netclaw` user, so persist state in a named volume (a host bind mount has to be `chown`ed to UID 1654 first). The container runs the daemon only, bound to loopback — drive it with `docker exec netclaw netclaw <command>`. To reach it from a host CLI or another machine (including [pairing](/guides/pairing-remote-devices/)), configure a non-local [exposure mode](/deployment/exposure-modes/). See [Docker Deployment](/deployment/docker/) for the full setup.

Pass provider credentials as environment variables:

```bash
docker run -d \
  --name netclaw \
  -v netclaw-home:/home/netclaw/.netclaw \
  -e NETCLAW_Providers__openrouter__Type=openrouter \
  -e NETCLAW_Providers__openrouter__ApiKey=sk-or-v1-... \
  -e NETCLAW_Models__Main__Provider=openrouter \
  -e NETCLAW_Models__Main__ModelId=anthropic/claude-sonnet-4 \
  ghcr.io/netclaw-dev/netclaw
```

For Docker Compose setups (including bundling Ollama), see [Docker Deployment](/deployment/docker/).

## Build from source

Requires [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

```bash
git clone https://github.com/netclaw-dev/netclaw.git
cd netclaw
dotnet publish src/Netclaw.Cli/Netclaw.Cli.csproj -c Release -o ./out
dotnet publish src/Netclaw.Daemon/Netclaw.Daemon.csproj -c Release -o ./out
export PATH="$PWD/out:$PATH"
```

## Verify the install

```bash
netclaw --version
```

You should see the version, commit hash, and build timestamp.

## Next step

```bash
netclaw init
```

The [`init` wizard](/cli/init/) walks you through provider setup, security posture, channels, identity, and network exposure — then starts the daemon. See the [Quickstart](/getting-started/quickstart/) for the full walkthrough.

## Switching release channels

By default, the install script and daemon pull from the **stable** channel — release builds only.

If Netclaw is already installed, switch channels with the CLI:

```bash
netclaw update --channel beta
```

This installs the newest build on that channel right away and saves to your config, so later update checks and self-updates follow the beta feed. Pass `--channel stable` to switch back.

To choose a channel at first install instead, pass `--channel` to the install script:

**Linux:**

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash -s -- --channel beta
```

**Windows:**

```powershell
.\install.ps1 --channel beta
```

**Docker:**

Use the `ghcr.io/netclaw-dev/netclaw:beta` image tag instead of the default `ghcr.io/netclaw-dev/netclaw` (which resolves to the latest stable).

The install script only swaps which binaries it pulls. Also set `Daemon.UpdateChannel: "beta"` in your config so the daemon checks the beta feed for self-updates. (Switching with `netclaw update --channel` does this for you.)

> **Note:** The install script is idempotent — running it on an existing install will update the binaries without breaking your configuration. If the daemon is running, stop it first:
>
> ```bash
> sudo systemctl stop netclawd
> curl -sSL https://releases.netclaw.dev/install.sh | bash -s -- --channel beta
> sudo systemctl start netclawd
> ```

## Updating

```bash
netclaw update                 # check for and install updates
netclaw update --check         # check only, don't install
netclaw update --channel beta  # switch channel (saved to config), then update
```

Self-update is disabled in the Docker image — update by pulling a new image tag instead.

| Channel | Description |
|---------|-------------|
| `stable` | Official releases only. The default. |
| `beta` | Prereleases. Resolves to the newest of {stable, prerelease}, so a stable release that supersedes a beta is still offered. |

## Resources

- [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) — required for building from source
- [Docker Engine](https://docs.docker.com/engine/install/) — container runtime for the Docker install method
- [Docker Deployment](/deployment/docker/) — Docker Compose, Ollama sidecar, and production container configuration
