---
title: "Skill Server"
description: "Running and connecting a skill server."
---

SkillServer is a self-hosted skill registry — a private NuGet feed or npm registry, but for [SKILL.md](https://agentskills.io) files. Host it behind your firewall, publish proprietary skills, and netclaw instances on the network sync from it automatically.

It implements two open standards:

- **[Cloudflare Agent Skills Discovery RFC v0.2.0](https://github.com/cloudflare/agent-skills-spec)** — discovery via `/.well-known/agent-skills/index.json`
- **[AgentSkills.io](https://agentskills.io)** — the SKILL.md format for skill definitions

Any agent that supports these standards can consume skills from your server, not just netclaw.

## What it does

- Stores versioned skills in content-addressable blob storage (SHA-256)
- Serves a discovery index that agents poll on an interval
- API key auth on writes; reads are open (agents fetch skills without credentials)
- Single container, no external dependencies — just SQLite + filesystem

## Deploy with Docker

Pull the image:

```bash
docker pull ghcr.io/netclaw-dev/skillserver:latest
```

Available for `linux/amd64` and `linux/arm64`.

### Docker Compose

```yaml
services:
  skill-server:
    image: ghcr.io/netclaw-dev/skillserver:latest
    ports:
      - "8080:8080"
    volumes:
      - skill-data:/data
    environment:
      - SKILLSERVER__DATAPATH=/data
      - SKILLSERVER__BASEURL=http://localhost:8080
      - SKILLSERVER__APIKEY=${SKILLSERVER_APIKEY:-}
      - ASPNETCORE_URLS=http://+:8080

volumes:
  skill-data:
```

Start it:

```bash
export SKILLSERVER_APIKEY="sk-$(openssl rand -base64 32)"
echo "Save this key: $SKILLSERVER_APIKEY"
docker compose up -d
```

Verify it's running:

```bash
curl http://localhost:8080/health
```

The bootstrap API key is hashed and stored on first startup. Save the raw value — it cannot be recovered from the server.

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SKILLSERVER__DATAPATH` | `./data` | SQLite database + blob storage directory |
| `SKILLSERVER__BASEURL` | `http://localhost:8080` | Base URL for absolute URLs in discovery responses |
| `SKILLSERVER__APIKEY` | *(none)* | Bootstrap API key, seeded on first run if no keys exist in DB |
| `ASPNETCORE_URLS` | `http://+:8080` | Listen address and port |

All state lives in `SKILLSERVER__DATAPATH`. Back up that volume and you have everything.

### Production

- Put a reverse proxy (Caddy, nginx, Traefik) in front for TLS
- Set `SKILLSERVER__BASEURL` to your public URL (e.g., `https://skills.internal.example.com`) so discovery responses have correct absolute URLs
- Mount `/data` to persistent storage — if the volume is lost, you'll need to re-publish all skills

## API key management

Reads are open. Writes (publish, delete, key management) require a `Bearer` token.

### Bootstrap

Set `SKILLSERVER__APIKEY` before the first run. The server hashes it and stores it as the "bootstrap" key. Once any key exists in the database, this environment variable is ignored on subsequent starts.

### Create additional keys

```bash
curl -X POST http://localhost:8080/api-keys \
  -H "Authorization: Bearer sk-your-bootstrap-key" \
  -H "Content-Type: application/json" \
  -d '{"label": "ci-deploy"}'
```

The response contains the raw key once. Store it in a secret manager or password vault.

### List and revoke

```bash
# List (never shows raw keys)
curl http://localhost:8080/api-keys \
  -H "Authorization: Bearer sk-your-key"

# Revoke
curl -X DELETE http://localhost:8080/api-keys/2 \
  -H "Authorization: Bearer sk-your-key"
```

You cannot delete the last remaining key.

### Key format

Format: `sk-{random}` (256 bits entropy, base64url-encoded). Stored as SHA-256 hashes, compared in constant time. Raw keys never touch disk.

## Publishing skills (skillserver CLI)

The `skillserver` CLI handles publishing and management from your terminal or CI.

### Install

```bash
# Standalone binary (no .NET runtime required)
curl -fsSL https://raw.githubusercontent.com/netclaw-dev/skill-server/dev/scripts/install-skillserver.sh | bash

# Or as a .NET global tool
dotnet tool install --global Netclaw.SkillServer.Cli
```

Standalone binaries are available for linux-x64, linux-arm64, osx-arm64, and win-x64.

### Configure

```bash
skillserver config init
```

Prompts for server URL and API key. Saves to `~/.skillserver/config.json`.

For CI, use environment variables instead:

```bash
export SKILLSERVER_URL=https://skills.internal.example.com
export SKILLSERVER_API_KEY=sk-your-ci-key
```

Priority: CLI flags > environment variables > config file.

### Publish

A skill is a directory containing a `SKILL.md` with YAML frontmatter:

```
my-skill/
  SKILL.md          # Required — name, description, version in frontmatter
  resources/        # Optional — supporting files
```

Name validation: 1-64 chars, lowercase alphanumeric + hyphens (`^[a-z0-9]+(-[a-z0-9]+)*$`).

```bash
# Single skill
skillserver publish ./my-skill

# All skills in a directory
skillserver publish-all ./skills

# Dry run (validates without uploading)
skillserver publish-all ./skills --dry-run

# Force re-publish (deletes existing version first)
skillserver publish ./my-skill --force
```

Publishing a version that already exists returns 409 Conflict and the CLI skips it. This makes `publish-all` idempotent — safe to run repeatedly in CI.

### Other commands

```bash
# List and search
skillserver list
skillserver list --search kubernetes

# Version history
skillserver versions my-skill

# Verify local matches server
skillserver verify ./my-skill

# Delete a version
skillserver delete my-skill 1.0.0 --yes

# Manage API keys
skillserver api-key create --label "CI Pipeline"
skillserver api-key list
skillserver api-key delete 7
```

### Global options

| Option | Description |
|--------|-------------|
| `--server-url <url>` | Override server URL |
| `--api-key <key>` | Override API key |
| `--output text\|json` | Output format |
| `--verbose, -v` | Show HTTP request/response details |

## CI/CD integration

A GitHub Actions workflow that publishes on push and validates on PR. This example uses Tailscale to reach a server on a private network:

```yaml
name: Publish Skills
on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Connect to Tailscale
        uses: tailscale/github-action@v2
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}

      - name: Install skillserver CLI
        run: curl -fsSL https://raw.githubusercontent.com/netclaw-dev/skill-server/dev/scripts/install-skillserver.sh | bash

      - name: Publish skills
        if: github.event_name == 'push'
        env:
          SKILLSERVER_URL: ${{ secrets.SKILLSERVER_URL }}
          SKILLSERVER_API_KEY: ${{ secrets.SKILLSERVER_API_KEY }}
        run: skillserver publish-all ./skills

      - name: Validate skills (PRs only)
        if: github.event_name == 'pull_request'
        env:
          SKILLSERVER_URL: ${{ secrets.SKILLSERVER_URL }}
          SKILLSERVER_API_KEY: ${{ secrets.SKILLSERVER_API_KEY }}
        run: skillserver publish-all ./skills --dry-run
```

PR builds validate with `--dry-run`. Pushes to master publish for real. Existing versions return 409 and are skipped — only new or bumped versions actually upload.

## Connecting netclaw instances

Add a skill server as a feed source:

```bash
netclaw skill feed add my-server --url http://skills.internal.example.com/manifest.json
```

The daemon syncs on a periodic interval. Skills land in `~/.netclaw/skills/.server-feeds/` (read-only). See [Skill Feeds](/skills/skill-feeds/) for sync intervals, authentication, and selective sync options.

## API reference

### Discovery (no auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/.well-known/agent-skills/index.json` | RFC-compliant skill discovery index |
| GET | `/manifest.json` | NetClaw-compatible manifest |
| GET | `/health` | Health check |

### Skills (reads open, writes require auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/skills` | List all (`?q=`, `?skip=`, `?take=` supported) |
| GET | `/skills/{name}` | All versions of a skill |
| GET | `/skills/{name}/latest` | Latest version metadata |
| GET | `/skills/{name}/{version}` | Specific version metadata |
| GET | `/skills/{name}/{version}/SKILL.md` | Download skill content |
| GET | `/skills/{name}/{version}/{*path}` | Download resource files |
| POST | `/skills/check-updates` | Batch update check (up to 100 skills) |
| POST | `/skills` | Upload new version (multipart/form-data) |
| DELETE | `/skills/{name}/{version}` | Delete a version |

### API keys (all require auth)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api-keys` | Create a key (returns raw key once) |
| GET | `/api-keys` | List keys (hashed, never shows raw) |
| DELETE | `/api-keys/{id}` | Revoke a key |

## Related pages

- [Skills Overview](/skills/overview/) — format, lifecycle, source types
- [Skill Feeds](/skills/skill-feeds/) — configuring netclaw to consume from skill servers
- [External Skills](/skills/external-skills/) — local skill directories
- [Security Model](/security/security-model/) — content scanning and trust model

## External resources

- [AgentSkills.io](https://agentskills.io) — the SKILL.md format spec
- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-spec) — the discovery protocol
- [netclaw-dev/skill-server on GitHub](https://github.com/netclaw-dev/skill-server) — source, issues, releases
- [Tailscale GitHub Action](https://github.com/tailscale/github-action) — CI/CD access to private network servers
