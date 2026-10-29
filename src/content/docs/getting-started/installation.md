---
title: "Installation"
description: "Requirements, install commands for Linux, macOS, Windows and Docker, plus how to update and uninstall netclaw."
---

Netclaw is two binaries: the CLI (`netclaw`) and the daemon (`netclawd`). The CLI is a thin client. Inference, tool execution and session state all live in the daemon, so install both on the machine that will run your assistant. For a remote setup, see [pairing remote devices](/guides/pairing-remote-devices/). If you just want it running, the [quickstart](/getting-started/quickstart/) is shorter.

## Requirements

| | Linux | macOS | Windows |
|---|---|---|---|
| Architecture | x86_64, ARM64 | Apple Silicon (M1 or later). Intel Macs are rejected. | x64 only |
| Tools the installer needs | `curl`, `tar`, `sha256sum` or `shasum` | `curl`, `tar`, `shasum` (all ship with macOS) | PowerShell |
| Extra packages | ICU runtime (`libicu`) for the daemon, `tzdata` for timezone-aware reminders | - | - |
| .NET runtime | Not needed | Not needed | Not needed |
| Runs as a service | systemd user unit | No, start it by hand | No, start it by hand |

The binaries are self-contained, so there's no .NET to install. There are no Homebrew, winget, apt or other package-manager packages. The install script, the PowerShell script and the Docker image are the supported routes.

:::caution
On a minimal Linux image the daemon crashes at startup with `Couldn't find a valid ICU package installed on the system` and `netclaw init` ends with `Failed to start daemon: process exited with code 134`. Install your distro's ICU runtime first, for example `sudo apt-get install libicu74` on Ubuntu 24.04. Most desktop installs and cloud VMs have it already. Minimal containers and some slim images don't. The same images often lack `tzdata` too. Without it the `init` identity step answers `Unknown time zone 'America/Chicago'` for every zone except `UTC`, and a reminder with a `CRON_TZ=` prefix fails with `Invalid CRON_TZ prefix. Unknown time zone`. `sudo apt-get install curl ca-certificates libicu74 tzdata` covers everything on Ubuntu 24.04.
:::

### Machine and network

| Resource | What to expect |
|---|---|
| Memory | Budget about 800 MB for `netclawd` with local embeddings on, the figure from the 0.27.0 release notes. Measured on 0.27.1: about 480 MB idle and 560 MB after a few memory writes, or about 235 MB with embeddings off. |
| Disk | About 160 MB for the two binaries, about 129 MB for the two embedding models, then session history and memory as you use it. |
| Network | `releases.netclaw.dev` for installs and updates, `huggingface.co` on the daemon's first start to fetch the embedding models, and your LLM provider. |
| LLM provider | An API key for a hosted provider, or the address of a server you run (Ollama, llama.cpp, vLLM). The [quickstart](/getting-started/quickstart/) covers choosing one. |

Semantic memory is on by default since 0.27.0. To skip the model download and cut memory use, turn embeddings off in `~/.netclaw/config/netclaw.json`:

```json
{
  "Memory": { "Embeddings": { "Enabled": false } }
}
```

The daemon restarts itself when that file changes. Memory recall falls back to keyword search. See [memory and embeddings](/configuration/memory/).

## Install on Linux or macOS

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash
```

The script detects your platform, downloads both binaries, checks them against the published SHA-256 checksums and puts them in `~/.netclaw/bin`. It ends by printing the next three commands.

| Goal | Command |
|---|---|
| CLI only | `curl -sSL https://releases.netclaw.dev/install.sh \| bash -s -- cli` |
| Daemon only | `curl -sSL https://releases.netclaw.dev/install.sh \| bash -s -- daemon` |
| Pin a version | `curl -sSL https://releases.netclaw.dev/install.sh \| NETCLAW_VERSION=0.28.2 bash` |
| Custom directory | `curl -sSL https://releases.netclaw.dev/install.sh \| INSTALL_DIR=$HOME/tools/netclaw bash` |
| Install into another home | `curl -sSL https://releases.netclaw.dev/install.sh \| NETCLAW_HOME=/srv/netclaw bash` |
| Preview only | `curl -sSL https://releases.netclaw.dev/install.sh \| bash -s -- --dry-run` |
| Leave my shell profile alone | `curl -sSL https://releases.netclaw.dev/install.sh \| bash -s -- --skip-shell` |

The environment variable goes on `bash`, after the pipe. Put it before `curl` and the script never sees it. `NETCLAW_HOME` moves the config, `bin/` and the `env` script together. `INSTALL_DIR` moves only the binaries. An existing install is upgraded where it sits, in `$NETCLAW_HOME/bin` first, then in a legacy `~/.netclaw/bin` (its `env` script stays at `~/.netclaw/env`). `CONFIG_DIR` and `NETCLAW_CONFIG_DIR` have no effect.

## Install on Windows

```powershell
iwr -useb https://releases.netclaw.dev/install.ps1 | iex
```

