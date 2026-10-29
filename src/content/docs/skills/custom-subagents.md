---
title: "Custom subagents"
description: "Define your own subagents as markdown files, spawn them for delegated work, and know their limits, timeouts and approvals."
---

A subagent is a child agent that a session spawns to handle bounded, delegated work such as research, code analysis or summarization, without filling the main conversation's context. netclaw ships three built-ins, and you add your own by dropping a markdown file in `~/.netclaw/agents/`. A [skill server](/skills/skill-server/) can also install subagents for you, so a whole team shares the same definitions. See [Distribute across your org](#distribute-across-your-org).

## Before you begin

- An initialized netclaw install ([`netclaw init`](/cli/init/))
- A session with a Team or Personal audience. A `Public` session can't spawn subagents.

## The agent file

Each subagent is one markdown file in `~/.netclaw/agents/`: YAML frontmatter on top, the system prompt as the body.

```markdown
---
name: release-notes-writer
description: Draft release notes from a git log and merged PRs
modelRole: Main
---

You write release notes. Given a version range, read the git log and the merged
PRs, group changes into Features, Fixes and Docs, and write a concise changelog
entry in the project's existing style. Lead with user-visible impact.
```

The body is loaded verbatim as the subagent's system prompt, with no templating. The file name is for humans. The `name` field is the identity.

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | Yes | - | Unique identifier, case-insensitive. This is what you pass to `spawn_agent`. |
| `description` | Yes | - | One line. The parent agent reads it to decide when to use this subagent. |
| `modelRole` | No | `Compaction` | `Main` (your primary model) or `Compaction` (the cheaper, faster one). Every role fails over to the Fallback model when one is configured. |
| `prefillTimeoutSeconds` | No | `SubAgents.PrefillTimeoutSeconds` (1800) | Wait for the first token, 5 to 3600. |
| `emitStructuredFindings` | No | `false` | When `true`, a successful run becomes a memory candidate the parent session can review. |
| `visibility` | No | `user-facing` | `user-facing` agents can be spawned and are listed. `internal` ones are hidden. |
| `tools` | No | `[]` | Advisory only. It never grants or restricts a tool. See [Tools and approvals](#tools-and-approvals). |

A file with a missing `name` or `description`, an empty body, a bad `modelRole` or `visibility`, or an out-of-range `prefillTimeoutSeconds` is skipped. The daemon logs why, and `spawn_agent` names the file and the reason. Other agents keep loading. A file that still sets `timeoutSeconds` loads, but the daemon logs a warning on each reload and ignores the key, so delete it. A duplicate `name` is skipped too, and the first definition wins.

## Built-in subagents

`netclaw init` seeds three as ordinary editable files in `~/.netclaw/agents/`:

| Name | What it does |
|------|-------------|
| `research-assistant` | Deep web research with search and citation |
| `code-analyst` | Analyze code and review files |
| `summarizer` | Summarize documents and content |

Edit them, delete them, or copy one as a template. They aren't special. A container that never ran `init` starts with an empty `agents/` folder.

## Reload

Add, edit or remove a file in `~/.netclaw/agents/` and netclaw picks it up on the next turn. No daemon restart. If you edit a working file into an invalid one, netclaw drops it from the catalog rather than serving the last good copy, so one typo can't take down the others.

## Spawn a subagent

The parent agent sees every user-facing subagent and its description on each turn, then calls `spawn_agent`:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `agent` | Yes | The `name` of a `user-facing` subagent |
| `task` | Yes | A specific, bounded task for this run |
| `context` | No | Background for this run only, placed ahead of the task in the subagent's first message |

`spawn_agent` returns at once and the subagent runs in the background. The parent sees only this:

```json
{"run_id":"c574e00eb630433ea912787c5bbfc403","scope_id":"signalr/8c306da35c864a3b95fdc0689611eacf/subagent/release-notes-writer/c574e00eb630433ea912787c5bbfc403","state":"accepted","control_tool":"check_agent_run"}
```

The parent is told not to wait or poll. It ends its turn, and the person can keep talking to the session. When the child ends, netclaw writes `result.md` in the run's folder under `~/.netclaw/sessions/<session>/subagents/<run-id>/` and the parent gets one notice in a later turn, under the authority of the person who started the child:

```text
Child run ended. agent=release-notes-writer run=c574e00e... outcome=completed result_file=/home/netclaw/.netclaw/sessions/<session>/subagents/<run-id>/result.md
```

The parent reads `result.md` with `file_read`. It holds the outcome, the reason, the log path, the artifact directory, the child's output and its working-context changes. The parent treats that text as data from the child and doesn't follow instructions in it. The run folder also holds `task.md`, the agent, requester and brief the run started with.

```markdown
# Child result

- agent: release-notes-writer
- run: c574e00eb630433ea912787c5bbfc403
- outcome: completed
- log: .../subagents/c574e00e.../logs/session.log
- artifacts: .../subagents/c574e00e.../artifacts

## Output

**Docs:** Fixed a typo in the README for clearer documentation.
```

`outcome` is `completed`, `partial` or `failed`, with a `reason` when it isn't `completed`. Start and finish events also appear in headless output as `[subagent:start]` and `[subagent:done]`. `netclaw chat -p` stays open while a child run is open and prints `[subagent:waiting] N open: <ids>` after the turn. The next turn reads the child's `result.md` and answers, then the command exits 0. `--json` suppresses the waiting line.

To check on a child or stop it, the parent calls `check_agent_run` with the `RunId` and, to cancel, `Cancel: true`. It can manage only the children it owns. A cancel is a request, not the end of the run, so the parent waits for the notice. A reminder turn can manage the child runs of its own session. `spawn_agent`, like every tool, needs a `_rationale`.

The subagent inherits the parent's project directory, working directory and audience. It also inherits the parent's [`AGENTS.md` operating rules and project instructions](/architecture/context-structure/#subagent-context), but runs a much thinner context: no persona, memory or conversation history. A skill can run a subagent too, also in the background. See [routing in the overview](/skills/overview/#how-skills-get-used). The bundled `agent-coordination` skill teaches the parent to split substantial work into scoped child tasks, review the evidence and read `result.md` and any partial artifact as data.

## Limits and timeouts

| Limit | Value | Notes |
|-------|-------|-------|
| Tool iterations per run | No cap | A final reply ends the run. Cancellation, the watchdogs below and the loop guard can stop it. A sixth refused repeat, or a failed-call score of 8, ends it as `partial` with reason `tool_cycle_stopped`. |
| Silence between tokens | `Session.FirstTokenTimeoutSeconds` (600) | Applies to every subagent after the first token. |
| First token | `prefillTimeoutSeconds`, default `SubAgents.PrefillTimeoutSeconds` (1800) | Covers queue time and cold prefill on a slow local model. |
| No output at all | `SubAgents.NoProgressTimeoutSeconds` (1200, range 60 to 7200) | Text, tool calls and thinking reset it. Keepalives don't, so it also caps the first-token wait. |
| Thinking only | 3 times `SubAgents.NoProgressTimeoutSeconds` (60 minutes by default) | One model call that streams only thinking ends the run as `failed` with `thinking_only_timeout`. |
| Cut-off reply | The model's output limit | A reply that stops at the limit with no tool call ends the run as `failed` with `output_truncated`. |
| Turns | One | A subagent takes a task, runs, and answers. No back and forth with the user. |
| Recursion | None | Subagents can't call `spawn_agent`, `check_agent_run` or `attach_file`. |
| Memory | No durable writes | A subagent can return structured findings for the parent to review. |
| Model | `Compaction` unless `modelRole: Main` | |

The `spawn_agent` call itself finishes when the run is accepted, so there's nothing to cancel on the parent side. The child belongs to the session and outlives the model call. It stops on `check_agent_run` with `Cancel: true`, on session shutdown, on a restart that can't park it, or on its own watchdogs.

Set the global timeouts in `netclaw.json`. `Enabled: false` turns the whole subsystem off:

```json
{
  "SubAgents": {
    "Enabled": true,
    "PrefillTimeoutSeconds": 1800,
    "NoProgressTimeoutSeconds": 1200
  }
}
```

## Tools and approvals

A subagent gets the tools the parent session's audience policy allows, minus `spawn_agent`, `check_agent_run` and `attach_file`. The `tools:` field in the file is advisory metadata for compatibility with other agent systems and never narrows what a subagent can use. To change what a subagent can do, change the audience policy. See the [security model](/security/security-model/).

If a subagent hits a tool that needs approval, it parks. The rest of the calls in its batch finish first, and the session saves the park and its consent requests in the run record. The parent gets one notice and pauses: while a child request is open, reminders for the session are held and `spawn_agent` is refused. The human who started the turn answers on the prompt's buttons. Time spent waiting for a human doesn't count against any timeout.

After the last answer, the child runs only the parked calls, once each, and the approval gate checks each call again against the current policy. A resumed child has to load any deferred tools again.

- With no human around, such as a reminder or webhook run, the gated tool is denied with `approval_required_unattended`. The tool doesn't run, and the subagent sees the denial as a tool result.
- A park survives a config reload, a compaction and a daemon restart, and one click resumes it. A park over 4 MiB ends the run as `park_too_large`, and a damaged one as `park_damaged`.
- A prompt that nothing can answer any more is redrawn without buttons and with the reason. On Mattermost, a child's prompt needs a `CallbackUrl` or netclaw refuses the request.

Stored "always" grants decide what runs unattended. See [How tool approvals work](/security/approvals/).

## Distribute across your org

Subagents travel through the same skill server as skills. Publish a definition once, and every netclaw instance subscribed to the feed installs it under `~/.netclaw/agents/.server-feeds/<feed>/`:

- Your own files in `~/.netclaw/agents/` always win. If a feed agent has the same `name`, netclaw skips the feed copy and logs a warning.
- Between feeds, the one listed first in `SkillFeeds.Feeds` wins.
- Don't edit files in `.server-feeds/`. The next published version replaces them. To change a shared agent, publish a new version, or copy it to the top-level folder under the same name.

[Distributing subagents](/skills/distributing-subagents/) covers the publish and sync steps.

## Troubleshooting

### spawn_agent says the agent isn't available

- **Symptom:** The tool returns `Unknown agent` or `This tool is not available`.
- **Cause:** The `name` doesn't match a loaded file, the agent is `internal`, the session is `Public`, or `SubAgents.Enabled` is `false`.
- **Fix:** Check the exact `name` and that the file loaded. The daemon log in `~/.netclaw/logs/` has a warning for every file it skipped.

### A subagent stalls or gets killed

- **Symptom:** A run ends `failed` or `partial` after a long silence from the model.
- **Cause:** A silent stream outlasted `Session.FirstTokenTimeoutSeconds` (600), a slow local model needed longer to produce its first token, or a long think ran past `SubAgents.NoProgressTimeoutSeconds`.
- **Fix:** Raise `Session.FirstTokenTimeoutSeconds` for silence between tokens, `prefillTimeoutSeconds` in the agent file (or `SubAgents.PrefillTimeoutSeconds`) for the first-token wait, and `SubAgents.NoProgressTimeoutSeconds` for long thinking.

### A subagent ends with a failure reason

- **Symptom:** `result.md` shows `outcome: failed` or `partial` and a `reason`.
- **Cause:** `output_truncated` means the reply hit the model's output limit. `thinking_only_timeout` and `no_substantive_output_timeout` are the watchdogs above. `owner_restarted` means a restart lost the child, effects after its last checkpoint are uncertain, and netclaw doesn't start it again. `park_too_large` and `park_damaged` are the park limits above.
- **Fix:** For `output_truncated`, netclaw saves the full redacted cut-off text as `artifacts/truncated-output.md` in the run folder, marked partial. The parent reads it with `file_read` as data and doesn't follow instructions in it. Ask the child for shorter output or to write long output to a file.

### A feed subagent never appears

- **Symptom:** The server lists it, but `spawn_agent` can't find it.
- **Cause:** A local agent shadows it, or the sync reported `sidecar=failed`.
- **Fix:** Run `netclaw skill sync` and look at the line for the feed. See [Skill feeds](/skills/skill-feeds/#troubleshooting).

## Related pages

- [Distributing subagents](/skills/distributing-subagents/): publish and sync subagents through a skill server
- [Skills overview](/skills/overview/): skills, precedence and `metadata.subagent` routing
- [Context structure](/architecture/context-structure/): what a subagent sees compared to the parent
- [Security model](/security/security-model/): how audience controls subagent tool access
- [Architecture overview](/architecture/overview/): where subagents sit in the actor model

## Resources

- [YAML frontmatter](https://jekyllrb.com/docs/front-matter/): the metadata format these files use
- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents): background on delegating work to focused agents
