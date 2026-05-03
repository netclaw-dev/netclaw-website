---
title: "netclaw provider"
description: "Manage LLM providers."
---

Add, remove, and inspect LLM providers. Run bare (`netclaw provider`) for an interactive TUI, or use subcommands for scripting.

## Usage

```bash
netclaw provider                          # launch TUI
netclaw provider <subcommand> [options]   # CLI mode
```

## Provider Manager TUI

`netclaw provider` with no subcommand opens the Provider Manager, a full-screen terminal UI.

![Provider Manager TUI showing configured providers with health status](/screenshots/output/provider-manager.png)

On launch, the TUI probes every configured provider and shows health status next to each one:

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

The sentinel row `+ Add new provider...` starts an interactive add flow. Connectivity is validated with a 20-second timeout, and you'll see the number of models discovered on success.

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

### `provider add`

```bash
netclaw provider add <name> <type> [--api-key <key>] [--endpoint <url>] [--auth <method>]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--api-key <key>` | API key for the provider | Prompted if required |
| `--endpoint <url>` | Custom endpoint URL | Provider default |
| `--auth <method>` | Auth method: `api-key` or `oauth-device` | Inferred from provider |

Provider type, auth method, and endpoint go to `~/.netclaw/config/netclaw.json`. Credentials go to `~/.netclaw/config/secrets.json` (encrypted). Restart the daemon after adding a provider.

#### OAuth device flow

OpenAI supports OAuth via device flow. Pass `--auth oauth-device`:

```bash
netclaw provider add my-openai openai --auth oauth-device
```

```
Starting OAuth device authorization...

  Visit:      https://auth.openai.com/...
  Enter code: ABCD-1234

Waiting for authorization......
Authorization successful!
Added provider 'my-openai' (openai) with OAuth authentication.
```

### `provider remove`

```bash
netclaw provider remove <name>
```

If model roles (Main, Fallback, or Compaction) reference the provider, removal is blocked:

```
Error: Cannot remove provider 'my-anthropic' — referenced by model role(s): Main, Fallback
Run `netclaw model set` to reassign these roles first, or `netclaw model clear` for optional roles.
```

Reassign models first with [`netclaw model`](/cli/model/), then remove.

## Provider types

| Type | Display Name | Default Endpoint | Auth |
|------|-------------|-----------------|------|
| `ollama` | Ollama | `http://localhost:11434` | None |
| `openai-compatible` | llama.cpp / vLLM | `http://localhost:11434` | None (optional API key) |
| `openai` | OpenAI | `https://api.openai.com` | OAuth or API key |
| `anthropic` | Anthropic | `https://api.anthropic.com` | API key |
| `openrouter` | OpenRouter | `https://openrouter.ai/api/v1` | API key |

## Examples

```bash
# Local Ollama on a remote GPU server
netclaw provider add my-ollama ollama --endpoint http://my-gpu-server:11434

# Anthropic with an API key
netclaw provider add my-anthropic anthropic --api-key sk-ant-...

# OpenRouter
netclaw provider add my-openrouter openrouter --api-key sk-or-...

# OpenAI via OAuth (uses your ChatGPT subscription)
netclaw provider add my-openai openai --auth oauth-device

# Remove a provider
netclaw provider remove my-ollama
```

## Environment variable override

Override a provider's API key without touching config files:

```bash
export NETCLAW_Providers__my-anthropic__ApiKey="sk-ant-..."
```

Double underscores (`__`) separate config path segments. The `NETCLAW_` prefix is required.

## Related commands

- [`netclaw init`](/cli/init/) — first-run wizard sets up your initial provider
- [`netclaw model`](/cli/model/) — assign providers to model roles (Main, Fallback, Compaction)
- [`netclaw doctor`](/cli/doctor/) — validates provider connectivity and config health
- [`netclaw status`](/cli/status/) — shows the active provider and model in the runtime
- [`netclaw secrets`](/cli/secrets/) — manage encrypted credentials in `secrets.json`

## Resources

- [Anthropic API keys](https://console.anthropic.com/settings/keys) — create and manage Anthropic keys
- [OpenAI API keys](https://platform.openai.com/api-keys) — create and manage OpenAI keys
- [OpenRouter keys](https://openrouter.ai/keys) — create and manage OpenRouter keys
- [Ollama](https://ollama.com/) — install and run local models
