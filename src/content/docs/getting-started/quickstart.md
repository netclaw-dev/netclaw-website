---
title: "Quickstart"
description: "Get Netclaw running in minutes with the init wizard."
---

Install netclaw, run the setup wizard, and start chatting. Takes about 5 minutes.

## 1. Install

```bash
curl -sSL https://releases.netclaw.dev/install.sh | bash
```

See [Installation](/getting-started/installation/) for Windows, Docker, and build-from-source options.

## 2. Run the setup wizard

```bash
netclaw init
```

The wizard covers four steps for Personal posture (five for Team/Public — more on that below).

### Pick a provider

![Provider selection](/screenshots/output/init-01-provider-list.png)

![Model selection](/screenshots/output/init-01-model-select.png)

Choose an LLM provider and enter credentials. Self-hosted providers like Ollama need an endpoint URL. Once credentials pass a connectivity check, you pick a default model.

Use [`netclaw provider`](/cli/provider/) to add more providers later.

### Set your identity

![Identity step](/screenshots/output/init-02-identity.png)

Four substeps in order: agent name → communication style → your name → timezone. All four fields pre-fill when you re-run `netclaw init` on an existing install.

### Set your security posture

![Security posture selection](/screenshots/output/init-02-security-posture.png)

Pick how much you trust the environment. **Personal** is single-user with full tool access. **Team** and **Public** are progressively more restrictive. See [Security Model](/security/security-model/) for details.

### Enabled features (Team / Public only)

If you chose Team or Public posture, the wizard adds a step to select which feature sets are active. Personal posture skips this step and goes straight to the health check.

### Health check

![Health check](/screenshots/output/init-05-health-check.png)

The wizard validates provider connectivity, writes config, and starts the daemon. When all checks pass, netclaw launches chat automatically — you land in the chat TUI without running anything else.

If the health check finishes with warnings, the wizard displays: "Setup complete with warnings. Run `netclaw daemon start`, then `netclaw chat`. Adjust settings with `netclaw config`." Fix the flagged issue and retry.

:::note
Channels (Slack, Discord, Mattermost), search providers, and network exposure are configured after init via [`netclaw config`](/cli/config/). Run `netclaw config` any time — it autosaves on completion.
:::

## 3. First chat session

<!-- TODO(screenshots): chat-session-start.png — capture after release; epic #55 -->

On a clean health check, init drops you straight into the chat TUI. The agent introduces itself and kicks off a personality-bootstrapping conversation — it asks about your work, your tools, and what you need help with. This builds your profile so future conversations have context.

See [Your First Conversation](/getting-started/first-conversation/) for the full walkthrough of what happens next.

### Headless mode

Don't need the TUI? Send a one-shot prompt from your terminal:

```bash
netclaw chat -p "what's the weather in Chicago?"
```

Pipe output to other tools with `--json`. See [`netclaw chat`](/cli/chat/) for the full reference.

## What's next

- [Your First Conversation](/getting-started/first-conversation/) — personality bootstrapping and your first real interaction
- [`netclaw config`](/cli/config/) — connect channels, enable search, set network exposure
- [`netclaw doctor`](/cli/doctor/) — diagnose issues if something didn't work
- [`netclaw status`](/cli/status/) — check daemon health and connector states
- [Slack](/channels/slack/) / [Discord](/channels/discord/) — full channel setup guides
