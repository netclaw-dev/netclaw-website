---
title: "Docker Deployment"
description: "Run the netclaw daemon in a Docker container with persistent config, health checks, and zero-downtime upgrades."
---

The netclaw Docker image runs the daemon (`netclawd`) in a supervised container. The CLI can stay on your host or run inside the container with `docker exec`. By default the local control-plane endpoint is `127.0.0.1:5199` when you publish it that way; non-local exposure modes add more auth and proxy rules.

## Before you begin

- [Docker Engine](https://docs.docker.com/engine/install/) 20.10+ or Docker Desktop
- A provider API key (OpenRouter, Anthropic, OpenAI, etc.) or a reachable [Ollama](https://ollama.com/) instance
- An initialized `~/.netclaw` directory — run `netclaw init` on the host first, or bind-mount a pre-configured one. If you don't have the CLI yet, see [Installation](/getting-started/installation/).

## Quick start

This path assumes you already have an initialized `~/.netclaw` directory.

```bash
docker run -d \
  --name netclaw \
  -v ~/.netclaw:/root/.netclaw \
  -p 127.0.0.1:5199:5199 \
  -e NETCLAW_Daemon__Host=0.0.0.0 \
  ghcr.io/netclaw-dev/netclaw
```

The port binding is loopback-only (`127.0.0.1:5199`) because the health check endpoint is unauthenticated — don't expose it to the network. `NETCLAW_Daemon__Host=0.0.0.0` makes the daemon listen on the container interface so Docker's published port can reach it. The volume mount persists identity, config, credentials, session state, and logs across restarts. Self-update is disabled in the image. Use the image tag as the version. Update availability checks still run, so you'll know when a new release exists.

**Tags:** `:latest` tracks the most recent release. Pin to a version tag (e.g., `:1.2.3`) in production.

Verify from the host:

```bash
netclaw status
```

The CLI defaults to `http://127.0.0.1:5199`, so no configuration is needed for local Docker. For remote daemons, see [Exposure Modes](/deployment/exposure-modes/).

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
  -v ~/.netclaw:/root/.netclaw \
  -p 127.0.0.1:5199:5199 \
  -e NETCLAW_Daemon__Host=0.0.0.0 \
  -e NETCLAW_Providers__openrouter__Type=openrouter \
  -e NETCLAW_Providers__openrouter__ApiKey=sk-or-v1-... \
  -e NETCLAW_Models__Main__Provider=openrouter \
  -e NETCLAW_Models__Main__ModelId=anthropic/claude-sonnet-4 \
  ghcr.io/netclaw-dev/netclaw
```

Keep secrets out of config files — inject them at runtime. The `ModelId` value must match a valid identifier from the provider API; see [Models](/configuration/models/) for the full schema and available model IDs.

## Docker Compose

For anything beyond quick testing, use Compose. This example pairs netclaw with a local Ollama instance and uses named volumes (unlike the bind mount in the quick start) for easier lifecycle management:

```yaml
services:
  netclaw:
    image: ghcr.io/netclaw-dev/netclaw
    container_name: netclaw
    restart: unless-stopped
    depends_on:
      - ollama
    ports:
      - "127.0.0.1:5199:5199"
    volumes:
      - netclaw-home:/root/.netclaw
    environment:
      NETCLAW_Daemon__Host: 0.0.0.0
      NETCLAW_Providers__local-ollama__Type: ollama
      NETCLAW_Providers__local-ollama__Endpoint: http://ollama:11434
      NETCLAW_Models__Main__Provider: local-ollama
      NETCLAW_Models__Main__ModelId: qwen3:30b

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ollama-data:/root/.ollama

volumes:
  netclaw-home:
  ollama-data:
```

```bash
docker compose up -d
```

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

Everything the daemon persists lives under `/root/.netclaw`:

```
/root/.netclaw/
├── client/config.json       # CLI endpoint state
├── config/
│   ├── netclaw.json         # Daemon settings
│   └── secrets.json         # Credentials
├── identity/                # Agent personality (SOUL.md, AGENTS.md, TOOLING.md)
├── sessions/                # Conversation history
├── keys/                    # Key material
├── projects/
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

# Start with the new image
docker run -d \
  --name netclaw \
  -v ~/.netclaw:/root/.netclaw \
  -p 127.0.0.1:5199:5199 \
  -e NETCLAW_Daemon__Host=0.0.0.0 \
  ghcr.io/netclaw-dev/netclaw:latest

# Wait for readiness
until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done
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
| Volume | `/root/.netclaw` |
| License | Apache-2.0 |

Built on Ubuntu 24.04 (not a minimal runtime), the image ships with `git`, `jq`, `sqlite3`, `python3`, `curl`, `wget`, `gh`, and more. Operators can `apt-get install` additional tools if the agent needs them.

## Troubleshooting

### Container starts but CLI can't connect

Confirm the port mapping binds to `127.0.0.1` and nothing else is on port 5199:

```bash
ss -tlnp | grep 5199
docker logs netclaw
```

If the container is configured for `reverse-proxy`, also check whether the daemon is still bound to loopback. Reverse-proxy mode rejects loopback final-hop topologies.

### Container keeps restarting

The entrypoint restarts the daemon on every exit, and that's by design. If it's a crash loop, check `docker logs netclaw` for the cause. Common culprits: missing provider config, invalid API key, or a required field missing from `netclaw.json`.

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
