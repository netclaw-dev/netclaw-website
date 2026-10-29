---
title: "Slack"
description: "Connect netclaw to your Slack workspace over Socket Mode with a bot token, an app token and an allow-list."
---

netclaw talks to Slack over [Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode), which means outbound WebSocket connections only. You need no public URL, no ingress rule and no reverse proxy. You create a Slack app, give netclaw two tokens, and it shows up in your workspace as a bot.

## Prerequisites

- netclaw installed and initialized ([`netclaw init`](/cli/init/))
- A Slack workspace where you can install apps (some organizations limit that to admins)

Connecting Slack has two parts. Create a Slack app to get the tokens, then enter them in [`netclaw config`](/cli/config/) → Channels.

## Create a Slack app

The fastest path is a manifest. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App**.

![Slack Your Apps page](/screenshots/output/slack-your-apps.png)

The page has a filter box for your existing apps and the **Create New App** button at the top right.

Choose **From a manifest**, pick your workspace, and paste this:

```json
{
  "display_information": {
    "name": "Netclaw",
    "description": "AI assistant powered by Netclaw",
    "background_color": "#512BD4"
  },
  "features": {
    "app_home": {
      "home_tab_enabled": false,
      "messages_tab_enabled": true,
      "messages_tab_read_only_enabled": false
    },
    "bot_user": {
      "display_name": "Netclaw",
      "always_online": true
    }
  },
  "oauth_config": {
    "scopes": {
      "bot": [
        "app_mentions:read",
        "channels:history",
        "channels:read",
        "chat:write",
        "chat:write.customize",
        "files:read",
        "files:write",
        "groups:history",
        "groups:read",
        "im:history",
        "im:read",
        "im:write",
        "mpim:history",
        "mpim:read",
        "users:read",
        "users:read.email"
      ]
    }
  },
  "settings": {
    "event_subscriptions": {
      "bot_events": [
        "app_mention",
        "message.channels",
        "message.groups",
        "message.im",
        "message.mpim"
      ]
    },
    "interactivity": {
      "is_enabled": true
    },
    "org_deploy_enabled": false,
    "socket_mode_enabled": true,
    "token_rotation_enabled": false
  }
}
```

Change `name` and `display_name` to what you want the bot called.

The manifest turns on the App Home **Messages tab** (`messages_tab_enabled`), which is what lets people DM the bot. If you create the app another way and skip it, Slack tells anyone who tries to DM the bot *"Sending messages to this app has been turned off"*. You can fix that under **Features > App Home > Messages Tab**.

After the app exists, you need two tokens.

1. **App-level token.** Open **Settings > Basic Information**, scroll to **App-Level Tokens**, click **Generate Token and Scopes**, name it anything, and add the `connections:write` scope.

   ![Generate an app-level token dialog](/screenshots/output/slack-generate-app-token.png)

   The dialog shows the `connections:write` scope that Socket Mode needs. Click **Generate** and copy the `xapp-...` token.

2. **Bot token.** Open **Install App** in the sidebar and click **Install to {Your Workspace}**.

   ![Slack Install App page](/screenshots/output/slack-install-app.png)

   The install page is also where you reinstall after changing scopes. After you approve, copy the `xoxb-...` Bot User OAuth Token from **OAuth & Permissions**.

Then invite the bot to each channel where it should answer: `/invite @YourBotName`.

### What the scopes do

| Scope | Why |
|-------|-----|
| `app_mentions:read` | Receive @-mention events |
| `channels:history` | Read history in public channels |
| `channels:read` | Resolve channel names to IDs, list public channels and read channel info |
| `chat:write` | Post replies in threads, and set the native loading status |
| `chat:write.customize` | Post under a custom name or icon. Netclaw doesn't do this today. |
| `files:read` | Download files shared in conversations |
| `files:write` | Upload files such as agent output |
| `groups:history` | Read history in private channels |
| `groups:read` | List private channels the bot is in |
| `im:history` | Receive DM message events and read DM thread replies for context |
| `im:read` | Read DM details, such as the name of a DM listed in `AllowedChannelIds` |
| `im:write` | Open DMs for proactive messages |
| `mpim:history` | Slack requires it for the `message.mpim` event the manifest subscribes to, and for reading group DM thread replies |
| `mpim:read` | Read group DM details, such as the name of a group DM listed in `AllowedChannelIds` |
| `users:read` | Look up users by name for `lookup_slack_user` |
| `users:read.email` | Look up users by email. Slack returns the email field only with this scope. |