This installs to `%LOCALAPPDATA%\Programs\netclaw` and prepends that folder to your User PATH. For options, download the script and run it with parameters:

```powershell
$script = Join-Path $env:TEMP "netclaw-install.ps1"
iwr -useb https://releases.netclaw.dev/install.ps1 -OutFile $script
& $script -Component cli                     # CLI only
& $script -Component daemon                  # daemon only
& $script -Version 0.28.2                    # pinned version
& $script -InstallDir C:\tools\netclaw       # custom directory
& $script -DryRun                            # preview only
& $script -SkipShell                         # leave PATH alone
```

## PATH and shell integration

A piped install can't change the PATH of the shell it ran in, so `netclaw` works in new terminals but not the current one.

- On Linux and macOS the installer writes `~/.netclaw/env` and sources it from `.bashrc` (`.bash_profile` or `.profile` on macOS), `.zshrc`, or `~/.config/fish/conf.d/netclaw.fish`. In the shell you installed from, load it now with `. ~/.netclaw/env` (`<home>/env` if you set `NETCLAW_HOME`).
- On Windows the installer updates your User PATH and the current session. Other terminals that are already open need a restart.

## Docker

The image runs the daemon only, as the non-root user `netclaw` (UID 1654), on port 5199 inside the container. Keep state in a named volume:

```bash
docker run -d \
  --name netclaw \
  -v netclaw-home:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw
```

Drive it with `docker exec -it netclaw netclaw <command>`. Give the container at least 768 MiB if you set a memory limit. With embeddings on, 512 MiB gets the daemon killed and restarted over and over. The image is multi-arch (`linux/amd64`, `linux/arm64`), and the entrypoint chowns the data directory for you, so a bind mount works too. To reach the daemon from another machine, configure an [exposure mode](/deployment/exposure-modes/). Compose files, Ollama sidecars and environment-variable configuration live in [Docker deployment](/deployment/docker/).

## Build from source

You need the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

```bash
git clone https://github.com/netclaw-dev/netclaw.git
cd netclaw
dotnet publish src/Netclaw.Cli/Netclaw.Cli.csproj -c Release -o ./out
dotnet publish src/Netclaw.Daemon/Netclaw.Daemon.csproj -c Release -o ./out
export PATH="$PWD/out:$PATH"
```

## What gets installed where

| Path | What it is |
|---|---|
| `~/.netclaw/bin/netclaw`, `netclawd` | The CLI (81 MB) and the daemon (86 MB). On Windows, `%LOCALAPPDATA%\Programs\netclaw`. |
| `~/.netclaw/env` | PATH snippet that your shell profile sources. |
| `~/.bashrc`, `~/.zshrc` or fish `conf.d/netclaw.fish` | Two lines that source `~/.netclaw/env`. |
| `~/.netclaw/` | The data directory, created on first run: `config/`, `identity/`, `sessions/`, `skills/`, `models/`, `logs/`, `schedules/`, `keys/` and `netclaw.db`. On Windows, `%USERPROFILE%\.netclaw`. Set `NETCLAW_HOME` to move it. |

See the [data directory reference](/reference/data-directory/) for every file.

## Verify the install

```bash
netclaw --version
```

```text
netclaw 0.28.2 (commit 7419d84, built 2026-10-29T00:09:05Z)
```

Then run [`netclaw init`](/cli/init/). After that, `netclaw status` should report `overall: healthy`.

## Keep the daemon running

On Linux, install the daemon as a systemd user service so it starts at boot. See [systemd deployment](/deployment/systemd/).

```bash
netclaw daemon install
```

On macOS and Windows there's no service yet. Start the daemon yourself after each reboot:

```bash
netclaw daemon start
```

In a container or on any host without `systemctl`, `netclaw daemon install` refuses and writes nothing:

```text
Cannot install the service: systemd user services are not available on this host (...). Run the daemon under a container supervisor, or start it with `netclaw daemon start` (it will not restart after a crash or reboot).
```

Use `netclaw daemon start` or the Docker image there. A daemon started by hand doesn't come back after a reboot or a crash.

## Update

```bash
netclaw update                 # check, then ask before installing
netclaw update --check         # check only
netclaw update --force         # install without the confirmation prompt
```

`netclaw update` downloads and checksums the new binaries, stops the daemon, swaps the binaries, and starts the daemon again if it was running. The daemon only checks for updates in the background and reports them in `netclaw status`. It never applies one. Self-update is disabled in the Docker image, so pull a newer image tag instead. See [upgrading](/guides/upgrading/) and [`netclaw update`](/cli/update/).

`netclaw daemon stop` and `netclaw update` signal a process only after proving the PID serves this home. Linux reads the proof from `/proc`. On macOS and Windows the CLI can't prove the home of a 0.27.1 daemon, so updating from 0.27.1 refuses with `Nothing was stopped. PID <pid> is not shown to serve <home>.` Run the `kill <pid>` command it prints (Task Manager on Windows) once, then update again.

