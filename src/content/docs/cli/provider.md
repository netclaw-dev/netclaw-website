---
title: "netclaw provider"
description: "Add, rename, validate and remove the LLM providers netclaw talks to, from a TUI or from scripts."
---

`netclaw provider` manages the LLM providers netclaw talks to. Run it bare for an interactive manager, or use subcommands to script provider setup. A provider is a named connection (a type, an endpoint and credentials). [`netclaw model`](/cli/model/) then assigns models from it to roles.

If you haven't run [`netclaw init`](/cli/init/) yet, start there. It configures your first provider.

## Usage

```bash
netclaw provider                          # interactive manager
netclaw provider <subcommand> [options]   # scriptable
```

Most of the manager and every subcommand run without the daemon. The exception is the **ChatGPT Subscription (browser)** sign-in, which needs a running daemon (`Could not reach the daemon. Is it running?`) because the CLI reads the OAuth tokens through a local-control endpoint on it. A CLI and daemon on different versions fail with `The daemon does not support the local-control provider OAuth read. Update the daemon and CLI to the same Netclaw version.` The device-code sign-in and `provider add --auth oauth-device` run in the CLI alone. The daemon restarts itself when `netclaw.json` changes. A credential you change in `secrets.json` needs a manual restart: `netclaw daemon stop` then `netclaw daemon start`, or `docker restart <container>`.

## Provider manager

```bash
netclaw provider
```

![Provider Manager listing lab-llama and my-ollama with a check mark, my-deepseek with a warning triangle, and five unconfigured providers below them](/screenshots/output/provider-manager.png)

The `my-deepseek` row carries the warning because its key is a placeholder, and the Provider column stops at 40 characters, so the long OpenAI-compatible label for `lab-llama` is cut with an ellipsis. Auth shows a dash for providers that need no credential.

On launch the manager probes every configured provider and shows its health. Providers you haven't configured appear as `(not configured)` rows, and **+ Add new provider...** starts the add flow.

| Indicator | Meaning |
|-----------|---------|
| `✓` | Healthy, models discovered |
| `⚠` | Unreachable or authentication failed |
| `…` | Probe in progress |

Select a provider to see its type, auth method, endpoint, status and model count:

```
Provider: lab-llama
  Type:     OpenAI-compatible (llama.cpp / vLLM / DwarfStar ds4)
  Auth:     -
  Endpoint: http://llm.example.internal:8080
  Status:   ✓ Healthy
  Models:   1 discovered
```

| Key | Where | Action |
|-----|-------|--------|
| `↑` / `↓` | List | Move |
| `Enter` | List | Open details, or start the add flow on a sentinel row |
| `Delete` | List | Remove the highlighted provider |
| `K` | Details | Update the API key |
| `N` | Details | Rename the provider |
| `R` | Details | Remove the provider |
| `V` | Details | Re-validate the connection |
| `C` / `O` | Device-code sign-in screen | Copy the code, open the verification URL in a browser. On the browser sign-in screen, `C` copies the URL when the browser didn't open. |
| `Esc` | Details and add flow | Go back. Does nothing on the list. |
| `Ctrl+Q` | Anywhere | Quit |

The add flow asks for the endpoint next. Here it is for an OpenAI-compatible server, with the default shown as a placeholder.

