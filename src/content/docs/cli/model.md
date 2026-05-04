---
title: "netclaw model"
description: "Manage model assignments across roles."
---

Assign LLM models to roles: Main, Fallback, and Compaction. Run `netclaw model` for an interactive TUI, or use subcommands to script it.

You need at least one provider configured first. If you haven't added one, see [`netclaw provider`](/cli/provider/).

## Usage

```bash
netclaw model                          # launch TUI
netclaw model <subcommand> [options]   # CLI mode
```

## Model roles

Three roles, only Main is required:

| Role | Purpose | When unset |
|------|---------|------------|
| **Main** | Primary model for all interactions | Required — cannot be cleared |
| **Fallback** | Automatic failover when Main is unavailable (rate limits, network errors, provider outages) | Falls back to Main |
| **Compaction** | Context summarization with a cheaper/faster model | Falls back to Main |

Role names are case-insensitive.

Compaction runs automatically when a session's context approaches the model's token limit.

## Model Manager TUI

```bash
netclaw model
```

![Model Manager TUI showing role assignments with Main configured and Fallback/Compaction unset](/screenshots/output/model-manager.png)

Select a role to reassign it, or use the hotkeys:

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate roles |
| `Enter` | Assign model to selected role |
| `D` | Discover available models from a provider |
| `C` | Clear optional role (Fallback or Compaction) |
| `Esc` | Back / Quit (from role overview) |
| `Ctrl+Q` | Quit from any screen |

`Enter` opens the assignment flow: pick a provider, discover its models, confirm. Discovery times out after 20 seconds and shows up to 30 results. If yours isn't listed, pick "Enter model ID manually..." and type it in (e.g., `qwen3:30b`, `llama3.2:latest`).

## Subcommands

### `model list`

```bash
netclaw model list
```

```
Role         Provider             Model ID                       Context Window
Main         remote-gpu           qwen3:30b                      32,768 tokens
Fallback     remote-gpu           qwen3:8b                       (default)
Compaction   (not set)
```

Context window shows `(default)` unless you've set an explicit `--context-window` value.

This reads from config, not from the running daemon. With no models configured, it prompts you to run `model set` or open the TUI.

### `model set`

```bash
netclaw model set <role> <provider> <model-id> [--context-window <tokens>]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--context-window <tokens>` | Override context window size (positive integer) | Provider-detected |

Use this when a local model doesn't report its context window (discovery shows `-`), or to cap usage below the model's actual maximum.

The provider must already exist in your config. If it doesn't, the error lists your configured providers:

```
Error: Provider 'my-cloud' not found in configuration.
Configured providers: remote-gpu, my-anthropic
```

Shrinking Main's context window prints a warning because existing sessions with longer histories may fail until compacted.

Restart the daemon for changes to take effect.

### `model discover`

```bash
netclaw model discover <provider>
```

The provider must be reachable. This queries its API live:

```
Model ID                                 Context Window        Cost (in/out per 1M)
claude-opus-4-1                          200,000               $15.00 / $75.00
claude-sonnet-4                          200,000               $3.00 / $15.00
gpt-4-turbo                              128,000               $10.00 / $30.00
gpt-4o                                   128,000               $5.00 / $15.00

4 model(s) found.
```

Cost and context window columns show `-` when the provider doesn't report them (common with Ollama and [OpenAI-compatible endpoints](/cli/provider/)).

### `model clear`

```bash
netclaw model clear <role>
```

Clears Fallback or Compaction. Cannot clear Main:

```
Error: Cannot clear the main model role. Use `netclaw model set main` to change it instead.
```

Cleared roles are removed from the config file entirely.

## Examples

```bash
# Set main model on a remote Ollama server
netclaw model set main remote-gpu qwen3:30b --context-window 32768

# Add a smaller fallback model on the same provider
netclaw model set fallback remote-gpu qwen3:8b

# Use a cloud model for compaction
netclaw model set compaction my-anthropic claude-sonnet-4

# See what models an Ollama server has available
netclaw model discover my-ollama

# Remove the fallback assignment
netclaw model clear fallback
```

## Configuration

Assignments live in `~/.netclaw/config/netclaw.json` under the `Models` key:

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
    }
  }
}
```

Restart the daemon afterward.

## Exit codes

`0` on success, `1` on invalid arguments, unknown provider, or validation failure.

## What's next

After setting your models, run [`netclaw status`](/cli/status/) to confirm the daemon picked them up.

## Related commands

- [`netclaw provider`](/cli/provider/) — add providers before assigning models
- [`netclaw status`](/cli/status/) — see which model the daemon is actually using
- [`netclaw doctor`](/cli/doctor/) — checks model config validity
- [`netclaw init`](/cli/init/) — initial model setup during onboarding

## Resources

- [Ollama model library](https://ollama.com/library) — browse models for local inference
- [Anthropic models](https://docs.anthropic.com/en/docs/about-claude/models) — Claude specs, pricing, context windows
- [OpenRouter catalog](https://openrouter.ai/models) — compare across providers
- [OpenAI models](https://platform.openai.com/docs/models) — GPT specs, pricing, context windows
