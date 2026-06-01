---
title: "Quickstart"
description: "Get Netclaw running in minutes with the init wizard."
---

Install netclaw, run the setup wizard, talk to your agent. Takes about 5 minutes.

## 1. Install

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash
```

See [Installation](/getting-started/installation/) for Windows, Docker, and build-from-source options.

## 2. Run the setup wizard

```bash
netclaw init
```

The wizard walks you through everything. Here's what to expect.

### Pick a provider

![Provider endpoint configuration](/screenshots/output/init-step1-provider-endpoint.png)

Choose an LLM provider and enter credentials. Self-hosted providers like Ollama need an endpoint URL. Once credentials pass a connectivity check, you pick a default model:

![Model selection](/screenshots/output/init-step1-provider-model.png)

Use [`netclaw provider`](/cli/provider/) to add more providers later.

### Set your security posture

![Security posture selection](/screenshots/output/init-step2-security-posture.png)

Pick how much you trust the environment. **Personal** is single-user with full tool access. **Team** and **Public** are progressively more restrictive. See [Security Model](/security/security-model/) for details.

### Connect channels (optional)

![Channel selection](/screenshots/output/init-03-channels.png)

Wire up Slack, Discord, or [Mattermost](/channels/mattermost/). Each channel needs a token — the wizard prompts for them and tests connectivity before moving on.

![Slack bot token entry](/screenshots/output/init-step3-slack-bot-token.png)

Tokens are masked and stored encrypted. See the [Slack](/channels/slack/) or [Discord](/channels/discord/) pages for full setup guides including app creation.

### Set your identity

![Your name](/screenshots/output/init-step7-your-name.png)

Tell netclaw who you are. This sets the owner identity for the agent.

![Communication style](/screenshots/output/init-step7-communication-style.png)

Pick a personality style — this shapes how the agent talks to you.

### Choose network exposure

![Exposure mode selection](/screenshots/output/init-step9-exposure-mode.png)

**Local** (default) means the daemon only listens on loopback. Tailscale and Cloudflare Tunnel options make it reachable from other machines. See [Exposure Modes](/deployment/exposure-modes/) and [Pairing Remote Devices](/guides/pairing-remote-devices/).

### Health check

![Health check results](/screenshots/output/init-step10-healthcheck.png)

The wizard validates your config — provider connectivity, channel tokens, network setup. All green means the daemon starts automatically.

## 3. Start chatting

```bash
netclaw chat
```

![First chat session](/screenshots/output/chat-session-start.png)

The agent introduces itself and kicks off a personality bootstrapping conversation — it asks about your work, your tools, and what you need help with. This builds your profile so future conversations have context.

See [Your First Conversation](/getting-started/first-conversation/) for the full walkthrough of what happens next.

### Headless mode

Don't need the TUI? Send a one-shot prompt from your terminal:

```bash
netclaw chat -p "what's the weather in Chicago?"
```

![Headless CLI execution](/screenshots/output/single-shot-cli-execution.png)

Pipe output to other tools with `--json`. See [`netclaw chat`](/cli/chat/) for the full reference.

## What's next

- [Your First Conversation](/getting-started/first-conversation/) — personality bootstrapping and your first real interaction
- [`netclaw doctor`](/cli/doctor/) — diagnose issues if something didn't work
- [`netclaw status`](/cli/status/) — check daemon health and connector states
- [Slack](/channels/slack/) / [Discord](/channels/discord/) — full channel setup guides
