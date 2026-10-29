---
title: "netclaw init"
description: "First-run setup wizard: provider, identity, security posture, enabled features, and health check."
---

`netclaw init` is the first-run wizard. It takes a fresh install to a working chat session in four steps (Personal posture) or five (Team and Public). Run it once. For channels, search, exposure mode and skill sources, use [`netclaw config`](/cli/config/) afterwards.

## Usage

```bash
netclaw init
```

`init` has no flags and no non-interactive mode. To set up a machine without a terminal, write `netclaw.json` yourself or pass `NETCLAW_*` environment variables, as the [Docker deployment](/deployment/docker/) page does.

:::caution
Netclaw 0.27.1 and earlier wrote every keystroke typed into `init` and the other full-screen commands, API keys and tokens included, to `netclaw-<command>-trace.log` in the temp directory. 0.28.0 removed it ([GHSA-mh95-h6p6-c9j3](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-mh95-h6p6-c9j3)). If you ran those commands on an older build, delete the leftover files and rotate the secrets you typed. See [Upgrading](/guides/upgrading/).
:::

## Before you begin

- An LLM provider: an [OpenRouter](https://openrouter.ai/docs) API key is the quickest, or [Ollama](https://ollama.com/download) running locally. Anthropic, OpenAI, DeepSeek, Venice.ai and GitHub Copilot work too.
- Nothing for channels, search, browser automation or network exposure. All of that is in `netclaw config`.

## Keys

| Key | Action |
|-----|--------|
| `↑` / `↓` | Move through a list |
| `Enter` | Accept and go to the next screen |
| `Space` | Toggle a feature (feature step only) |
| `Esc` | In the wizard, go back one screen. Does nothing on the first screen. On the existing-install menu it quits `init`. See [existing install](#running-init-on-an-existing-install). |
| `Ctrl+Q` | Quit |

## Wizard steps

The header counts steps as "of 5" until you pick a posture. Choose Personal and the count drops to 4.

### 1. Provider

Pick a provider, enter credentials, and choose a default model.

![Netclaw Setup, Step 1 of 5, LLM Provider, with eight providers listed and Anthropic highlighted](/screenshots/output/init-01-provider-list.png)

The wizard lists Anthropic, DeepSeek, GitHub Copilot, Ollama, OpenAI, OpenAI-compatible (llama.cpp / vLLM / DwarfStar ds4), OpenRouter and Venice.ai. Ollama and OpenAI-compatible ask for an endpoint next.

The endpoint field arrives pre-filled with `http://localhost:11434` and the cursor sits at the end, so press `Backspace` to clear the default before you type your own. Enter the server address, such as `http://llm.example.internal:8080`, with or without `/v1`. If the connectivity check fails, press `Enter` to retry, `M` to type a model ID by hand, or `Esc` to go back.

Hosted providers ask for an API key. Self-hosted ones treat the key as optional.

Once the connectivity check passes, pick a default model from the discovered list, or choose **Enter model ID manually...**.

![Model selection step listing one discovered model, qwen2:0.5b, and an Enter model ID manually option](/screenshots/output/init-01-model-select.png)

The discovered models come first and the manual entry is always the last row. Add or swap providers later with [`netclaw provider`](/cli/provider/), and reassign roles with [`netclaw model`](/cli/model/).

### 2. Identity

Four prompts in order:

| Prompt | Notes |
|--------|-------|
| `Agent name:` | `Netclaw` if you leave it |
| `Communication style:` | Concise & casual, Concise & formal, Detailed & casual or Detailed & formal |
| `Your name:` | So the agent knows what to call you |
| `Your timezone:` | An IANA id such as `America/Chicago`. Starts as `UTC`. Used for time-aware answers and scheduling |

![Netclaw Setup, Step 2 of 5, Identity, asking for a communication style with four options](/screenshots/output/init-02-identity.png)

The communication style is the second of the four identity prompts. A timezone that isn't an IANA id gets an inline message such as `Unknown time zone 'Foo/Bar'. Use an IANA id such as America/Chicago.`, and `Central Standard Time` is refused because it has spaces. On a minimal Linux image without `tzdata`, every zone except `UTC` is refused. Webhook URLs and the workspaces directory aren't asked here. They live in `netclaw config`.

### 3. Security posture

Pick who will use this instance.

![Netclaw Setup, Step 3 of 5, Security Posture, listing Personal, Team and Public with a short explanation under the list](/screenshots/output/init-02-security-posture.png)

The grey text under the list summarizes what each posture allows.

| Posture | For | Shell tool | Feature step |
|---------|-----|------------|--------------|
| **Personal** | You, on this machine | On, with approval prompts | Skipped, all features on |
| **Team** | Trusted teammates | Off | Shown, all features on |
| **Public** | Untrusted users | Off | Shown, all features off |

The wizard writes the posture, not per-audience tool lists. See [what init writes](#what-init-writes). The hint on this screen points to **Channels** in `netclaw config` for per-channel overrides.

### 4. Enabled features (Team and Public only)

Six toggles that apply to every audience:

| Feature | Key written |
|---------|-------------|
| Memory | `Memory.Enabled` |
| Search | `Search.Enabled` |
| Skills | `SkillSync.Enabled` |
| Scheduling | `Scheduling.Enabled` |
| SubAgents | `SubAgents.Enabled` |
| Webhooks | `Webhooks.Enabled` |

Press `Space` to toggle and `Enter` to continue.

![Netclaw Setup, Step 4 of 5, Feature Selection, with Memory, Search, Skills, Scheduling, SubAgents and Webhooks all checked](/screenshots/output/init-04-enabled-features.png)

This is the Team posture, which starts with all six on. Public starts with all six off.

### Health check

The last step starts by itself when you leave the previous one. There's no extra `Enter`. It ticks off the provider, the model and the memory backend, writes the configuration, applies it to the daemon and validates the result.

![Netclaw Setup, Step 4 of 4, Health Check, four green checks and an Applying configuration spinner](/screenshots/output/init-05-health-check.png)

That's the Personal run, ending at 4 of 4. Team and Public have the extra features step, so their health check reads Step 5 of 5. The checks are identical and only the counter differs.

On a clean pass the wizard opens `netclaw chat` and your agent introduces itself. If anything fails, the failed check shows `✗`, and you stay on the summary with:

```text
Setup complete with warnings. Run `netclaw daemon start`, then `netclaw chat --onboarding`. Adjust settings with `netclaw config`.
```

Files written before a failure stay on disk. Fix the cause (on a bare Linux image it's usually a missing `libicu`, see [installation troubleshooting](/getting-started/installation/#failed-to-start-daemon-process-exited-with-code-134)), run `netclaw daemon start`, then `netclaw chat --onboarding`. That command starts the identity interview the wizard would have opened. [`netclaw doctor`](/cli/doctor/) shows what else is wrong.

## What init writes

Here's the Personal config from a real run against an OpenAI-compatible server. The model key is `<provider>-<model id>`, so a model named `demo-model` becomes `openai-compatible-demo-model`:

```json
{
  "configVersion": 1,
  "Providers": {
    "openai-compatible": { "Type": "openai-compatible", "Endpoint": "http://llm.example.internal:8080" }
  },
  "Models": {
    "Definitions": {
      "openai-compatible-demo-model": {
        "Provider": "openai-compatible",
        "ModelId": "demo-model",
        "Provenance": "Live"
      }
    },
    "Roles": { "Main": "openai-compatible-demo-model" }
  },
  "Security": { "DeploymentPosture": "Personal", "ShellExecutionMode": "HostAllowed", "StrictDefaults": true },
  "Tools": { "ShellMode": "HostAllowed" },
  "Identity": { "AgentName": "Netclaw", "CommunicationStyle": "Concise & casual", "UserTimezone": "UTC", "UserName": "Sam" }
}
```

| File | Contents |
|------|----------|
| `~/.netclaw/config/netclaw.json` | The config above. Team and Public add `Memory`, `Search`, `SkillSync`, `Scheduling`, `SubAgents` and `Webhooks` blocks with `Enabled`, and set `ShellExecutionMode` and `Tools.ShellMode` to `Off`. |
| `~/.netclaw/config/secrets.json` | Only if you entered an API key. Credentials are encrypted. |
| `~/.netclaw/identity/` | `SOUL.md`, `AGENTS.md` and `TOOLING.md` for the agent's personality and rules |
| `~/.netclaw/agents/` | Four [sub-agent](/skills/custom-subagents/) profiles: `task-worker`, `research-assistant`, `code-analyst` and `summarizer`. Profiles that already exist are never overwritten. |

`init` writes the posture, not `Tools.AudienceProfiles`. The daemon computes the per-audience profiles from the posture, so an absent profile is normal.

## Running init on an existing install

When `~/.netclaw/config/netclaw.json` exists, `init` opens an action menu instead of the wizard. Nothing changes until you confirm an action. The exception is the seed that `install.sh --channel` and `install.ps1` write, a config holding only `configVersion` and `Daemon.UpdateChannel`. That one opens the first-run wizard. A config `init` can't read still opens the menu, so a damaged file is never written over.

![Netclaw Setup menu reading Existing Netclaw install detected, with Redo identity setup, Open configuration editor, Start over from scratch and Cancel](/screenshots/output/init-existing-menu.png)

The menu says your config is untouched until you confirm an action.

| Option | Effect |
|--------|--------|
| **Redo identity setup** | Re-runs the four identity prompts with your current answers filled in and saves them to `netclaw.json`. Provider and settings stay. Then `Enter` starts the guided identity chat and `Esc` skips it. |
| **Open configuration editor** | Hands off to `netclaw config` |
| **Start over from scratch** | Opens the reset scope chooser |
| **Cancel** | Exits with everything as it was |

On this menu `Esc` exits `init`, the same as **Cancel**. In the reset screens it steps back one screen: from a confirmation to the scope chooser, then to this menu.

### Start over from scratch

Choosing **Start over from scratch** opens a scope chooser.

![Start over from scratch scope chooser with Reset setup only, Full reset and Cancel](/screenshots/output/init-start-over-scope.png)

Full reset is the destructive row, and its description says it deletes everything.

| Scope | What's deleted |
|-------|----------------|
| **Reset setup only** | Everything in `~/.netclaw/config/` (`netclaw.json`, `secrets.json`, `tool-approvals.json`, webhook routes, paired devices) and the identity and soul directories. Memory, sessions and skills stay. |
| **Full reset** | Everything under `~/.netclaw/` except `bin/`, where the installed binaries live |
| **Cancel** | Back to the menu |

Both scopes ask you to confirm twice. Each prompt puts **Cancel** first, so you have to move down to **Yes** and press `Enter` twice. The reset stops the daemon, deletes the files, then drops you into the wizard from step 1. If `daemon stop` refuses because the PID in `netclaw.pid` isn't shown to serve this home (see [`netclaw daemon`](/cli/daemon/#pid-n-is-not-shown-to-serve-home)), the reset prints the refusal and `Nothing was deleted.`

:::caution
**Reset setup only** also deletes `secrets.json` and your saved grants. Copy `~/.netclaw/config/` somewhere first if you want them back. See [Back up, restore and move netclaw](/guides/backup-and-restore/).
:::

## After init

After init, netclaw answers you locally through `netclaw chat` and nothing else. No channels are connected and the daemon listens on loopback only.

```bash
netclaw config    # channels, search, exposure mode, skill sources
netclaw doctor    # check config and connectivity
netclaw status    # confirm the daemon is healthy
```

## Related pages

- [`netclaw config`](/cli/config/): post-install settings for channels, search, exposure and skills
- [`netclaw doctor`](/cli/doctor/): diagnose config and connectivity problems
- [`netclaw provider`](/cli/provider/): add or swap providers without re-running init
- [`netclaw model`](/cli/model/): reassign model roles
- [Quickstart](/getting-started/quickstart/): the whole path from install to first chat

## Resources

- [OpenRouter documentation](https://openrouter.ai/docs): API keys, model catalog and rate limits
- [Ollama installation](https://ollama.com/download): local model runtime setup
- [llama.cpp server docs](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md): the OpenAI-compatible server the self-hosted option talks to
