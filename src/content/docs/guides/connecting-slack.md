---
title: "Connecting Slack"
description: "Get netclaw responding in your Slack workspace, from app creation to first message."
---

You've got netclaw installed but it's not talking to Slack yet. This page covers the whole setup -- creating a Slack app, wiring up tokens, and verifying the connection.

The [Slack channel reference](/channels/slack/) has the full config field list, ACL details, and message behavior docs. This page just gets you connected.

## Before You Begin

- Netclaw installed and running ([`netclaw init`](/cli/init/) completed, or at least the daemon is up)
- Permission to install apps in your Slack workspace (some orgs restrict this to admins)
- A channel in mind where the bot should respond

## 1. Create a Slack App

Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App**. "From scratch" is fine.

### Enable Socket Mode

Under **Settings > Socket Mode**, flip the toggle on. Generate an **App-Level Token** when prompted -- give it the `connections:write` scope. Copy the `xapp-...` token somewhere safe.

[Socket Mode](https://api.slack.com/apis/socket-mode) is an outbound WebSocket connection -- netclaw dials out, so you don't need a public URL or any ingress rules.

### Add Bot Token Scopes

Under **OAuth & Permissions > Scopes**, add these bot token scopes:

| Scope | Why |
|-------|-----|
| `app_mentions:read` | Receive @-mention events |
| `channels:history` | Read channel messages for thread backfill |
| `channels:read` | Resolve channel names to IDs |
| `chat:write` | Post messages and replies |
| `files:read` | Access shared file content |
| `users:read` | User lookup |

If you plan to use private channels, also add `groups:history` and `groups:read`.

### Install to Workspace

Click **Install to Workspace** under OAuth & Permissions. After authorizing, copy the **Bot User OAuth Token** (`xoxb-...`).

### Invite the Bot

In each Slack channel where netclaw should respond, run:

```
/invite @yourbot
```

The bot won't auto-join channels -- you have to invite it.

## 2. Configure Netclaw

The `netclaw init` wizard is fastest. Manual config gives you more control.

### Fast Path: `netclaw init`

If you haven't run `netclaw init` yet, or want to reconfigure, this handles everything. Step 4 of the wizard covers channel setup -- paste your tokens, pick Slack, done.

![Channel selection during netclaw init](/screenshots/output/init-03-channels.png)

Paste both tokens when prompted -- the wizard stores them encrypted and enables Slack.

### Manual Path

Store tokens with [`netclaw secrets`](/cli/secrets/):

```bash
netclaw secrets set Slack.BotToken xoxb-your-bot-token
netclaw secrets set Slack.AppToken xapp-your-app-token
```

Then enable Slack in `~/.netclaw/config/netclaw.json` and set at least one allowed channel:

```json
{
  "Slack": {
    "Enabled": true,
    "DefaultChannelName": "general"
  }
}
```

Channel names go without the `#` prefix.

Environment variables also work:

```bash
export NETCLAW_Slack__BotToken="xoxb-..."
export NETCLAW_Slack__AppToken="xapp-..."
```

:::caution[Don't skip channel configuration]
Netclaw uses **default-deny access control**. If you don't set `DefaultChannelName`, `DefaultChannelId`, or `AllowedChannelIds`, the bot connects to Slack but silently ignores every message. This is the most common setup mistake.
:::

## 3. Set Allowed Channels

If you used the manual path above, you still need to configure which channels the bot monitors. Set at least one:

| Field | What it does |
|-------|-------------|
| `DefaultChannelName` | Allow a single channel by name (resolved to an ID at startup) |
| `DefaultChannelId` | Same thing, but by ID |
| `AllowedChannelIds` | Allow multiple channels by ID |

```json
{
  "Slack": {
    "Enabled": true,
    "DefaultChannelName": "eng-claw",
    "AllowedChannelIds": ["C0123456789", "C9876543210"]
  }
}
```

To find a channel's ID: right-click the channel name in Slack > "View channel details" > scroll to the bottom. [Slack's help article](https://slack.com/help/articles/221769328) has screenshots.

The [Slack channel reference](/channels/slack/#access-control) covers user allow-lists, DM settings, and audience overrides -- worth reading before you go to production.

## 4. Restart and Verify

Restart the daemon to pick up the new config:

```bash
netclaw daemon stop && netclaw daemon start
```

Check the connection:

```bash
netclaw status
```

![System status showing channel health](/screenshots/output/status.png)

Slack should show `connected`. If it doesn't, run the diagnostics:

```bash
netclaw doctor
```

![Doctor output showing Slack Auth and Slack ACL checks](/screenshots/output/doctor.png)

`netclaw doctor` validates your token against Slack's `auth.test` API and warns if no channel allow-list or default channel is configured.

@-mention the bot in an allowed channel. If it responds, you're done.

## Troubleshooting

### Bot connects but never responds

This is by far the most common problem. Tokens are configured, `netclaw status` shows `connected`, but the bot ignores every message.

Almost always, it's the default-deny access control: `AllowedChannelIds` is empty and no `DefaultChannelName`/`DefaultChannelId` is set, so every message gets dropped.

Set `DefaultChannelName` or add channel IDs to `AllowedChannelIds`, then restart the daemon.

### `DefaultChannelName` is set but bot still ignores messages

If the channel name can't be resolved at startup (typo, or the bot hasn't been `/invite`d to that channel), netclaw falls back to having no default channel -- which means the default-deny access control kicks in. Check the daemon logs for a channel resolution warning, fix the name, and restart.

### Bot works in some channels but not others

The channel is either missing from `AllowedChannelIds` or the bot hasn't been `/invite`d there. Add the channel ID and run `/invite @yourbot`.

### Socket Mode keeps disconnecting

The `xapp-...` App-Level Token has probably expired or been revoked. Generate a new one under Settings > Socket Mode in your [Slack app config](https://api.slack.com/apps), then update it:

```bash
netclaw secrets set Slack.AppToken xapp-new-token
```

### `netclaw doctor` fails the Slack Auth check

The `xoxb-...` Bot Token is invalid -- either it expired or the app was uninstalled from the workspace. Reinstall the app under OAuth & Permissions, copy the fresh Bot Token, and update it:

```bash
netclaw secrets set Slack.BotToken xoxb-new-token
```

## Next Steps

- [Slack channel reference](/channels/slack/) -- all config fields, ACL details, message behavior, proactive messaging
- [Security model](/security/security-model/) -- how audiences and approval gates work
- [`netclaw doctor`](/cli/doctor/) -- run this periodically to catch token expiry and ACL drift
- [Discord channel reference](/channels/discord/) -- setting up the other supported channel

## External Resources

- [Slack API: Socket Mode](https://api.slack.com/apis/socket-mode) -- how outbound WebSocket connections work
- [Slack: Getting Started with Socket Mode](https://api.slack.com/start/quickstart) -- quickstart walkthrough from Slack
- [Slack API: Bot Token Scopes](https://api.slack.com/scopes) -- full scope reference
- [Slack: Finding Channel IDs](https://slack.com/help/articles/221769328) -- where to find IDs for ACL config
