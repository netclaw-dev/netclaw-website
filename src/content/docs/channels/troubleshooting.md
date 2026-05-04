---
title: "Channel Troubleshooting"
description: "Diagnose and fix common Slack and Discord channel issues."
---

Netclaw not responding in Slack or Discord? Two commands will tell you what's wrong most of the time:

```bash
netclaw status    # live connector health (requires running daemon)
netclaw doctor    # offline config and credential checks
```

Daemon logs live at `~/.netclaw/logs/`, or `journalctl -u netclaw` if you're running it as a systemd service.

## Symptom Triage

| What you're seeing | Jump to |
|---|---|
| Bot shows "disconnected" in `netclaw status` | [Authentication Errors](#authentication-errors) |
| Bot connected but never replies | [ACL and Permissions](#acl-and-permissions) |
| Bot replies to some messages but not others | [Bot Not Responding to Messages (MentionOnly)](#bot-not-responding-to-messages-mentiononly) |
| Bot was working, then stopped | [Connectivity](#connectivity) |
| Bot processes messages but replies never appear | [Message Delivery](#message-delivery) |

![netclaw doctor running diagnostic checks including Slack Auth and Slack ACL](/screenshots/output/doctor.png)

Doctor only checks Slack right now (Auth and ACL). For Discord, you're looking at `netclaw status` and daemon logs.

## Authentication Errors

### Slack: Invalid or Expired Bot Token

`netclaw status` shows Slack as `disconnected`. Doctor's Slack Auth check fails with one of these:

| Error | Meaning |
|-------|---------|
| `invalid_auth` | Bot token is invalid. Check your Slack app's Bot User OAuth Token. |
| `token_revoked` | Token has been revoked. Generate a new one. |
| `token_expired` | Token has expired. Generate a new one. |
| `account_inactive` | Bot account is deactivated. |
| `not_authed` | No authentication token provided. |
| `missing_scope` | Bot token lacks `channels:read` scope. |

If you're not sure which token is bad, regenerate both from the [Slack App Management page](https://api.slack.com/apps):

```bash
netclaw secrets set Slack.BotToken xoxb-your-new-token
netclaw secrets set Slack.AppToken xapp-your-new-token
netclaw daemon stop && netclaw daemon start
```

### Slack: No Bot Token Found

Doctor reports "Slack is enabled but no bot token found."

Run [`netclaw init`](/cli/init/) or set the token directly:

```bash
netclaw secrets set Slack.BotToken xoxb-your-token
```

### Discord: Invalid Bot Token

`netclaw status` shows Discord as `disconnected`. Daemon logs show an authentication error at startup.

| HTTP Code | Meaning |
|-----------|---------|
| 401 | Bot token is invalid. Check your Discord application's bot token. |
| 403 (code 50001) | Bot lacks access. Ensure it has been invited to the server. |
| 403 | Access denied. Check bot permissions. |
| 404 | Resource not found. Check the ID is correct. |

Discord uses a single bot token (not a `xoxb-`/`xapp-` pair like Slack). Regenerate it from the [Discord Developer Portal](https://discord.com/developers/applications):

```bash
netclaw secrets set Discord.BotToken your-new-token
netclaw daemon stop && netclaw daemon start
```

### Discord: Connection Timeout at Startup

Daemon start hangs, then Discord shows `disconnected`. Logs show a 30-second timeout waiting for the gateway READY event.

The bot token may be valid but the bot hasn't been invited to any server, so Discord has nothing to initialize. Verify the bot has been added to your server with the correct OAuth2 scopes. Use Discord's [URL Generator](https://discord.com/developers/docs/topics/oauth2#bot-authorization-flow) to create an invite link with `bot` and `applications.commands` scopes.

## ACL and Permissions

### All Channel Traffic Denied

Netclaw receives messages but never responds. `netclaw status` counters show `recv > 0`, `dropped > 0`, `routed = 0`. Logs show `channel_not_allowed`.

This is the number one gotcha. When `AllowedChannelIds` is empty and no `DefaultChannelId`/`DefaultChannelName` is set, netclaw denies all channel traffic.

Set a default channel or list specific channels in `~/.netclaw/config/netclaw.json`:

```json
{
  "Slack": {
    "DefaultChannelId": "C0123456789"
  }
}
```

Or allow specific channels:

```json
{
  "Slack": {
    "AllowedChannelIds": ["C0123456789", "C9876543210"]
  }
}
```

After editing config, restart the daemon: `netclaw daemon stop && netclaw daemon start`

To find Slack channel IDs, right-click the channel name, select "View channel details," and scroll to the bottom. For Discord, enable Developer Mode in Settings > App Settings > Advanced, then right-click any channel and select "Copy Channel ID." See [Slack: Finding IDs](https://slack.com/help/articles/221769328) and [Discord: Finding IDs](https://support.discord.com/hc/en-us/articles/206346498).

[`netclaw doctor`](/cli/doctor/) catches this one automatically.

### User Not Allowed

Specific users get no response. Logs show `user_not_allowed`.

Add the user's ID to `AllowedUserIds`, or clear the list to allow all users:

```json
{
  "Slack": {
    "AllowedUserIds": ["U0123456789", "U9876543210"]
  }
}
```

### DMs Not Working

Direct messages to the bot get no response, but channel messages work fine. Logs show `DmNotAllowed`.

`AllowDirectMessages` defaults to `false`. Turn it on:

```json
{
  "Slack": {
    "AllowDirectMessages": true
  }
}
```

Doctor warns if you enable DMs with an empty `AllowedUserIds` list, since any workspace member can then DM the bot.

### Bot Not Responding to Messages (MentionOnly)

Bot is connected and healthy but only responds to some messages. Logs show `ChannelMentionRequired`.

`MentionOnly` defaults to `true`, so the bot ignores messages that don't @-mention it. Either @-mention the bot every time, or turn it off:

**Slack:**

```json
{
  "Slack": {
    "MentionOnly": false
  }
}
```

**Discord:**

```json
{
  "Discord": {
    "MentionOnly": false,
    "MentionRequiredInDm": false
  }
}
```

`MentionRequiredInDm` controls whether DMs also need a mention (defaults to `false`).

## Connectivity

### Slack Socket Mode Disconnected

`netclaw status` shows Slack as `disconnected`. Was working, then stopped.

Restart the daemon:

```bash
netclaw daemon stop && netclaw daemon start
```

If it keeps disconnecting, check the [Slack Status page](https://status.slack.com/) and your network. Make sure the App Token (`xapp-...`) is still valid; Socket Mode requires it.

Only Socket Mode is supported. Setting `SocketMode: false` in config throws an `InvalidOperationException` at startup.

### Discord Gateway Disconnected

`netclaw status` shows Discord as `disconnected`.

Restart the daemon: `netclaw daemon stop && netclaw daemon start`. If it keeps dropping, check the [Discord Status page](https://discordstatus.com/) and verify the bot token.

### Rate Limiting

Replies are delayed or fail intermittently. Logs show `rate_limited` (Slack) or HTTP 429 (Discord).

Netclaw retries on its own. If rate limiting is sustained, check whether another integration shares the same bot token's rate limit budget.

## Message Delivery

### Slack: Reply Not Posted

Bot processes the message (logs show session activity) but the reply never appears in Slack.

| Error | Meaning |
|-------|---------|
| `not_in_channel` | Bot hasn't been invited to the channel. Invite it with `/invite @botname`. |
| `channel_not_found` | Channel ID is wrong or the channel was deleted. |
| `missing_scope` | Bot token lacks the required OAuth scope for posting. |
| `no_permission` | Bot doesn't have permission to post in this channel. |
| `msg_too_long` | Response exceeded Slack's message size limit. |
| `invalid_blocks` | Malformed Block Kit payload. Usually a formatting edge case in the response. |
| `too_many_attachments` | Response has too many attachments. |

For permission errors: add the bot to the channel and make sure it has `chat:write` scope. Check your app's OAuth scopes in the [Slack API dashboard](https://api.slack.com/apps).

### Discord: Reply Not Posted

Bot processes the message but no reply appears in Discord.

Check daemon logs for HTTP error codes. Usually the bot is missing `Send Messages` permission in the target channel. Fix it in your Discord server's channel permission settings.

### Bot Reply Loop

Bot responds to its own messages, creating an infinite loop. High `events.filtered{reason="bot_message"}` counter alongside high `events.received`.

Netclaw filters its own messages to prevent loops, so this is rare. Restart the daemon. If the loop comes back, bot user ID detection probably failed at startup. Look for errors around the `slack.Auth.Test()` call in the logs.

## Debug Logging

Still stuck? Turn on debug logging in `~/.netclaw/config/netclaw.json`:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug"
    },
    "Console": {
      "Enabled": true
    }
  }
}
```

Restart the daemon, trigger the failing interaction, and look for these patterns:

**Healthy message flow (Slack):**
1. `Routing Slack event ... to conversation ...`
2. `Routing Slack event ... to session thread actor`
3. `Accepted inbound Slack message for session queue`
4. `Received user message`
5. `Posted Slack reply message`

If the chain stalls at step 3, something in ACL config is rejecting the message. If it stalls at step 5, the reply couldn't be posted. Check the error tables above.

**Quick triage commands:**

```bash
# Daemon process status
netclaw daemon status

# Recent crash logs
ls -lt ~/.netclaw/logs/crash-*.log

# Recent session activity (SQLite)
sqlite3 ~/.netclaw/netclaw.db \
  "SELECT persistence_id, MAX(created), MAX(sequence_number) \
   FROM journal GROUP BY persistence_id \
   ORDER BY MAX(created) DESC LIMIT 10;"
```

## OTLP Diagnostic Patterns

If [OpenTelemetry](/observability/opentelemetry/) is enabled, channel metrics tell the story faster than logs:

| Pattern | Metrics | Likely Cause |
|---------|---------|--------------|
| Messages received, none routed | `events.received > 0`, `events.routed = 0` | ACL blocking all traffic |
| Messages routed, no replies | `messages.enqueued > 0`, `replies.posted = 0` | Outbound delivery failure |
| High drop rate | `events.dropped` spiking with `reason=channel_not_allowed` | Channel not in allow list |
| Suspected loop | High `events.filtered{reason="bot_message"}` + high `events.received` | Bot message filter working, but volume suggests upstream issue |

Channel metrics use the namespace `netclaw.channel.slack.*` and `netclaw.channel.discord.*`.

## Related Pages

- [`netclaw doctor`](/cli/doctor/) — offline diagnostics
- [`netclaw status`](/cli/status/) — live connector health and message counters
- [`netclaw secrets`](/cli/secrets/) — manage encrypted tokens
- [`netclaw init`](/cli/init/) — first-run wizard for channel setup
- [OpenTelemetry](/observability/opentelemetry/) — OTLP metrics reference

## External Resources

- [Slack API: Bot tokens and permissions](https://api.slack.com/authentication/token-types#bot) — token types and required scopes
- [Slack API: Socket Mode](https://api.slack.com/apis/socket-mode) — how Socket Mode connections work
- [Slack: Finding Channel and User IDs](https://slack.com/help/articles/221769328) — locate IDs for ACL config
- [Discord Developer Docs: Getting Started](https://discord.com/developers/docs/getting-started) — bot setup and permissions
- [Discord: Finding IDs](https://support.discord.com/hc/en-us/articles/206346498) — enable Developer Mode to copy IDs
- [Slack Status](https://status.slack.com/) — check for Slack API outages
- [Discord Status](https://discordstatus.com/) — check for Discord API outages
