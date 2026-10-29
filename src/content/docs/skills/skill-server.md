---
title: "Skill server"
description: "Run a self-hosted skill server for skills and subagents, secure it with API keys, and point netclaw at it."
---

SkillServer is a self-hosted skill registry: a private NuGet feed or npm registry, but for [SKILL.md](https://agentskills.io) files and netclaw subagents. Host it behind your firewall, publish your proprietary skills and subagents, and every netclaw instance on the network syncs from it.

Source code and releases: [github.com/netclaw-dev/skill-server](https://github.com/netclaw-dev/skill-server)

It implements two open standards and adds a native feed for netclaw:

- [Cloudflare Agent Skills Discovery RFC v0.2.0](https://github.com/cloudflare/agent-skills-discovery-rfc): discovery through `/.well-known/agent-skills/index.json`
- [AgentSkills.io](https://agentskills.io): the `SKILL.md` format
- [Native manifest](/skills/native-manifest/): a versioned `/manifest.json` feed that also carries subagents

Any agent that speaks the RFC can read skills from your server. netclaw takes skills and archives from the RFC index and subagents from the native manifest.

## What it does

- Stores versioned skills and subagents in content-addressable blob storage (SHA-256)
- Serves the RFC index and the native manifest that clients poll
- Packages skills with supporting files as deterministic [archives](/skills/bundled-resources/)
- Ships a web gallery for browsing skills and subagents
- Protects writes with API keys once a key exists. Reads are open, so agents fetch without credentials
- Runs as a single container with SQLite and the filesystem, nothing else

## Deploy with Docker

Pull the image. It's published for `linux/amd64` and `linux/arm64`:

```bash
docker pull ghcr.io/netclaw-dev/skillserver:latest
```

### Set a bootstrap key

Generate a strong random secret and keep it in your password manager. In production, inject it through your secret manager before the first start. For a local setup, read it into a variable in a private Bash terminal:

```bash
read -r -s -p "Bootstrap API key: " SKILLSERVER_APIKEY
printf '\n'
export SKILLSERVER_APIKEY
```

The Compose file below maps `SKILLSERVER_APIKEY` to the server's `SKILLSERVER__APIKEY`. Keep the value out of committed YAML and `.env` files.

:::caution
A database with no API keys leaves publishing, deletion and key management open to anyone who can reach the server. Seed a key before you expose it. Reads and discovery stay open even with keys, so private content also needs a private network or a proxy access policy.
:::

### Run it with Docker Compose

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

Start it, clear the variable from your shell, and check the health endpoint:

```bash
docker compose up -d
unset SKILLSERVER_APIKEY
curl http://localhost:8080/health
```

The server hashes and stores the bootstrap key when the database has none. Next, [create a dedicated publishing key](#create-a-publishing-key) for your CLI or CI.

### Before you go to production

- Put a reverse proxy (Caddy, nginx, Traefik) in front for TLS.
- Set `SKILLSERVER__BASEURL` to your public URL, like `https://skills.internal.example.com`, so discovery responses carry correct absolute URLs.
- Mount `/data` on persistent storage. If the volume is lost, you re-publish everything.

All state lives in `SKILLSERVER__DATAPATH`, so a backup of that volume is a backup of the server.

## Publish and connect

The [`skillserver` CLI](/skills/skillserver-cli/) publishes and manages content from your terminal or CI. The essentials:

```bash
# Publish one skill, or every skill directory under a parent
skillserver publish ./my-skill
skillserver publish-all ./skills

# Publish subagents. The version comes from --version, not frontmatter.
skillserver publish-subagent ./release-notes-writer.md --version 1.0.0
skillserver publish-subagents ./subagents --version 1.0.0
```

Publishing a version that already exists is skipped, so `publish-all` and `publish-subagents` are safe to run on every CI push. A skill with a `references/`, `scripts/` or `assets/` folder becomes an [archive](/skills/bundled-resources/) that keeps relative paths and executable bits. A bare `SKILL.md` publishes as a lightweight `skill-md` artifact. The [Distributing subagents](/skills/distributing-subagents/) guide covers a full subagent publish.

To connect a netclaw instance, add the server as a feed in `netclaw config` under **Skill Sources**, or in `netclaw.json`:

```json
{ "SkillFeeds": { "Feeds": [ { "Name": "my-server", "Url": "https://skills.internal.example.com", "Enabled": true } ] } }
```

The daemon syncs at startup and on a timer. To pull something you just published, run `netclaw skill sync`. Skills land in `~/.netclaw/skills/.server-feeds/<feed>/` and subagents in `~/.netclaw/agents/.server-feeds/<feed>/`. netclaw restores a changed skill file at the next sync, but it leaves an edited subagent file alone. [Skill feeds](/skills/skill-feeds/) covers intervals, authentication and the sync output.

## Manage API keys

Publishing, deleting and every key command, including `api-key list`, need a valid key once authentication is on. Reads and discovery stay open. Every valid key has the same permissions, because there's no publish-only scope.

### Create a publishing key

Install the [`skillserver` CLI](/skills/skillserver-cli/#install) on your workstation or CI runner. It's a separate tool from the server container. In a private Bash terminal, authenticate with the bootstrap key (or any valid key) and create one for CI:

```bash
export SKILLSERVER_URL=https://skills.example.com
read -r -s -p "Existing SkillServer API key: " SKILLSERVER_API_KEY
printf '\n'
export SKILLSERVER_API_KEY
skillserver api-key list
skillserver api-key create --label ci-publish
unset SKILLSERVER_API_KEY
```

Use your server's HTTPS URL, or `http://localhost:8080` for local testing. `list` proves your key works. `create` prints the new `sk-...` key once, with its ID and label. Copy it into your secret manager right away. The server keeps only a hash, so it can't show the key again.

:::caution
The label is a name you pick, and the key is what authenticates. A made-up string saved as a CI secret won't work. Create keys in a private terminal and never in shared CI logs.
:::

In GitHub Actions, save the key as a `SKILLSERVER_API_KEY` secret and hand it to the CLI:

```yaml
- name: Publish skills
  env:
    SKILLSERVER_URL: https://skills.example.com
    SKILLSERVER_API_KEY: ${{ secrets.SKILLSERVER_API_KEY }}
  run: skillserver publish-all ./skills
```

Create the secret under repository **Settings → Secrets and variables → Actions**, or under the environment if the job uses one. GitHub's [secrets guide](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions) has the details. Give CI its own key so you can revoke or rotate it without touching anyone else's.

### List, revoke and rotate keys

```bash
skillserver api-key list
skillserver api-key delete 2
```

`list` shows IDs, labels and dates, never raw keys or hashes. Replace `2` with the ID to revoke. The server won't delete the last remaining key. `create` also takes `--expires-at <date>` for a key that expires.

To rotate, create a replacement and update the client or CI secret. Then run `skillserver api-key list` with the new key to confirm it works, and delete the old ID. No restart or database reset needed. If you lose a freshly created key, create another with any valid key and revoke the lost one.

## Reference

### Configuration

All configuration is through environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SKILLSERVER__DATAPATH` | `./data` | SQLite database and blob storage directory |
| `SKILLSERVER__BASEURL` | `http://localhost:8080` | Base URL for the absolute URLs in discovery responses |
| `SKILLSERVER__APIKEY` | none | Bootstrap API key, seeded on first run if the database has no keys |
| `ASPNETCORE_URLS` | `http://+:8080` | Listen address and port |

### Which key variable is which

| Variable | Used by | Purpose |
|----------|---------|---------|
| `SKILLSERVER__APIKEY` | The server | Seeds the initial key when the database has none |
| `SKILLSERVER_APIKEY` | The Compose example above | Carries the value into `SKILLSERVER__APIKEY` |
| `SKILLSERVER_API_KEY` | The CLI and CI | Authenticates with a key the server already knows |

Once any key exists, the server ignores `SKILLSERVER__APIKEY` on later starts. Changing it doesn't rotate anything. Generated keys are `sk-` plus 256 bits of randomness encoded as base64url, and the server stores only SHA-256 hashes.

### Feeds

| Feed | Path | Contents |
|------|------|----------|
| RFC index | `/.well-known/agent-skills/index.json` | Skills with type, URL and digest. Archives are described here too. |
| Native manifest | `/manifest.json` | Skills and subagents, with version history |

See [Native manifest](/skills/native-manifest/) for the tree.

### API endpoints

Reads are open. Rows marked `auth` need an `Authorization: Bearer <key>` header.

#### Discovery and feeds

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/api/v1/info` | Server version |
| GET | `/.well-known/agent-skills/index.json` | RFC discovery index |
| GET | `/manifest.json` | Native manifest root |
| GET | `/skills/v1/index.json` | Native skill collection index |
| GET | `/skills/v1/pages/{page}.json` | One page of skills |
| GET | `/skills/v1/{name}/index.json` | One skill and its versions |
| GET | `/skills/v1/{name}/versions/{version}.json` | One skill version |
| GET | `/subagents/v1/index.json` | Native subagent collection index |
| GET | `/subagents/v1/pages/{page}.json` | One page of subagents |
| GET | `/subagents/v1/{name}/index.json` | One subagent and its versions |
| GET | `/subagents/v1/{name}/versions/{version}.json` | One subagent version |

#### Skills

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/skills` | List all (`?q=`, `?skip=`, `?take=`) |
| GET | `/api/v1/skills/{name}` | All versions of a skill |
| GET | `/api/v1/skills/{name}/latest` | Latest version metadata |
| GET | `/api/v1/skills/{name}/{version}` | One version's metadata |
| GET | `/api/v1/skills/{name}/{version}/SKILL.md` | Download `SKILL.md` |
| GET | `/api/v1/skills/{name}/{version}/archive.zip` | Download the archive |
| GET | `/api/v1/skills/{name}/{version}/resources` | List bundled resources (path, digest, mode) |
| GET | `/api/v1/skills/{name}/{version}/{*path}` | Download one resource file |
| POST | `/api/v1/skills/check-updates` | Batch update check |
| POST | `/api/v1/skills` | `auth` Upload a version (multipart/form-data) |
| DELETE | `/api/v1/skills/{name}/{version}` | `auth` Delete a version |

#### Subagents

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/subagents` | List all |
| GET | `/api/v1/subagents/{name}` | All versions of a subagent |
| GET | `/api/v1/subagents/{name}/{version}` | One version's metadata |
| GET | `/api/v1/subagents/{name}/{version}/agent.md` | Download the definition |
| POST | `/api/v1/subagents` | `auth` Upload a version |
| DELETE | `/api/v1/subagents/{name}/{version}` | `auth` Delete a version |

#### Blobs and API keys

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/blobs/sha256/{digest}` | Download a blob by digest |
| POST | `/api/v1/api-keys` | `auth` Create a key (returns the raw key once) |
| GET | `/api/v1/api-keys` | `auth` List key metadata |
| DELETE | `/api/v1/api-keys/{id}` | `auth` Revoke a key |

### Web gallery

The server also serves a browser UI. `/`, `/skills` and `/subagents` return the gallery SPA instead of JSON.

## Related pages

- [`skillserver` CLI](/skills/skillserver-cli/): the publishing and management commands
- [Skill feeds](/skills/skill-feeds/): point netclaw at a server
- [Native manifest](/skills/native-manifest/): how subagents reach netclaw
- [Distributing subagents](/skills/distributing-subagents/): publish a subagent end to end
- [Skills overview](/skills/overview/): tiers, precedence and trust

## Resources

- [AgentSkills.io](https://agentskills.io): the `SKILL.md` format spec
- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc): the discovery protocol
- [netclaw-dev/skill-server](https://github.com/netclaw-dev/skill-server): source, issues and releases
