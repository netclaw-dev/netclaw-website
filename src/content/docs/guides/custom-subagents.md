---
title: "Custom Subagents"
description: "Define your own subagents as markdown files and spawn them for delegated work."
---

A subagent is a child agent a session spawns to handle bounded, delegated work -- research, code analysis, summarization -- without polluting the main conversation's context. Netclaw ships three built-ins, and you define your own by dropping a markdown file in `~/.netclaw/agents/`.

## Before you begin

- An initialized netclaw install ([`netclaw init`](/cli/init/))
- Subagents run for any audience except `Public` -- a public-channel session can't spawn them

## The agent file

Each subagent is one markdown file in `~/.netclaw/agents/` -- YAML frontmatter on top, the system prompt as the body:

```markdown
---
name: release-notes
description: Draft release notes from a git log and merged PRs
modelRole: Main
timeoutSeconds: 180
visibility: user-facing
---

You write release notes. Given a version range, read the git log and the merged
PRs, group changes into Features / Fixes / Docs, and write a concise changelog
entry in the project's existing style. Lead with user-visible impact.
```

The body after the closing `---` is loaded verbatim as the subagent's system prompt -- no templating.

### Frontmatter fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | Yes | -- | Unique identifier. This is what you pass to `spawn_agent`. Case-insensitive. |
| `description` | Yes | -- | One line. Shown to the parent agent so it knows when to reach for this subagent. |
| `modelRole` | No | `Compaction` | Which model the subagent runs on: `Main` (your primary model) or `Compaction` (the cheaper/faster one). |
| `timeoutSeconds` | No | `60` | Inactivity budget between streamed updates. Range 5--600. |
| `prefillTimeoutSeconds` | No | inherits | Wait-for-first-token budget. Range 5--3600. Falls back to the global subagent default when unset. |
| `emitStructuredFindings` | No | `false` | When `true`, a successful run becomes a memory candidate the parent session can keep. |
| `visibility` | No | `user-facing` | `user-facing` agents are spawnable and listed; `internal` ones are hidden. |
| `tools` | No | `[]` | Advisory metadata only. It does **not** grant or restrict tools -- a subagent's tool access comes from the parent session's audience. |

A file that's missing `name` or `description`, has an empty body, or sets an out-of-range timeout is rejected, and that agent simply doesn't load -- the rest keep working.

## Built-in subagents

`netclaw init` seeds three, as ordinary editable files in `~/.netclaw/agents/`:

| Name | What it does |
|------|-------------|
| `research-assistant` | Deep web research with search and citation |
| `code-analyst` | Analyze code, run commands, and review files |
| `summarizer` | Summarize documents and content concisely |

Edit them, delete them, or use them as templates for your own -- they aren't special.

## Hot reload

Add, edit, or remove a file in `~/.netclaw/agents/` and netclaw picks it up on the next turn -- no daemon restart. An edit that fails validation is dropped rather than served stale, so a typo in one file never takes down the others.

## Spawning a subagent

The parent agent calls the `spawn_agent` tool:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `agent` | Yes | The `name` of a `user-facing` subagent |
| `task` | Yes | A specific, bounded task for this run |
| `context` | No | Extra background prepended to the task |

The subagent runs its own tool loop and returns a single text result to the parent. It inherits the parent's session and project directories, working directory, and trust audience -- so file tools resolve against the same workspace, and a subagent can never widen its own permissions.

Each subagent run gets up to **30 tool iterations** before it's forced to wrap up with a text answer. That's separate from the main session's per-turn budget, `Session:MaxToolIterationsPerTurn` (default **60**, configurable in `netclaw.json`).

## Troubleshooting

### `spawn_agent` says the agent isn't available

The `name` doesn't match any loaded file, or the agent is `visibility: internal`. Check the exact `name` in the frontmatter and that the file parsed -- an invalid file is skipped. Run [`netclaw doctor`](/cli/doctor/) to surface load warnings.

### A subagent stalls or gets killed mid-run

Raise `timeoutSeconds` (inter-update budget) or `prefillTimeoutSeconds` (time to first token) in the agent file. A subagent making steady progress won't be killed; the timeouts catch genuinely stuck runs.

### Subagents don't show up at all

They're unavailable to `Public`-audience sessions by design. Confirm the session's [audience](/security/security-model/) is `Team` or `Personal`.

## Related pages

- [Architecture Overview](/architecture/overview/) -- where subagents sit in the actor model
- [Security Model](/security/security-model/) -- how audience controls subagent tool access
- [`netclaw doctor`](/cli/doctor/) -- surfaces agent-file load warnings

## External resources

- [YAML frontmatter](https://jekyllrb.com/docs/front-matter/) -- the metadata format these files use
- [Anthropic: subagents and orchestration](https://www.anthropic.com/engineering/building-effective-agents) -- background on delegating work to focused agents
