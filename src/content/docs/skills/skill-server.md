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
- Protects writes with API keys once a key exists. Reads are open, so agents fetch without credentials
- Runs as a single container with no external dependencies, just SQLite and the filesystem

## Deploy with Docker

Pull the image:

```bash
docker pull ghcr.io/netclaw-dev/skillserver:latest
```

Available for `linux/amd64` and `linux/arm64`.

### Set a bootstrap key

Generate and save a strong random secret in your password manager. Inject it through your deployment secret manager before the first startup. For a local setup, use a private Bash terminal:

```bash
read -r -s -p "Bootstrap API key: " SKILLSERVER_APIKEY
printf '\n'
export SKILLSERVER_APIKEY
```

The Compose example below maps `SKILLSERVER_APIKEY` to the server's `SKILLSERVER__APIKEY` variable. Keep the value out of committed YAML and `.env` files.

:::caution
A database with no API keys leaves publishing, deletion, and key management unauthenticated. Seed a key before exposing the server. Reads and discovery remain open even with keys configured; private content also needs a private network or proxy access policy.
:::

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
docker compose up -d
unset SKILLSERVER_APIKEY
```

Verify it's running:

```bash
curl http://localhost:8080/health
```

The bootstrap key is hashed and stored when the database has no keys. Next, [create a dedicated publishing key](#create-a-publishing-key) for your CLI or CI.

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

Publishing, deletion, and all key-management commands, including `api-key list`, require an existing valid key once authentication is enabled. Reads and discovery remain open. Every valid key has the same permissions; there is no publisher-only scope.

### Create a publishing key

Install the [`skillserver` CLI](/skills/skillserver-cli/#install) on your workstation or CI runner. It is a separate tool from the server container. In a private Bash terminal, authenticate with the bootstrap key or another existing valid key:

```bash
export SKILLSERVER_URL=https://skills.example.com
read -r -s -p "Existing SkillServer API key: " SKILLSERVER_API_KEY
printf '\n'
export SKILLSERVER_API_KEY
skillserver api-key list
skillserver api-key create --label ci-publish
unset SKILLSERVER_API_KEY
```

Use your server's HTTPS URL, or `http://localhost:8080` for local testing. `list` confirms authentication. Creation prints the new `sk-...` key once, along with its ID and label. Save the actual key immediately in your secret manager; it cannot be recovered from the server.

:::caution
The label is a name you choose. The credential is the key the server generates and registers. Saving an arbitrary string as a CI secret will not authenticate. Run key creation in a private terminal, never in shared CI logs.
:::

For GitHub Actions, save the returned value as a **`SKILLSERVER_API_KEY` secret**, then pass it to the CLI:

```yaml
- name: Publish skills
  env:
    SKILLSERVER_URL: https://skills.example.com
    SKILLSERVER_API_KEY: ${{ secrets.SKILLSERVER_API_KEY }}
  run: skillserver publish-all ./skills
```

Create the secret under repository **Settings → Secrets and variables → Actions**, or under the deployment environment if the job uses one. See [GitHub secret setup](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions).

Install the CLI and configure network access before this step. Use a separate CI key so you can revoke or rotate it independently.

### List, revoke, and rotate

With the CLI authenticated using an existing valid key:

```bash
skillserver api-key list
skillserver api-key delete 2
```

Listing shows IDs, labels, and dates, never raw keys or hashes. Replace `2` with the ID to revoke. The server refuses to delete the last remaining key. Creation also accepts `--expires-at <date>` for an expiring key.

To rotate, create a replacement, update the client or CI secret, and run `skillserver api-key list` authenticated with the replacement. Then revoke the old ID. No server restart or database reset is needed. If a newly created key is lost, create another using an existing valid key and revoke the lost key.

### Server bootstrap vs. client authentication

| Variable | Consumer | Purpose |
|----------|----------|---------|
| `SKILLSERVER__APIKEY` | Server | Seed the initial bootstrap key when the database has no keys |
| `SKILLSERVER_APIKEY` | This Compose example | Supply the value mapped to `SKILLSERVER__APIKEY` |
| `SKILLSERVER_API_KEY` | CLI and CI | Authenticate using a key already registered with the server |

Once any key exists in the database, `SKILLSERVER__APIKEY` is ignored on later startups. Changing it does not rotate existing credentials.

Generated keys use `sk-` plus 256 bits of randomness encoded as base64url. The server persists only SHA-256 hashes; creation is the only response containing the raw key.

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
| GET | `/api/v1/api-keys` | `auth` List key metadata (no raw keys or hashes) |
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
