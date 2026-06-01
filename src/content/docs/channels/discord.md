---
title: "Discord"
description: "Connect Netclaw to your Discord server."
---

Netclaw connects to Discord over the [Gateway WebSocket API](https://discord.com/developers/docs/events/gateway) -- outbound connections only, no public URLs needed. You create a Discord bot, give netclaw one token, and it shows up in your server.

## Prerequisites

- Netclaw installed and initialized ([`netclaw init`](/cli/init/))
- A Discord server where you have the "Manage Server" permission
- [Developer Mode](https://support.discord.com/hc/en-us/articles/206346498) enabled in Discord (for copying IDs)

## Create a Discord bot

Head to [discord.com/developers/applications](https://discord.com/developers/applications) and create a new application.

![Discord Applications page](/screenshots/output/discord-setup-applications.png)

### 1. Create the application

Click **New Application**, give it a name, and hit Create.

![New Application dialog](/screenshots/output/discord-setup-create-app.png)

### 2. Copy the bot token

Go to **Bot** in the left sidebar. Click **Reset Token** to generate a bot token and copy it immediately -- Discord only shows it once.

![Bot settings page](/screenshots/output/discord-setup-bot-settings.png)

If you lose the token, you can always reset it here, but you'll need to update your netclaw config with the new value.

### 3. Enable Message Content Intent

Scroll down on the Bot page to **Privileged Gateway Intents** and enable **Message Content**. Without this, netclaw receives message events but can't read their text.

![Privileged Gateway Intents with Message Content enabled](/screenshots/output/discord-setup-bot-intents.png)

### 4. Set up OAuth2 scopes and permissions

Go to **OAuth2 > URL Generator**. Check the `bot` scope.

![OAuth2 scopes selection](/screenshots/output/discord-setup-oauth-scopes.png)

Then select bot permissions:

![Bot permissions checklist](/screenshots/output/discord-setup-bot-permissions.png)

**Required permissions:** Send Messages, Create Public Threads, Send Messages in Threads, Manage Threads, Embed Links, Read Message History, Add Reactions.

Manage Threads is needed so netclaw can rename threads with session titles as conversations progress.

### 5. Install the bot to your server

Copy the generated URL at the bottom of the page.

![Generated OAuth2 URL](/screenshots/output/discord-setup-oauth-url.png)

Open it in your browser. Discord asks which server to add the bot to -- pick yours and click **Continue**.

![OAuth install approval dialog](/screenshots/output/discord-setup-install-dialog.png)

Discord then lists the permissions the bot is requesting. Confirm they match the set from step 4 and click **Authorize**.

![Discord OAuth2 permissions confirmation with the Authorize button](/screenshots/output/discord-setup-authorize-dialog.png)

The bot appears in your server's member list once the daemon is running.

### 6. Set Installation to None

Under **Installation** in the left sidebar, set the install method to **None**. This prevents users from installing the bot to other servers through Discord's app directory.

![Installation settings set to None](/screenshots/output/discord-setup-installation-none.png)

If you want others to install via a link you control, use **Discord Provided Link** instead.

![Installation with Discord Provided Link](/screenshots/output/discord-setup-installation-provided-link.png)

## Configure netclaw

Easiest path: [`netclaw init`](/cli/init/). Step 3 handles channel selection and token entry.

![Channel selection during netclaw init](/screenshots/output/init-03-channels.png)

Pick Discord, paste your bot token, done.

For manual setup, store the token with [`netclaw secrets`](/cli/secrets/):

```bash
netclaw secrets set Discord.BotToken your-bot-token
```

Then enable Discord in `~/.netclaw/config/netclaw.json`:

```json
{
  "Discord": {
    "Enabled": true,
    "DefaultChannelId": "123456789012345678"
  }
}
```

Environment variables work too:

```bash
export NETCLAW_Discord__BotToken="your-bot-token"
export NETCLAW_Discord__Enabled="true"
```

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Turn on Discord |
| `BotToken` | string | -- | Bot token from the Developer Portal. Store with `netclaw secrets set`. |
| `DefaultChannelId` | string | -- | Channel ID for the default channel |
| `MentionOnly` | bool | `true` | Only respond when @-mentioned |
| `AllowDirectMessages` | bool | `false` | Accept DMs |
| `MentionRequiredInDm` | bool | `false` | Require @-mention even in DMs |
| `AllowedChannelIds` | string[] | `[]` | Channel allow-list. Empty + no default = all channel messages denied |
| `AllowedUserIds` | string[] | `[]` | User allow-list. Empty = everyone in allowed channels is accepted |
| `ChannelAudiences` | object | `{}` | Per-channel [audience](/security/security-model/) overrides. Keys are channel IDs or `"dm"`. Values: `"personal"`, `"team"`, `"public"`. |

The token lives in `~/.netclaw/config/secrets.json` (encrypted at rest).

## Access control

Discord ACL is **default-deny**. Three settings decide who talks to the bot and where.

### Channels

The bot only responds in channels that pass the allow-list:

- `DefaultChannelId` allows one channel
- `AllowedChannelIds` allows multiple
- **If both are empty, every channel message is denied.** This is the number one setup mistake.

```json
{
  "Discord": {
    "DefaultChannelId": "123456789012345678",
    "AllowedChannelIds": ["234567890123456789", "345678901234567890"]
  }
}
```

Finding channel IDs: right-click a channel in Discord with Developer Mode on, click "Copy Channel ID."

### Users

`AllowedUserIds` restricts who gets responses:

- Empty (default) -- everyone in allowed channels is accepted
- Non-empty -- only listed user IDs get responses, everyone else is silently dropped

Finding user IDs: right-click a user in Discord with Developer Mode on, click "Copy User ID."

Users in `AllowedUserIds` are treated as `TrustedInternal` by the [security model](/security/security-model/). Everyone else is `UntrustedExternal`.

### Direct messages

DMs are off by default:

```json
{
  "Discord": {
    "AllowDirectMessages": true
  }
}
```

With DMs on, users can just type normally -- `MentionRequiredInDm` defaults to `false`, so no @-mention needed. Each user gets a single long-running DM session (unlike channels, where each root message starts a new session).

:::caution
With `AllowDirectMessages: true` and `AllowedUserIds` empty, any server member can DM the bot. Lock down `AllowedUserIds` if that's not what you want.
:::

### Audience overrides

Override the default audience per-channel with `ChannelAudiences`:

```json
{
  "Discord": {
    "ChannelAudiences": {
      "123456789012345678": "team",
      "dm": "personal"
    }
  }
}
```

The `"dm"` key is reserved -- it matches every direct message rather than a channel ID. A channel-ID entry takes precedence over it. An unrecognized audience value is rejected outright: the message is denied rather than falling back to a default.

[Security Model](/security/security-model/) has the full breakdown on how audiences map to tools and permissions.

## Behavior in Discord

### Threads and sessions

When someone messages the bot in a regular channel, netclaw creates a public thread on its first reply and continues the conversation there. The thread starts as "Netclaw" and netclaw renames it once the LLM generates a session title.

Thread replies don't need a @-mention -- if there's an active session in the thread, the bot responds to everything.

Idle conversations are freed from memory after 2 hours (individual sessions after 1 hour, unless an approval request is pending). On daemon restart, up to 200 messages of thread history are backfilled so in-progress conversations resume.

### Mention behavior

`MentionOnly: true` (the default) means the bot ignores messages that don't @-mention it. Two exceptions:

- **Thread replies** -- if a thread already has an active session, the bot responds without needing a mention
- **Daemon restart recovery** -- if the daemon restarts and a user continues a thread, the session is re-created from the thread's message history

Netclaw strips the @-mention before passing text to the LLM.

### Message formatting

Discord natively renders markdown -- bold, italic, code blocks, headers, lists, links. Responses longer than 2,000 characters are split at newline boundaries.

### Tool approval

When a tool call needs approval, netclaw posts an interactive button prompt in the thread. The prompt shows the tool name, action, and pattern(s). The full set is five buttons: **Once**, **This chat**, **Always here**, **Always anywhere**, and **Deny** -- "Always anywhere" grants the command everywhere, so use it sparingly. netclaw shows fewer when some don't apply -- a command it can't cleanly parse (shell control flow, or unbalanced quotes) drops to just **Once** and **Deny**. Only the user who triggered the request can approve.

If posting the button prompt fails, netclaw falls back to a text prompt where you reply with the letter shown next to each option.

After a decision, netclaw updates the original message in-place with a checkmark or denied icon.

### Reminders

Reminder targets for Discord users accept several formats:

- `<@123456789012345678>` or `<@!123456789012345678>` -- standard Discord mention
- `@123456789012345678` -- shorthand
- `123456789012345678` -- raw user ID
- `dm:123456789012345678` -- explicit DM channel

### Proactive messaging

Discord does not have proactive messaging tools yet. Unlike Slack's `send_slack_message` and `lookup_slack_user`, there are no equivalent tools for initiating conversations in Discord channels or looking up users by name. Reminders work, but the bot can't start new threads on its own.

### Ignored messages

The bot drops: empty messages (no text, no attachments), other bots' messages, its own messages, DMs when `AllowDirectMessages` is off, and un-mentioned channel messages when `MentionOnly` is on and there's no active thread.

Messages over 4,000 characters are truncated.

## Verify it works

Restart the daemon and check status:

```bash
netclaw daemon stop && netclaw daemon start
netclaw status
```

Discord should show `connected`. If it shows `disabled` or `disconnected`, check the [troubleshooting guide](/channels/troubleshooting/).

Then @-mention the bot in an allowed channel. If it creates a thread and responds, you're set.

:::note
`netclaw doctor` doesn't validate Discord tokens yet. For now, use `netclaw status` and check the daemon logs.
:::

## Troubleshooting

Common problems and fixes are in [Channel Troubleshooting](/channels/troubleshooting/). The hits:

- **Connected but silent** -- `AllowedChannelIds` is empty and no `DefaultChannelId` is set, so all traffic gets denied
- **Invalid bot token** -- HTTP 401 on startup means the token is wrong or was regenerated in the Developer Portal
- **Gateway disconnected** -- the daemon couldn't establish a connection. Usually a network issue or [Discord outage](https://discordstatus.com/).
- **Message Content privileged intent not enabled** -- turn it on under Privileged Gateway Intents in the [Developer Portal](https://discord.com/developers/applications)

## Next steps

- [Configure audiences and approval gates](/security/security-model/) to control what tools are available in each channel
- [Set up systemd](/deployment/systemd/) so the daemon stays running after reboots
- [Add Slack](/channels/slack/) if your team uses both

## Related pages

- [`netclaw init`](/cli/init/) -- Discord setup at step 3
- [`netclaw secrets`](/cli/secrets/) -- token management
- [`netclaw status`](/cli/status/) -- primary diagnostic tool for Discord
- [Security Model](/security/security-model/) -- audiences and approval gates
- [Channel Troubleshooting](/channels/troubleshooting/) -- error codes and debug logging
- [Slack](/channels/slack/) -- sibling channel integration

## External resources

- [Discord Developer Portal](https://discord.com/developers/applications) -- create and manage your bot
- [Discord Developer Docs: Getting Started](https://discord.com/developers/docs/getting-started) -- bot setup walkthrough
- [Discord: Privileged Intents](https://discord.com/developers/docs/events/gateway#privileged-intents) -- Message Content intent setup
- [Discord: Bot Permissions](https://discord.com/developers/docs/topics/permissions) -- permission reference
- [Discord: Enable Developer Mode](https://support.discord.com/hc/en-us/articles/206346498) -- how to copy channel and user IDs
- [Discord Status](https://discordstatus.com/) -- check for outages
