---
title: "Quickstart"
description: "Install netclaw, run the setup wizard and send your first message in about five minutes."
---

Install netclaw, answer a few setup questions, and talk to your assistant. Allow about five minutes, plus a minute or two on first start while the daemon fetches its memory models. This is the short path with no detours. [Your first conversation](/getting-started/first-conversation/) explains what you see in the chat, and [Build your first assistant](/getting-started/first-assistant/) is the long tutorial that adds tools, memory and a reminder.

## Before you begin

- A 64-bit Linux, an Apple Silicon Mac or Windows x64. On Linux you also need `curl`, the ICU library (`libicu`) and `tzdata`. Without ICU the daemon won't start, and without `tzdata` the identity step rejects every timezone but UTC. See [requirements](/getting-started/installation/#requirements).
- About 1 GB of free memory and outbound access to `releases.netclaw.dev` and `huggingface.co`.
- An LLM: an API key for one of the eight providers `init` lists (Anthropic, OpenAI, OpenRouter and DeepSeek among them), or the address of a server you run, such as Ollama or llama.cpp.

## 1. Install

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash
```

The installer adds `netclaw` to your PATH for new shells. Load it into this one:

```bash
. ~/.netclaw/env
```

On Windows, use the [PowerShell installer](/getting-started/installation/#install-on-windows) and restart your terminal. Check it worked:

```bash
netclaw --version
```

```text
netclaw 0.28.2 (commit 7419d84, built 2026-10-29T00:09:05Z)
```

## 2. Run the setup wizard

```bash
netclaw init
```

The wizard asks for four things:

| Step | You choose |
|---|---|
| Provider | An LLM provider, its credentials or endpoint, and a default model |
| Identity | Agent name, communication style, your name, timezone |
| Security posture | Personal, Team or Public |
| Health check | Nothing. It writes config, starts the daemon and opens chat. |

Team and Public add a fifth step, enabled features. The header says "Step 1 of 5" until you pick a posture, then drops to "of 4" if you chose Personal.

### Provider

Press a number to pick a provider, then enter its credentials. For llama.cpp or vLLM, pick **OpenAI-compatible** and give the server address, with or without `/v1`: `http://llm.example.internal:8080`. The endpoint field starts with `http://localhost:11434` already in it and your cursor sits at the end, so press Backspace until the default is gone before you type. After a connectivity check you pick a default model.

![Netclaw Setup, Step 1 of 5, LLM Provider, listing eight providers from Anthropic to Venice.ai with Anthropic highlighted](/screenshots/output/init-01-provider-list.png)

The first screen lists all eight providers, and the counter reads "of 5" until you choose a posture.

### Identity and posture

Answer the four identity prompts, then pick **Personal** for a single-user machine. The timezone must be an IANA id such as `America/Chicago`. `UTC` is already filled in. See the [security model](/security/security-model/) for Team and Public.

![Netclaw Setup, Step 2 of 5, Identity, with four communication styles from Concise & casual to Detailed & formal](/screenshots/output/init-02-identity.png)

The style you pick here shapes the assistant's first greeting, and you can redo this step later from `netclaw init`.

![Netclaw Setup, Step 3 of 5, Security Posture, offering Personal, Team and Public with Personal highlighted](/screenshots/output/init-02-security-posture.png)

The grey text under the options summarizes what each posture allows. Channels are set up later in `netclaw config`.

### Health check

The wizard writes `~/.netclaw/config/netclaw.json`, starts the daemon and checks the provider. A clean run looks like this:

```text
✓  LLM provider configured (OpenAI-compatible (llama.cpp / vLLM / DwarfStar ds4))
✓  Model selected (<your model>)
✓  Memory backend (SQLite)
✓  Configuration written
```

![Netclaw Setup, Step 4 of 4, Health Check, with four green check lines and an Applying configuration spinner](/screenshots/output/init-05-health-check.png)

The four checks go green while the daemon applies the new configuration, and the step counter ends at 4 of 4 because this was a Personal setup. This capture used an OpenAI-compatible endpoint serving `qwen2:0.5b`, so that's what the first two lines name. Yours name your provider and model. The spinner is the last frame `init` shows before it opens the chat.

If the daemon fails to start, the last line reads "Setup complete with warnings" and tells you to run `netclaw daemon start`, then `netclaw chat --onboarding`. On a bare Linux image the cause is usually a missing `libicu`. See [troubleshooting](/getting-started/installation/#failed-to-start-daemon-process-exited-with-code-134).

## 3. Send your first message

After a clean health check, `init` opens the chat and your assistant greets you by name and asks what you want to use it for. Answer in plain language. The first reply can take 30 seconds or more on a local model. Press `Ctrl+Q` to leave.

If `init` ended with warnings, there's no greeting. Fix the warning, run `netclaw daemon start`, then `netclaw chat --onboarding`. It opens the same conversation.

## Verify it works

```bash
netclaw status
```

```text
overall: healthy
version: 0.28.2 (commit 7419d84, built 2026-10-29T00:10:12Z)
daemon: PID 3644, uptime 0m 24s, endpoint http://127.0.0.1:5199
persistence: Sqlite
memory: sqlite (healthy)
telemetry: disabled
model: <your model> (provider: openai-compatible, context: 131,072 tokens)
connectors:
- discord: disabled (disabled)
- mattermost: disabled (disabled)
- slack: disabled (disabled)
- tui: healthy (enabled)
```

`overall: healthy` and a reply in the chat mean you're done. If something looks off, run `netclaw doctor`. A `WARN` about a missing `secrets.json` is normal when your provider needs no API key.

## What's next

- [Your first conversation](/getting-started/first-conversation/): what to try, the keys that matter and your first approval prompt
- [Build your first assistant](/getting-started/first-assistant/): identity, tools, memory and a reminder that reports back
- [`netclaw config`](/cli/config/): connect Slack, Discord or Mattermost, enable web search, set exposure

## Related pages

- [Installation](/getting-started/installation/): every platform, update and uninstall
- [`netclaw init`](/cli/init/): the wizard in full, including re-running it
- [Self-hosted providers](/configuration/self-hosted-providers/): Ollama, llama.cpp and vLLM settings
- [`netclaw status`](/cli/status/) and [`netclaw doctor`](/cli/doctor/): check health when something is wrong

## Resources

- [Ollama](https://ollama.com/): run models locally with one command
- [llama.cpp server](https://github.com/ggml-org/llama.cpp/tree/master/tools/server): an OpenAI-compatible server for GGUF models
- [OpenRouter](https://openrouter.ai/): one API key for many hosted models
