---
title: "Run netclaw in Docker"
description: "Run the netclaw daemon in a container with a persistent volume, health checks, a clean restart path, and an optional hardened profile."
---

The netclaw image runs the daemon (`netclawd`) as the non-root user `netclaw` (UID 1654). PID 1 is [`tini`](https://github.com/krallin/tini), which starts an entrypoint script that supervises the daemon and restarts it when it exits. The daemon binds loopback inside the container, so you drive it with `docker exec`. To reach it from the host or another container, use a non-local mode from [Exposure modes](/deployment/exposure-modes/).

## Before you begin

- [Docker Engine](https://docs.docker.com/engine/install/) with Compose v2. These steps were run on Docker 29.
- At least 1 GiB of memory for the container. See [Memory and first start](#memory-and-first-start).
- Outbound HTTPS to `huggingface.co` on first start, unless you [turn embeddings off](#memory-and-first-start).
- A model provider: an API key for a hosted one, or a reachable [Ollama](https://ollama.com/) or other OpenAI-compatible endpoint.

:::caution
Don't set `NETCLAW_Daemon__Host=0.0.0.0` to "open up" the container. The default `local` mode rejects a non-loopback host and the daemon aborts at startup. Pick an exposure mode instead, which also sets up authentication for remote callers.
:::

## Quick start

One named volume holds all state. Docker creates it owned by UID 1654, so there's nothing to `chown`.

```bash
docker run -d \
  --name netclaw \
  --stop-timeout 60 \
  -v netclaw-home:/home/netclaw/.netclaw \
  -e NETCLAW_Providers__openrouter__Type=openrouter \
  -e NETCLAW_Providers__openrouter__ApiKey="$OPENROUTER_API_KEY" \
  -e NETCLAW_Models__Definitions__claude__Provider=openrouter \
  -e NETCLAW_Models__Definitions__claude__ModelId=anthropic/claude-sonnet-4 \
  -e NETCLAW_Models__Roles__Main=claude \
  ghcr.io/netclaw-dev/netclaw:0.28.2
```

The container reaches `healthy` in about ten seconds. Check it:

```bash
docker inspect --format '{{.State.Health.Status}}' netclaw
docker exec netclaw netclaw daemon status
```

![Terminal showing docker ps for the netclaw container Up and healthy on 5199/tcp, docker inspect printing healthy, and netclaw daemon status reporting the daemon running](/screenshots/output/docker-health.png)

A few seconds after start, Docker reports `(healthy)` and the daemon answers from inside the container.

`docker logs` shows only the entrypoint's own lines. The daemon writes to `logs/daemon-YYYY-MM-DD.log` inside the volume, and continues in `daemon-YYYY-MM-DD.1.log`, `.2.log` and so on once a file reaches 10 MiB. `tail -f ~/.netclaw/logs/daemon-*.log` follows all of them. To stream daemon logs to `docker logs` too, add `-e NETCLAW_Logging__Console__Enabled=true`.

Env vars override both `netclaw.json` and `secrets.json`, so a value set with `-e` can't be changed later with `netclaw config`. Double underscores separate path segments, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider). The `ModelId` must match an identifier the provider serves. See [Models](/configuration/models/).

**Tags:** `0.28.2` is one exact release. `0.28` floats to the newest 0.28 patch, `latest` to the newest stable release, and `beta` to the newest prerelease. Pin an exact tag in production and read the [upgrade guide](/guides/upgrading/) before you move it.

### Use the CLI: put the config in a file

:::caution
A container configured only with `NETCLAW_*` variables has no `config/netclaw.json`. The daemon runs fine, but `netclaw status` and `netclaw chat -p` print `daemon not configured - please run netclaw init` and exit, because the CLI checks for the file.
:::

Write the config as a file instead. Create the directory on the host with a `config/netclaw.json`:

```json
{
  "configVersion": 1,
  "Security": {
    "DeploymentPosture": "Personal",
    "ShellExecutionMode": "HostAllowed",
    "StrictDefaults": true
  },
  "Tools": { "ShellMode": "HostAllowed" },
  "Providers": {
    "ollama": { "Type": "ollama", "Endpoint": "http://llm.example.internal:11434" }
  },
  "Models": {
    "Definitions": { "main": { "Provider": "ollama", "ModelId": "qwen3:30b" } },
    "Roles": { "Main": "main" }
  }
}
```

Point `Endpoint` at your own server. Mount the directory as the data directory. The entrypoint changes its ownership to UID 1654 on start:

```bash
docker run -d --name netclaw --stop-timeout 60 \
  -v "$PWD/netclaw-data:/home/netclaw/.netclaw" \
  ghcr.io/netclaw-dev/netclaw:0.28.2

docker exec netclaw netclaw status
docker exec netclaw netclaw chat -p "Reply with the single word pong."
```

For a scripted setup, `docker exec netclaw netclaw provider add` and `netclaw model set` create the file without the wizard. Or run the wizard in a container that's already up:

```bash
docker exec -it netclaw netclaw init
```

Without `Security.DeploymentPosture` the daemon uses the strict Public posture, and `shell_execute` is denied outright. If you stay env-only and want the Personal posture `init` writes, add `NETCLAW_Security__DeploymentPosture=Personal` and `NETCLAW_Security__ShellExecutionMode=HostAllowed`. See [Hardening](/security/hardening/).

Env list entries merge with file lists by position, so set a list such as `Tools.AudienceProfiles.Team.AllowedTools` in the file or in env vars, never both. An empty `NETCLAW_*` list variable next to a file value aborts startup:

```text
Configuration key 'Tools.AudienceProfiles.Team.AllowedTools' has list items and also a value. One source sets items and another source sets a value. Remove one of them, for example the NETCLAW_* variable.
```

## Docker Compose

Use Compose for anything you plan to keep. This file runs netclaw next to Ollama on a private network. There's no `Host` override and no published port, because you reach the daemon with `docker exec`:

```yaml
services:
  netclaw:
    image: ghcr.io/netclaw-dev/netclaw:0.28.2
    restart: unless-stopped
    stop_grace_period: 60s
    depends_on:
      - ollama
    volumes:
      - netclaw-home:/home/netclaw/.netclaw
    environment:
      NETCLAW_Providers__local-ollama__Type: ollama
      NETCLAW_Providers__local-ollama__Endpoint: http://ollama:11434
      NETCLAW_Models__Definitions__qwen__Provider: local-ollama
      NETCLAW_Models__Definitions__qwen__ModelId: qwen3:30b
      NETCLAW_Models__Roles__Main: qwen

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    volumes:
      - ollama-data:/root/.ollama

volumes:
  netclaw-home:
  ollama-data:
```

```bash
docker compose up -d
docker compose exec ollama ollama pull qwen3:30b
```

The daemon reports `healthy` without the model, but it can't answer until Ollama has pulled it. `qwen3:30b` is a large download. Pick a smaller tag for a first test.

For a hosted provider, keep one service and swap the `environment` block for the `openrouter` variables from the quick start, reading the key from your shell with `${OPENROUTER_API_KEY}`.

## Hardened profile

The image runs as non-root already. This profile adds a read-only root filesystem, no Linux capabilities, `no-new-privileges`, and a process limit:

```yaml
services:
  netclaw:
    image: ghcr.io/netclaw-dev/netclaw:0.28.2
    restart: unless-stopped
    stop_grace_period: 60s
    user: "1654:1654"
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    pids_limit: 512
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m
      - /var/netclaw-bundle:rw,exec,nosuid,size=128m,uid=1654,gid=1654
    volumes:
      - netclaw-home:/home/netclaw/.netclaw
    environment:
      # The root filesystem is read-only, so unpack into the exec tmpfs above.
      DOTNET_BUNDLE_EXTRACT_BASE_DIR: /var/netclaw-bundle
      NETCLAW_Providers__openrouter__Type: openrouter
      NETCLAW_Providers__openrouter__ApiKey: ${OPENROUTER_API_KEY}
      NETCLAW_Models__Definitions__claude__Provider: openrouter
      NETCLAW_Models__Definitions__claude__ModelId: anthropic/claude-sonnet-4
      NETCLAW_Models__Roles__Main: claude

volumes:
  netclaw-home:
```

Two settings make it start, and each one fails without it. The Mattermost [Compose guide](/guides/mattermost-docker-compose/) uses the same recipe.

| Setting | Why |
|---------|-----|
| `user: "1654:1654"` | The entrypoint starts as root to repair ownership, then drops privileges. With `cap_drop: [ALL]` root can't write into a directory it doesn't own, so the entrypoint exits with `failed to create /home/netclaw/.netclaw`. Starting as 1654 skips that step. |
| `DOTNET_BUNDLE_EXTRACT_BASE_DIR` and the `/var/netclaw-bundle` tmpfs | The single-file daemon unpacks its native libraries at startup, about 43 MB under `/var/netclaw-bundle`. With a read-only root filesystem and no override it exits with `Failed to determine location for extracting embedded files`. The mount needs `exec`: a `noexec` mount fails with `Unable to load shared library 'e_sqlite3'` and `failed to map segment from shared object`. |

The `/tmp` tmpfs isn't optional if the agent uses a shell or writes files. On Linux the daemon creates each run's private temp folder at `/tmp/netclaw-<uid>/<key>/p` (mode 0700) and doesn't fall back to another directory. With a read-only root and no writable `/tmp`, the container still starts and reports `healthy`, but every shell call fails with `Error preparing managed temporary directory: Read-only file system : '/tmp/netclaw-1654'`. The tmpfs is `noexec`, so a program the agent writes there can't run, and `size=64m` caps the folder. Don't point the extraction directory at it.

We keep the unpack in its own small tmpfs because it's rebuilt on every start anyway. Nothing executable lands in the data volume, so backups stay clean, and nothing you'd miss lives in RAM. The 128m size leaves about three times the 43 MB it uses. This setup passed a health check and a chat turn with a shell call, which ran in `/tmp/netclaw-1654/<key>/p`. The same file without the `/tmp` line failed that shell call.

Two other layouts also run:

- Mount the whole home as an exec tmpfs, such as `/home/netclaw:exec,uid=1654,gid=1654,size=256m`, with the volume mounted inside it. Home becomes writable, so `~/.gitconfig` and `~/.local/bin` work until a restart wipes them. It's a larger mount, and it holds more than the unpack.
- Point `DOTNET_BUNDLE_EXTRACT_BASE_DIR` into the data volume, such as `/home/netclaw/.netclaw/.bundle`. It survives restarts, but it puts 43 MB of executables in the volume, which a backup picks up. The folder is safe to delete.

The volume mounts at `/home/netclaw/.netclaw` and stays writable. Everything else under `/home/netclaw` is read-only, so a tool that writes to `~/.cache`, `~/.gitconfig` or `~/.local` fails. With a bind mount instead of a named volume, `chown 1654:1654` the host directory first, because nothing in this profile runs as root to do it.

If you'd rather keep the entrypoint's ownership repair, leave out `user:` and add `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID` and `KILL` back with `cap_add`. Without `KILL`, root can't signal the daemon after it drops to UID 1654. `docker stop` then exits `1` with `Unexpected error when forwarding signal` and the daemon never gets to drain.

## Reaching the daemon

`docker exec netclaw netclaw <command>` is the default path. The CLI inside the container talks to the daemon over loopback, and a root `exec` re-runs itself as `netclaw`.

A published port won't work in `local` mode, because the daemon only listens on the container's loopback. From another container, `curl http://netclaw:5199/api/health/ready` gets `connection refused`. Inside the container, call the daemon as `http://127.0.0.1:5199` or `http://localhost:5199`. In `local` mode the daemon answers `/api/health/status` with `401` when the `Host` header is any other name, such as `netclaw:5199`, or when an `Origin` header doesn't match it. `/api/health/ready` stays anonymous either way. For a host CLI, a sibling container, or a reverse proxy, set an exposure mode. A same-network reverse proxy needs these variables, where `TrustedProxies` is your proxy's address or the Docker network's subnet:

```bash
-e NETCLAW_Daemon__ExposureMode=reverse-proxy \
-e NETCLAW_Daemon__Host=0.0.0.0 \
-e NETCLAW_Daemon__TrustedProxies__0=172.16.0.0/12
```

That container reached `healthy`, answered `/api/health/ready` to another container, and returned `401` for `/api/health/status` without a device token. Tunnel modes (`tailscale-serve`, `cloudflare-tunnel`) need the tunnel agent in the same network namespace and `NETCLAW_Daemon__SkipTunnelProcessCheck=true`. See [Exposure modes](/deployment/exposure-modes/).

## Memory and first start

Embeddings are on by default since 0.27.0. On first start the daemon downloads two ONNX models from `huggingface.co` (about 129 MB) into `models/` inside the volume, then loads them.

| Setup | Observed |
|-------|----------|
| Embeddings on, idle | About 485 MiB resident, flat |
| 512 MiB limit | OOM-killed over and over. In three minutes the entrypoint restarted the daemon six times |
| 768 MiB limit | Stable at about 555 MiB |
| `Memory.Embeddings.Enabled=false` | About 300 MiB for the first minute and a half, then 220 to 225 MiB. Nothing downloaded, and `/api/health/status` reports embeddings `disabled`. A 512 MiB limit is stable |

An OOM kill doesn't stop the container. The entrypoint restarts the daemon, so `docker ps` keeps showing the container as running while the health check flaps. Set a 1 GiB limit or more. To turn embeddings off:

```bash
-e NETCLAW_Memory__Embeddings__Enabled=false
```

Without egress, copy the model files into `models/` and set `NETCLAW_Memory__Embeddings__AutoDownload=false`, or turn embeddings off. See [Memory and embeddings](/configuration/memory/). The daemon starts either way. It raises a `memory.embedding_model.unavailable` [alert](/observability/operational-alerts/) and falls back to lexical recall.

## Process supervision

The entrypoint restarts the daemon every time it exits, so a config-driven restart never stops the container. A daemon that dies within 30 seconds of starting is restarted after 2, 4, 8, 16, 32, then 60 seconds. A daemon that runs longer than 30 seconds resets the delay.


- Valid edits to `netclaw.json` restart the daemon in-process, including `Daemon.Host`, `Daemon.Port` and `Daemon.ExposureMode`.
- Changes to `NETCLAW_*` variables, `secrets.json`, or the image need `docker restart netclaw`.
- Inside the image `netclaw daemon start` never launches a second daemon. With the daemon up it prints `Daemon managed by container supervisor (PID n).` and exits `0`. With it down it says the supervisor owns startup and exits `1`. `netclaw daemon stop` prints `The container supervisor will restart the daemon.` and the entrypoint brings it back two seconds later. There is no `netclaw daemon restart`, so use `docker restart`.
- A restart or `docker stop` stops a session's tool loop at a safe point and posts one notice in its channel ("restarting", or "stopping" for `netclaw daemon stop`). A running sub-agent is parked and resumes after the restart, which can add about 18 seconds. The `daemon.stopping` [alert](/observability/operational-alerts/) names sessions that didn't acknowledge in `timedOutSessionIds`.
- `docker stop` forwards SIGTERM. The daemon needs up to 30 seconds to drain sessions and webhook alerts, so set `--stop-timeout 60` or `stop_grace_period: 60s`. Docker's 10 second default can kill a daemon with a turn in flight. An idle container stops in under a second.

## Health checks

The image defines this check, and Docker reports it as `healthy`, `unhealthy` or `starting`:

```dockerfile
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD netclaw daemon status >/dev/null || exit 1
```

`netclaw daemon status` exits `1` when the daemon isn't running, when `/api/health/ready` doesn't answer, or when the PID in `netclaw.pid` isn't shown to serve this home. The image bakes `NETCLAW_HOME`, so the home check passes. It finds the endpoint from `netclaw.json`, `NETCLAW_*` variables or the default, so a container with a custom `Daemon.Port` stays `healthy`. If it can't read the config, it won't guess an address. See [Health checks](/observability/health-checks/) for the endpoints and response fields.

A container with no provider configured still reports `healthy`, because the daemon is up. `netclaw status` shows `degraded` and chat turns return a configuration banner. A container whose `Models` or provider config is invalid doesn't report `healthy`: the daemon exits at startup. A running daemon whose `netclaw.json` becomes unreadable keeps serving its old config, but the check prints `The local daemon address is unknown. No readiness probe was sent. Repair the local configuration and retry.` and exits `1`, so the container turns `unhealthy` after three failed checks. See [the troubleshooting entry](#container-keeps-restarting-with-error-modelsroles).

## Volume layout and backups

State lives in `/home/netclaw/.netclaw`. See [Data directory layout](/reference/data-directory/) for every folder. The daemon deletes its own daemon and crash logs, numbered segments included, after 14 days, and [Data retention](/configuration/data-retention/) covers what else grows and how to change that. Stop the container, copy the whole directory (including `keys/`, without which `secrets.json` can't be read), then start it again. [Back up, restore and move netclaw](/guides/backup-and-restore/) has the commands and a tested round trip.

## Upgrading

Self-update is off in the image (`NETCLAW_Daemon__DisableSelfUpdate=true`). The tag is the version. When a newer release exists, `netclaw update` inside a container reports it and exits `1` with `Pull a newer container image to upgrade.` On the current release it prints `Netclaw is up to date` and exits `0`.

```bash
docker compose pull
docker compose up -d
```

Back up first and read [Upgrade netclaw](/guides/upgrading/). A newer image migrates the database on start and can't be undone by switching the tag back.

## Image details

| Property | Value |
|----------|-------|
| Registry | `ghcr.io/netclaw-dev/netclaw` |
| Base | `ubuntu:24.04` |
| Architectures | `linux/amd64`, `linux/arm64` |
| Port | `5199` |
| Volume | `/home/netclaw/.netclaw` |
| Baked environment | `NETCLAW_HOME`, `NETCLAW_DAEMON_PATH`, `NETCLAW_Daemon__DisableSelfUpdate=true`, `NETCLAW_CONTAINER_SUPERVISOR=entrypoint` |
| License | Apache-2.0 |

The image ships `git`, `gh`, `jq`, `sqlite3`, `python3`, `curl` and `wget`. The daemon runs as a normal user, so the agent can't `apt-get install`. It can install into `~/.local/bin`, `~/.dotnet` and `~/.dotnet/tools`, which are on `PATH`, and a mounted `/tools/bin` is on `PATH` too. For system packages, run `docker exec -u root netclaw apt-get install ...` or build a derived image.

### Docker socket access

To let the agent manage containers, mount the socket with `-v /var/run/docker.sock:/var/run/docker.sock`. Anything that can talk to the socket can usually control the host, so treat this as host-level access.

### Kubernetes

The image needs one writable volume at `/home/netclaw/.netclaw` and one replica, because the daemon holds a lock file on the data directory. Kubernetes ignores the image's `HEALTHCHECK`. An `httpGet` probe fails in `local` mode, because the kubelet calls the pod IP and the daemon only listens on loopback. Use an `exec` probe that runs the image's own check, `netclaw daemon status`, which follows `Daemon.Port`. In `reverse-proxy` mode with `Daemon.Host` set to `0.0.0.0`, `httpGet` works. These probes haven't been run on a cluster, so test them before you rely on them.

## Troubleshooting

### `daemon not configured - please run netclaw init`

**Symptom:** `docker exec netclaw netclaw status` or `chat -p` prints this, but the container is healthy.

**Cause:** The container is configured with `NETCLAW_*` variables only, so there's no `config/netclaw.json`.

**Fix:** [Put the config in a file](#use-the-cli-put-the-config-in-a-file) or run `docker exec -it netclaw netclaw init`.

### Container is `unhealthy` and `docker logs` shows `Aborted (core dumped)`

**Symptom:** The container flaps between `starting` and `unhealthy`. `docker logs` shows a `Fatal error` line with a crash log path, the exception, then `Aborted (core dumped)` and `restarting in 60s`.

**Cause:** The daemon failed during startup and the entrypoint keeps restarting it. The abort is how the daemon reports a fatal configuration error. The restart delay climbs to 60 seconds.

**Fix:** Read the first lines of `docker logs netclaw` for the exception, or the newest `logs/crash-*.log` in the volume. Common causes:

| Message | Cause |
|---------|-------|
| `Invalid local topology: Daemon.Host '0.0.0.0' is not a loopback address.` | A host override in `local` mode. |
| `Tunnel prerequisite not met: ExposureMode='tailscale-serve' requires 'tailscaled'` | A tunnel mode without the tunnel process. Set `SkipTunnelProcessCheck` for a sidecar. |
| `The key {...} was not found in the key ring` | `secrets.json` restored without its `keys/` directory. See [Back up, restore and move netclaw](/guides/backup-and-restore/). |
| `has list items and also a value` | A list set in both a variable and the file. |

### Container keeps restarting with `error: Models:Roles...`

**Symptom:** `docker logs` repeats one line, then `netclawd exited (code=1) after 0s, restarting in 2s...` with a delay that doubles to 60 seconds. There's no stack trace, no `Aborted (core dumped)` and no crash log.

```text
error: Models:Roles:Main references unknown definition 'nope'. Defined: stub-stub-model. Fix the name, or run `netclaw model set main <provider> <model>`.
```

**Cause:** `Models` or a provider entry is invalid, and the daemon refuses to start with it. A running daemon behaves differently. It keeps its previous configuration and shows `config on disk not applied` in [`netclaw status`](/cli/status/).

**Fix:** Correct the `Models` section in `netclaw.json`, or the `NETCLAW_Models__*` variable the message names. The next restart picks it up.

### Container keeps restarting with `error: Couldn't read netclaw.json`

**Symptom:** The same loop as above, with this line:

```text
error: Couldn't read netclaw.json: A duplicate key 'configVersion' was found.
```

**Cause:** `netclaw.json` or `secrets.json` is empty, cut off, or has a duplicate key. The container turns `unhealthy` after a minute. `docker exec` still works, but `netclaw status` and `netclaw chat` print the same line. If the daemon was already running when the file broke, it keeps its old config and `netclaw daemon status` exits `1` with `The local daemon address is unknown`.

**Fix:** Repair the file in the volume, or `docker cp` a good copy in. The next restart picks it up. See [`Couldn't read netclaw.json`](/troubleshooting/common-problems/#couldnt-read-netclawjson).

### Exit code 137, `Killed` or a restarting daemon with a healthy-looking container

**Cause:** The memory limit is too low for the embedding models. `docker inspect --format '{{.State.OOMKilled}}' netclaw` prints `true`, and the container stays `running` because the entrypoint restarts the daemon.

**Fix:** Raise the limit to 1 GiB or more, or turn embeddings off.

### Permission denied on a bind mount

**Cause:** The entrypoint couldn't take ownership. The mount is read-only, or the container runs with `user: "1654:1654"` against a directory owned by someone else.

**Fix:** Make the mount writable, or `chown -R 1654:1654` the host directory.

### Host CLI or `curl` can't connect

**Cause:** `local` mode listens on the container's loopback only.

**Fix:** Run the CLI with `docker exec`, or set an [exposure mode](/deployment/exposure-modes/).

## Related pages

- [Upgrade netclaw](/guides/upgrading/) - what changes between releases and how to roll back
- [Back up, restore and move netclaw](/guides/backup-and-restore/) - copy the volume and prove it restores
- [Exposure modes](/deployment/exposure-modes/) - reach the daemon from outside the container
- [Health checks](/observability/health-checks/) - endpoints and response fields
- [Data directory layout](/reference/data-directory/) - what's in the volume

## Resources

- [Docker Engine installation guide](https://docs.docker.com/engine/install/) - platform-specific install instructions
- [Docker Compose documentation](https://docs.docker.com/compose/) - multi-container orchestration
- [Docker security guide](https://docs.docker.com/engine/security/) - capabilities, `no-new-privileges` and socket exposure
- [`docker run` reference](https://docs.docker.com/reference/cli/docker/container/run/) - `--read-only`, `--tmpfs`, `--cap-drop` and `--stop-timeout`
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) - the double-underscore nesting convention
- [Ollama model library](https://ollama.com/library) - available models for local inference
