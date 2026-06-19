---
title: "Memory Model"
description: "How netclaw forms, stores, and recalls memories across sessions without manual effort."
---

Agents that forget everything between conversations aren't useful for real work. Agents that require users to manually tag and save context don't get used. Netclaw's memory system sits between these extremes: it forms memories automatically from conversation, stores them durably in SQLite, and recalls relevant ones before each turn — no manual effort, no external services. If you're not familiar with how [sessions](/architecture/sessions/) work, start there.

## What memory looks like in practice

### Conversation 1: Booking a flight

```
You:     I'm a United MileagePlus member and I need to book a flight
         to Amsterdam.

netclaw: What's your origin airport, and when do you need to travel?

You:     IAH. First week of October.

netclaw: Here are some United flights from Houston Intercontinental
         to Amsterdam departing October 1–7...
```

After this conversation ends, the memory sidecar (a companion actor running alongside the session) observes two things worth remembering:

| What it stores | Memory class | Why |
|----------------|-------------|-----|
| You're a United MileagePlus member | **Durable fact** | Airline preference — useful indefinitely |
| Your usual origin airport is IAH | **Durable fact** | Travel pattern — useful indefinitely |
| You need a flight to Amsterdam in early October | **Evidence** | Specific task — expires after 30 days |

The agent didn't ask you to save any of this. It observed, classified, and stored it.

### Conversation 2: A week later

```
You:     I need to book a flight to Boston for next week.

netclaw: Here are some United flights from IAH to Boston departing
         next Monday through Friday. Want me to check MileagePlus
         award availability too?
```

The agent recalled your airline preference and home airport from durable memory. You didn't repeat yourself. The Amsterdam trip evidence is still in memory too, but it's a different task — the agent doesn't confuse the two.

### Living documents: memory that updates over time

Not all memories are write-once. If you ask the agent to track RAM prices every week, it doesn't create a new memory each time. It updates the same document — appending the latest prices alongside the historical record:

```
You:     Check DDR5 64GB kit prices on Newegg and update your
         price tracking memory.

netclaw: Updated the DDR5 price tracker. Current best: $142.99
         (down from $149.99 last week). I've added this week's
         data point to the tracking document.
```

