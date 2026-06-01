---
title: "Docker Deployment"
description: "Run the netclaw daemon in a Docker container with persistent config, health checks, and zero-downtime upgrades."
---

The netclaw Docker image runs the daemon (`netclawd`) in a supervised container as the non-root user `netclaw` (UID 1654). The daemon binds loopback inside the container, so you drive it with `docker exec`. Reaching it from the host or the network is a non-local exposure mode — see [Exposure Modes](/deployment/exposure-modes/).

## Before you begin

- [Docker Engine](https://docs.docker.com/engine/install/) 20.10+ or Docker Desktop
- A provider API key (OpenRouter, Anthropic, OpenAI, etc.) or a reachable [Ollama](https://ollama.com/) instance
- Either provider/model config to pass as `NETCLAW_*` env vars, or an initialized config you run with [`netclaw init`](/cli/init/) inside the container

:::caution
Don't add `-e NETCLAW_Daemon__Host=0.0.0.0`. The default `local` exposure mode binds loopback and **rejects** a non-loopback host — the daemon aborts on startup if you force `0.0.0.0` without switching exposure modes. To reach the daemon from outside the container, use a non-local exposure mode (see [Exposure Modes](/deployment/exposure-modes/)), not a raw bind override.
:::

## Quick start

Use a named volume — Docker creates it with the right ownership for the non-root `netclaw` user. (Bind-mounting a host directory works too, but you must `chown` it to UID 1654 first, or the daemon can't write to it.)

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

The volume persists identity, config, credentials, session state, and logs across restarts. Self-update is disabled in the image — the image tag is the version, though update-availability checks still run so you'll know when a new release exists.

**Tags:** `:latest` tracks the most recent release. Pin to a version tag (e.g., `:1.2.3`) in production.

Verify the daemon is healthy:

```bash
docker exec netclaw netclaw status
```

The CLI inside the container talks to the daemon over loopback, so no endpoint config is needed. To run the CLI from your host instead, point a daemon at a non-local exposure mode — see [Exposure Modes](/deployment/exposure-modes/).

### First run with Docker only

If you don't have `netclaw init` on the host, run it inside the container:

```bash
docker exec -it netclaw netclaw init
```

The interactive wizard works the same way over `docker exec -it`.

If you choose a non-local exposure mode during first-run setup, netclaw now seeds a one-shot local bootstrap credential before the first successful non-local daemon start. That prevents first boot from getting stuck waiting on pairing.

## Configuration via environment variables

Pass provider credentials and model config as `NETCLAW_`-prefixed environment variables. Double underscores separate path segments, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider). Env vars take highest priority, overriding both `netclaw.json` and `secrets.json`.

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

Keep secrets out of config files — inject them at runtime. The `ModelId` value must match a valid identifier from the provider API; see [Models](/configuration/models/) for the full schema and available model IDs.

## Docker Compose

For anything beyond quick testing, use Compose. This example pairs netclaw with a local Ollama instance on a private Compose network. The daemon stays in `local` mode (loopback); you reach it with `docker exec`, so there's no `Host` override and no published control-plane port:

```yaml
services:
  netclaw:
    image: ghcr.io/netclaw-dev/netclaw
    container_name: netclaw
    restart: unless-stopped
    depends_on:
      - ollama
    volumes:
      - netclaw-home:/home/netclaw/.netclaw
    environment:
      NETCLAW_Providers__local-ollama__Type: ollama
      NETCLAW_Providers__local-ollama__Endpoint: http://ollama:11434
      NETCLAW_Models__Main__Provider: local-ollama
      NETCLAW_Models__Main__ModelId: qwen3:30b

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    volumes:
      - ollama-data:/root/.ollama

volumes:
  netclaw-home:
  ollama-data:
```

```bash
docker compose up -d
```

The daemon comes up reporting `healthy`. Drive it with `docker exec netclaw netclaw status` (or `docker exec -it netclaw netclaw chat`).

Pull the model into Ollama before netclaw can use it:

```bash
docker exec ollama ollama pull qwen3:30b
```

Netclaw references Ollama by service name (`http://ollama:11434`) since Compose puts both containers on the same network.

`qwen3:30b` is a large model. For first-time testing on modest hardware, pick a smaller Ollama model.

### Docker socket access

If you want the agent to manage Docker containers as part of its tool use, mount the socket:

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

Add this to the `volumes` section of the netclaw service in your Compose file or to the `docker run` command.

Treat this as host-level access. A process that can talk to the Docker socket can usually control the host.

## Volume layout

Everything the daemon persists lives under `/home/netclaw/.netclaw`:

```
/home/netclaw/.netclaw/
├── client/config.json       # CLI endpoint state
├── config/
│   ├── netclaw.json         # Daemon settings
│   └── secrets.json         # Credentials
├── identity/                # Agent personality (SOUL.md, AGENTS.md, TOOLING.md)
├── sessions/                # Conversation history
├── keys/                    # Key material
├── workspaces/              # Agent project workspaces (git repos with AGENTS.md)
├── environment/
├── schedules/
└── logs/                    # crash-*.log, session logs
```

Back up this volume before upgrades. `config/` and `identity/` are the critical directories; everything else can be regenerated. If you use a bind mount, copy `~/.netclaw` directly. If you use a named volume, export it with your normal Docker volume backup process before upgrades.

## Health checks

The image has a built-in health check that polls every 15 seconds with a 30-second startup grace period:

```
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3
  CMD curl -sf http://127.0.0.1:5199/api/health/ready || exit 1
```

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /api/health/ready` | None | Returns `200 OK` when the daemon is ready. Use this for orchestrators and load balancers. |
| `GET /api/health/status` | Required | Returns detailed runtime status. |

Check container health from the host:

```bash
docker inspect --format='{{.State.Health.Status}}' netclaw
```

## Process supervision

The entrypoint script is a PID 1 supervisor. If the daemon exits (config-update restart, crash, `netclaw init` wizard completion), the entrypoint waits 2 seconds and restarts it. The container stays alive, so `docker exec` sessions survive daemon restarts.

That also helps with pairing: if the daemon is running in a container and you need a daemon-host bootstrap or recovery path, `docker exec netclaw netclaw daemon pair` works the same way as running it on a bare-metal daemon host.

`docker stop` sends SIGTERM, which the entrypoint forwards to the daemon for a clean shutdown. Docker's default 10-second stop timeout is plenty.

## Upgrading

Self-update is disabled in the image (`NETCLAW_Daemon__DisableSelfUpdate=true`), so upgrades mean pulling a new image. Schema migrations are forward-only with no automatic rollback.

```bash
# Pull the new version
docker pull ghcr.io/netclaw-dev/netclaw:latest

# Stop the old container (volume stays)
docker stop netclaw && docker rm netclaw

# Start with the new image (same flags you launched it with)
docker run -d \
  --name netclaw \
  -v netclaw-home:/home/netclaw/.netclaw \
  ghcr.io/netclaw-dev/netclaw:latest

# Wait for readiness
until [ "$(docker inspect --format='{{.State.Health.Status}}' netclaw)" = "healthy" ]; do sleep 2; done
echo "Daemon is ready"
```

With Compose:

```bash
docker compose pull
docker compose up -d
```

To rollback, stop the container and start with the previous image tag. If the new version already ran a schema migration, restore the volume from backup to roll back.

## Image details

| Property | Value |
|----------|-------|
| Registry | `ghcr.io/netclaw-dev/netclaw` |
| Base | `ubuntu:24.04` |
| Architectures | `linux/amd64`, `linux/arm64` |
| Port | `5199` |
| Volume | `/home/netclaw/.netclaw` |
| License | Apache-2.0 |

Built on Ubuntu 24.04 (not a minimal runtime), the image ships with `git`, `jq`, `sqlite3`, `python3`, `curl`, `wget`, `gh`, and more. Operators can `apt-get install` additional tools if the agent needs them.

## Troubleshooting

### CLI can't connect

Run the CLI inside the container, where it reaches the daemon over loopback:

```bash
docker exec netclaw netclaw status
```

A host CLI (or `curl`) hitting a published port won't reach a `local`-mode daemon — it binds loopback inside the container, and `local` mode refuses to bind `0.0.0.0`. For host or network access, configure a non-local exposure mode (see [Exposure Modes](/deployment/exposure-modes/)); reverse-proxy mode additionally needs `Daemon.TrustedProxies` set to the proxy's address or CIDR.

### Container keeps restarting (crash loop)

The entrypoint restarts the daemon on every exit by design, so a misconfiguration shows up as a restart loop. Check `docker logs netclaw` for the fatal error. The most common one:

```
Invalid local topology: Daemon.Host '0.0.0.0' is not a loopback address.
```

That means `NETCLAW_Daemon__Host=0.0.0.0` was set while the exposure mode is still `local` — remove the host override (the default loopback bind is correct) or switch to a non-local exposure mode. Other culprits: missing provider config, an invalid API key, or a required `netclaw.json` field.

### Health check failing

The 30-second start period gives the daemon time to initialize. If it's still unhealthy after that, the daemon isn't starting. Check logs and run `netclaw doctor` from the host, or `docker exec netclaw netclaw doctor` inside the container.

## Related pages

- [Models](/configuration/models/) — model slot configuration
- [Exposure Modes](/deployment/exposure-modes/) — remote access via reverse proxy, Tailscale, or Cloudflare Tunnel
- [systemd Service](/deployment/systemd/) — bare-metal Linux alternative
- [OpenTelemetry](/observability/opentelemetry/) — daemon metrics and log export

## Resources

- [Docker Engine installation guide](https://docs.docker.com/engine/install/) — platform-specific install instructions
- [Docker Compose documentation](https://docs.docker.com/compose/) — multi-container orchestration
- [Docker security guide](https://docs.docker.com/engine/security/) — baseline guidance for socket mounts and daemon exposure
- [GitHub Container Registry (GHCR)](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) — pulling and authenticating with ghcr.io
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention
- [Docker exec reference](https://docs.docker.com/reference/cli/docker/container/exec/) — run CLI commands inside a live container
- [Ollama model library](https://ollama.com/library) — browse available models for local inference
