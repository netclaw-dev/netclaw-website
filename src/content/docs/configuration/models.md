---
title: "Models"
description: "Configure Main, Fallback, and Compaction model slots."
---

Netclaw assigns LLMs to three roles in the `Models` section of `~/.netclaw/config/netclaw.json`: **Main**, **Fallback**, and **Compaction**. Only Main is required. The other two route to Main when unset.

Before assigning models, you need at least one provider configured. See [Managed Providers](/configuration/managed-providers/) or [Self-Hosted Providers](/configuration/self-hosted-providers/).

For CLI commands that manage models interactively, see [`netclaw model`](/cli/model/).

## Model roles

| Role | Purpose | Required? |
|------|---------|-----------|
| **Main** | Primary model for all interactions | Yes — defaults to `qwen3:30b` on `local-ollama` |
| **Fallback** | Automatic failover when Main is unavailable | No — routes to Main when unset |
| **Compaction** | Cheaper/faster model for context summarization | No — routes to Main when unset |

![Model Manager TUI showing role assignments](/screenshots/output/model-manager.png)

## Configuration schema

Each role is an object under `Models` with these fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Provider` | string | `"local-ollama"` | Key into the `Providers` dictionary |
| `ModelId` | string | `"qwen3:30b"` | Model identifier as used by the provider API |
| `ContextWindow` | int? | `null` | Clamps the runtime context window in tokens; takes precedence over provider-reported value |
| `Provenance` | enum? | `null` | Read-only. Set by the CLI: `"Live"` (discovered from provider), `"Defaults"` (curated defaults), or `"Manual"` (`model set`) |
| `InputModalities` | flags enum? | `null` | Override input modalities, e.g. `"Text, Image"`. Values: `Text`, `Image`, `Audio`, `Video` |
| `OutputModalities` | flags enum? | `null` | Override output modalities (same values, e.g. `"Text"`) |

The schema enforces `additionalProperties: false`, so only `Main`, `Fallback`, and `Compaction` are valid role names.

## Minimal config

With Ollama running locally and `qwen3:30b` pulled, this is all you need. The `Provider` value must match a key you've defined under `Providers` in the same config file.

```json
{
  "Models": {
    "Main": {
      "Provider": "local-ollama",
      "ModelId": "qwen3:30b"
    }
  }
}
```

Context window is auto-detected from Ollama.

## Production config

Here's a more realistic setup: 30B for Main, 8B for Fallback (resilience if the big model goes down), same 8B for Compaction (summarization doesn't need a big model):

```json
{
  "Models": {
    "Main": {
      "Provider": "remote-gpu",
      "ModelId": "qwen3:30b",
      "ContextWindow": 32768
    },
    "Fallback": {
      "Provider": "remote-gpu",
      "ModelId": "qwen3:8b",
      "ContextWindow": 32768
    },
    "Compaction": {
      "Provider": "remote-gpu",
      "ModelId": "qwen3:8b"
    }
  }
}
```

<!-- TODO: needs user input — recommended model combinations for cloud provider scenarios (e.g., OpenRouter Main + local Ollama Fallback) -->

## Context window resolution

Config takes precedence over anything the provider reports:

1. `ContextWindow` value in config (highest priority)
2. Provider-detected value (via `/api/show`, `/v1/models`, etc.)
3. Default: 32,768 tokens

Any role with an explicit `ContextWindow` must set it to at least 4,096 tokens. If Main's `ContextWindow` exceeds what the provider reports, the daemon refuses to start and tells you why.

## Capability detection

Netclaw auto-detects what a model supports (context window, modalities) by walking this list until something answers:

1. Built-in static catalog (covers well-known models with zero network cost)
2. Ollama `/api/show` — only when the provider type is `ollama`
3. OpenAI-compatible `/v1/models` metadata — only when the provider type is `openai-compatible`
4. [OpenRouter](https://openrouter.ai/models) public catalog
5. [HuggingFace](https://huggingface.co/models) capability resolver
6. Text-only defaults (32,768 token context window)

If your provider misreports capabilities (say, an Ollama model supports vision but detection shows text-only), set `InputModalities` or `OutputModalities` in config to override detection.

## Failover

When Fallback is configured, netclaw wraps both models in a failover layer. If Main throws after exhausting retries, the request goes to Fallback automatically.

Retries happen first: 3 attempts with exponential backoff (1s base, 30s max, ±25% jitter). Retried errors: network failures, HTTP 408/429/5xx, `TaskCanceledException`, `TimeoutException`. Only after all retries fail does failover kick in.

There's a catch with streaming. Failover only applies if Main fails before the first chunk reaches the caller. Once a chunk has been emitted, failures propagate directly. Splicing two model responses together mid-stream would produce garbage, so netclaw doesn't try.

| Event | Alert Level |
|-------|-------------|
| Main fails, Fallback takes over | `provider.failover` — Warning |
| Both Main and Fallback fail | `provider.unreachable` — Critical |

If Fallback is not configured, failed retries on Main surface the error directly.

## Compaction

Compaction is for background LLM work: summarizing conversation context when it grows too long, generating session titles, extracting memories. These don't need your best model. An 8B handles them fine and saves compute for actual conversations.

Compaction fires when context reaches 75% of the context window. You can tune this with `Session.CompactionThreshold`.

## Environment variable overrides

You can override any model field with `NETCLAW_` environment variables. Double underscores separate path segments, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider):

```bash
export NETCLAW_Models__Main__Provider="openrouter"
export NETCLAW_Models__Main__ModelId="anthropic/claude-sonnet-4"
export NETCLAW_Models__Main__ContextWindow="200000"
```

These take highest priority, overriding anything in `netclaw.json`. On Linux, variable names are case-sensitive.

## Validation errors

| Condition | Result |
|-----------|--------|
| Main `Provider` or `ModelId` is empty | Startup fails |
| `ContextWindow` < 4,096 on any role | Startup fails |
| Main `ContextWindow` exceeds provider-reported value | Startup fails with descriptive error |
| Unknown role name in `Models` | Config schema rejects it |
| Provider key doesn't exist in `Providers` | `netclaw model set` rejects it; lists configured providers |

## Applying changes

All model config changes require a daemon restart:

<!-- TODO: needs user input — verify `netclaw daemon restart` command exists and link to its page when available -->

```bash
netclaw daemon restart
```

Verify models are picked up:

```bash
netclaw model list     # reads from config
netclaw status         # shows what the running daemon is using
```

## Typical setup sequence

1. Configure a provider ([Managed Providers](/configuration/managed-providers/) or [Self-Hosted Providers](/configuration/self-hosted-providers/))
2. Assign models to roles (this page, or [`netclaw model set`](/cli/model/))
3. Restart the daemon
4. Verify with `netclaw status`

## Related pages

- [`netclaw model`](/cli/model/) — CLI reference for model management (TUI, `set`, `discover`, `list`, `clear`)
- [Managed Providers](/configuration/managed-providers/) — configure cloud providers (OpenRouter, Anthropic, OpenAI)
- [Self-Hosted Providers](/configuration/self-hosted-providers/) — configure Ollama, llama.cpp, vLLM
- [Secrets Management](/security/secrets/) — how credentials are encrypted and stored

## Resources

- [Ollama model library](https://ollama.com/library) — browse models for local inference
- [Ollama modelfile parameters](https://docs.ollama.com/modelfile) — context window and other model-level settings
- [OpenRouter model catalog](https://openrouter.ai/models) — compare models across providers with pricing
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention
