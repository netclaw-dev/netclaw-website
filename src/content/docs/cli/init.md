---
title: "netclaw init"
description: "First-run setup wizard: provider, identity, security posture, enabled features, and health check."
---

`netclaw init` runs the bootstrap wizard — four or five steps depending on your security posture — that get netclaw from zero to a working chat session. Run it once on a fresh install. If you need to adjust channels, search, exposure mode, or skills after setup, use [`netclaw config`](/cli/config/) instead.

## Usage

```bash
netclaw init
```

## Before you begin

- **LLM provider credentials** — an [OpenRouter](https://openrouter.ai/docs) API key (easiest) or [Ollama](https://ollama.com/download) installed locally
- **Anthropic, OpenAI, or other cloud-provider API key** if not using OpenRouter

Channel tokens (Slack, Discord, Mattermost), search providers, browser automation, skill sources, and network exposure are all configured in `netclaw config` after init — you don't need them now.

## Wizard steps

The wizard counts steps dynamically: **4 steps** for Personal posture (the Enabled Features step is skipped), **5 steps** for Team or Public.

### Step 1 — Provider

Pick an LLM provider, enter credentials, and select a default model.

![Provider selection list](/screenshots/output/init-01-provider-list.png)

Available providers: Anthropic, GitHub Copilot, Ollama, OpenAI, llama.cpp / vLLM, OpenRouter, and Venice.ai. Self-hosted backends (Ollama, llama.cpp / vLLM) prompt for an endpoint URL next.

![Endpoint configuration](/screenshots/output/init-01-endpoint.png)

After credentials pass a connectivity check, you pick a default model from the discovered list.

![Model selection](/screenshots/output/init-01-model-select.png)

Add or swap providers later with [`netclaw provider`](/cli/provider/). Reassign model roles without re-running init with [`netclaw model`](/cli/model/).

### Step 2 — Identity

Four substeps in order: **agent name → communication style → your name → timezone**.

| Substep | Prompt | Notes |
|---------|--------|-------|
| Agent name | `Agent name:` | Defaults to `Netclaw` if left blank |
| Communication style | `Communication style:` | Choose: Concise & casual, Concise & formal, Detailed & casual, Detailed & formal |
| Your name | `Your name:` | Optional — used to personalize responses |
| Timezone | `Your timezone:` | Defaults to local system timezone |

![Identity step — communication style](/screenshots/output/init-02-identity.png)

:::note
Webhook URLs and workspace directories are **not** collected here — they're post-install settings in `netclaw config`.
:::

### Step 3 — Security Posture

![Security posture selection](/screenshots/output/init-02-security-posture.png)

Three postures are listed with a brief annotation; the hint line below explains the shell-access implications of each.

| Posture | Who uses it | Shell access | Enabled Features step |
|---------|------------|--------------|----------------------|
| **Personal** | Single user, high trust | Enabled with approval gates | Skipped (all features on by default) |
| **Team** | Multiple users, medium trust | Off | Shown (all features on by default) |
| **Public** | Untrusted users, low trust | Off | Shown (all features off by default) |

You can tighten or loosen per-channel behavior later in `netclaw config`.

### Step 4 — Enabled Features *(Team and Public only)*

Six toggles that control what's available across all audiences:

| Feature | Config key |
|---------|-----------|
| Memory | `Memory.Enabled` |
| Search | `Search.Enabled` |
| Skills | `SkillSync.Enabled` |
| Scheduling | `Scheduling.Enabled` |
| SubAgents | `SubAgents.Enabled` |
| Webhooks | `Webhooks.Enabled` |

Space to toggle, Enter to continue. Personal posture skips this step entirely — all features are on by default.

![Feature selection on Team posture](/screenshots/output/init-04-enabled-features.png)

All six features default to enabled on Team posture; Public posture defaults them all off.

### Step 5 — Health Check

Press Enter to run the health checks. The wizard validates config files, tests provider connectivity, and starts the daemon.

![Health check running](/screenshots/output/init-05-health-check.png)

On a clean pass — all probes green — the wizard writes config and launches `netclaw chat` automatically. No extra confirmation needed.

If any check fails, the wizard stays on the summary screen and shows:

```
Setup complete with warnings. Run `netclaw daemon start`, then `netclaw chat`. Adjust settings with `netclaw config`.
```

If init fails partway through, the files it already wrote stay on disk. Rerun `netclaw init` or inspect the saved config and run `netclaw doctor` before trying again.

## Existing install

Running `netclaw init` when `~/.netclaw/config/netclaw.json` already exists opens an action menu instead of the bootstrap wizard.

<!-- TODO(screenshots): init-existing-menu.png — capture after release; epic #55 -->

| Option | Effect |
|--------|--------|
| **Redo identity setup** | Re-runs the four-substep identity flow; provider and all other settings are kept |
| **Open configuration editor** | Launches `netclaw config` |
| **Start over from scratch** | Destructive reset — see below |
| **Cancel** | Exits with config untouched |

### Start over from scratch

Selecting "Start over from scratch" opens a scope chooser:

| Scope | What's deleted |
|-------|---------------|
| **Reset setup only** | Config, secrets, identity, and personality (`~/.netclaw/config/`, `~/.netclaw/identity/`, `~/.netclaw/soul/`). Memory, sessions, and skills are kept. |
| **Full reset** | Everything under `~/.netclaw/` |
| **Cancel** | Returns to the action menu |

Both destructive scopes require **two confirmations**. The default selection at each confirmation is Cancel — you have to move to the Yes option and confirm twice before anything is deleted.

<!-- TODO(screenshots): init-start-over-scope.png — capture after release; epic #55 -->

## What init creates

| File | Purpose |
|------|---------|
| `~/.netclaw/config/netclaw.json` | Main configuration (includes security posture and feature flags) |
| `~/.netclaw/config/secrets.json` | Encrypted credentials |
| `~/.netclaw/identity/` | Agent identity and personality |

## After init

```bash
# Verify everything is healthy
netclaw doctor

# Check daemon status
netclaw status

# Add channels, search, exposure, and skills
netclaw config
```

## Related commands

- [`netclaw config`](/cli/config/) — Post-install configuration for channels, search, exposure, skills, and webhooks
- [`netclaw doctor`](/cli/doctor/) — Diagnose config and connectivity issues
- [`netclaw status`](/cli/status/) — Check daemon health and connector states
- [`netclaw provider`](/cli/provider/) — Add or swap providers without re-running init
- [`netclaw model`](/cli/model/) — Reassign model roles without re-running init

## Resources

- [OpenRouter documentation](https://openrouter.ai/docs) — API keys, model catalog, rate limits
- [Ollama installation](https://ollama.com/download) — Local model runtime setup
- [Tailscale Funnel documentation](https://tailscale.com/kb/1223/funnel/) — Exposing services to the public internet via Tailscale (configure in `netclaw config` after init)
- [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — Exposing services via Cloudflare's network (configure in `netclaw config` after init)
