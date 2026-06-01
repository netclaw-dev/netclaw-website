---
title: "Mattermost"
description: "Connect Netclaw to your self-hosted Mattermost server."
---

Netclaw connects to Mattermost over a WebSocket for events and the REST API for replies. You run a bot account on your Mattermost server, give netclaw the bot's access token, and it shows up as a bot user -- same default-deny ACL model as [Slack](/channels/slack/) and [Discord](/channels/discord/), against infrastructure you host yourself.

## Prerequisites

- Netclaw installed and initialized ([`netclaw init`](/cli/init/))
- A self-hosted Mattermost server reachable from the daemon
- System Console access on that server (to enable bot accounts and create the bot)

## Create a bot account

Mattermost bots authenticate with a **personal access token**, not OAuth. Two server settings have to be on before you can create one.

### 1. Enable bot accounts and access tokens

In the **System Console**, under **Integrations > Bot Accounts**, set **Enable Bot Account Creation** to `true`. Then, under **Integrations > Integration Management**, turn on **Enable Personal Access Tokens**.

![System Console Bot Accounts settings with Enable Bot Account Creation set to True](/screenshots/output/mattermost-bot-accounts.png)

Both are off by default on a fresh Mattermost install -- skipping either is the most common setup snag.

### 2. Create the bot and copy its token

Under **Integrations > Bot Accounts**, click **Add Bot Account** and give it a username (e.g. `netclaw`) and display name. Then click **Create New Token**: Mattermost reveals the access token **once**, in a banner -- copy it right then. That token (not the Token ID shown in the list) is the `BotToken` netclaw needs.

![Mattermost Bot Accounts page listing the netclaw bot with its Create New Token control](/screenshots/output/mattermost-create-bot.png)

### 3. Add the bot to your team and channels

A bot only sees channels it belongs to. Add it to the target team, then invite it to each channel where it should respond (`/invite @netclaw`, or through the channel member menu).

## Configure netclaw

Easiest path: [`netclaw init`](/cli/init/) walks channel selection and token entry -- pick Mattermost, enter your server URL and bot token, and it writes the config for you.

For manual setup, store the token with [`netclaw secrets`](/cli/secrets/):

```bash
netclaw secrets set Mattermost.BotToken your-bot-token
```

Then enable Mattermost and point it at your server in `~/.netclaw/config/netclaw.json`:

```json
{
  "Mattermost": {
    "Enabled": true,
    "ServerUrl": "https://mm.example.com",
    "DefaultChannelId": "abcdefghijklmnopqrstuvwxyz"
  }
}
```

Environment variables work too:

