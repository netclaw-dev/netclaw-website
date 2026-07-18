---
title: "netclaw model"
description: "Manage model assignments across roles."
---

Assign LLMs to roles: Main, Fallback, and Compaction. Run `netclaw model` for an interactive TUI, or use subcommands to script it.

You need at least one provider configured first. If you haven't added one, see [`netclaw provider`](/cli/provider/).

## Usage

```bash
netclaw model                          # launch TUI
netclaw model <subcommand> [options]   # CLI mode
```

## Model roles

Three roles — only Main is required:

| Role | Purpose | When unset |
|------|---------|------------|
| **Main** | Primary model for all interactions | Required — cannot be cleared |
| **Fallback** | Automatic failover when Main is unavailable (rate limits, network errors, provider outages) | Falls back to Main |
| **Compaction** | Context summarization with a cheaper/faster model | Falls back to Main |

Role names are case-insensitive.

[Compaction](/architecture/sessions/#compaction) runs automatically when a session's context approaches the model's token limit.

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

`Enter` opens the assignment flow: pick a provider, discover its models, confirm. Discovery times out after 45 seconds and shows up to 30 results. If yours isn't listed, pick "Enter model ID manually..." and type it in (e.g., `qwen3:30b`, `llama3.2:latest`).

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

Context window shows `(default)` unless you've set an explicit `--context-window` value. The table resolves roles to their provider and model — it doesn't show definition names or modality overrides. Read the config file for those.

This reads from config, not from the running daemon. With no models configured, it prompts you to run `model set` or open the TUI.

If a role points at a definition that doesn't exist, `list` names the bad reference and stops:

```
Error: Models:Roles:Main references unknown definition 'does-not-exist'.
Fix the Models section in netclaw.json, then rerun `netclaw model list`.
```

Open the config, compare `Roles` against `Definitions`, and make the names agree — this usually happens after renaming a definition and forgetting a role. `netclaw doctor` flags the same thing (it won't auto-fix it), and the daemon refuses to start on it, so fix it before restarting.

### `model set`

```bash
netclaw model set <role> <provider> <model-id> [options]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--context-window <tokens>` | Override context window size (positive integer) | Provider-detected |
| `--clear-context-window` | Drop the override and go back to detection | — |
| `--input-modalities <list>` | Comma-separated `Text`, `Image`, `Audio`, `Video` | Detected |
| `--output-modalities <list>` | Same values, for output | Detected |
| `--clear-modalities` | Drop both modality overrides | — |

Use `--context-window` when a local model doesn't report its window (discovery shows `-`), or to cap usage below the model's actual maximum. Use the modality flags when detection gets a model's capabilities wrong — an Ollama vision model reported as text-only, say.

```bash
netclaw model set main remote-gpu qwen3-vl:32b \
  --context-window 65536 \
  --input-modalities "Text, Image" \
  --output-modalities "Text"
```

`--context-window` and `--clear-context-window` are mutually exclusive:

```
Error: --context-window and --clear-context-window cannot be combined.
```

Modality names are case-insensitive and are stored canonicalized — `text,image` lands on disk as `"Text, Image"`. Only the four names are accepted; anything else, including a raw integer, is rejected:

```
Error: invalid modalities '1'. Use a comma-separated list of: Text, Image, Audio, Video (or --clear-modalities to remove the override).
```

#### What set and clear actually touch

`set` and the `--clear-*` flags edit the **model definition** — the stored facts about a given provider/model pair. Assigning a role only repoints a reference at a definition. That distinction is the whole point: **switch a role away from a model and back, and its overrides are still there.**

```bash
netclaw model set main remote-gpu qwen3:30b --context-window 65536
netclaw model set main remote-gpu qwen3:8b     # 30b's definition is untouched
netclaw model set main remote-gpu qwen3:30b    # still 65536
```

Clearing removes the property outright rather than writing a sentinel, so a cleared value reads as "detect this at runtime".

:::note
`netclaw model set` doesn't check that the model exists. Netclaw probes for metadata only on `openai`-type providers using OAuth device or PKCE auth — for Ollama, Anthropic, OpenRouter, and even API-key OpenAI, no probe runs, and a typo'd model ID is accepted quietly and fails at first use. Passing `--context-window` skips the probe even where it would have run. Use [`netclaw model discover`](#model-discover) to confirm the ID first.
:::

The provider must already exist in your config. If it doesn't, the error lists your configured providers:

```
Error: Provider 'my-cloud' not found in configuration.
Configured providers: remote-gpu, my-anthropic
```

Shrinking Main's context window prints a warning because existing sessions with longer histories may fail until compacted.

:::note
On an older config that still uses inline roles, the first `model set` — or `model clear`, or a TUI assignment — converts the whole `Models` section to definitions and roles. It says nothing while doing it. Netclaw copies `netclaw.json` to `netclaw.json.legacy-models.bak` first, so the change is reversible. See [Migrating model configuration](/guides/migrating-model-config/).
:::

Restart the daemon for changes to take effect: `netclaw daemon stop && netclaw daemon start`.

### `model discover`

```bash
netclaw model discover <provider>
```

Discovery hits the provider's API live, so it has to be reachable:

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

The role assignment goes away; the definition stays. Re-assign that model later and its overrides are still there.

## Examples

```bash
# Set main model on a remote Ollama server
netclaw model set main remote-gpu qwen3:30b --context-window 32768

# Add a smaller fallback model on the same provider
netclaw model set fallback remote-gpu qwen3:8b

# Use a cloud model for compaction
netclaw model set compaction my-anthropic claude-sonnet-4

# Tell netclaw a local model can see images when detection says otherwise
netclaw model set main remote-gpu qwen3-vl:32b --input-modalities "Text, Image"

# Undo that override and let detection decide again
netclaw model set main remote-gpu qwen3-vl:32b --clear-modalities

# Drop a context-window cap you no longer need
netclaw model set main remote-gpu qwen3:30b --clear-context-window

# See what models an Ollama server has available
netclaw model discover my-ollama

# Remove the fallback assignment
netclaw model clear fallback
```

## Configuration

Assignments live in `~/.netclaw/config/netclaw.json` under the `Models` key. Definitions hold the model facts; roles point at them by name:

```json
{
  "Models": {
    "Definitions": {
      "remote-gpu-qwen3-30b": {
        "Provider": "remote-gpu",
        "ModelId": "qwen3:30b",
        "Provenance": "Manual",
        "ContextWindow": 65536,
        "InputModalities": "Text, Image",
        "OutputModalities": "Text"
      },
      "remote-gpu-qwen3-8b": {
        "Provider": "remote-gpu",
        "ModelId": "qwen3:8b",
        "Provenance": "Manual"
      }
    },
    "Roles": {
      "Main": "remote-gpu-qwen3-30b",
      "Fallback": "remote-gpu-qwen3-8b"
    }
  }
}
```

`model set` names new definitions after the provider and model (`remote-gpu-qwen3-30b`), but the names are yours — hand-edit them to anything readable and point the roles at the new name. Definitions stick around after you switch a role away, which is what keeps their overrides intact.

[Models configuration](/configuration/models/) covers the fields in full. Older configs use an inline shape that netclaw still reads — see [Migrating model configuration](/guides/migrating-model-config/).

Restart the daemon afterward.

## Exit codes

`0` on success, `1` on invalid arguments, unknown provider, or validation failure.

## What's next

After setting your models, run [`netclaw status`](/cli/status/) to confirm the daemon picked them up.

## Related commands

- [`netclaw provider`](/cli/provider/) — add providers before assigning models
- [Models configuration](/configuration/models/) — the `Models` shape these commands write
- [Migrating model configuration](/guides/migrating-model-config/) — converting an older inline `Models` section
- [`netclaw status`](/cli/status/) — see which model the daemon is actually using
- [`netclaw doctor`](/cli/doctor/) — checks model config validity
- [`netclaw init`](/cli/init/) — initial model setup during onboarding

## Resources

- [Ollama context length FAQ](https://github.com/ollama/ollama/blob/main/docs/faq.md#how-can-i-specify-the-context-window-size) — Ollama serves at its own `num_ctx` and truncates past it regardless of `--context-window`; set both
- [Ollama model library](https://ollama.com/library) — browse models for local inference
- [Anthropic models](https://docs.anthropic.com/en/docs/about-claude/models) — Claude specs, pricing, context windows
- [OpenRouter catalog](https://openrouter.ai/models) — compare across providers
- [OpenAI models](https://platform.openai.com/docs/models) — GPT specs, pricing, context windows
