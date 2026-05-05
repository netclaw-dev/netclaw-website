---
title: "Your First Conversation"
description: "Start your first chat session with Netclaw."
---

You've installed Netclaw, run `netclaw init`, and the daemon is up. Open a chat.

## Prerequisites

- Netclaw [installed](/getting-started/installation/) with a running daemon
- At least one [provider configured](/cli/provider/) (done during `netclaw init`)

## 1. Open a chat

```bash
netclaw chat
```

![Netclaw Chat TUI on startup](/screenshots/output/chat-session-start.png)

The TUI launches into a new session. The status bar shows your active model and "Generating..." because Netclaw is already composing its opening message.

## 2. Meet your agent

Netclaw introduces itself without any prompt from you. It reads your identity file (created during `netclaw init`) and greets you by name.

![Netclaw greeting and profile check](/screenshots/output/chat-intro-greeting.png)

The `file_read` tool call in the output means Netclaw pulled your identity from `~/.netclaw/identity/SOUL.md` to check what it already knows about you. Then it asks what you want to use it for.

## 3. Teach it about you

Tell Netclaw about your work. It asks follow-up questions to build your profile.

![Multi-turn profile conversation](/screenshots/output/chat-profile-questions.png)

In this example, the conversation went:

1. "I need help with administrative tasks for NetclawCorp."
2. Netclaw asks about team size and role
3. "5 people" / "COO. We use Google Workspace, Slack, Xero, and Invoicely."

Give it as much context as you want. Your role, team, tools, workflows. It remembers everything across sessions.

## 4. Profile saved

Netclaw writes your profile to `SOUL.md`, the identity file that persists across sessions.

![Profile written to SOUL.md](/screenshots/output/chat-profile-update-soul.md.png)

The `file_write` line confirms your profile landed at `~/.netclaw/identity/SOUL.md`. Every future session loads this file automatically, so you never re-introduce yourself.

`SOUL.md` grows over time. As you work with Netclaw, it updates the file with new preferences and context it picks up from your conversations.

## 5. Do something real

Profile bootstrapping done. Try a tool-assisted task.

### Ask a live question

```
what is the current temperature in Chicago?
```

![Web fetch tool in action](/screenshots/output/single-shot-chat-web-fetch.png)

Netclaw calls `web_fetch`, pulls weather data, and returns a plain-language answer. Tool calls appear inline so you can see exactly what happened behind the scenes.

### Headless mode

Skip the TUI for quick one-offs. The `-p` flag sends a single prompt and exits:

```bash
netclaw chat -p "can you tell me if there's an MCP server for Xero?"
```

![Headless mode with tool call output](/screenshots/output/single-shot-cli-execution.png)

Tool calls and results stream to stdout, then the process exits. Good for scripting and quick terminal lookups.

## Where to go from here

At this point, Netclaw has your profile and a working tool stack. A few directions worth exploring:

- Resume this session later: `Ctrl+Q` to close, [`netclaw sessions`](/cli/sessions/) to pick it back up
- Give Netclaw more tools via [`netclaw mcp`](/cli/mcp-tools/) — MCP servers for databases, APIs, file systems, whatever you need
- Wire it into Slack or Discord so your team can talk to the same agent ([Channels](/channels/slack/))
- [`netclaw chat`](/cli/chat/) has the full reference: keyboard shortcuts, JSON output, named sessions, scripted multi-turn workflows

## Resources

- [`netclaw chat` reference](/cli/chat/) — flags, modes, keyboard shortcuts
- [Security Model](/security/security-model/) — how tool access and permissions work
- [MCP Tools](https://modelcontextprotocol.io/specification/2025-03-26/server/tools) — the protocol behind tool execution
- [SignalR documentation](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction) — real-time protocol between CLI and daemon
