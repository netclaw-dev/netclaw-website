---
title: Managed Providers
description: Configure cloud-hosted LLM providers (OpenRouter, Anthropic, OpenAI, GitHub Copilot, Venice.ai, DeepSeek) and know what an OpenAI-compatible cloud endpoint has to support.
---

Managed providers are cloud-hosted LLM services that netclaw connects to over HTTPS. Each authenticates with an API key or OAuth: OpenRouter, Anthropic, OpenAI, GitHub Copilot, Venice.ai, and DeepSeek.

Provider config lives in two files. Non-secret fields (type, endpoint, auth method) go in `~/.netclaw/config/netclaw.json`. Credentials go in `~/.netclaw/config/secrets.json`, which is [encrypted at rest](/security/secrets/). Write plaintext values and netclaw encrypts them on first read. Environment variables override both.

If you're setting up netclaw for the first time, [`netclaw init`](/cli/init/) handles provider selection interactively. This page covers manual configuration and the details behind each provider type.

For self-hosted inference (Ollama, llama.cpp, vLLM), see [Self-Hosted Providers](/configuration/self-hosted-providers/).

## Provider summary

| Type | Display Name | Default Endpoint | Auth | Key Source |
|------|-------------|-----------------|------|------------|
| `openrouter` | OpenRouter | `https://openrouter.ai/api/v1` | API key | [openrouter.ai/keys](https://openrouter.ai/keys) |
| `anthropic` | Anthropic | `https://api.anthropic.com` | API key | [console.anthropic.com](https://console.anthropic.com/settings/keys) |
| `openai` | OpenAI | `https://api.openai.com` | ChatGPT OAuth (device or browser) or API key | [platform.openai.com](https://platform.openai.com/api-keys) |
| `github-copilot` | GitHub Copilot | `https://api.githubcopilot.com` | OAuth (device) | GitHub Copilot subscription |
| `veniceai` | Venice.ai | `https://api.venice.ai/api/v1` | API key | [venice.ai/settings/api](https://venice.ai/settings/api) |
| `deepseek` | DeepSeek | `https://api.deepseek.com/v1` | API key | [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys) |

## Configuration schema

Each provider is a named entry under the `Providers` section. The key is a name you choose, and you can have several entries of one type (two Anthropic providers with different keys, say).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Type` | string | `"ollama"` | Provider SDK: `openrouter`, `anthropic`, `openai`, `github-copilot`, `veniceai`, or `deepseek` for managed providers. Always set this explicitly. |
| `Endpoint` | string | `""` | Base URL. Leave empty to use the provider's default |
| `ApiKey` | string? | `null` | API key. Store in `secrets.json`, never `netclaw.json` |
| `AuthMethod` | enum | `None` | `None`, `ApiKey`, `OAuthDevice`, or `OAuthPkce` |
| `VendorOptions` | object | `{}` | Per-vendor switches: `GitHubHost` and `GitHubApiBase` (Copilot), `IncludeVeniceSystemPrompt` (Venice.ai), `ExcludeReasoning` (OpenRouter). Self-hosted types have their own, see [Self-hosted providers](/configuration/self-hosted-providers/) |

`netclaw provider add <name> <type>` takes `--api-key`, `--endpoint`, `--auth` (`api-key` or `oauth-device`), and for Copilot Enterprise `--github-host` and `--github-api-base`. Browser OAuth (PKCE) is only available from the TUI.

## Config file examples

### `netclaw.json`: non-secret fields

```json
{
  "Providers": {
    "openrouter": {
      "Type": "openrouter",
      "Endpoint": "https://openrouter.ai/api/v1"
    },
    "my-anthropic": {
      "Type": "anthropic"
    },
    "my-openai": {
      "Type": "openai",
      "AuthMethod": "OAuthPkce"
    }
  }
}
```

### `secrets.json`: encrypted credentials

```json
{
  "Providers": {
    "openrouter": { "ApiKey": "sk-or-v1-..." },
    "my-anthropic": { "ApiKey": "sk-ant-..." }
  }
}
```

OAuth providers (OpenAI via ChatGPT, GitHub Copilot) don't need an `ApiKey` in `secrets.json`. netclaw stores and refreshes the tokens after you authenticate.

You can also manage credentials with [`netclaw secrets set`](/cli/secrets/) instead of editing `secrets.json` directly.

After adding a provider, assign it to a [model role](/configuration/models/) (Main, Fallback, or Compaction) with [`netclaw model set`](/cli/model/).

## OpenRouter

One API key, hundreds of models. OpenRouter proxies requests to Anthropic, OpenAI, Meta, Mistral, and others, so you don't need a separate account with each vendor.

```bash
netclaw provider add openrouter openrouter --api-key sk-or-v1-...
```

Or configure manually in `netclaw.json`:

```json
{
  "Providers": {
    "openrouter": {
      "Type": "openrouter"
    }
  }
}
```

The endpoint defaults to `https://openrouter.ai/api/v1`. Override it only for a proxy.

Get your key at [openrouter.ai/keys](https://openrouter.ai/keys). Browse available models in the [OpenRouter model catalog](https://openrouter.ai/models).

## Anthropic

Connects directly to Claude models via the Anthropic API.

```bash
netclaw provider add my-anthropic anthropic --api-key sk-ant-...
```

The endpoint defaults to `https://api.anthropic.com`. Netclaw sends the `x-api-key` header and `anthropic-version: 2023-06-01` on probe requests.

Without a configured limit, Anthropic replies get a 32000-token output limit, capped to the model maximum the Anthropic Models API reports. Replies used to stop at 1024 tokens, so the cost per call can rise. Thinking levels come from the capabilities the API reports for each model. `max` is Anthropic's highest level and needs an output limit. Set both per model with [`netclaw model set --max-output-tokens --thinking`](/configuration/models/#output-limit-and-thinking-level). OpenRouter, OpenAI, Venice.ai and DeepSeek get the same 32000 default.

Get your key at [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys). See the [Anthropic API docs](https://docs.anthropic.com/en/api/getting-started) for model versions and usage limits.

## OpenAI

OpenAI has three auth methods. Two use your ChatGPT subscription: a device-code flow (**ChatGPT Subscription (recommended)**) and a browser flow with [OAuth PKCE](https://datatracker.ietf.org/doc/html/rfc7636) (**ChatGPT Subscription (browser)**). The third is an API key that bills platform.openai.com credits.

### ChatGPT subscription (OAuth)

If you already pay for ChatGPT Plus or Pro, use this and skip API keys. Open the Provider Manager:

```bash
netclaw provider   # opens Provider Manager
```

Select **+ Add new provider**, choose **OpenAI**, then pick **ChatGPT Subscription (recommended)**.

You can also start the OAuth device flow from the CLI without the TUI:

```bash
netclaw provider add my-openai openai --auth oauth-device
```

The device flow works on a headless server: netclaw prints a code and a URL, and you approve on any machine with a browser. Only the browser variant needs a browser on the same machine as netclaw.

netclaw refreshes the ChatGPT token before it expires. If the Codex backend answers a request with HTTP 401 anyway, netclaw forces one refresh and retries the request once. If the refresh fails, open `netclaw provider`, select the unhealthy provider, and re-authenticate.

A refresh that OpenAI rejects for good (`invalid_grant`, `refresh_token_reused`, `refresh_token_expired` or `refresh_token_invalidated`) raises the `provider.auth.expired` alert with the code in `reason`, and `netclaw status` lists the provider as `auth-failed`. Only a new sign-in helps. A transient failure (network, timeout, HTTP 5xx or 429) gets one retry after 2 seconds. The tokens and their expiry live in `secrets.json`. If the daemon stops at startup with an error that names `Providers:<name>`, an older build left an encrypted `OAuthTokenExpiry` there, and signing in again in `netclaw provider` fixes it.

netclaw discovers your ChatGPT models live. After you authenticate it probes OpenAI's Codex backend and reads each model's context window and modalities from the response, so new models show up without a netclaw release. With ChatGPT sign-in, netclaw talks to `https://chatgpt.com/backend-api/codex`, not `api.openai.com`.

### API key

```bash
netclaw provider add my-openai openai --api-key sk-proj-...
```

Get your key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). With API key auth, netclaw discovers available models automatically via `/v1/models`.

## GitHub Copilot

Run inference through your GitHub Copilot subscription. There's no API key. Auth is GitHub's [OAuth device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow):

```bash
netclaw provider add copilot github-copilot --auth oauth-device
```

netclaw prints a one-time code and a verification URL. Enter the code, approve, and you're connected. It stores the GitHub OAuth token in `secrets.json` and exchanges it on demand for a short-lived Copilot token that stays in memory. Models are whatever your subscription exposes, discovered from Copilot's API.

Requires an active [GitHub Copilot](https://github.com/features/copilot) subscription.

### GitHub Enterprise

By default the provider authenticates against github.com. For GitHub Enterprise Server or Enterprise Cloud with data residency, point auth at your enterprise host with two vendor options:

| Vendor option | Default | Controls |
|---------------|---------|----------|
| `GitHubHost` | `https://github.com` | The OAuth auth host: device-code, OAuth token, and token-refresh endpoints (`<host>/login/device/code`, `<host>/login/oauth/access_token`) |
| `GitHubApiBase` | `https://api.github.com` | The API base for the Copilot token exchange (`<api-base>/copilot_internal/v2/token`) |

Set them from the CLI with `--github-host` and `--github-api-base`:

```bash
netclaw provider add copilot-ghe github-copilot --auth oauth-device \
  --github-host https://github.example.com \
  --github-api-base https://github.example.com/api/v3
```

Pass `--github-host` alone and netclaw derives the API base for you: `github.com` becomes `https://api.github.com`, a `*.ghe.com` data-residency tenant becomes `api.<host>`, and any other host (GitHub Enterprise Server) becomes `<host>/api/v3`. Both values must be HTTPS, and `GitHubHost` must be a bare origin with no path.

In the TUI, **+ Add new provider** then **GitHub Copilot** offers a **GitHub.com / GitHub Enterprise** auth-host choice. Pick **GitHub Enterprise** and enter the host (the API base is prefilled from it).

The stored config looks like this:

```json
{
  "Providers": {
    "copilot-ghe": {
      "Type": "github-copilot",
      "AuthMethod": "OAuthDevice",
      "VendorOptions": {
        "GitHubHost": "https://github.example.com",
        "GitHubApiBase": "https://github.example.com/api/v3"
      }
    }
  }
}
```

#### Auth host and model endpoint

Two different hosts are in play, and they're set separately:

- **Auth plane:** `GitHubHost` and `GitHubApiBase` decide where device OAuth, token refresh, and the Copilot token exchange happen. This is what GitHub Enterprise changes.
- **Model plane:** the provider `Endpoint` decides where chat and `/models` traffic goes. Leave it at the default (`https://api.githubcopilot.com`) and netclaw sends chat to the host the token exchange reports in `endpoints.api`, which is the tenant host data residency requires. Set `--endpoint` only to force a specific host, such as a corporate proxy. An explicit override always wins.

For a standard GHE setup, set `GitHubHost` and `GitHubApiBase` and leave `Endpoint` alone. The model host is discovered at token-exchange time.

On a headless server, ambient GitHub environment variables seed the host during `--auth oauth-device` setup: `GitHubHost` from the first of `COPILOT_GH_HOST`, `GHE_HOST`, `GH_HOST`, or `GITHUB_SERVER_URL`, and `GitHubApiBase` from `GITHUB_API_URL`. An explicit flag always wins over the environment.

#### Verify and troubleshoot

Open `netclaw provider` after setup. The probe hits `/models` at the token's real host, so a misconfigured enterprise host fails at setup instead of silently reporting healthy and breaking on the first chat.

| Symptom | Cause | Fix |
|---------|-------|-----|
| Device flow never shows a code | Wrong `GitHubHost`, so `login/device/code` is unreachable | Point `--github-host` at your enterprise host origin (HTTPS, no path) |
| `token exchange failed` | Wrong `GitHubApiBase`, or the host doesn't serve `copilot_internal/v2/token` | Set `--github-api-base` to the enterprise API base (`<host>/api/v3` for GHES) |
| `authorization expired` on a long run | OAuth token expired and refresh failed against the enterprise host | Re-authenticate: `netclaw provider remove <name>` then re-add with `--auth oauth-device` |
| `token exchange did not return an API host (endpoints.api)` | Token isn't scoped to a data-residency host | Re-authenticate, or set an explicit `--endpoint` to override the model host |

## Venice.ai

[Venice.ai](https://venice.ai/) is privacy-focused inference with an OpenAI-style API. Auth is an API key:

```bash
netclaw provider add venice veniceai --api-key vk-...
```

The endpoint defaults to `https://api.venice.ai/api/v1`. Get a key at [venice.ai/settings/api](https://venice.ai/settings/api).

By default, netclaw tells Venice not to prepend its own system prompt (`include_venice_system_prompt = false`), so your [identity grounding](/architecture/design-philosophy/) stays the first system message and the context-budget math stays correct. If you actually want Venice's default prompt, opt in with a vendor option:

```json
{
  "Providers": {
    "venice": {
      "Type": "veniceai",
      "VendorOptions": { "IncludeVeniceSystemPrompt": true }
    }
  }
}
```

## DeepSeek

[DeepSeek](https://api-docs.deepseek.com/) is a hosted inference provider. Auth is an API key:

```bash
netclaw provider add deepseek deepseek --api-key sk-...
```

The endpoint defaults to `https://api.deepseek.com/v1`. Get a key at [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys).

DeepSeek's `/models` endpoint doesn't report capabilities, so netclaw fills them in itself, and only for model ids that start with `deepseek-v4-`. Those get a 1,000,000-token context window and text-only input and output. Any other model id is listed with unknown limits, so set the context window yourself in the model definition. Model ids change, so take the current ones from the [DeepSeek API docs](https://api-docs.deepseek.com/) or from the model list in `netclaw model discover`. The `deepseek` provider uses the `DeepSeek` thinking dialect, so `netclaw model set --thinking` and `Thinking` on the definition apply: `off` turns thinking off, and `low`, `high` and `max` turn it on at that effort. There is no `medium`. DeepSeek's `/models` reports no thinking capability, so `model set` offers only `off` until you edit `Thinking` in `netclaw.json` by hand.

## Provider Manager

Run `netclaw provider` to open the Provider Manager. It probes each configured provider and shows whether it's reachable and authenticated:

![Provider Manager listing lab-llama and my-ollama with a check mark, my-deepseek with a warning triangle, and five unconfigured providers below them](/screenshots/output/provider-manager.png)

One row per configured provider, with the unconfigured types listed below so you can add them. DeepSeek is the second configured row here, and its warning triangle means the placeholder key was rejected.

| Indicator | Meaning |
|-----------|---------|
| `✓` | Healthy, models discovered |
| `⚠` | Unreachable or auth failure |
| `…` | Probe in progress |

Select a provider to manage it:

| Key | Action |
|-----|--------|
| `K` | Update API key |
| `R` | Remove provider |
| `N` | Rename (changes the config key only, so update any definition that names it) |
| `V` | Re-validate connection |

Delete removes the highlighted provider from the list.

## Environment variable overrides

Skip config files entirely by setting environment variables with the `NETCLAW_` prefix. Double underscores (`__`) separate path segments, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider):

```bash
# Override a provider's API key
export NETCLAW_Providers__openrouter__ApiKey="sk-or-v1-..."

# Point a model role at a provider (named definition + role reference)
export NETCLAW_Models__Definitions__claude__Provider="openrouter"
export NETCLAW_Models__Definitions__claude__ModelId="anthropic/claude-sonnet-4"
export NETCLAW_Models__Roles__Main="claude"
```

Environment variables take highest priority, overriding both `netclaw.json` and `secrets.json`. On Linux, variable names are case-sensitive: `NETCLAW_Providers__openrouter__ApiKey` won't match `NETCLAW_PROVIDERS__OPENROUTER__APIKEY`. Changes to environment variables need a manual restart.

## Probe and health checks

The Provider Manager, `netclaw provider add`, and `netclaw model discover` probe a provider by hitting its model-listing endpoint, with a 10-second timeout for hosted providers.

Common probe errors:

| HTTP status | Message (provider name filled in) |
|-------------|---------|
| 401 | `Invalid credentials. Double-check your <provider> credentials.` |
| 403 | `Access denied. Your <provider> credentials may lack model-listing permissions.` |
| 404 | `The <provider> models API was not found at <url>. Check the endpoint URL, or the service may be down.` |
| 429 | `Rate limited by <provider>. Wait a moment and try again.` |
| 5xx | The provider returned an error, so it may be having issues |
| Connection failure | `Connection failed: <reason>`: check the endpoint and connectivity |

When the provider's error body says why, the 401 and 403 messages end with that detail. URLs in these messages drop any username, password, and query string.

To test a provider now, open `netclaw provider` and press `V`, or run `netclaw model discover <name>`. [`netclaw doctor`](/cli/doctor/) validates the config shape and credentials for every provider a role uses, but it doesn't call the provider.

## OpenAI-compatible cloud endpoints

Azure AI Foundry, OVHcloud AI Endpoints, and similar gateways speak the OpenAI chat API, so people point netclaw's `openai-compatible` provider at them. That provider is built for local servers (llama.cpp, vLLM). Hosted gateways that enforce the OpenAI schema strictly can reject it, and some do.

What netclaw sends on every streaming request, on top of the standard `model`, `messages`, `tools`, and `stream` fields:

| Field | Why | Strict gateways |
|-------|-----|-----------------|
| `stream_options.include_usage` | Token counts in the final chunk | Accepted by OpenAI-style APIs |
| `return_progress: true` | llama.cpp prompt-progress keepalives | Rejected by some, with an HTTP 400 |
| `max_tokens` | The output limit, sent when the context window is known (`ContextWindow` set or probed) | Accepted by OpenAI-style APIs |
| `reasoning_effort`, `thinking` or `chat_template_kwargs` | The thinking level, sent only when `Thinking` is set and the provider has a thinking dialect | Depends on the dialect |

The 400 looks like this in the daemon and session logs:

```
400 {"message":"feature 'extra arguments: {\"return_progress\":true}' is not currently supported"}
```

In chat you only see `LLM provider returned an error (HTTP 400). Please try again.` The reason is in the log under `~/.netclaw/logs/`. Reported on Azure Foundry and OVHcloud ([netclaw#1566](https://github.com/netclaw-dev/netclaw/issues/1566), still open). There's no switch to turn the field off yet.

What "compatible" has to mean for netclaw:

- `GET /v1/models` lists the model, and `POST /v1/chat/completions` streams server-sent events.
- Unknown request fields are ignored, not rejected.
- Streaming tool calls arrive as structured `tool_calls` deltas (netclaw also parses `<tool_call>` text, but structured is the path that works everywhere).
- Auth is a Bearer header. netclaw sends `Authorization: Bearer <key>` and no other header, so a gateway that insists on `api-key` can't be reached with this provider.

One reported workaround, unsupported: configure the provider as type `openrouter` with a custom `Endpoint`, an API key, and `"VendorOptions": { "ExcludeReasoning": false }`. In a test against a strict stub that path sent no `return_progress`. The issue's reporter found some models then return empty streams, so treat it as a last resort. [Self-hosted providers](/configuration/self-hosted-providers/#openai-compatible-llamacpp-vllm-lemonade) covers the endpoint URL rules, including the `/v1` suffix.

## Common problems

| Symptom | Cause | Fix |
|---------|-------|-----|
| `netclaw status` says `config on disk not applied`, or the daemon crash-loops on restart, and the message says `requires authentication` | A role uses a provider with no API key or OAuth token | Add the key (`netclaw secrets set` or `netclaw provider`, `K`), then restart. A provider no role uses isn't checked |
| Provider shows a warning in `netclaw provider` | Probe failed: see the probe table above | Fix credentials or endpoint, then press `V` |
| Main fails and Fallback answers | Automatic [failover](/configuration/models/#failover) | Check the `provider.failover` alert for the error |

Each role uses one provider, so there's no per-channel provider selection. Failover between providers is the Fallback role. Changing providers restarts the daemon, automatically for `netclaw.json` edits and by hand for environment variables and `secrets.json`.

## Related pages

- [`netclaw provider`](/cli/provider/) - CLI reference for all provider commands
- [`netclaw model`](/cli/model/) - assign providers to Main, Fallback, and Compaction roles
- [Secrets Management](/security/secrets/) - how credentials are encrypted and stored
- [Self-Hosted Providers](/configuration/self-hosted-providers/) - Ollama and openai-compatible setup
- [Models](/configuration/models/) - model role configuration

## Resources

- [OpenRouter API docs](https://openrouter.ai/docs/api-reference/overview) - request format, rate limits, model routing
- [Anthropic API docs](https://docs.anthropic.com/en/api/getting-started) - authentication, model versions, usage limits
- [OpenAI API docs](https://platform.openai.com/docs/api-reference) - endpoints, authentication, model capabilities
- [GitHub Copilot](https://github.com/features/copilot) - subscription details and supported models
- [Venice.ai API docs](https://docs.venice.ai/) - endpoints, models, and vendor parameters
- [DeepSeek API docs](https://api-docs.deepseek.com/) - authentication, models, and rate limits
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) - the double-underscore nesting convention
- [RFC 7636 - OAuth PKCE](https://datatracker.ietf.org/doc/html/rfc7636) - the code exchange flow OpenAI uses
