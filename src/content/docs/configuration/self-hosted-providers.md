---
title: Self-Hosted Providers
description: Configure self-hosted inference servers like Ollama, llama.cpp, and vLLM.
---

Self-hosted providers run inference on your own hardware. No API keys, no data leaving your network. Netclaw has two provider types for this: native Ollama integration and an OpenAI-compatible mode that works with any server exposing a `/v1/chat/completions` endpoint — llama.cpp, vLLM, Lemonade, DwarfStar (ds4), or anything else OpenAI-compatible.

Config goes in `~/.netclaw/config/netclaw.json`. Self-hosted providers don't need credentials unless you're running an authenticated endpoint. Environment variables with the `NETCLAW_` prefix override file-based config.

`netclaw init` handles provider setup interactively if you're starting fresh. This page covers manual configuration.

For cloud-hosted providers (OpenRouter, Anthropic, OpenAI), see [Managed Providers](/configuration/managed-providers/).

## Before You Start

- [Ollama](https://ollama.com/) or another inference server installed and running
- `netclaw init` completed (or you're configuring manually for the first time)
- The netclaw daemon running (`netclaw daemon start`)

## Provider Summary

| Type | Display Name | Default Endpoint | Auth | Use Case |
|------|-------------|-----------------|------|----------|
| `ollama` | Ollama | `http://localhost:11434` | None | Ollama servers (auto-detects model capabilities) |
| `openai-compatible` | llama.cpp / vLLM / DwarfStar ds4 | `http://localhost:11434` | Optional Bearer token | Anything exposing `/v1/chat/completions` |

## Configuration Schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Type` | string | `"ollama"` | Provider SDK: `ollama` or `openai-compatible` |
| `Endpoint` | string | varies by type | Base URL of the inference server |
| `ApiKey` | string? | `null` | Optional Bearer token for authenticated endpoints |

## Ollama

The default provider. Netclaw discovers models via `/api/tags` and detects capabilities per-model through `/api/show`.

Ollama must have at least one model pulled before netclaw can use it — an empty model list is treated as a probe failure. Pull a model first:

```bash
ollama pull qwen3:30b
```

Browse available models at the [Ollama model library](https://ollama.com/library).

### Local Ollama

```json
{
  "Providers": {
    "local": {
      "Type": "ollama",
      "Endpoint": "http://localhost:11434"
    }
  },
  "Models": {
    "Definitions": { "local-qwen": { "Provider": "local", "ModelId": "qwen3:30b" } },
    "Roles": { "Main": "local-qwen" }
  }
}
```

If Ollama is running locally, no other config is needed.

### Remote Ollama Instance

Point to any machine on your network:

```json
{
  "Providers": {
    "gpu-box": {
      "Type": "ollama",
      "Endpoint": "http://192.168.1.50:11434"
    }
  }
}
```

### Capability Detection

Netclaw queries `/api/show` for each model and inspects the architecture metadata:

| Capability | Detection Method | Example Models |
|-----------|-----------------|----------------|
| Context window | `{arch}.context_length` field | All models |
| Vision | `{arch}.vision.block_count` field | llava, llama3.2-vision |

Models without native tool calling still work — netclaw falls back to structured prompting for tool use.

![Ollama provider setup during the init wizard](/screenshots/output/init-01-provider-ollama.png)

The init wizard auto-discovers models pulled in your local Ollama instance and lets you assign them to roles.

## OpenAI-Compatible (llama.cpp, vLLM, Lemonade)

For any inference server with a `/v1/chat/completions` endpoint — llama.cpp, vLLM, Lemonade, or anything else OpenAI-compatible. Netclaw discovers models via `/v1/models` and streams completions with tool calling.

### Basic Setup

```json
{
  "Providers": {
    "llama-server": {
      "Type": "openai-compatible",
      "Endpoint": "http://localhost:8080"
    }
  },
  "Models": {
    "Definitions": { "llama": { "Provider": "llama-server", "ModelId": "my-model" } },
    "Roles": { "Main": "llama" }
  }
}
```

Note: the netclaw default endpoint for `openai-compatible` is `http://localhost:11434`, but llama-server defaults to port 8080 — specify the endpoint explicitly when using llama.cpp.

### With Authentication

Some deployments protect the API with a Bearer token. Store tokens in `secrets.json` to keep credentials out of version-controlled config:

```json
{
  "Providers": {
    "vllm-cluster": { "ApiKey": "your-token-here" }
  }
}
```

The main config in `netclaw.json` just references the provider without the key:

```json
{
  "Providers": {
    "vllm-cluster": {
      "Type": "openai-compatible",
      "Endpoint": "https://inference.internal:8443"
    }
  }
}
```

### llama.cpp Server Example

Start llama-server, then point netclaw at it:

```bash
# Start llama-server (defaults to port 8080)
llama-server -m ./models/qwen3-30b-q4_k_m.gguf --port 8080

# Configure netclaw
netclaw provider add llama-local openai-compatible --endpoint http://localhost:8080
```

## Multi-Provider Setup

Mix provider types freely. Here's Ollama handling Main with a llama.cpp instance as Fallback:

```json
{
  "Providers": {
    "ollama-local": {
      "Type": "ollama",
      "Endpoint": "http://localhost:11434"
    },
    "llama-gpu": {
      "Type": "openai-compatible",
      "Endpoint": "http://localhost:8080"
    }
  },
  "Models": {
    "Definitions": {
      "main": { "Provider": "ollama-local", "ModelId": "qwen3:30b" },
      "fallback": { "Provider": "llama-gpu", "ModelId": "qwen3:14b" }
    },
    "Roles": { "Main": "main", "Fallback": "fallback" }
  }
}
```

Assign models to roles with [`netclaw model set`](/cli/model/).

## Environment Variable Overrides

```bash
# Point at a remote Ollama instance
export NETCLAW_Providers__local__Type="ollama"
export NETCLAW_Providers__local__Endpoint="http://gpu-server:11434"

# Override model assignment (named definition + role reference)
export NETCLAW_Models__Definitions__local-qwen__Provider="local"
export NETCLAW_Models__Definitions__local-qwen__ModelId="qwen3:30b"
export NETCLAW_Models__Roles__Main="local-qwen"
```

Environment variables follow the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — double underscores separate path segments.

## Health Checks

Netclaw probes each provider on startup — `/api/tags` for Ollama, `/v1/models` for openai-compatible. Each probe times out after 10 seconds.

Common issues:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection refused | Server not running | Start Ollama (`ollama serve`) or llama-server |
| Empty model list | No models pulled | Run `ollama pull <model>` |
| Timeout | Server overloaded or wrong port | Check endpoint URL and server logs |
| 401 Unauthorized | Token required | Add `ApiKey` to provider config |

Run [`netclaw doctor`](/cli/doctor/) for a full connectivity diagnostic, or open `netclaw provider` to see live health status.

## Applying Changes

After editing `netclaw.json`, restart the daemon for changes to take effect:

```bash
netclaw daemon restart
```

Verify your provider is healthy:

```bash
netclaw provider    # check health indicators in the TUI
netclaw doctor      # full diagnostic including provider probes
```

## Provider Manager TUI

![Provider Manager TUI showing configured providers with health status](/screenshots/output/provider-manager.png)

Self-hosted entries show `✓` when reachable with models discovered, or `⚠` when the server is down or returns errors. Select a provider to manage endpoints, re-probe, or remove it.

## Limitations

- Changing providers requires a daemon restart.
- Tool calling quality varies between models. Qwen3 30B+ and Llama 3.1 70B+ handle it well; smaller models often choke on complex tool schemas.
- The openai-compatible provider sends standard OpenAI tool-calling format. Servers that don't implement tool calling will fall back to structured prompting.
- llama.cpp requires `--jinja` for Qwen3 and other reasoning models — without it, raw XML leaks into chat. See [llama.cpp Troubleshooting](/troubleshooting/llama-cpp/).

## See Also

- [`netclaw provider`](/cli/provider/) — manage providers from the CLI or TUI
- [`netclaw model`](/cli/model/) — assign models to Main, Fallback, and Compaction roles
- [Managed Providers](/configuration/managed-providers/) — cloud providers when you want someone else to run the GPUs
- [Models](/configuration/models/) — deep dive on model role configuration and routing
- [Secrets Management](/security/secrets/) — how netclaw encrypts and stores credentials at rest

## Resources

- [Ollama](https://ollama.com/) — install and run local models
- [Ollama model library](https://ollama.com/library) — browse available models
- [Ollama API reference](https://github.com/ollama/ollama/blob/main/docs/api.md) — model management, tags, and show endpoints
- [llama.cpp server docs](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) — flags, endpoints, performance tuning
- [vLLM OpenAI-compatible serving](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) — model parallelism and quantization options
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention
