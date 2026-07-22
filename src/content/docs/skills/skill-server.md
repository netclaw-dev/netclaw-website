---
title: "Skill Server"
description: "Running and connecting a self-hosted skill server for skills and sub-agents."
---

SkillServer is a self-hosted skill registry - a private NuGet feed or npm registry, but for [SKILL.md](https://agentskills.io) files and netclaw sub-agents. Host it behind your firewall, publish proprietary skills and sub-agents, and every netclaw instance on the network syncs from it automatically.

Source code and releases: [github.com/netclaw-dev/skill-server](https://github.com/netclaw-dev/skill-server)

It implements two open standards, plus a native feed for netclaw-aware clients:

- [Cloudflare Agent Skills Discovery RFC v0.2.0](https://github.com/cloudflare/agent-skills-discovery-rfc) - discovery via `/.well-known/agent-skills/index.json`
- [AgentSkills.io](https://agentskills.io) - the SKILL.md format for skill definitions
- [Native Manifest](/skills/native-manifest/) - a versioned `/manifest.json` feed that also carries sub-agents and packaged archives

Any agent that speaks the RFC can consume skills from your server, and netclaw additionally reads the native manifest for sub-agents and archive artifacts.

## What it does

- Stores versioned skills and sub-agents in content-addressable blob storage (SHA-256)
- Serves an RFC discovery index and a native manifest that agents poll on an interval
- Packages skills with bundled resources as deterministic [archives](/skills/bundled-resources/)
- Ships a web gallery for browsing skills and sub-agents
- Requires API key auth on writes. Reads are open, so agents fetch without credentials
- Runs as a single container with no external dependencies, just SQLite and the filesystem

## Deploy with Docker

Pull the image:

```bash
docker pull ghcr.io/netclaw-dev/skillserver:latest
```

Available for `linux/amd64` and `linux/arm64`.

### Docker Compose

```yaml
name: skillserver

services:
  # The server runs as a non-root user (uid 1654). Docker creates the named
  # volume's mount point owned by root, so this one-shot service fixes ownership
  # before the server starts - otherwise it can't create the SQLite database.
  init-data:
    image: ghcr.io/netclaw-dev/skillserver:latest
    user: "0:0"
    volumes:
      - skill-data:/data
    entrypoint: ["sh", "-c", "chown -R 1654:1654 /data"]
    restart: "no"

  skill-server:
    image: ghcr.io/netclaw-dev/skillserver:latest
    depends_on:
      init-data:
        condition: service_completed_successfully
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

The bootstrap API key is hashed and stored on first startup. Save the raw value, because it can't be recovered from the server.

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
- Mount `/data` to persistent storage. If the volume is lost, you'll re-publish everything

## API key management

Reads are open. Writes (publish, delete, key management) require a `Bearer` token.

### Bootstrap

Set `SKILLSERVER__APIKEY` before the first run. The server hashes it and stores it as the "bootstrap" key. Once any key exists in the database, this environment variable is ignored on later starts.

### Create additional keys

```bash
curl -X POST http://localhost:8080/api/v1/api-keys \
  -H "Authorization: Bearer sk-your-bootstrap-key" \
  -H "Content-Type: application/json" \
  -d '{"label": "ci-deploy"}'
```

The response contains the raw key once. Store it in a secret manager or password vault. The [`skillserver api-key`](/skills/skillserver-cli/) commands do the same thing without hand-writing curl.

### List and revoke

```bash
# List (never shows raw keys)
curl http://localhost:8080/api/v1/api-keys \
  -H "Authorization: Bearer sk-your-key"

# Revoke
curl -X DELETE http://localhost:8080/api/v1/api-keys/2 \
  -H "Authorization: Bearer sk-your-key"
```

You can't delete the last remaining key.

### Key format

`sk-{random}` (256 bits of entropy, base64url-encoded). Stored as SHA-256 hashes, compared in constant time. Raw keys never touch disk.

## Publishing skills and sub-agents

The [`skillserver` CLI](/skills/skillserver-cli/) handles publishing and management from your terminal or CI, and that page has the full command and flag reference. The essentials:

```bash
# Publish one skill, or every skill directory under a parent
skillserver publish ./my-skill
skillserver publish-all ./skills

# Publish sub-agents (version is required - it's not read from frontmatter)
skillserver publish-subagent ./release-notes-writer.md --version 1.0.0
skillserver publish-subagents ./subagents
```

Publishing a version that already exists is skipped, so `publish-all` and `publish-subagents` are idempotent and safe to run on every CI push. A skill with a `references/`, `scripts/`, or `assets/` folder is packaged as an [archive](/skills/bundled-resources/) that preserves relative paths and executable bits. A bare `SKILL.md` publishes as a lightweight skill-md artifact.

<!-- TODO: once /skills/publishing-skills/ (CI/CD guide) ships after #103, link it here for the full GitHub Actions setup. -->

## Feeds and the native manifest

The server exposes two discovery feeds:

| Feed | Path | Contents |
|------|------|----------|
| RFC index | `/.well-known/agent-skills/index.json` | Skills only, per the Cloudflare RFC |
| Native manifest | `/manifest.json` | Skills, sub-agents, and archives, with API version negotiation |

The netclaw daemon reads the native manifest, so it picks up sub-agents and archive resources the RFC feed can't express. See [Native Manifest](/skills/native-manifest/) for the manifest tree and version negotiation, and [Skill Feeds](/skills/skill-feeds/) for how the daemon syncs from it.

## Connecting netclaw instances

Add a skill server as a feed source through `netclaw config` → Skill Sources (select **+ Add skill server** and enter the base URL), or by adding it to the `SkillFeeds.Feeds` array in `~/.netclaw/config/netclaw.json`:

```json
{ "SkillFeeds": { "Feeds": [ { "Name": "my-server", "Url": "http://skills.internal.example.com", "Enabled": true } ] } }
```

The daemon syncs on a periodic interval. Skills land in `~/.netclaw/skills/.server-feeds/` and sub-agents in `~/.netclaw/agents/.server-feeds/`, both read-only. See [Skill Feeds](/skills/skill-feeds/) for sync intervals, authentication, and selective sync options.

## API reference

Reads are open. Endpoints marked `auth` require an `Authorization: Bearer <key>` header.

### Discovery and feeds

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/api/v1/info` | Server info and capabilities |
| GET | `/.well-known/agent-skills/index.json` | RFC-compliant skill discovery index |
| GET | `/manifest.json` | Native manifest root (version negotiation) |
| GET | `/skills/v1/index.json` | Native skill collection (paginated) |
| GET | `/skills/v1/{name}/versions/{version}.json` | Native skill version entry |
| GET | `/subagents/v1/index.json` | Native sub-agent collection (paginated) |
| GET | `/subagents/v1/{name}/versions/{version}.json` | Native sub-agent version entry |

### Skills

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/skills` | List all (`?q=`, `?skip=`, `?take=` supported) |
| GET | `/api/v1/skills/{name}` | All versions of a skill |
| GET | `/api/v1/skills/{name}/latest` | Latest version metadata |
| GET | `/api/v1/skills/{name}/{version}` | Specific version metadata |
| GET | `/api/v1/skills/{name}/{version}/SKILL.md` | Download SKILL.md |
| GET | `/api/v1/skills/{name}/{version}/archive.zip` | Download the packaged archive |
| GET | `/api/v1/skills/{name}/{version}/resources` | List bundled resources (path, digest, mode) |
| GET | `/api/v1/skills/{name}/{version}/{*path}` | Download a single resource file |
| POST | `/api/v1/skills/check-updates` | Batch update check |
| POST | `/api/v1/skills` | `auth` Upload a new version (multipart/form-data) |
| DELETE | `/api/v1/skills/{name}/{version}` | `auth` Delete a version |

### Sub-agents

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/subagents` | List all sub-agents |
| GET | `/api/v1/subagents/{name}` | All versions of a sub-agent |
| GET | `/api/v1/subagents/{name}/{version}` | Specific version metadata |
| GET | `/api/v1/subagents/{name}/{version}/agent.md` | Download the sub-agent definition |
| POST | `/api/v1/subagents` | `auth` Upload a new version |
| DELETE | `/api/v1/subagents/{name}/{version}` | `auth` Delete a version |

### Blobs and API keys

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/blobs/sha256/{digest}` | Download a blob by digest |
| POST | `/api/v1/api-keys` | `auth` Create a key (returns raw key once) |
| GET | `/api/v1/api-keys` | `auth` List keys (hashed, never shows raw) |
| DELETE | `/api/v1/api-keys/{id}` | `auth` Revoke a key |

### Web gallery

The server also serves a browser UI: `/`, `/skills`, and `/subagents` return the gallery SPA rather than JSON.

## Related pages

- [skillserver CLI](/skills/skillserver-cli/) - full publishing and management command reference
- [Native Manifest](/skills/native-manifest/) - the sync feed netclaw reads for skills and sub-agents
- [Bundling Resources with Skills](/skills/bundled-resources/) - archive artifacts and packaged resources
- [Skill Feeds](/skills/skill-feeds/) - configuring netclaw to consume from skill servers
- [Skills Overview](/skills/overview/) - format, lifecycle, source types
- [Security Model](/security/security-model/) - content scanning and trust model

## External resources

- [AgentSkills.io](https://agentskills.io) - the SKILL.md format spec
- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc) - the discovery protocol
- [netclaw-dev/skill-server on GitHub](https://github.com/netclaw-dev/skill-server) - source, issues, releases