```bash
export NETCLAW_Mattermost__BotToken="your-bot-token"
export NETCLAW_Mattermost__Enabled="true"
```

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Turn on Mattermost |
| `ServerUrl` | string | -- | Base URL of your Mattermost server. Required when enabled. |
| `BotToken` | string | -- | Bot personal access token. Store with `netclaw secrets set`. |
| `CallbackUrl` | string | -- | URL Mattermost can reach for interactive button callbacks. Set it to get approval buttons; leave it unset for text-reply approvals (see [Tool approval](#tool-approval)). |
| `DefaultChannelId` | string | -- | A 26-character channel ID. Allows one channel without listing it in `AllowedChannelIds`. |
| `MentionOnly` | bool | `true` | Only respond when @-mentioned in channels |
| `AllowDirectMessages` | bool | `false` | Accept DMs |
| `MentionRequiredInDm` | bool | `false` | Require @-mention even in DMs |
| `AllowedChannelIds` | string[] | `[]` | Channel allow-list. Empty + no default = all channel messages denied |
| `AllowedUserIds` | string[] | `[]` | User allow-list. Empty = everyone in allowed channels is accepted |
| `ChannelAudiences` | object | `{}` | Per-channel [audience](/security/security-model/) overrides. Keys are channel IDs or `"dm"`. Values: `"personal"`, `"team"`, `"public"`. |

The token lives in `~/.netclaw/config/secrets.json` (encrypted at rest). Mattermost channel and user IDs are 26-character alphanumeric strings -- the System Console lists them, or pull them from the [REST API](https://api.mattermost.com/).

## Access control

Mattermost ACL is **default-deny**, evaluated the same way as Slack and Discord.

### Channels

The bot only responds in channels that pass the allow-list:

- `DefaultChannelId` allows one channel
- `AllowedChannelIds` allows multiple
- **If both are empty, every channel message is denied.** This is the number one setup mistake.

```json
{
  "Mattermost": {
    "DefaultChannelId": "abcdefghijklmnopqrstuvwxyz",
    "AllowedChannelIds": ["abcdefghijklmnopqrstuvwxyz", "zyxwvutsrqponmlkjihgfedcba"]
  }
}
```

### Users

`AllowedUserIds` restricts who gets responses:

- Empty (default) -- everyone in allowed channels is accepted
- Non-empty -- only listed user IDs get responses, everyone else is silently dropped

Users in `AllowedUserIds` are treated as `TrustedInternal` by the [security model](/security/security-model/). Everyone else is `UntrustedExternal`.

:::caution
Always set `AllowedUserIds` on a production server. With it empty, any user the bot can see can click an approval button in a shared channel and approve a tool call on someone else's behalf. The action-token check still blocks *forged* clicks -- but a legitimate click from the wrong person is a real one.
:::

### Direct messages

DMs are off by default:

```json
{
  "Mattermost": {
    "AllowDirectMessages": true
  }
}
```

With DMs on, users type normally -- `MentionRequiredInDm` defaults to `false`, so no @-mention needed.

### Audience overrides

Audience resolves per message: `ChannelAudiences[channelId]` wins first, then `ChannelAudiences["dm"]` for direct messages, then a fallback that lands on `Team` for allow-listed channels and users and `Public` for everything else. Override it explicitly:

```json
{
  "Mattermost": {
    "ChannelAudiences": {
      "abcdefghijklmnopqrstuvwxyz": "team",
      "dm": "personal"
    }
  }
}
```

The `"dm"` key is reserved -- it matches every direct message rather than a channel ID, and a channel-ID entry takes precedence over it. An unrecognized audience value is rejected outright: the message is denied rather than falling back to a default.

[Security Model](/security/security-model/) has the full breakdown on how audiences map to tools and permissions.

## Behavior in Mattermost

### Threads and sessions

Each thread is its own isolated session, keyed by `{channelId}/{rootPostId}`, and the bot replies in-thread. On daemon restart, thread history is backfilled so in-progress conversations pick up where they left off.

### Mention behavior

`MentionOnly: true` (the default) means the bot ignores channel messages that don't @-mention it. Thread replies are the exception -- once a thread has an active session, the bot responds to everything in it without a mention. Netclaw strips the @-mention before passing text to the LLM.

### Tool approval

When a tool call needs approval, how netclaw asks depends on `CallbackUrl`:

- **`CallbackUrl` set** -- netclaw posts interactive buttons. The full prompt offers five choices, in order: **Once**, **This chat**, **Always here**, **Always anywhere**, **Deny**. Clicks come back over an inbound HTTP POST to `/api/mattermost/actions`, which the daemon only exposes when a callback URL is configured. Each button carries a one-time, post-bound token that expires after 12 hours.
- **`CallbackUrl` unset** -- approvals fall back to text replies: reply with the letter shown next to each option. No inbound HTTP surface is opened.

netclaw shows fewer than five when some don't apply -- a command it can't cleanly parse (shell control flow, or unbalanced quotes) collapses to just **Once** and **Deny**, and the reply letters track whatever is shown. **Always anywhere** is the broadest grant: it approves the command's verb for every session everywhere and persists to `tool-approvals.json`. Reach for **Always here** or narrower unless you really mean it.

The token store is in-memory: buttons posted before a daemon restart return "no longer valid" when clicked afterward. The pending request survives on the session, so ask the agent to re-issue the prompt.

:::caution
Reach `/api/mattermost/actions` over TLS. The callback trusts the user ID in the payload as the clicker's identity, so a network attacker who can rewrite headers in plaintext could impersonate another user.
:::

### Proactive messaging

The LLM can start a conversation with the `send_mattermost_message` tool. It takes a `channel_id` or a `user_id` (one or the other), posts a new thread root, and routes replies in that thread back to a live session. ACL rules still apply -- DMing a `user_id` also requires `AllowDirectMessages: true`.

### Reminders

[Reminders](/configuration/reminders/) reach Mattermost through `channel` delivery with `delivery_transport: "mattermost"`. (In-thread `current_session` delivery isn't available from a Mattermost session yet -- `set_reminder` only accepts it for Slack, Discord, the TUI, and SignalR.) Because Mattermost user IDs and channel IDs are both 26-character strings, channel-delivery targets need a prefix:

- `@<userId>` -- delivers to that user's DM
- `channel:<channelId>` -- delivers to that channel

A bare ID with no prefix is rejected with a disambiguation error. Unlike Discord, DM delivery works, because a Mattermost DM is itself an addressable channel.

## Verify it works

Restart the daemon, then @-mention the bot in an allowed channel:

```bash
netclaw daemon stop && netclaw daemon start
```

If it replies in a thread, you're set.

![Netclaw replying to a testuser @-mention in a Mattermost thread](/screenshots/output/mattermost-conversation.png)

`netclaw status` doesn't list Mattermost yet (it covers Slack and Discord), so when something's off, the daemon logs are where to look. A bad token, an unreachable server, or any connection failure is contained there -- the Mattermost channel degrades on its own and the daemon plus every other channel keeps running. See [Troubleshooting](#troubleshooting) below for the common messages.

## Troubleshooting

Common problems and fixes are in [Channel Troubleshooting](/channels/troubleshooting/). The hits:

- **Connected but silent** -- `AllowedChannelIds` is empty and no `DefaultChannelId` is set, so all traffic gets denied; or the bot was never added to the channel.
- **`Mattermost is enabled but Mattermost:ServerUrl is not configured`** -- add `Mattermost.ServerUrl` to `netclaw.json`.
- **`Mattermost rejected the bot token (HTTP 401)`** -- re-issue the bot token and update `secrets.json`.
- **Can't create a bot or token** -- Enable Bot Account Creation and Enable Personal Access Tokens are both off by default in the System Console.

:::note
Running Mattermost in a container on Apple Silicon? The [`mattermost/mattermost-preview`](https://hub.docker.com/r/mattermost/mattermost-preview) image is amd64-only -- start it with `--platform linux/amd64`. It's a testing image with a bundled database; for production, deploy the [`mattermost/mattermost-team-edition`](https://hub.docker.com/r/mattermost/mattermost-team-edition) image and a real database per [Mattermost's Docker install guide](https://docs.mattermost.com/install/install-docker.html).
:::

## Next steps

- [Configure audiences and approval gates](/security/security-model/) to control what tools are available in each channel
- [Set up systemd](/deployment/systemd/) so the daemon stays running after reboots
- [Add Slack](/channels/slack/) or [Discord](/channels/discord/) if your team uses more than one

## Related pages

- [`netclaw init`](/cli/init/) -- Mattermost setup at step 3
- [`netclaw secrets`](/cli/secrets/) -- token management
- [`netclaw status`](/cli/status/) -- primary diagnostic for Mattermost
- [Security Model](/security/security-model/) -- audiences and approval gates
- [Channel Troubleshooting](/channels/troubleshooting/) -- error codes and debug logging

## External resources

- [Mattermost](https://mattermost.com/) -- the project, if you don't already run a server
- [Mattermost: Bot accounts](https://developers.mattermost.com/integrate/reference/bot-accounts/) -- creating and managing bots
- [Mattermost: Personal access tokens](https://developers.mattermost.com/integrate/reference/personal-access-token/) -- enabling and issuing tokens
- [Mattermost: Enable bot account creation](https://docs.mattermost.com/configure/integrations-configuration-settings.html) -- the System Console settings
- [Mattermost: Install with Docker](https://docs.mattermost.com/install/install-docker.html) -- container deployment, including the [official images on Docker Hub](https://hub.docker.com/u/mattermost)
- [Mattermost API reference](https://api.mattermost.com/) -- the REST endpoints netclaw uses for replies