Re-running the install script also works and keeps your configuration. A running daemon keeps the old version until you restart it, so stop it first and start it after:

```bash
netclaw daemon stop
curl -sSL https://releases.netclaw.dev/install.sh | bash
netclaw daemon start
```

### Release channels

`stable` is the default and carries release builds only. `beta` resolves to the newest prerelease, or to a newer stable release if one supersedes it.

```bash
netclaw update --channel beta     # switch, save to config, and install now
netclaw update --channel stable   # switch back
```

To pick a channel at first install, pass it to the script. The script saves the channel to `netclaw.json` itself, using `jq` when a config already exists. Without `jq` it prints the line to add. A `netclaw.json` that holds only the channel doesn't count as an existing install, so `netclaw init` still runs the full setup wizard.

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash -s -- --channel beta
```

```powershell
& $script -Channel beta
```

For Docker, use the `ghcr.io/netclaw-dev/netclaw:beta` tag.

## Uninstall

There's no uninstall command. Remove the pieces in this order:

1. Stop the daemon, and remove the service if you installed one.

   ```bash
   netclaw daemon stop
   netclaw daemon uninstall
   ```

2. Delete the binaries and the PATH hook.

   ```bash
   rm -rf ~/.netclaw/bin ~/.netclaw/env
   ```

   Then delete the `# netclaw shell setup` comment and the `. '.../.netclaw/env'` line from your `~/.bashrc` or `~/.zshrc`. For fish, delete `~/.config/fish/conf.d/netclaw.fish`.

3. Optional: delete your data.

   ```bash
   rm -rf ~/.netclaw
   ```

   :::caution
   This removes your config, secrets, encryption keys, sessions, memory and reminders for good. [Back them up first](/guides/backup-and-restore/) if you might want them again.
   :::

On Windows, run `netclaw daemon stop`, delete `%LOCALAPPDATA%\Programs\netclaw`, remove that folder from your User PATH in Environment Variables, and delete `%USERPROFILE%\.netclaw` if you want the data gone too. For Docker, `docker rm -f netclaw` and `docker volume rm netclaw-home`.

## Troubleshooting

### `netclaw: command not found`

**Symptom:** the install finished but `netclaw --version` fails.
**Cause:** your current shell started before the installer changed the PATH.
**Fix:** run `. ~/.netclaw/env`, or open a new terminal. On Windows, restart the terminal.

### `Error: Required command 'curl' not found`

**Symptom:** the script stops straight away, or the shell says `curl: command not found`.
**Cause:** minimal images and containers ship without `curl`.
**Fix:** `sudo apt-get install curl ca-certificates` (or your distro's equivalent), then run the script again.

### `Failed to start daemon: process exited with code 134`

**Symptom:** `netclaw init` ends with that line and `Setup complete with warnings`, followed by a .NET stack trace that begins `Couldn't find a valid ICU package`.
**Cause:** the ICU runtime library is missing. The CLI runs without it and the daemon doesn't.
**Fix:** install it (`sudo apt-get install libicu74` on Ubuntu 24.04, or the `libicu` or `icu-libs` package on other distros), run `netclaw daemon start`, then `netclaw chat --onboarding` to get the opening conversation `init` would have started. If you can't install packages, `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 netclaw daemon start` also works.

### `Unknown time zone 'America/Chicago'`

**Symptom:** the `init` identity step or `netclaw reminder create` rejects a valid IANA zone.
**Cause:** the machine has no timezone database. Minimal images ship without `tzdata`. `UTC` still works.
**Fix:** install it (`sudo apt-get install tzdata`) and retry.

### `Error: Intel Macs are not supported`

**Cause:** the installer only ships Apple Silicon builds.
**Fix:** run netclaw on an Apple Silicon Mac, a Linux machine or in Docker.

### `Failed to fetch checksum file`

**Cause:** the version you pinned isn't on the release feed.
**Fix:** check the spelling against the [release list](https://github.com/netclaw-dev/netclaw/releases), or drop `NETCLAW_VERSION` to install the latest stable.

## Related pages

- [Quickstart](/getting-started/quickstart/): install, `netclaw init` and a first message in five minutes
- [Build your first assistant](/getting-started/first-assistant/): the full path from a fresh machine to an assistant that works unprompted
- [Docker deployment](/deployment/docker/): Compose, sidecars and environment-variable configuration
- [systemd deployment](/deployment/systemd/): run the daemon as a user service on Linux
- [Upgrading](/guides/upgrading/): what to check before and after an update

## Resources

- [netclaw releases on GitHub](https://github.com/netclaw-dev/netclaw/releases): release notes for every version
- [.NET globalization and ICU](https://learn.microsoft.com/en-us/dotnet/core/extensions/globalization-icu): why the daemon needs ICU and the invariant-mode switch
- [Docker Engine install guide](https://docs.docker.com/engine/install/): container runtime for the Docker route
- [.NET 10 SDK downloads](https://dotnet.microsoft.com/en-us/download/dotnet/10.0): required only to build from source
