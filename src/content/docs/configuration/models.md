---
title: "Models"
description: "Configure Main, Fallback, and Compaction model slots."
---

Netclaw assigns LLMs to three named roles — Main, Fallback, and Compaction — in the `Models` section of `~/.netclaw/config/netclaw.json`. Only Main is required. Fallback and Compaction default to using Main when unset.

For CLI commands that manage models interactively, see [`netclaw model`](/cli/model/).

## Model Roles

| Role | Purpose | Required? |
|------|---------|-----------|
| **Main** | Primary model for all interactions | Yes — defaults to `qwen3:30b` on `local-ollama` |
| **Fallback** | Automatic failover when Main is unavailable | No — routes to Main when unset |
| **Compaction** | Cheaper/faster model for context summarization | No — routes to Main when unset |

![Model Manager TUI showing role assignments](/screenshots/output/model-manager.png)

The Model Manager TUI (`netclaw model`) shows current role assignments and lets you reassign them interactively.

## Configuration Schema

Each role is an object under `Models` with these fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Provider` | string | `"local-ollama"` | Key into the `Providers` dictionary |
| `ModelId` | string | `"qwen3:30b"` | Model identifier as used by the provider API |
| `ContextWindow` | int? | `null` | Clamps the runtime context window in tokens; takes precedence over provider-reported value |
| `Provenance` | string? | `null` | How the model ID was resolved: `"Live"`, `"Defaults"`, or `"Manual"` |
| `InputModalities` | string[]? | `null` | Override input modalities: `"Text"`, `"Image"`, `"Audio"`, `"Video"` |
| `OutputModalities` | string[]? | `null` | Override output modalities (same values) |

The schema uses `additionalProperties: false` — only `Main`, `Fallback`, and `Compaction` are valid role names.

## Minimal Config

With Ollama running locally and `qwen3:30b` pulled, this is all you need:

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

Fallback and Compaction silently route to Main. Context window is auto-detected from Ollama.

## Production Config

A production setup might use a 30B Main, an 8B Fallback for resilience, and the same 8B for Compaction since summarization doesn't need a big model:

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

## Context Window Resolution

The runtime resolves context window size in this order:

1. `ContextWindow` value in config (highest priority)
2. Provider-detected value (via `/api/show`, `/v1/models`, etc.)
3. Default: 32,768 tokens

When `ContextWindow` is set, it must be >= 4,096 tokens. If it exceeds what the provider reports, the daemon refuses to start and tells you why.

## Capability Detection

Netclaw tries several sources to figure out what a model supports (context window, vision, etc.). It walks this list and stops at the first match:

1. OpenAI Codex static catalog
2. Ollama `/api/show`
3. OpenAI-compatible `/v1/models` metadata
4. OpenRouter oracle
5. HuggingFace capability resolver
6. Text-only defaults (32,768 token context window)

Setting `InputModalities` or `OutputModalities` in config skips detection entirely. Use this when a provider misreports what a model can do.

## Failover

When Fallback is configured, netclaw wraps both models in a FailoverChatClient. If Main throws after exhausting retries, Fallback gets the request automatically.

Retries happen first: 3 attempts with exponential backoff (1s base, 30s max, ±25% jitter). Retried errors include network failures, HTTP 408/429/5xx, `TaskCanceledException`, and `TimeoutException`. Only after all retries fail does failover kick in.

One catch: failover only works before streaming starts. Once the first chunk comes back from Main, mid-stream failures propagate directly rather than switching models. Splicing two different model responses together would produce garbage.

**Alerts:**

| Event | Alert Level |
|-------|-------------|
| Main fails, Fallback takes over | `provider.failover` — Warning |
| Both Main and Fallback fail | `provider.unreachable` — Critical |

If Fallback is not configured, failed retries on Main surface the error directly.

## Compaction

Compaction handles background summarization: context compaction, session title generation, observer summaries, and memory extraction. It fires when a session's context reaches 75% of the model's context window.

These tasks don't need a big model. An 8B parameter model handles them fine and saves compute for actual conversations.

## Environment Variable Overrides

Override any model field with `NETCLAW_` environment variables. Double underscores separate path segments per the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider):

```bash
export NETCLAW_Models__Main__Provider="openrouter"
export NETCLAW_Models__Main__ModelId="anthropic/claude-sonnet-4"
export NETCLAW_Models__Main__ContextWindow="200000"
```

Environment variables take highest priority, overriding `netclaw.json`. On Linux, variable names are case-sensitive.

## Validation and Errors

| Condition | Result |
|-----------|--------|
| Main `Provider` or `ModelId` is empty | Startup fails |
| `ContextWindow` < 4,096 | Startup fails |
| `ContextWindow` exceeds provider-reported value | Startup fails with descriptive error |
| Unknown role name in `Models` | Rejected by JSON schema (`additionalProperties: false`) |
| Provider key doesn't exist in `Providers` | `netclaw model set` rejects it; lists configured providers |

## Applying Changes

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

## Related Pages

- [`netclaw model`](/cli/model/) — CLI reference for model management (TUI, `set`, `discover`, `list`, `clear`)
- [Managed Providers](/configuration/managed-providers/) — configure cloud providers (OpenRouter, Anthropic, OpenAI)
- [Self-Hosted Providers](/configuration/self-hosted-providers/) — configure Ollama, llama.cpp, vLLM
- [Secrets Management](/security/secrets/) — how credentials are encrypted and stored

## Resources

- [Ollama model library](https://ollama.com/library) — browse models for local inference
- [OpenRouter model catalog](https://openrouter.ai/models) — compare models across providers with pricing
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention
