---
title: "netclaw init"
description: "Interactive setup wizard for providers, channels, security, and network exposure."
---

Interactive first-run setup. Configures your provider, security policy, channels, identity, skills, and network exposure in one pass, then starts the daemon.

## Usage

```bash
netclaw init
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| *(none)* | Launch the interactive wizard | — |

## Before you begin

Have these ready before starting:

- **LLM provider credentials** — an [OpenRouter](https://openrouter.ai/docs) API key (easiest) or [Ollama](https://ollama.com/download) installed locally
- **Slack tokens** (if using Slack) — Bot Token (`xoxb-...`) + App Token (`xapp-...`). See the [Slack quickstart](https://api.slack.com/start/quickstart)
- **Discord bot token** (if using Discord) — from the [Discord developer portal](https://discord.com/developers/docs/getting-started)

For local-only setup, that is enough. For non-local exposure modes, you may also need `tailscaled`, `cloudflared`, or a working reverse proxy depending on the mode you choose.


## Wizard steps

The wizard skips steps based on your choices, security posture, and feature selections.

### 1. LLM Provider

Pick a provider, enter credentials, select a model.

![Provider selection list](/screenshots/output/init-01-provider-list.png)

Netclaw supports many providers out of the box — pick one to start with here, and use [`netclaw provider`](/cli/provider/) to add more later. Self-hosted providers like Ollama need an endpoint URL:

![Endpoint configuration](/screenshots/output/init-01-endpoint.png)

![Ollama provider configuration](/screenshots/output/init-01-provider-ollama.png)

Once credentials pass a connectivity check, you pick a default model:

![Model selection](/screenshots/output/init-01-model-select.png)

### 2. Security posture

![Security posture selection](/screenshots/output/init-02-security-posture.png)

| Posture | Trust Level | Shell Access |
|---------|-------------|--------------|
| **Personal** | Single-user, high trust | Enabled with approval gates |
| **Team** | Multi-user, medium trust | Off by default |
| **Public** | Untrusted users, low trust | Off |

Every new shell command needs your sign-off the first time. You can override per-channel later.

### 3. Feature selection

Enable or disable memory, search, skills, scheduling, sub-agents, and webhooks. Skipped in Personal mode (everything on by default).

### 4. Channels

![Channel picker](/screenshots/output/init-03-channels.png)

Slack, Discord, [Mattermost](/channels/mattermost/), or any combination. Each one opens a sub-step for tokens and workspace config.

Slack needs a Bot Token (`xoxb-...`) and App Token (`xapp-...`) for [Socket Mode](https://api.slack.com/apis/socket-mode). It tests connectivity before moving on.

### 5. Web search

![Search toggle](/screenshots/output/init-04-search.png)

Enable web search so netclaw can pull live results during conversations.

### 6. Browser automation

![Browser automation toggle](/screenshots/output/init-05-browser.png)

Activate browser automation — page fetching, screenshots, form interaction.

### 7. Identity

![Owner/user identity](/screenshots/output/init-06-identity-user.png)

The owner identity determines who gets operator-level access.

![Agent name](/screenshots/output/init-06-identity-name.png)

![Personality style](/screenshots/output/init-06-identity-style.png)

![Timezone](/screenshots/output/init-06-identity-timezone.png)

![Webhook URL](/screenshots/output/init-06-identity-webhook.png)

![Workspace configuration](/screenshots/output/init-06-identity-workspaces.png)

Give your agent a name, pick a personality style (shapes tone in chat), set a timezone for scheduling, and optionally wire up a webhook URL for outbound notifications. The screenshots walk you through each field.

### 8. External skills

![Custom skills path](/screenshots/output/init-07-custom-skills-path.png)

Point to a local directory with custom skill definitions.

![External skills](/screenshots/output/init-07-external-skills.png)

Add remote skill servers or additional skill packages.

### 9. Skill feeds

![Skill feeds](/screenshots/output/init-08-skill-feeds.png)

Subscribe to skill feeds — curated skill collections from the community or your org.

### 10. Network exposure

![Exposure mode selection](/screenshots/output/init-09-exposure.png)

| Mode | Reachability | Requires |
|------|-------------|----------|
| `local` | Loopback only (this machine) | Nothing |
| `reverse-proxy` | Whatever your proxy exposes | Reverse proxy + trusted proxy list |
| `tailscale-serve` | Your [Tailscale](https://tailscale.com/kb/) tailnet | `tailscaled` running |
| `tailscale-funnel` | Public internet via Tailscale | `tailscaled` running |
| `cloudflare-tunnel` | Public internet via [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | `cloudflared` running |

The internet-facing modes (`tailscale-funnel`, `cloudflare-tunnel`) make you type an explicit confirmation because they expose the daemon to the internet.

![Webhook configuration](/screenshots/output/init-09-webhooks.png)

If you enabled webhooks, you'll configure inbound routes here.

### 11. Health check

![Health check running](/screenshots/output/init-10-health-check.png)

Validates config files, tests provider connectivity, verifies channel tokens, and checks tunnel or reverse-proxy prerequisites.

![Health check complete](/screenshots/output/init-10-health-check-complete.png)

If all checks pass, the daemon starts automatically.

If you picked a non-local exposure mode, the first successful daemon start also keeps a bootstrap pairing path available so the local CLI can finish remote-auth setup.

If something fails, the wizard tells you which check broke, shows exposure-mode validation failures directly, and suggests running `netclaw doctor` for detailed diagnostics.

If `netclaw init` fails partway through, the files it already wrote stay on disk. It is safe to rerun `netclaw init`, or inspect the saved config and use `netclaw doctor` before trying again.

## What it creates

| File | Purpose |
|------|---------|
| `~/.netclaw/config/netclaw.json` | Main configuration (includes security posture) |
| `~/.netclaw/config/secrets.json` | Encrypted credentials |
| `~/.netclaw/config/devices.json` | Paired device registry, including first-launch bootstrap device when needed |
| `~/.netclaw/identity/` | Agent identity and personality |

## After init

```bash
# Verify everything is healthy
netclaw doctor

# Check daemon status
netclaw status

# Start your first conversation
netclaw chat
```

## Related commands

- [`netclaw doctor`](/cli/doctor/) — Diagnose config and connectivity issues post-setup
- [`netclaw status`](/cli/status/) — Check daemon health and connector states
- [`netclaw provider`](/cli/provider/) — Change or add providers without re-running init
- [`netclaw model`](/cli/model/) — Reassign model roles without re-running init

## Resources

- [OpenRouter documentation](https://openrouter.ai/docs) — API keys, model catalog, rate limits
- [Slack Socket Mode](https://api.slack.com/apis/socket-mode) — How netclaw connects to Slack without a public endpoint
- [Tailscale Funnel documentation](https://tailscale.com/kb/1223/funnel/) — Exposing services to the public internet via Tailscale
- [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — Exposing services via Cloudflare's network
- [Traefik reverse proxy docs](https://doc.traefik.io/traefik/routing/routers/) — reverse-proxy option if you're exposing netclaw behind Traefik