The memory system supports two update patterns: **merge-document** (revise and consolidate, like the price tracker) and **immutable-record** (append-only evidence — "completed the database migration on May 2nd" is a historical fact that shouldn't be revised, just recorded). The LLM picks the pattern based on the content.

## How it works

Memory formation happens outside the conversation turn — the user never waits for it.

```text
┌────────────────────────┐
│    Session Actor       │◂──────────┐
└───────────┬────────────┘           │
            │                        │
            ▾ transcript stream      │
┌────────────────────────┐           │
│  Observation Sidecar   │           │
└───────────┬────────────┘           │
            │                        │
            ▾ idle timeout           │
┌────────────────────────┐           │
│  Sidecar LLM Call      │           │
└───────────┬────────────┘           │
            │                        │
            ▾ memory proposals       │
┌────────────────────────┐           │
│  Checkpoint Queue      │ (SQLite)  │
└───────────┬────────────┘           │
            │                        │
            ▾                        │
┌────────────────────────┐           │
│  Curation Pipeline     │           │
└───────────┬────────────┘           │
            │                        │
            ▾ validated memories     │
┌────────────────────────┐           │
│  Memory Store (SQLite) │───────────┘
└────────────────────────┘ auto-recall
```

**Observation sidecar.** Each session has a companion [actor](/architecture/sessions/#session-identity) that accumulates the conversation transcript — user messages, assistant replies, tool calls. When the session goes idle, the sidecar makes a separate LLM call (not part of the conversation) to distill observations into memory proposals.

**Checkpoint queue.** Proposals land in a durable SQLite table (`memory_checkpoints`), not an in-memory queue. If the daemon crashes between observation and curation, pending proposals survive the restart. A background worker continuously leases and processes pending checkpoints with retry logic (up to 5 attempts per proposal).

**Curation pipeline.** The background worker applies rules-first extraction (pattern-matching for project facts, milestones, preferences), deduplicates against existing memories via fingerprinting, blocks anything that looks like a secret or credential, and persists what survives.

**Automatic recall.** Before each user turn, a deterministic retrieval coordinator runs a lightweight [retrieval-augmented generation](https://en.wikipedia.org/wiki/Retrieval-augmented_generation) (RAG) pipeline. It tokenizes the user's message and recent context, builds a query plan, searches the memory store via full-text search (SQLite FTS5), and scores candidates using a composite of lexical match strength and memory class rank. The top results are injected directly into the system prompt — not as a tool call, but as context the model sees before it starts generating.

That's why the agent already knows your airline preference in Conversation 2. It didn't call a tool — the retrieval coordinator found the memory, scored it as relevant, and injected it into the system prompt.

Retrieval is deterministic by design — no embeddings, no neural ranking, no non-determinism in the recall path. The same query against the same memory store produces the same results every time. Durable facts are heavily prioritized for auto-recall; evidence can also surface when it scores highly enough, but traces are excluded entirely. Recall runs on a 300ms budget so it never delays the conversation.

## Memory classes

The LLM classifies each memory into one of three classes based on how long the information is useful:

| Class | Lifespan | Auto-recalled | Example |
|-------|----------|---------------|---------|
| **Durable fact** | Permanent | Yes (prioritized) | "Prefers TypeScript over JavaScript" |
| **Evidence** | 30 days | Sometimes (if score is high enough) | "Completed the database migration on May 2nd" |
| **Trace** | 72 hours | Never | Raw conversation logs |

Durable facts are what make the agent feel like it knows you. Evidence — work product, findings, completed tasks — matters for weeks but not forever. When something goes wrong with memory, traces are how you debug it.

Expired evidence stays in the database but drops out of search results. The query layer filters expired records at read time — no garbage collection runs.

## The knowledge graph

Memories are organized around **anchors** — entities like projects, people, preferences, workflows, and milestones. Anchors can relate to each other (`related_to`, `depends_on`), forming a lightweight knowledge graph. The LLM manages the graph structure behind the scenes as it creates and updates memories.

This is what connects the dots across conversations. When the agent stores "uses PostgreSQL" as a durable fact anchored to your backend project, and later you ask about the backend project's infrastructure, the PostgreSQL preference comes along for the ride — because the anchor links them.

## Audience scoping

Netclaw classifies every session into a [trust tier](/architecture/design-philosophy/#lightweight-access-control-without-an-identity-provider) based on its source channel — Personal, Team, or Public. Memory respects these tiers:

- **Public** sessions have no memory access — no recall, no writes, no search. Memories authored by Public sessions are excluded from all audiences.
- **Team** and **Personal** sessions have full memory access, scoped by policy boundary.

Each memory carries the audience and boundary context of the session that created it. This prevents a memory formed in a private Personal session from surfacing in a shared Team channel unless the policy explicitly allows it.

## Compaction and memory

When a session's context window fills up and [compaction](/architecture/sessions/#compaction) kicks in, the memory system gets involved at Phase 2 — before the lossy summarization step. Key facts, decisions, and action items are extracted and checkpointed into the memory pipeline, ensuring they survive even if the summary misses them.

This is the safety net: compaction can lose nuance, but durable memories persist independently of the conversation history.

## Explicit tools

The agent also has four tools for direct memory management, available in Team and Personal sessions:

| Tool | Purpose |
|------|---------|
| `find_memories` | Search durable facts and current evidence by keyword (includes evidence that auto-recall may not surface) |
| `get_memories` | Retrieve full content of specific memories by ID |
| `store_memory` | Explicitly save a memory (bypasses most curation filters) |
| `update_memory` | Correct or supersede an existing memory |

These are the manual-control layer. Most of the time, automatic observation handles memory formation. Explicit tools are for when you want to correct something the agent got wrong or store something it wouldn't have observed on its own. If the agent recalls something incorrect, tell it — "that's wrong, I switched to Postgres last month" — and it will update or supersede the old memory.

## Observability

Memory formation is invisible during normal use — the agent just gets smarter over time. To see what's happening:

- **`netclaw stats`** shows memory recall counts and checkpoint queue depth
- **`netclaw doctor`** runs a health check on the checkpoint queue (warns if pending checkpoints exceed 25)
- **Debug logs** emit query plans, recall scores, and curation decisions for troubleshooting

## Configuration

Memory is enabled by default. The key settings in `netclaw.json`:

| Setting | Default | What it controls |
|---------|---------|-----------------|
| `Memory.Enabled` | `true` | Master switch — disables all memory when `false` |
| `Memory.RecallTimeoutMs` | `300` | Time budget for auto-recall per turn |
| `Memory.AutoRecallMaxItems` | `3` | Maximum memories injected per turn |

SQLite is the only storage backend — no vector database, no external service, no API keys. Netclaw should work on a single machine with nothing beyond what ships in the binary. FTS5 handles the current recall workload; vector search may arrive later.

## Keep reading

- [Sessions & Input Model](/architecture/sessions/) — session lifecycle and compaction (where memory extraction fits)
- [Security Architecture](/architecture/security-model/) — audience scoping that governs memory access
- [Design Philosophy](/architecture/design-philosophy/#automatic-memory-formation) — why memory belongs in core

## Resources

- [SQLite FTS5](https://www.sqlite.org/fts5.html) — the full-text search engine behind memory recall
- [Actor model](https://en.wikipedia.org/wiki/Actor_model) — the concurrency model that makes the observation sidecar possible
- [Akka.NET Persistence](https://getakka.net/articles/persistence/event-sourcing.html) — journal and snapshot recovery for the checkpoint queue
- [Write-Ahead Logging](https://www.sqlite.org/wal.html) — how SQLite ensures memory durability
