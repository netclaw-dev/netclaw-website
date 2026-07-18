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

:::caution
The `local-ollama` / `qwen3:30b` values below are the config-schema defaults, not a working setup. Since 0.24.3 netclaw no longer silently falls back to a local Ollama when no valid model is configured. Start with no reachable Main model and the daemon boots **degraded** — it runs, but every turn returns a `No valid model configuration detected.` banner until you point Main at a provider you've actually configured. [`netclaw doctor`](/cli/doctor/) surfaces the degraded state.
:::

![Model Manager TUI showing role assignments](/screenshots/output/model-manager.png)

## Configuration schema

`Models` has two halves. **Definitions** describe models; **Roles** name which definition fills each job:

```json
{
  "Models": {
    "Definitions": {
      "qwen-main": {
        "Provider": "remote-gpu",
        "ModelId": "qwen3:30b",
        "ContextWindow": 32768
      }
    },
    "Roles": {
      "Main": "qwen-main"
    }
  }
}
```

The split is what makes role changes non-destructive. Point Main at a different definition and the old one keeps its context window and modality overrides — switch back and it's exactly as you left it.

Definition names are yours. `netclaw model set` generates `<provider>-<model-id>` (`remote-gpu-qwen3-30b`), but nothing depends on that shape — rename them to whatever reads well and update the roles to match. Names match case-insensitively and must be unique.