![Provider Manager add flow for OpenAI-compatible, naming the provider my-openai-compatible and showing an empty endpoint field with the default http://localhost:11434 as a placeholder](/screenshots/output/provider-add-openai-compatible.png)

The hint under the field says authentication is optional for this type. Type the server address with or without a `/v1` suffix. Both work, and the manager stores what you typed.

The connectivity check during an add gives up after 45 seconds, then reports how many models it found. Individual requests time out after 10 seconds for hosted providers and 30 seconds for self-hosted ones.

OpenAI offers two ChatGPT sign-ins as well as an API key: **ChatGPT Subscription (recommended)**, which uses a device code, and **ChatGPT Subscription (browser)**.

## Subcommands

### `provider list`

```bash
netclaw provider list
```

```
Name                 Provider               Auth       Endpoint
lab-llama            OpenAI-compatible (llama.cpp / vLLM / DwarfStar ds4) None       http://llm.example.internal:8080
my-ds                DeepSeek               ApiKey     https://api.deepseek.com/v1
```

`list` reads config only. It doesn't probe, so open the manager to see live health. With nothing configured it prints `No providers configured.` and a pointer to `provider add`.

### `provider add`

```bash
netclaw provider add <name> <type> [options]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--api-key <key>` | API key for the provider | Prompted, for providers that only take a key |
| `--endpoint <url>` | Endpoint URL | The type's default (see [types](#provider-types)) |
| `--auth <method>` | `api-key` or `oauth-device` | Inferred from the type |
| `--github-host <url>` | GitHub Enterprise auth host (`github-copilot` only) | `https://github.com` |
| `--github-api-base <url>` | GitHub Enterprise API base (`github-copilot` only) | `https://api.github.com` |

How the credential is chosen:

- **Key-only providers** (Anthropic, DeepSeek, OpenRouter, Venice.ai) prompt for the key when you leave out `--api-key`.
- **Self-hosted providers** (Ollama, OpenAI-compatible) need no key. Pass `--api-key` to send a Bearer token to a gateway.
- **`openai`** with neither `--api-key` nor `--auth` starts the OAuth device flow and waits for you to approve the code it prints. Pass `--api-key` to use a key.
- **`github-copilot`** only supports `--auth oauth-device`.

An unknown type lists the valid ones:

```
Error: Unknown provider type 'nosuchtype'.
Known types: anthropic, deepseek, github-copilot, ollama, openai, openai-compatible, openrouter, veniceai
```

Type and endpoint land in `~/.netclaw/config/netclaw.json`. Credentials are encrypted in [`secrets.json`](/cli/secrets/). For an OAuth sign-in, the access and refresh tokens are encrypted, but `Providers.<name>.OAuthTokenExpiry` is stored there as plain text because it's a date, not a secret. It never goes in `netclaw.json`, so a token refresh doesn't restart the daemon. If an older `OAuthTokenExpiry` is still in `netclaw.json`, `netclaw doctor --fix` moves it.

An endpoint must be a full `http://` or `https://` URL. A bare host is rejected before anything is written:

```
Error: Endpoint 'llm.example.internal:8080' is not an absolute http or https URL. Use a form like http://localhost:8080.
```

Provider names match without regard to case. `netclaw provider add Stub ...` when `stub` exists updates `stub`, and `remove`, `rename` and `model set` accept any spelling too.

### `provider rename`

```bash
netclaw provider rename <old-name> <new-name>
```

```
Renamed provider 'lab-ollama' to 'lab-a100'.
```

Rename changes the key under `Providers` and repoints every model definition that used the old name, so model roles keep working. If any were repointed, it adds `Reassigned model role(s): ...`. An unknown name prints `Error: Provider '<name>' not found.` and exits `1`.

### `provider remove`

```bash
netclaw provider remove <name>
```

```
Removed provider 'lab-a100'
```

An unknown name prints `Provider '<name>' not found.` and exits `1`.

`provider remove` refuses a provider that a model role still uses:

```
Error: Cannot remove provider 'lab-a100' ... referenced by model role(s): Main
Run `netclaw model set` to reassign these roles first, or `netclaw model clear` for optional roles.
```

It exits `1` and changes nothing. Reassign the role with [`netclaw model set`](/cli/model/#model-set), or drop an optional one with `netclaw model clear`, then remove the provider. If the `Models` section itself can't be resolved (a role names a definition that doesn't exist), `remove` stops with `Cannot remove provider ... the Models section in netclaw.json cannot be resolved` and tells you to repair it first. The Provider Manager's `R` and `Delete` keys apply the same check and show `Referenced by model role(s): ...`.

## Provider types

Pick Anthropic or OpenAI for hosted models, Ollama for local inference, OpenAI-compatible for llama.cpp or vLLM, or OpenRouter for many vendors behind one key.

| Type | Display name | Default endpoint | Auth |
|------|--------------|------------------|------|
| `anthropic` | Anthropic | `https://api.anthropic.com` | API key |
| `deepseek` | DeepSeek | `https://api.deepseek.com/v1` | API key |
| `github-copilot` | GitHub Copilot | `https://api.githubcopilot.com` | OAuth device flow |
| `ollama` | Ollama | `http://localhost:11434` | None |
| `openai` | OpenAI | `https://api.openai.com` | OAuth (device or browser) or API key |
| `openai-compatible` | OpenAI-compatible (llama.cpp / vLLM / DwarfStar ds4) | `http://localhost:11434` | None, optional key |
| `openrouter` | OpenRouter | `https://openrouter.ai/api/v1` | API key |
| `veniceai` | Venice.ai | `https://api.venice.ai/api/v1` | API key |

`openai-compatible` has no thinking dialect by default, so `netclaw model set ... --thinking` fails until you set `Providers:<name>:VendorOptions:ThinkingDialect` or `model set` detects llama.cpp. See [Output limit and thinking level](/cli/model/#output-limit-and-thinking-level).

For the self-hosted types, give the server address. `http://llm.example.internal:8080` and `http://llm.example.internal:8080/v1` both work ([endpoint rules](/configuration/self-hosted-providers/#endpoint-url)). See [Managed providers](/configuration/managed-providers/) for hosted-provider setup, including GitHub Copilot on GitHub Enterprise, and [Self-hosted providers](/configuration/self-hosted-providers/) for llama.cpp and vLLM.

## Examples

```bash
# Ollama on a GPU box
netclaw provider add my-ollama ollama --endpoint http://my-gpu-server:11434

# Anthropic with a key
netclaw provider add my-anthropic anthropic --api-key sk-ant-...

# OpenAI through your ChatGPT subscription
netclaw provider add my-openai openai --auth oauth-device

# DeepSeek
netclaw provider add my-deepseek deepseek --api-key sk-...

# OpenRouter
netclaw provider add my-openrouter openrouter --api-key sk-or-...

# llama.cpp or vLLM
netclaw provider add my-llama openai-compatible --endpoint http://llm.example.internal:8080

# GitHub Copilot on GitHub Enterprise
netclaw provider add copilot-ghe github-copilot --auth oauth-device \
  --github-host https://github.example.com \
  --github-api-base https://github.example.com/api/v3

# Give a provider a better name, then drop one you don't use
netclaw provider rename my-ollama lab-a100
netclaw provider remove my-openrouter
```

After adding a provider, assign it to a role with [`netclaw model set`](/cli/model/).

## Override API keys with environment variables

Set an environment variable instead of writing the key to disk:

```bash
export NETCLAW_Providers__my-anthropic__ApiKey="sk-ant-..."
```

Double underscores separate path segments, and the `NETCLAW_` prefix is required. Restart the daemon after you change one.

## Exit codes

`0` on success. `1` for missing arguments, an unknown type, an unknown provider, a provider a model role still uses, or a failed OAuth flow.

## Related pages

- [`netclaw init`](/cli/init/): set up your first provider
- [`netclaw model`](/cli/model/): assign provider models to roles
- [`netclaw doctor`](/cli/doctor/): validate provider configuration
- [`netclaw status`](/cli/status/): see the provider and model the daemon is using
- [`netclaw secrets`](/cli/secrets/): manage encrypted credentials

## Resources

- [Anthropic API keys](https://console.anthropic.com/settings/keys): create and manage Anthropic keys
- [OpenAI API keys](https://platform.openai.com/api-keys): create and manage OpenAI keys
- [DeepSeek API keys](https://platform.deepseek.com/api_keys): create and manage DeepSeek keys
- [OpenRouter keys](https://openrouter.ai/keys): create and manage OpenRouter keys
- [Ollama](https://ollama.com/): install and run local models
- [llama.cpp server docs](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md): run an OpenAI-compatible server