If you installed from an older copy of this manifest, add `users:read.email` under **OAuth & Permissions** and reinstall the app, or email lookups won't match.

## Configure netclaw

Run `netclaw config` → Channels, enable Slack, and paste your tokens. netclaw resolves channel names to IDs and saves, so you don't edit JSON.

![The Channels area in netclaw config](/screenshots/output/config-channels-menu.png)

The Channels area lists Slack, Discord and Mattermost with a checkbox each. Once an adapter is set up, its row also shows how many channels and users it allows. Nothing is set up in this capture.

When you save from this screen, netclaw writes the first channel as `DefaultChannelId` and removes `DefaultChannelName`. If you set `DefaultChannelName` by hand, the TUI will replace it.

### Manual configuration

For scripted or headless installs, store the tokens with [`netclaw secrets`](/cli/secrets/):

```bash
netclaw secrets set Slack.BotToken xoxb-your-bot-token
netclaw secrets set Slack.AppToken xapp-your-app-token
```

Then enable Slack and point it at a channel in `~/.netclaw/config/netclaw.json`:

```json
{
  "Slack": {
    "Enabled": true,
    "DefaultChannelName": "general"
  }
}
```

Environment variables work too, with list entries indexed from zero:

```bash
export NETCLAW_Slack__BotToken="xoxb-..."
export NETCLAW_Slack__AppToken="xapp-..."
export NETCLAW_Slack__AllowedChannelIds__0="C0123456789"
```

An edit to `netclaw.json` restarts the daemon by itself. A vault or environment change needs a restart you run:

| Where it runs | Restart |
|---------------|---------|
| Native | `netclaw daemon stop`, then `netclaw daemon start` |
| systemd user unit | `systemctl --user restart netclaw` |
| Docker | `docker restart <container>` |

:::caution
Keep each list in one place. Environment entries and `netclaw.json` entries merge by position, so a blank `NETCLAW_Slack__AllowedChannelIds__0` overwrites the first channel in the file. `netclaw config` → Channels writes the lists into `netclaw.json`.
:::

### How channel IDs are stored

Enter channel names or IDs, comma-separated, in `netclaw config` → Channels. netclaw resolves each against the Slack API and saves the canonical ID, never the display name.

- **Confirmed ID:** kept as is.
- **Display name:** resolved and saved as the ID.
- **ID-shaped but not listable:** kept. A channel ID is the stable ACL key, so it's never dropped, even if the bot can't list the channel right now.
- **Unresolvable display name:** dropped and flagged with a warning. Invite the bot, then reopen the screen.

`DefaultChannelName` is Slack-only and resolves to an ID at daemon startup.

