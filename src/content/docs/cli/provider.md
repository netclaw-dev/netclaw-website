---
title: "netclaw provider"
description: "Manage LLM providers."
---

Manage the LLM providers that netclaw talks to. Run `netclaw provider` for an interactive TUI, or use subcommands to script provider setup.

If you haven't run `netclaw init` yet, start there — it configures your first provider.

## Usage

```bash
netclaw provider                          # launch TUI
netclaw provider <subcommand> [options]   # CLI mode
```

## Provider Manager TUI

![Provider Manager TUI showing configured providers with health status](/screenshots/output/provider-manager.png)

On launch, the TUI probes every configured provider and shows health status:

| Indicator | Meaning |
|-----------|---------|
| `✓` | Healthy, models discovered |
| `⚠` | Unreachable or auth failure |
| `…` | Probe in progress |

Select a provider to view details (type, auth, endpoint, model count) or take action:

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate |
| `Enter` | Select / open details |
| `K` | Update API key (details view) |
| `R` | Remove provider (details view) |
| `V` | Re-validate connection (details view) |
| `Esc` | Back / quit |

The sentinel row `+ Add new provider...` starts an interactive add flow. Netclaw validates connectivity with a 20-second timeout and reports how many models it found.

OpenAI OAuth is only available through this TUI flow — select Add, choose OpenAI, then pick "ChatGPT Subscription" to authenticate with your existing account.

## Subcommands

### `provider list`

```bash
netclaw provider list
```

```
Name                 Provider               Auth       Endpoint
my-anthropic         Anthropic              ApiKey     https://api.anthropic.com
my-ollama            Ollama                 None       http://localhost:11434
```

This shows static config only — no live health probing. Open the TUI to see real-time provider health.

### `provider add`

```bash
netclaw provider add <name> <type> [--api-key <key>] [--endpoint <url>]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--api-key <key>` | API key for the provider | Prompted if required |
| `--endpoint <url>` | Custom endpoint URL | Provider default |
| `--auth <method>` | Auth method: `api-key` or `oauth-device` | Inferred from provider |
| `--github-host <url>` | GitHub Enterprise auth host (`github-copilot` only) | `https://github.com` |
| `--github-api-base <url>` | GitHub Enterprise API base (`github-copilot` only) | `https://api.github.com` |

Provider type and endpoint are stored in `~/.netclaw/config/netclaw.json`. Credentials are encrypted in [`secrets.json`](/cli/secrets/). Restart the daemon after adding a provider so it picks up the new config.

### `provider remove`

```bash
netclaw provider remove <name>
```

Netclaw blocks removal if any [model role](/cli/model/) (Main, Fallback, or Compaction) references the provider:

```
Error: Cannot remove provider 'my-anthropic' — referenced by model role(s): Main, Fallback
Run `netclaw model set` to reassign these roles first, or `netclaw model clear` for optional roles.
```

Reassign models first with [`netclaw model`](/cli/model/), then remove.

## Provider types

Pick Anthropic or OpenAI for hosted models, Ollama for fully local inference, or OpenRouter for access to models from multiple vendors through a single key.

| Type | Display Name | Default Endpoint | Auth |
|------|-------------|-----------------|------|
| `ollama` | Ollama | `http://localhost:11434` | None |
| `openai-compatible` | llama.cpp / vLLM / DwarfStar ds4 | `http://localhost:11434` | None |
| `openai` | OpenAI | `https://api.openai.com` | OAuth or API key |
| `anthropic` | Anthropic | `https://api.anthropic.com` | API key |
| `openrouter` | OpenRouter | `https://openrouter.ai/api/v1` | API key |
| `github-copilot` | GitHub Copilot | `https://api.githubcopilot.com` | OAuth (device) |
| `veniceai` | Venice.ai | `https://api.venice.ai/api/v1` | API key |

For hosted-provider setup details — including GitHub Copilot on GitHub Enterprise — see [Managed Providers](/configuration/managed-providers/).

## Examples

```bash
# Local Ollama on a remote GPU server
netclaw provider add my-ollama ollama --endpoint http://my-gpu-server:11434

# Anthropic with an API key
netclaw provider add my-anthropic anthropic --api-key sk-ant-...

# OpenAI with an API key
netclaw provider add my-openai openai --api-key sk-proj-...

# OpenRouter
netclaw provider add my-openrouter openrouter --api-key sk-or-...

# llama.cpp or vLLM behind an OpenAI-compatible endpoint
netclaw provider add my-llama openai-compatible --endpoint http://localhost:8080

# GitHub Copilot on GitHub Enterprise
netclaw provider add copilot-ghe github-copilot --auth oauth-device \
  --github-host https://github.example.com \
  --github-api-base https://github.example.com/api/v3

# Remove a provider
netclaw provider remove my-ollama
```

After adding a provider, assign it to a model role with [`netclaw model set`](/cli/model/).

## Override API keys with environment variables

Skip config files entirely by setting an environment variable:

```bash
export NETCLAW_Providers__my-anthropic__ApiKey="sk-ant-..."
```

Double underscores (`__`) separate config path segments. The `NETCLAW_` prefix is required.

## Related commands

- [`netclaw init`](/cli/init/) — set up your initial provider during first-run
- [`netclaw model`](/cli/model/) — assign providers to model roles
- [`netclaw doctor`](/cli/doctor/) — validate provider connectivity and config health
- [`netclaw status`](/cli/status/) — check the active provider and model at runtime
- [`netclaw secrets`](/cli/secrets/) — manage encrypted credentials in `secrets.json`

## Resources

- [Anthropic API keys](https://console.anthropic.com/settings/keys) — create and manage Anthropic keys
- [OpenAI API keys](https://platform.openai.com/api-keys) — create and manage OpenAI keys
- [OpenRouter keys](https://openrouter.ai/keys) — create and manage OpenRouter keys
- [OpenRouter model catalog](https://openrouter.ai/models) — browse available models
- [Ollama](https://ollama.com/) — install and run local models
- [llama.cpp server docs](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) — set up an OpenAI-compatible local server
