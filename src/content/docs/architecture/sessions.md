---
title: "Sessions & Input Model"
description: "How netclaw maps conversations to persistent actors, handles multiple clients, and keeps long-running sessions bounded."
---

Every conversation in netclaw is a session. One Slack thread, one Discord thread, one CLI chat — each maps to a single persistent [actor](https://en.wikipedia.org/wiki/Actor_model) that owns the conversation's state, processes one turn at a time, and survives daemon restarts.

The session doesn't know or care where its messages come from. That's the foundation everything else builds on.

## Session identity

A session's identity is derived from its channel and thread. In Slack, the key is `{channelId}/{threadTs}`. Discord uses a similar channel-plus-thread mapping. The CLI generates its own session ID when you start a chat.

This is a deliberate 1:1 mapping. One thread, one session, one actor. No shared state between conversations, no cross-thread contamination, no global context that leaks between users. If a session actor crashes, the rest keep running — that's what the actor model buys you.

The `SessionManager` routes messages to the right session actor using child-per-entity routing (each session is a child actor created on demand, keyed by session ID). No lookup table, no registry. The actor hierarchy *is* the routing table.

## Everything is just input

Slack messages, webhook POSTs, scheduled reminders, CLI chat input — they all enter through different channel adapters but produce the same kind of command: a `SendUserMessage` routed to a session actor. The actor processes the turn identically regardless of source.

```
┌──────────┐
│  Slack    │──┐
├──────────┤  │    ┌──────────┐    ┌─────────────────┐
│  Discord  │──┼───▸│  Gateway  │───▸│  Session Actor   │
├──────────┤  │    └──────────┘    └─────────────────┘
│  Webhook  │──┤         ▲
├──────────┤  │         │ policy checks
│  CLI/TUI  │──┘         │ before dispatch
└──────────┘
```

Channel adapters run inside the daemon as hosted services — in-process actors that maintain persistent connections to platform APIs. Slack uses [Socket Mode](https://api.slack.com/apis/socket-mode); Discord uses a WebSocket connection via [Discord.Net](https://discordnet.dev/).

Adding a new channel means writing a new adapter. No changes to the session layer, the compaction logic, the tool system, or the security model.

## Lifecycle

Sessions move through five explicit phases. Transitions are validated at runtime — illegal transitions throw an exception, not a silent fallback.

```
Recovering ──▸ Ready ◂──▸ Processing
               │ ▴ ▴         │
               │ │ └─────────┘
               ▾ │
           Compacting
               │
               ▾
           Passivating ──▸ Ready (on new message)
```

Ready can also transition directly to Compacting (if a threshold is crossed outside of a turn), and Processing can transition to Compacting mid-turn.

**Recovering** — journal replay and snapshot recovery. The actor rebuilds its state from persisted events before accepting any new messages.

**Ready** — accepting user messages. Idle timeout is ticking. If no one talks to the session for long enough and no subscribers are connected, it passivates.

**Processing** — an LLM call or tool execution is in flight. Incoming messages get buffered and processed after the current turn completes. One turn at a time, always.

**Compacting** — the context window is getting full. The session runs a [tiered compaction](#compaction) to shrink the history. Messages are buffered during compaction, same as during processing.

**Passivating** — the session is winding down. It extracts any remaining observations to durable memory (with a 5-second grace period), takes a persistence snapshot, and stops the actor. A new message during passivation aborts the shutdown and returns to Ready — passivation is always interruptible.

## Multi-subscriber delivery

Multiple clients can attach to the same session simultaneously. This is how you can start a conversation in Slack, then connect to the same session from the CLI to watch tool calls and token usage in real time — each subscriber gets its own filtered view.

Subscribers join with an `OutputFilter` bitmask that controls what they see:

| Filter | What it includes |
|--------|-----------------|
| **Text** | Final assembled assistant replies |
| **TextStreaming** | Incremental token-by-token deltas |
| **Thinking** | Reasoning/thinking tokens |
| **ToolCalls** | Tool call requests and results |
| **Usage** | Token counts and context window consumption |
| **Files** | File attachments produced by the LLM or tools |

Lifecycle messages — turn completed, session title changes, errors, compaction notifications — are always delivered regardless of the filter.

Adding or removing a subscriber doesn't affect other active subscribers. If a subscriber disconnects (the Slack adapter restarts, a CLI session closes), the actor detects it via a death watch and removes it from the subscriber list. No impact on the conversation.

## Compaction

Sessions can run for hours or days. Without compaction, the [context window](https://platform.openai.com/docs/guides/context-window) fills up and the model starts losing earlier context. Netclaw uses a tiered compaction sequence that trades off cost against context preservation.

Compaction triggers when the input token count crosses a threshold — a configurable percentage of the model's context window, set via `CompactionThreshold` in `netclaw.json`.

**Phase 1: Tool result clearing.** The cheapest step — no LLM call required. Old tool results get replaced with placeholders while keeping the N most recent tool interactions in full detail. This preserves the reasoning chain ("I called this tool because...") while dropping the bulky output. Often sufficient on its own.

**Phase 2: Memory flush.** An LLM call extracts key facts, decisions, and action items from the conversation and persists them to durable memory storage. This happens *before* the lossy summarization step so that important context survives even if the summary misses it.

**Phase 3: Structured summarization.** Another LLM call produces a structured summary of the conversation history covering the primary request, key decisions, pending tasks, and what to do next. The summary replaces the compacted messages. If a prior summary exists, it gets merged iteratively rather than replaced.

Tool call/result pairs stay atomic during compaction. A tool call is never orphaned from its result. The compaction boundary always aligns to a user-message boundary to keep the conversation coherent.

After compaction, the session takes a persistence snapshot, resets its token counter, and returns to Ready (or Processing, if there are buffered messages waiting).

## Recovery and warm restart

Sessions persist their state to [SQLite](https://www.sqlite.org/docs.html) via [Akka.Persistence](https://getakka.net/articles/persistence/event-sourcing.html). Events (`TurnRecorded`, `SessionTitleSet`, `SessionCompacted`) are journaled. Snapshots capture the full session state periodically and after every compaction.

Recovery is automatic. When a session actor starts — whether from a daemon restart, a crash, or a lazy activation — it replays its journal from the latest snapshot forward and transitions to Ready.

For config-triggered restarts (you edited `netclaw.json`, the daemon reloads), the daemon goes further. Before shutting down, it persists a manifest of all active sessions. On startup, those sessions warm proactively — they recover from persistence before normal traffic resumes. The first message after restart includes a transient continuity notice so the model knows it's resuming, not starting fresh.

Sessions that were idle at restart time stay cold. They recover lazily when someone talks to them again.

## Passivation

Passivation (idle shutdown) keeps the daemon's memory footprint bounded. Without it, every conversation you've ever had stays resident in memory as a live actor.

A new message during the passivation window cancels the shutdown and the session resumes normally. The session also defers passivation if subscribers are still connected or if tool interactions are pending — it won't shut down while someone is actively watching or waiting for a decision.

## Keep reading

- [Architecture Overview](/architecture/overview/) — the three-boundary design and actor internals
- [Design Philosophy](/architecture/design-philosophy/) — why sessions are transport-agnostic
- [Security Architecture](/architecture/security-model/) — how audience dispositions scope what a session can do
- [`netclaw sessions`](/cli/sessions/) — CLI commands for listing and resuming sessions

## Resources

- [Actor model](https://en.wikipedia.org/wiki/Actor_model) — the concurrency model behind session actors
- [Akka.NET Persistence](https://getakka.net/articles/persistence/event-sourcing.html) — journal and snapshot recovery
- [SQLite](https://www.sqlite.org/docs.html) — the persistence backend
- [Slack Socket Mode](https://api.slack.com/apis/socket-mode) — how the Slack adapter connects
- [Discord.Net](https://discordnet.dev/) — the .NET library behind the Discord adapter