:::caution
Since 0.24.0, channel display names you put in `AllowedChannelIds` by hand no longer match, and messages from those channels are silently dropped. Re-enter them through `netclaw config` → Channels. ID-shaped entries and `DefaultChannelName` are unaffected.
:::

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Turn on Slack |
| `SocketMode` | bool | `true` | Must stay `true`. Slack supports Socket Mode only. |
| `BotToken` | string | - | Bot User OAuth Token (`xoxb-...`). Store with `netclaw secrets set`. |
| `AppToken` | string | - | App-level token (`xapp-...`). Store with `netclaw secrets set`. |
| `DefaultChannelName` | string | - | Channel name, resolved to an ID at startup |
| `DefaultChannelId` | string | - | Channel ID, if you'd rather not use a name |
| `MentionOnly` | bool | `true` | In channels, answer only when @-mentioned |
| `AllowDirectMessages` | bool | `false` | Accept DMs |
| `MentionRequiredInDm` | bool | `false` | Require an @-mention even in DMs |
| `MentionRequiredInThreadByChannel` | object | `{}` | Channel ID to bool. `true` makes a thread reply in that channel need an @-mention. See [Mention behavior](#mention-behavior). |
| `AllowedChannelIds` | string[] | `[]` | Channel allow-list. Empty with no default denies every channel message. |
| `AllowedUserIds` | string[] | `[]` | User allow-list. Empty accepts everyone in allowed channels. |
| `ChannelAudiences` | object | `{}` | Per-channel [audience](/security/security-model/) overrides. Keys are channel IDs or `"dm"`. Values are `"personal"`, `"team"` or `"public"`. |

Tokens live in `~/.netclaw/config/secrets.json`, encrypted at rest.

## Access control

Slack ACL is **default-deny**. Three settings decide who talks to the bot and where.

### Channels

The bot answers only in channels that pass the allow-list. `DefaultChannelName` or `DefaultChannelId` allows one, `AllowedChannelIds` allows more, and if all of them are empty every channel message is denied. That's the number one setup mistake.

```json
{
  "Slack": {
    "DefaultChannelName": "general",
    "AllowedChannelIds": ["C0123456789", "C9876543210"]
  }
}
```

To find a channel ID, right-click the channel name, choose **View channel details**, and scroll to the bottom. [Slack's help article](https://slack.com/help/articles/221769328) has screenshots.

### Users

`AllowedUserIds` restricts who gets answers. Empty means everyone in an allowed channel. Non-empty means only the listed users, and everyone else is dropped silently. To copy a member ID, open the profile, then the three-dot menu, then **Copy member ID** ([Slack's help article](https://slack.com/help/articles/360003534892)).

Listed users are `TrustedInternal` in the [security model](/security/security-model/), and everyone else is `UntrustedExternal`.

### Direct messages

DMs are off by default. Turn them on with `"AllowDirectMessages": true`. Users then write without a mention, because `MentionRequiredInDm` defaults to `false`.

:::caution
With DMs on and `AllowedUserIds` empty, any workspace member can DM the bot. Set `AllowedUserIds` unless that's what you want.
:::

### Audience overrides

Audience resolves per message: `ChannelAudiences[channelId]` first, then `ChannelAudiences["dm"]`, then a fallback. The fallback is `Team` for a channel listed in `AllowedChannelIds` or a user listed in `AllowedUserIds`, and `Public` for everything else. A DM accepted only because `AllowedUserIds` is empty is `Public`. So is a channel allowed only through `DefaultChannelId` or `DefaultChannelName`, which includes the `DefaultChannelName` example above, unless you also list it in `AllowedChannelIds` or set `ChannelAudiences`.

```json
{
  "Slack": {
    "ChannelAudiences": {
      "C0123456789": "team",
      "dm": "personal"
    }
  }
}
```

A channel-ID entry beats `"dm"`, and an unrecognized value denies the message instead of falling back. [Security model](/security/security-model/) maps audiences to tools.

## Behavior in Slack

### Threads and sessions

Each Slack thread is its own session, and the bot always replies in-thread. An idle thread is freed from memory when its session goes idle, after `Session.IdleTimeout` (one hour by default), and a later reply wakes it again. After a daemon restart, thread history is backfilled so conversations continue.

### Mention behavior

`MentionOnly: true` makes the bot ignore channel messages that don't @-mention it. netclaw strips the mention before the text reaches the model. These rules sit on top:

- **Thread replies:** once a thread has an active session, replies in it don't need a mention, unless `MentionRequiredInThreadByChannel` is `true` for that channel.
- **File shares:** a message with an attachment follows the same mention rules as any other message. An un-mentioned upload in a channel is ignored.

`MentionRequiredInThreadByChannel` maps channel IDs to `true` or `false`:

```json
{
  "Slack": {
    "MentionRequiredInThreadByChannel": {
      "C0123456789": true
    }
  }
}
```

With the rule on, an un-mentioned thread reply is ignored (`ThreadMentionRequired` in the log). The next message that mentions the bot makes netclaw re-read everything posted since its last reply, so it answers with full context. A channel with no entry behaves as `false`. The rule doesn't apply to DMs.

In `netclaw config` → Channels, **Space** toggles **Require @mention** on the selected channel. A channel you add there starts with the rule on if its audience is `team` or `public`, and off if it's `personal`. Only `true` entries are saved.

### Message formatting

Netclaw sends each reply as a single Slack Markdown block, and Slack renders it, tables included. Replies over 12,000 characters go out as plain text instead.

### Loading status

While netclaw works on a reply, Slack shows the bot's native thread status as `<Bot Name> is thinking...`. That uses `assistant.threads.setStatus` with the existing `chat:write` scope, so the manifest doesn't need `assistant:write`.

### Tool approval

When a tool call needs approval, netclaw posts a prompt in the thread with one button per choice. For a prompt from the main agent you can also reply with the letter next to a choice. A prompt from a sub-agent has buttons only, and a typed letter doesn't answer it.

![Tool approval prompt in a Mattermost thread: shell_execute, a push to origin main, and six lettered choices from A (Once) to F (Deny)](/assets/approval-prompt.png)

The picture shows the same prompt in Mattermost's text-reply form. Slack renders the same six choices as buttons, with the lettered list as a fallback line underneath. A sub-agent prompt has no lettered line.

The choices are **Once**, **This chat**, **Always here**, **Always anywhere**, **Deny**, and **This repository** when it applies. A command netclaw can't parse cleanly gets only **Once** and **Deny**. [How tool approvals work](/security/approvals/) explains what each one grants. Only the user whose request triggered the prompt can answer it. System-initiated calls (`VerifiedAutomation`) can be answered by anyone in the thread. A prompt that nothing can answer any more is redrawn as a single line with the reason and no buttons, such as `This approval request was withdrawn because the task that asked for it ended. Nothing ran.`

### Proactive messaging

The model can start conversations with two tools:

| Tool | What it does |
|------|--------------|
| `send_channel_message` | Posts to a Slack channel or DM. Pass `channel_key="slack"` and a `destination` (`kind`, `id`) from `lookup_slack_user` or `lookup_channel_destination`. Respects ACL. |
| `lookup_slack_user` | Searches users by name, display name or email, up to 10 matches, filtered to `AllowedUserIds` when set, cached for five minutes. Email matching needs `users:read.email`. |

### Ignored messages

The bot drops empty messages, hidden messages, its own and other bots' messages, subtypes it doesn't handle (edits, joins), DMs when `AllowDirectMessages` is off, and un-mentioned channel messages when `MentionOnly` is on and there's no active thread.

### Connection supervision

A supervisor checks the Socket Mode connection every 5 seconds and reconnects with exponential backoff up to 5 minutes. You don't restart the daemon for a dropped connection. A bad token or `SocketMode: false` is a fatal connect error: Slack stays offline until you fix it and restart.

## Verify it works

```bash
netclaw status
```

Look for `slack: healthy (enabled)` under `connectors`. Trimmed output from a daemon that has been on Slack for a few minutes:

```text
daemon: PID 25721, uptime 11m 33s, endpoint http://127.0.0.1:5199
...
slack counters: recv=27 routed=27 dropped=26 replied=9 rejected=0 reply_failed=0
...
connectors:
- discord: disabled (disabled)
    Discord connector is disabled in configuration.
...
- slack: healthy (enabled)
```

`recv` goes up as Slack delivers events, so a number above zero means the bot is hearing the workspace. `dropped` counts events the bot ignores on purpose, such as a message the ACL denies or a thread reply it isn't part of. In 0.28.2 it also counts the bot's own replies coming back from Slack, so expect it to climb with every answer. `rejected` and `reply_failed` count replies that Slack refused or that failed to post, and they should stay at `0`. If Slack isn't `healthy`, run [`netclaw doctor`](/cli/doctor/), which checks the bot token and the ACL config.

Then @-mention the bot in an allowed channel. If it answers in a thread, you're set.

## Troubleshooting

[Channel troubleshooting](/channels/troubleshooting/) is organized by symptom. The usual ones:

| Symptom | Likely cause |
|---------|--------------|
| Connected but silent | `AllowedChannelIds` is empty and no default channel is set. |
| Works in some channels, not others | The channel isn't in `AllowedChannelIds`, or the bot wasn't invited. |
| Stopped answering in a thread | `MentionRequiredInThreadByChannel` is on for the channel. Mention the bot. |
| Doesn't match users by email | The app lacks `users:read.email`. |
| `Sending messages to this app has been turned off` | The Messages tab is off. |
| Socket Mode won't connect | The `xapp-...` token is wrong or revoked. |

## Related pages

- [Mattermost](/channels/mattermost/) and [Discord](/channels/discord/) - the other chat channels
- [Channel troubleshooting](/channels/troubleshooting/) - fixes by symptom
- [How tool approvals work](/security/approvals/) - the approval choices
- [Security model](/security/security-model/) - audiences and approval gates
- [`netclaw doctor`](/cli/doctor/) - Slack auth and ACL checks

## Resources

- [Slack: Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode) - how Socket Mode connections work
- [Slack: app manifests](https://docs.slack.dev/app-manifests/configuring-apps-with-app-manifests) - the manifest format
- [Slack: scopes](https://docs.slack.dev/reference/scopes) - scope reference
- [Slack: finding channel IDs](https://slack.com/help/articles/221769328) - for the allow-list
- [Slack: finding member IDs](https://slack.com/help/articles/360003534892) - for `AllowedUserIds`
