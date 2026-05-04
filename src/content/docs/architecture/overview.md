---
title: "Architecture Overview"
description: "Daemon + CLI architecture, Akka.NET, and design principles."
---

Netclaw is a single-process .NET 10 application that runs as an always-on autonomous agent. It takes input from Slack, Discord, webhooks, timers, and a local TUI, and treats all of them the same way: as messages routed into persistent conversation actors.

Two binaries ship together: `netclawd` (the daemon) and `netclaw` (the CLI). The daemon does everything. The CLI is a thin client that renders the daemon's output in a terminal. If the daemon isn't running, the CLI can't do anything interesting.

## Two binaries

### `netclawd` — the daemon

The daemon is an ASP.NET Core application that owns all agent logic: Akka.NET actor system, LLM sessions, tool execution, channel adapters (Slack/Discord), SignalR hub, REST API, and SQLite persistence.

It binds to `http://127.0.0.1:5199` (loopback only) by default. A PID file at `~/.netclaw/netclaw.pid` and a lock file enforce single-instance — one daemon per machine.

### `netclaw` — the CLI

A Termina-based TUI. No actor system, no persistence, no tool execution. It connects to the daemon over SignalR and renders what comes back.

The CLI binary includes a `daemon` subcommand (`netclaw daemon start`, `netclaw daemon stop`) for managing the `netclawd` process. Think of `netclaw` as both the management interface and the interactive shell for a daemon that runs independently.

The split matters: restart the CLI without interrupting conversations. Run the daemon in Docker and the CLI on your host. Swap the CLI out entirely for the web UI or a channel adapter.

![Netclaw status output showing a running daemon](/screenshots/output/status.png)

`netclaw status` showing daemon state, active connectors, uptime, and current model.

## Communication

The CLI talks to the daemon over two protocols:

| Protocol | Path | Purpose |
|----------|------|---------|
| **SignalR** | `/hub/session` | Real-time session interaction: create sessions, send messages, receive streaming output |
| **REST** | `/api/*` | Non-session operations: health, stats, device pairing, MCP queries, shutdown |

SignalR carries the interactive traffic. The client sends commands (`CreateSession`, `SendMessage`, `CompactSession`) and receives typed `SessionOutputDto` events back as a stream. REST handles everything that doesn't need real-time delivery.

## Akka.NET internals

[Akka.NET](https://getakka.net/) is the concurrency and persistence layer. Every conversation is an actor. Every channel adapter is an actor. Background jobs, reminders, tool approvals — all actors.

### Key actors

| Actor | Role |
|-------|------|
| `LlmSessionActor` | One per conversation thread, keyed by channel + thread identifier. Persistent, with three states: Ready, Processing, Compacting. |
| `SessionManager` | Routes messages to the right session actor via child-per-entity routing (no lookup table). |
| `ReminderManagerActor` | Scheduled tasks, backed by Akka.Reminders + SQLite. |
| `BackgroundJobManagerActor` | Async shell execution. |
| `SubAgentActor` | Child of a session actor. Handles delegated work (research, code analysis, summarization). |
| `ModelCapabilityActor` | Singleton that caches model capabilities at startup. |
| `ToolApprovalActor` | Approval gates for restricted tools. |

### Why actors?

Each conversation needs its own state, its own message queue, and crash isolation from other conversations. Actors give you that without thread management. A session actor processes one turn at a time, persists events to SQLite, and recovers its full history on restart. If one conversation crashes, the rest keep running.

Persistence uses [Akka.Persistence.Sql](https://getakka.net/articles/persistence/overview.html) with SQLite. Events: `TurnRecorded`, `SessionTitleSet`, `SessionCompacted`. Serialization is [Google Protobuf](https://protobuf.dev/) via the `NetclawProtobufSerializer`.

## Three boundaries

Three logical boundaries divide the daemon (from the [runtime spec](https://github.com/netclaw-dev/netclaw/blob/main/docs/spec/SPEC-001-runtime-boundaries.md)):

At the edge, the **gateway** receives transport events (Slack message, webhook POST, CLI input), runs policy checks, and converts them to actor commands. Nothing reaches the session layer before policy runs.

The **session** layer owns conversation state, turn lifecycle, compaction, and persistence. Sessions communicate outward only by broadcasting messages — they have no idea whether they're talking to Slack, Discord, or the CLI.

**Subscribers** (channel adapters and UI clients) consume those broadcasts via pub/sub. They render output and nothing else. They can't read actor internals or influence model behavior.

Data flows one direction: gateway sends commands to sessions, sessions broadcast to subscribers. Policy errors close the gate.

## Everything is just input

Every input source — Slack message, webhook POST, timer, CLI chat, web UI — produces a message routed to a session actor with context-specific instructions. The actor doesn't know or care where it came from; turns process identically regardless of source.

Adding a new channel adapter requires no changes to the session layer.

## Channel adapters

Slack and Discord adapters run inside the daemon as [hosted services](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/hosted-services). They're in-process actors that maintain persistent connections to the platform APIs, not external bridges.

| Channel | Connection | Actors |
|---------|-----------|--------|
| **Slack** | [Socket Mode](https://api.slack.com/apis/socket-mode) via SlackNet | `SlackGatewayActor`, `SlackConversationActor`, `SlackThreadBindingActor` |
| **Discord** | WebSocket via Discord.Net | `DiscordGatewayActor`, `DiscordConversationActor`, `DiscordSessionBindingActor` |

An [Akka.Streams](https://getakka.net/articles/streams/introduction.html) `SessionPipeline` bridges channel adapters to the actor system.

## LLM providers

Netclaw uses [Microsoft.Extensions.AI](https://learn.microsoft.com/en-us/dotnet/ai/ai-extensions) (`IChatClient`) as the provider abstraction. Supported providers:

| Provider | Type key | Notes |
|----------|----------|-------|
| **Ollama** | `ollama` | Code default. Native integration, queries `/api/show` for capabilities. |
| **OpenRouter** | `openrouter` | Recommended for cloud models. Widest model catalog. |
| **Anthropic** | `anthropic` | Direct API. |
| **OpenAI** | `openai` | Direct API. |
| **OpenAI-compatible** | `openai-compatible` | Generic self-hosted endpoint. |

At startup, the daemon queries the provider to detect context window size, vision support, and tool use capabilities. If the direct query fails, it falls back to the OpenRouter catalog, then HuggingFace metadata, then assumes text-only.

See [Models](/configuration/models/) for configuration and [Managed Providers](/configuration/managed-providers/) / [Self-hosted Providers](/configuration/self-hosted-providers/) for provider setup.

## Session lifecycle

Each conversation thread maps to one persistent actor. In Slack, the key is `{channelId}/{threadTs}`; Discord uses a similar channel + thread mapping.

**States:** Ready → Processing → (threshold check) → Ready or Compacting → Ready.

When a session's context grows past the compaction threshold, the actor compacts in phases: clear stale tool results (Phase 1), drop old messages via extractive reduction keeping the N most recent (Phase 2), then optionally generate observation notes from the discarded window via a best-effort LLM call (Phase 3). If the LLM call fails, extractive-only results stand. Context shrinks, and the session returns to Ready.

## Tool system

Tools are C# methods registered at compile time via a Roslyn incremental source generator. The generator produces JSON schema and typed deserializers — no runtime reflection. `ToolRegistry` holds the catalog; `IToolExecutor` runs them.

Access control is layered: `ToolAccessPolicy` (which tools are available), `ToolPathPolicy` (filesystem boundaries), `ShellCommandPolicy` (allowed shell commands). Feature gates control progressive exposure.

### MCP integration

External tool servers connect via the [Model Context Protocol](https://modelcontextprotocol.io/). `McpClientManager` handles server lifecycle including OAuth 2.1 flows. Sessions see only server summaries until a tool is explicitly requested via `search_tools` (progressive disclosure). See [MCP Servers](/configuration/mcp-servers/) for configuration.

## Supporting systems

The daemon keeps a [SQLite](https://www.sqlite.org/docs.html)-backed memory store in `~/.netclaw/netclaw.db`. Facts persist across sessions; a background `MemoryCurationEngine` handles pruning and deduplication.

**Skills** are markdown files in `~/.netclaw/skills/` that extend what the agent knows how to do. Built-ins ship as embedded resources; extras sync from a CDN feed at startup.

For delegated work — research, code analysis, summarization — a session spawns a **subagent** as a child actor. Definitions live in `~/.netclaw/agents/*.md` with YAML frontmatter (built-ins: research-assistant, code-analyst, summarizer). Max 10 tool iterations per subagent.

Scheduled tasks go through `ReminderManagerActor`. See [Reminders](/configuration/reminders/).

## Configuration

Layered, with later sources winning:

1. `~/.netclaw/config/netclaw.json` — base config
2. `~/.netclaw/config/secrets.json` — encrypted credentials (ASP.NET Core Data Protection)
3. `NETCLAW_*` environment variables — highest priority

A `ConfigWatcherService` monitors `netclaw.json` with a 500ms debounce. Valid changes trigger a coordinated restart: close ingress, drain active sessions, persist state, restart, then warm active sessions back up. Active CLI sessions reconnect automatically after the restart completes.

## Deployment

The daemon runs on anything .NET 10 supports, from a Raspberry Pi to a cloud VM. Ships as a self-contained tarball: `netclaw-{version}-{os}-{arch}.tar.gz`.

| Method | Guide |
|--------|-------|
| **systemd** (recommended for Linux) | [systemd Service](/deployment/systemd/) |
| **Docker** | [Docker Deployment](/deployment/docker/) |
| **Direct** | `netclaw daemon start` (detached process) |

Docker runs only the daemon; the CLI stays on the host. For remote access beyond loopback, see [Exposure Modes](/deployment/exposure-modes/).

## Design principles

None of these are aspirational — they're constraints the codebase enforces.

1. **Gall's Law first** — ship a simple working system before building a generalized framework.
2. **Actor transport boundary** — channel adapters consume broadcasts via pub/sub and never drive model internals directly.
3. **Serialization boundary** — Netclaw controls its own persistence schema. Never persist framework-external chat types.
4. **Security boundary** — default deny, explicit allow, fail closed. See [Security Model](/security/security-model/).
5. **Everything is just input** — every source (Slack, webhook, CLI, timer) produces a message routed to a session actor. No special-casing by channel.

## Limitations

No clustering or multi-node distribution. One daemon, one machine, one actor system.

SQLite is the only persistence backend. Good for single-node; won't scale to multi-instance.

Security is in Phase 1: all connections are loopback-only with `LocalOperator` trust (full access). Bearer token auth and device pairing for remote access are planned for a future release.

Binary updates require a daemon restart. No hot code reload.

## What to read next

Setting up for the first time? Go to [Models](/configuration/models/) to configure your LLM provider.

For production deployment, see [systemd Service](/deployment/systemd/) or [Docker Deployment](/deployment/docker/).

For the security model, see [Security Model](/security/security-model/) — covers ACLs, trust context, and audience scoping.

## Resources

- [Akka.NET documentation](https://getakka.net/) — the actor model framework behind netclaw's concurrency
- [Microsoft.Extensions.AI](https://learn.microsoft.com/en-us/dotnet/ai/ai-extensions) — the `IChatClient` abstraction netclaw uses to talk to LLM providers
- [Model Context Protocol specification](https://modelcontextprotocol.io/) — standard for external tool server integration
- [SignalR documentation](https://learn.microsoft.com/en-us/aspnet/core/signalr/introduction) — real-time communication between CLI and daemon
- [SQLite documentation](https://www.sqlite.org/docs.html) — the persistence and memory backend