Each definition takes these fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Provider` | string | `"local-ollama"` | Key into the `Providers` dictionary |
| `ModelId` | string | `"qwen3:30b"` | Model identifier as used by the provider API |
| `ContextWindow` | int? | `null` | Clamps the runtime context window in tokens; takes precedence over provider-reported value |
| `Provenance` | enum? | `null` | Read-only. Set by the CLI: `"Live"` (discovered from provider), `"Defaults"` (curated defaults), or `"Manual"` (`model set`) |
| `InputModalities` | flags enum? | `null` | Override input modalities, e.g. `"Text, Image"`. Values: `Text`, `Image`, `Audio`, `Video` |
| `OutputModalities` | flags enum? | `null` | Override output modalities (same values, e.g. `"Text"`) |

And `Roles` takes exactly three keys — `Main`, `Fallback`, `Compaction` — each naming a definition. `Main` is required.

**An omitted optional field means "detect it at runtime."** Netclaw writes no placeholder or sentinel to mean "cleared" — if `ContextWindow` isn't there, detection resolves it.

## Minimal config

With Ollama running locally and `qwen3:30b` pulled, this is all you need. The `Provider` value must match a key you've defined under `Providers` in the same config file.

```json
{
  "Models": {
    "Definitions": {
      "qwen-main": {
        "Provider": "local-ollama",
        "ModelId": "qwen3:30b"
      }
    },
    "Roles": {
      "Main": "qwen-main"
    }
  }
}
```

Context window is auto-detected from Ollama.

## Production config

A more realistic setup: 30B for Main, 8B for Fallback (resilience if the big model goes down), and the same 8B definition reused for Compaction, because summarization doesn't need a big model. Two definitions, three roles:

```json
{
  "Models": {
    "Definitions": {
      "qwen-main": {
        "Provider": "remote-gpu",
        "ModelId": "qwen3:30b",
        "ContextWindow": 32768
      },
      "qwen-small": {
        "Provider": "remote-gpu",
        "ModelId": "qwen3:8b",
        "ContextWindow": 32768
      }
    },
    "Roles": {
      "Main": "qwen-main",
      "Fallback": "qwen-small",
      "Compaction": "qwen-small"
    }
  }
}
```

Two roles sharing one definition is normal — Fallback and Compaction both resolve to `qwen-small` here, and editing that definition moves both.

<!-- TODO: needs user input — recommended model combinations for cloud provider scenarios (e.g., OpenRouter Main + local Ollama Fallback) -->

## Context window resolution

Config takes precedence over anything the provider reports:

1. `ContextWindow` value in config (highest priority)
2. Provider-detected value (via `/api/show`, `/v1/models`, etc.)
3. Default: 32,768 tokens

Any role-bound definition with an explicit `ContextWindow` must set it to at least 4,096 tokens. Definitions no role points at aren't validated.

Set Main's `ContextWindow` higher than the provider reports and netclaw logs a warning and uses your number anyway. It doesn't refuse to boot — a detected context window is a guess, and taking down every session over a number netclaw can't trust is worse than trying. If the number really is too big, the provider rejects the oversized request and the session compacts and retries.

Modalities follow the same precedence as the context window: an explicit value wins, then whatever's already stored, then detection. Clearing a value with [`netclaw model set --clear-context-window`](/cli/model/#model-set) or `--clear-modalities` hands that field back to detection — it doesn't restore the value you cleared.

## Capability detection

Netclaw auto-detects what a model supports (context window, modalities) by walking this list until something answers:

1. Built-in static catalog (covers well-known models with zero network cost)
2. Ollama `/api/show` — only when the provider type is `ollama`
3. OpenAI-compatible `/v1/models` metadata — only when the provider type is `openai-compatible`
4. [OpenRouter](https://openrouter.ai/models) public catalog
5. [HuggingFace](https://huggingface.co/models) capability resolver
6. Text-only defaults (32,768 token context window)

If your provider misreports capabilities (say, an Ollama model supports vision but detection shows text-only), override detection on that definition — either by hand or with [`netclaw model set`](/cli/model/#model-set):

```bash
netclaw model set main remote-gpu qwen3-vl:32b --input-modalities "Text, Image"
```

The override sticks to the definition, so it survives role reassignment.

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

[Compaction](/architecture/sessions/#compaction) is for background LLM work: summarizing conversation context when it grows too long, generating session titles, extracting memories. These don't need your best model. An 8B handles them fine and saves compute for actual conversations.

Compaction fires when context reaches 75% of the context window. Tune it with `Session.CompactionThreshold`.

## Environment variable overrides

Override any model field with `NETCLAW_` environment variables. Double underscores separate path segments, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider). Definitions and roles nest the same way as the file:

```bash
export NETCLAW_Models__Definitions__claude__Provider="openrouter"
export NETCLAW_Models__Definitions__claude__ModelId="anthropic/claude-sonnet-4"
export NETCLAW_Models__Roles__Main="claude"
```

These take highest priority, overriding anything in `netclaw.json`. On Linux, variable names are case-sensitive.

:::caution
The legacy `NETCLAW_Models__Main__*` form still works on its own, but it **blocks migration of the config file**. While any legacy model override is set, `netclaw model set` and `netclaw doctor --fix` refuse to convert `netclaw.json` and say why — otherwise, restarting with a migrated file and legacy variables still exported would leave netclaw reading a shape that's half one thing and half the other. Convert the variables to `Definitions`/`Roles` first; [Migrating model configuration](/guides/migrating-model-config/) walks through it.
:::

## Validation errors

| Condition | Result |
|-----------|--------|
| Main `Provider` or `ModelId` is empty | Daemon boots **degraded** — every turn returns the `No valid model configuration detected.` banner |
| Fallback or Compaction is incomplete | Startup fails |
| `ContextWindow` < 4,096 on a role-bound definition | Startup fails |
| Main `ContextWindow` exceeds provider-reported value | Warning; netclaw uses your value |
| Unknown role name in `Roles` | Config schema rejects it |
| Provider key doesn't exist in `Providers` | `netclaw model set` rejects it; lists configured providers |
| A role names a definition that doesn't exist | Startup fails: `Models:Roles:Main references unknown definition 'x'.` |
| `Definitions` present without `Roles`, or vice versa | Rejected — the canonical shape needs both |
| `Definitions` is empty | Rejected — needs at least one definition |
| Two definitions whose names differ only by case | Rejected as duplicates |
| Legacy inline roles mixed with `Definitions`/`Roles` | Rejected — [pick one shape](/guides/migrating-model-config/) |

An unresolved role reference is the one worth watching for, since it's easy to introduce by renaming a definition and forgetting a role. It stops the daemon at startup, and `netclaw model list` and `netclaw doctor` both name the offending reference (`Models:Roles:Main references unknown definition '...'`). The fix is manual — compare `Roles` against `Definitions` and make them agree.

## Applying changes

All model config changes require a daemon restart. There's no `daemon restart` subcommand — stop and start it:

```bash
netclaw daemon stop && netclaw daemon start
```

Under systemd, restart the unit instead:

```bash
systemctl --user restart netclaw
```

In Docker, restart the container: `docker restart netclaw`.

Verify models are picked up:

```bash
netclaw model list     # reads the config file
netclaw status         # shows what the running daemon is using
```

:::note
`netclaw model list` and `netclaw doctor` read `netclaw.json` and nothing else. Model settings supplied through `NETCLAW_` environment variables are invisible to both, even though the daemon honors them — so an env-only setup shows "No models configured" while running fine. `netclaw status` is what reflects the daemon's live view.
:::

## Typical setup sequence

1. Configure a provider ([Managed Providers](/configuration/managed-providers/) or [Self-Hosted Providers](/configuration/self-hosted-providers/))
2. Assign models to roles (this page, or [`netclaw model set`](/cli/model/))
3. Restart the daemon
4. Verify with `netclaw status`

## Related pages

- [`netclaw model`](/cli/model/) — CLI reference for model management (TUI, `set`, `discover`, `list`, `clear`)
- [Migrating Model Configuration](/guides/migrating-model-config/) — moving an older inline `Models` section to definitions and roles
- [Managed Providers](/configuration/managed-providers/) — configure cloud providers (OpenRouter, Anthropic, OpenAI)
- [Self-Hosted Providers](/configuration/self-hosted-providers/) — configure Ollama, llama.cpp, vLLM
- [Secrets Management](/security/secrets/) — how credentials are encrypted and stored

## Resources

- [Ollama model library](https://ollama.com/library) — browse models for local inference
- [Ollama modelfile parameters](https://docs.ollama.com/modelfile) — context window and other model-level settings
- [OpenRouter model catalog](https://openrouter.ai/models) — compare models across providers with pricing
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention
