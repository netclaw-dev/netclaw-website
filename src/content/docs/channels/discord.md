---
title: "Discord"
description: "Connect netclaw to your Discord server with a bot token, the Message Content intent and an allow-list."
---

netclaw connects to Discord over the [Gateway WebSocket API](https://docs.discord.com/developers/topics/gateway), which means outbound connections only and no public URL. You create a Discord bot, give netclaw one token, and it shows up in your server and answers in threads.

## Prerequisites

- netclaw installed and initialized ([`netclaw init`](/cli/init/))
- A Discord server where you have the **Manage Server** permission
- [Developer Mode](https://support.discord.com/hc/en-us/articles/206346498) turned on in Discord, so you can copy IDs

## Create a Discord bot

Open the [Discord Developer Portal](https://discord.com/developers/applications) and create an application.

![Discord Applications page](/screenshots/output/discord-setup-applications.png)

The Applications page lists your apps and has the **New Application** button.

### 1. Create the application

Click **New Application**, name it, and click Create.

![New Application dialog](/screenshots/output/discord-setup-create-app.png)

The name you pick here is what members see on the bot.

### 2. Copy the bot token

Open **Bot** in the sidebar, click **Reset Token**, and copy the token right away. Discord shows it once.

![Bot settings page](/screenshots/output/discord-setup-bot-settings.png)

If you lose it, reset it here and update netclaw with the new value.

### 3. Enable Message Content Intent

Scroll to **Privileged Gateway Intents** and turn on **Message Content**. It's the only privileged intent netclaw needs, so leave Server Members and Presence off. Without it netclaw receives message events but can't read their text, except in DMs and when the message mentions the bot.

![Privileged Gateway Intents with Message Content enabled](/screenshots/output/discord-setup-bot-intents.png)

The Message Content toggle sits at the bottom of the privileged intents list.

### 4. Set OAuth2 scopes and permissions

Open **OAuth2 > URL Generator** and check the `bot` scope.

![OAuth2 scopes selection](/screenshots/output/discord-setup-oauth-scopes.png)

Then select the bot permissions.

![Bot permissions checklist](/screenshots/output/discord-setup-bot-permissions.png)

The permissions netclaw uses:

| Permission | Why |
|------------|-----|
| Send Messages | Post replies |
| Create Public Threads | Open a thread on the first reply |
| Send Messages in Threads | Reply inside threads |
| Manage Threads | Rename a thread to the session title. Discord normally lets a thread's creator rename it, so this may be unnecessary. We haven't tested without it. |
| Read Message History | Backfill thread history after a restart |
| Attach Files | Upload files the agent produces |

The checklist in the screenshot also ticks View Channels, Create Private Threads, Embed Links and Add Reactions. netclaw doesn't call Create Private Threads, Embed Links or Add Reactions, so you can leave those off. Keep View Channels on so the bot can see the channels you add it to. The table is the source of truth for what netclaw needs.

### 5. Install the bot to your server

Copy the generated URL at the bottom of the page.

![Generated OAuth2 URL](/screenshots/output/discord-setup-oauth-url.png)

Open it in a browser. Discord asks which server to add the bot to. Pick yours and click **Continue**.

![OAuth install approval dialog](/screenshots/output/discord-setup-install-dialog.png)

The server list only offers servers where you have the Manage Server permission.

Discord then lists the permissions the bot is requesting. Check they match step 4 and click **Authorize**.

![Discord OAuth2 permissions confirmation with the Authorize button](/screenshots/output/discord-setup-authorize-dialog.png)

The bot appears in the member list. It shows as online once the daemon is running.

### 6. Set Installation to None

Under **Installation** in the sidebar, set the install method to **None**. That stops people installing the bot to other servers from the app directory.

![Installation settings set to None](/screenshots/output/discord-setup-installation-none.png)

If you want others to install through a link you control, choose **Discord Provided Link** instead.

## Configure netclaw

Run [`netclaw config`](/cli/config/), open **Channels**, enable Discord, and enter the bot token. netclaw stores it encrypted and saves the config.

![The Channels area in netclaw config](/screenshots/output/config-channels-menu.png)

The Channels area lists Slack, Discord and Mattermost with a checkbox each. Once an adapter is set up, its row also shows how many channels and users it allows.

### Manual setup

For scripted or headless installs, store the token with [`netclaw secrets`](/cli/secrets/):

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

Environment variables work too, with list entries indexed from zero:

```bash
export NETCLAW_Discord__BotToken="your-bot-token"
export NETCLAW_Discord__Enabled="true"
export NETCLAW_Discord__AllowedChannelIds__0="123456789012345678"
```

An edit to `netclaw.json` restarts the daemon by itself. A vault or environment change needs a restart you run:

| Where it runs | Restart |
|---------------|---------|
| Native | `netclaw daemon stop`, then `netclaw daemon start` |
| systemd user unit | `systemctl --user restart netclaw` |
| Docker | `docker restart <container>` |

:::caution
Keep each list in one place. Environment entries and `netclaw.json` entries merge by position, so a blank `NETCLAW_Discord__AllowedChannelIds__0` overwrites the first channel in the file. `netclaw config` → Channels writes the lists into `netclaw.json`.
:::

### How channel IDs are stored

Enter channel names or IDs, comma-separated, in `netclaw config` → Channels. netclaw resolves each against the Discord API and saves the canonical ID. `AllowedChannelIds` holds IDs, never display names. A name that can't be resolved stays verbatim with a warning and matches nothing until the bot can see the channel, then a background refresh rewrites it to the ID. A channel added one at a time is rejected on the spot if it doesn't resolve, and a real auth or network failure blocks the whole save.

:::caution
Since 0.24.0, channel display names you put in `AllowedChannelIds` by hand no longer match, and messages from those channels are silently dropped. Re-enter them through `netclaw config` → Channels. `DefaultChannelId` is already an ID.
:::

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Turn on Discord |
| `BotToken` | string | - | Bot token from the Developer Portal. Store with `netclaw secrets set`. |
| `DefaultChannelId` | string | - | Channel ID that's allowed without being listed in `AllowedChannelIds` |
| `MentionOnly` | bool | `true` | In channels, answer only when @-mentioned |
| `AllowDirectMessages` | bool | `false` | Accept DMs |
| `MentionRequiredInDm` | bool | `false` | Require an @-mention even in DMs |
| `MentionRequiredInThreadByChannel` | object | `{}` | Channel ID to bool. `true` makes a thread reply in that channel need an @-mention. See [Mention behavior](#mention-behavior). |
| `AllowedChannelIds` | string[] | `[]` | Channel allow-list. Empty with no default denies every channel message. |
| `AllowedUserIds` | string[] | `[]` | User allow-list. Empty accepts everyone in allowed channels. |
| `ChannelAudiences` | object | `{}` | Per-channel [audience](/security/security-model/) overrides. Keys are channel IDs or `"dm"`. Values are `"personal"`, `"team"` or `"public"`. |

The token lives in `~/.netclaw/config/secrets.json`, encrypted at rest.

## Access control

Discord ACL is **default-deny**. Three settings decide who talks to the bot and where.

### Channels

The bot answers only in channels that pass the allow-list. `DefaultChannelId` allows one, `AllowedChannelIds` allows more, and if both are empty every channel message is denied. That's the number one setup mistake.

```json
{
  "Discord": {
    "DefaultChannelId": "123456789012345678",
    "AllowedChannelIds": ["234567890123456789", "345678901234567890"]
  }
}
```

To find a channel ID with Developer Mode on, right-click the channel and choose **Copy Channel ID**.

### Users

`AllowedUserIds` restricts who gets answers. Empty means everyone in an allowed channel. Non-empty means only the listed users, and everyone else is dropped silently. To copy a user ID, right-click the user and choose **Copy User ID**.

Listed users are `TrustedInternal` in the [security model](/security/security-model/), and everyone else is `UntrustedExternal`.

### Direct messages

DMs are off by default. Turn them on with `"AllowDirectMessages": true`. Users then write without a mention, because `MentionRequiredInDm` defaults to `false`. Each user gets one long-running DM session, unlike channels, where each root message starts a new session.

:::caution
With DMs on and `AllowedUserIds` empty, any server member can DM the bot. Set `AllowedUserIds` unless that's what you want.
:::

### Audience overrides

Audience resolves per message: `ChannelAudiences[channelId]` first, then `ChannelAudiences["dm"]`, then a fallback. The fallback is `Team` for a channel listed in `AllowedChannelIds` or a user listed in `AllowedUserIds`, and `Public` for everything else. A channel allowed only through `DefaultChannelId` is `Public` unless you also list it in `AllowedChannelIds` or set `ChannelAudiences` for it.

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

A channel-ID entry beats `"dm"`, and an unrecognized value denies the message instead of falling back. [Security model](/security/security-model/) maps audiences to tools.

## Behavior in Discord

### Threads and sessions

When someone messages the bot in a channel, netclaw creates a public thread on its first reply and continues there. The thread starts as "Netclaw" and is renamed once the model produces a session title.

A thread is freed from memory when its session goes idle, after `Session.IdleTimeout` (one hour by default), and a later reply wakes it again. After a daemon restart, netclaw backfills up to 200 messages of thread history so conversations resume.

### Mention behavior

`MentionOnly: true` makes the bot ignore channel messages that don't @-mention it. netclaw strips the mention before the text reaches the model. These rules sit on top:

- **Thread replies:** once a thread has an active session, replies in it don't need a mention, unless `MentionRequiredInThreadByChannel` is `true` for that channel.
- **Restart recovery:** if the daemon restarts and someone continues a thread, netclaw recreates the session from the thread's history.

`MentionRequiredInThreadByChannel` maps channel IDs to `true` or `false`:

```json
{
  "Discord": {
    "MentionRequiredInThreadByChannel": {
      "123456789012345678": true
    }
  }
}
```

With the rule on, an un-mentioned thread reply is ignored (`ThreadMentionRequired` in the log). The next message that mentions the bot makes netclaw re-read everything posted since its last reply, so it answers with full context. A channel with no entry behaves as `false`. The rule doesn't apply to DMs.

In `netclaw config` → Channels, **Space** toggles **Require @mention** on the selected channel. A channel you add there starts with the rule on if its audience is `team` or `public`, and off if it's `personal`. Only `true` entries are saved.

### Message formatting

Discord renders markdown natively. netclaw splits replies longer than 2,000 characters at newline boundaries.

### Tool approval

When a tool call needs approval, netclaw posts a prompt with buttons in the thread. It shows the tool, the action and the pattern. The choices are **Once**, **This chat**, **Always here**, **Always anywhere**, **Deny**, and **This repository** when it applies. A command netclaw can't parse cleanly gets only **Once** and **Deny**. [How tool approvals work](/security/approvals/) explains what each one grants. Only the user whose request triggered the prompt can answer it.

If posting the buttons fails for a prompt from the main agent, netclaw falls back to a text prompt, and you reply with the letter next to an option. A prompt from a sub-agent has buttons only and no letter fallback. If its buttons can't be posted, netclaw refuses the request and the call doesn't run. After a decision, netclaw edits the original message with a check mark or a denied icon. A prompt that nothing can answer any more is edited to remove the buttons and say why, for example `This approval request was withdrawn because Netclaw restarted before the task finished. Nothing ran.`

### Reminders

[Reminders](/configuration/reminders/) deliver to a guild text channel or to a user's DM. Accepted targets:

| Target | Delivers to |
|--------|-------------|
| `<#123456789012345678>` | A channel, by mention |
| `channel:123456789012345678` | A channel, by ID |
| `<@123456789012345678>` or `<@!123456789012345678>` | A user's DM, by mention |
| `dm:123456789012345678` or `@123456789012345678` | A user's DM, by ID |

A bare ID is rejected, because channel IDs and user IDs have the same shape. DM delivery still goes through ACL, so it needs `AllowDirectMessages: true` and, if you use `AllowedUserIds`, the user on that list. `current_session` reminders post back into the thread that set them. That reminder ends when the session admits the fire, and netclaw doesn't retry a failed post. If the reply post fails for good, the session logs an Error and raises a `reminder.delivery.failed` [alert](/observability/operational-alerts/).

### Proactive messaging

The model can start a conversation with `send_channel_message`, passing `channel_key: discord` and a destination (a guild text channel or a DM) from `lookup_channel_user` or `lookup_channel_destination`. ACL still applies.

### Ignored messages

The bot drops empty messages (no text, no attachments), its own and other bots' messages, DMs when `AllowDirectMessages` is off, and un-mentioned channel messages when `MentionOnly` is on and there's no active thread.

## Verify it works

```bash
netclaw status
```

Discord should show `healthy`. If it shows `disabled` or `disconnected`, see [Channel troubleshooting](/channels/troubleshooting/).

Then @-mention the bot in an allowed channel. If it creates a thread and answers, you're set.

:::note
`netclaw doctor` doesn't check Discord yet. Use `netclaw status` and the daemon log.
:::

## Troubleshooting

[Channel troubleshooting](/channels/troubleshooting/) is organized by symptom. The usual ones:

| Symptom | Likely cause |
|---------|--------------|
| Connected but silent | `AllowedChannelIds` is empty and no `DefaultChannelId` is set. |
| Messages arrive but the text is empty | Message Content intent is off in the Developer Portal. |
| HTTP 401 at startup | The token is wrong or was reset. |
| Startup waits 30 seconds, then `disconnected` | The gateway never sent READY, often because the bot isn't in any server. |
| Stopped answering in a thread | `MentionRequiredInThreadByChannel` is on for the channel. Mention the bot. |

## Related pages

- [Slack](/channels/slack/) and [Mattermost](/channels/mattermost/) - the other chat channels
- [Channel troubleshooting](/channels/troubleshooting/) - fixes by symptom
- [How tool approvals work](/security/approvals/) - the approval choices
- [Security model](/security/security-model/) - audiences and approval gates
- [`netclaw status`](/cli/status/) - connector health

## Resources

- [Discord Developer Portal](https://discord.com/developers/applications) - create and manage your bot
- [Discord: Gateway and privileged intents](https://docs.discord.com/developers/topics/gateway) - what Message Content does
- [Discord: permissions](https://discord.com/developers/docs/topics/permissions) - permission reference
- [Discord: enable Developer Mode](https://support.discord.com/hc/en-us/articles/206346498) - copy channel and user IDs
- [Discord Status](https://discordstatus.com/) - check for outages
