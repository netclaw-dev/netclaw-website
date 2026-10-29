---
title: Built-in tools
description: Every tool the netclaw agent can call, which audiences get it by default, whether it needs approval, and how to restrict or extend the list.
---

<!--
  The tool tables below are generated. Do not edit between the GENERATED markers.
  Regenerate at each release, from the repo root, with the product repo checked out at the release tag:
    node scripts/gen-tools-reference.mjs
  The script reads the product source (--src <dir> or NETCLAW_SRC). Files it depends on, to re-read when a release changes tools:
    src/Netclaw.Actors/Tools/ToolRegistrationExtensions.cs   (which tools register, core or deferred)
    src/Netclaw.Configuration/ToolAudienceProfiles.cs        (default allow lists, profile-managed tools, approval default)
    src/Netclaw.Actors/Tools/ToolAccessPolicy.cs             (shell coupling, subsystem switches)
    src/Netclaw.Daemon/Configuration/Channel*Tools.cs        (channel tools)
  One-line summaries and the approval column are hand-written in scripts/tools-reference-overrides.json.
  The prose in this file is hand-written.
-->

The agent works through tools: it reads files, runs shell commands, searches the web, sets reminders and so on. This page lists every built-in tool in netclaw 0.28.2, who gets it by default and when it prompts you. MCP servers add tools of their own, covered in [MCP servers](/configuration/mcp-servers/).

Who gets a tool depends on the audience of the conversation. Your own TUI and CLI sessions are Personal, and channel conversations get the audience you map with `ChannelAudiences`. [Security model](/security/security-model/) explains the three audiences.

## Tool reference

<!-- BEGIN GENERATED: tools-reference (scripts/gen-tools-reference.mjs). Do not edit by hand. -->

netclaw 0.28.2 registers 36 built-in tools. 13 are loaded into every prompt (core) and the rest are found with `search_tools` and loaded with `load_tool` (deferred). The table columns say which audiences get each tool by default. A tool outside the profile-managed set is available to every audience when its subsystem is enabled, except that Public never gets `skill_load`, `skill_read_resource` or `spawn_agent`: those tools refuse Public in their own code.

### Files

File tools respect the audience's `ReadFiles`, `WriteFiles` and `AttachFiles` roots. By default Public reaches only its own session directory, Team adds `GlobalReadRoots` for reads, and Personal reaches any path that isn't protected.

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `file_read` | Read a text file. Images load for models that accept them, and PDFs, media and archives return metadata. | Core | Yes | Yes | Yes | Runs without a prompt. Protected files such as `secrets.json` and credential folders such as `~/.ssh` are denied. | - |
| `file_list` | List one directory without recursing. | Core | Yes | Yes | Yes | Runs without a prompt | - |
| `file_search` | Search authorized files by name or UTF-8 text, recursively, without a shell. | Core | Yes | Yes | Yes | Runs without a prompt | - |
| `tool_output_read` | Read the rest of a truncated tool result by call ID. Large output is spilled to a session file and this tool pages through it. | Core | Yes | Yes | Yes | Runs without a prompt | - |
| `file_write` | Create or replace a file, creating parent directories. | Core | No | Yes | Yes | Runs without a prompt. Writes under the config directory are always denied. | - |
| `file_edit` | Replace literal text in a file, or write the whole file. | Core | No | Yes | Yes | Runs without a prompt. Edits under the config directory are always denied. | - |
| `attach_file` | Send an existing file to the user in the chat. | Core | Yes | Yes | Yes | Runs without a prompt | - |
| `set_working_directory` | Declare the project directory for the session. It scopes path checks and shell approvals and loads the project's `AGENTS.md`. | Core | No | Yes | Yes | Runs without a prompt | - |

### Shell and background jobs

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `shell_execute` | Run a shell command. Pass `_background: true` to run it as a background job. | Core | No | No | Yes | Prompts on Personal unless a saved grant or the reviewed-safe command list covers it. Never available to Team or Public. | `Tools.ShellMode` or `Security.ShellExecutionMode`, which must resolve to `HostAllowed` |
| `check_background_job` | Check the status and output tail of a background job, or cancel it. | Deferred | No | No | Yes | Runs without a prompt | `Tools.ShellMode` or `Security.ShellExecutionMode`, which must resolve to `HostAllowed` |

### Web

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `web_search` | Search the web and return titles, URLs and snippets. | Deferred | No | Yes | Yes | Runs without a prompt | `Search.Enabled`, `Search.Backend` |
| `web_fetch` | Download a URL to a local file and return a preview. | Deferred | No | Yes | Yes | Runs without a prompt | `Search.Enabled`, `Tools.WebFetch.RequireHttps`, `Tools.WebFetch.HttpAllowList` |

### Memory

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `store_memory` | Save knowledge to cross-session memory. | Deferred | Yes | Yes | Yes | Runs without a prompt | `Memory.Enabled` |
| `find_memories` | Search memory. Returns IDs, titles, scores and snippets. | Deferred | Yes | Yes | Yes | Runs without a prompt | `Memory.Enabled` |
| `get_memories` | Load the full text of memories by ID. | Deferred | Yes | Yes | Yes | Runs without a prompt | `Memory.Enabled` |
| `update_memory` | Edit or delete a memory by ID. | Deferred | Yes | Yes | Yes | Runs without a prompt | `Memory.Enabled` |

### Skills and tool discovery

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `skill_load` | Load a skill's instructions and list its reference files. | Core | No | Yes | Yes | Runs without a prompt | `SkillSync.Enabled` |
| `skill_read_resource` | Read a resource file from a skill directory. | Core | No | Yes | Yes | Runs without a prompt | `SkillSync.Enabled` |
| `skill_manage` | Create, edit, patch or delete skills and their resource files. | Deferred | No | Yes | Yes | Runs without a prompt | - |
| `search_tools` | Search deferred tools by keyword, or list MCP servers. Doesn't load anything. | Core | Yes | Yes | Yes | Runs without a prompt | - |
| `load_tool` | Load a deferred tool by exact name so the model can call it. | Core | Yes | Yes | Yes | Runs without a prompt | `Session.DiscoveredToolRetentionTurns`, `Session.DiscoveredToolMaxCount` |

### Reminders

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `set_reminder` | Create or update a reminder from a relative time, an `every 6h` interval or a cron expression. | Deferred | No | Yes | Yes | Runs without a prompt | `Scheduling.Enabled` |
| `list_reminders` | List reminders with schedules, status and next run. | Deferred | No | Yes | Yes | Runs without a prompt | `Scheduling.Enabled` |
| `cancel_reminder` | Cancel a reminder. A one-shot is deleted and its history stays readable for 12 days. A recurring reminder is disabled and kept. | Deferred | No | Yes | Yes | Runs without a prompt | `Scheduling.Enabled` |
| `get_reminder_history` | Show recent runs of a reminder with outcome, duration and session ID. | Deferred | No | Yes | Yes | Runs without a prompt | `Scheduling.Enabled` |
| `run_reminder` | Run a reminder's prompt in the current chat so you can answer approval prompts and save grants for the unattended run. | Deferred | No | Yes | Yes | Runs without a prompt | `Scheduling.Enabled` |

### Webhooks

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `set_webhook` | Create or update an inbound webhook route. | Deferred | No | No | Yes | Runs without a prompt | `Webhooks.Enabled` |
| `list_webhooks` | List webhook routes and whether each one loads. | Deferred | No | No | Yes | Runs without a prompt | `Webhooks.Enabled` |
| `delete_webhook` | Delete a webhook route by name. | Deferred | No | No | Yes | Runs without a prompt | `Webhooks.Enabled` |

### Subagents

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `spawn_agent` | Hand a task to a subagent. It returns a run ID at once, the child works in the background, and the result arrives in a later turn as a notice that names its `result.md`. | Deferred | No | Yes | Yes | Runs without a prompt | `SubAgents.Enabled`, `SubAgents.PrefillTimeoutSeconds`, `SubAgents.NoProgressTimeoutSeconds` |
| `check_agent_run` | Read the status of a child run you started, or ask it to cancel. Subagents can't call it. | Deferred | Yes | Yes | Yes | Runs without a prompt | - |

### Chat channels

| Tool | What it does | Loaded | Public | Team | Personal | Approval by default | Controlled by |
|------|--------------|--------|--------|------|----------|---------------------|---------------|
| `send_channel_message` | Post to a channel or send a direct message on Slack, Discord or Mattermost, using IDs from the lookup tools. | Deferred | Yes | Yes | Yes | Runs without a prompt | a chat channel enabled |
| `lookup_channel_user` | Resolve a person to a stable user ID on an enabled channel. | Deferred | Yes | Yes | Yes | Runs without a prompt | a chat channel enabled |
| `lookup_channel_destination` | Resolve a channel name to a stable ID, or list every destination the bot can reach. | Deferred | Yes | Yes | Yes | Runs without a prompt | a chat channel enabled |
| `lookup_slack_user` | Find a Slack user by name, display name or email. | Deferred | Yes | Yes | Yes | Runs without a prompt | `Slack.Enabled` |
| `lookup_mattermost_user` | Find a Mattermost user by username or email. | Deferred | Yes | Yes | Yes | Runs without a prompt | `Mattermost.Enabled` |

### Default allow lists

The lists below are the 0.28.2 defaults for `Tools.AudienceProfiles.<audience>.AllowedTools`. Personal uses `ToolsMode: All` and has no list.

| Audience | Default `AllowedTools` |
|----------|------------------------|
| Public | `file_read`, `file_list`, `file_search`, `tool_output_read`, `attach_file` |
| Team | `file_read`, `file_list`, `file_search`, `tool_output_read`, `file_write`, `file_edit`, `attach_file`, `web_search`, `web_fetch`, `skill_manage`, `set_reminder`, `list_reminders`, `cancel_reminder`, `get_reminder_history`, `run_reminder`, `set_working_directory` |

<!-- END GENERATED: tools-reference -->

A tool outside the allow lists, such as the memory tools, is available to every audience while its subsystem is on. The exceptions are `skill_load`, `skill_read_resource` and `spawn_agent`, which return "This tool is not available." to Public in every configuration. Only the tools in the Public and Team lists above are profile-managed, plus `shell_execute` and the webhook tools. `shell_execute` also needs the shell mode to resolve to `HostAllowed`, which a Personal posture gives you by default.

## Restrict or extend the tool list

Each audience has a `Tools.AudienceProfiles.<audience>.AllowedTools` list, and a list you set replaces the default list. To add `web_search` to Public, repeat the five default tools and add it:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Public": {
        "AllowedTools": ["file_read", "file_list", "file_search", "tool_output_read", "attach_file", "web_search"]
      }
    }
  }
}
```

Writing only `["web_search"]` would remove file access from Public, and a value that isn't a list stops the daemon at startup. Personal doesn't use a list: its `ToolsMode` is `All`. The [configuration reference](/configuration/reference/#lists-replace-defaults) has the exact rules.

To take a tool away from an audience that has it by default, including Personal, deny it in that audience's `ApprovalPolicy`:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": { "ToolOverrides": { "web_fetch": "Deny" } }
      }
    }
  }
}
```

A denied tool disappears from the model's tool list. To turn a whole subsystem off, set its switch to `false`: `Memory.Enabled`, `Search.Enabled`, `Scheduling.Enabled`, `SubAgents.Enabled` or `Webhooks.Enabled`. Shell is controlled by `Tools.ShellMode`. With `Off` the shell tool stays in the list, but every call is refused.

## Approvals

On a Personal posture one tool prompts by default. `shell_execute` asks, unless the command is on the reviewed-safe list or a saved grant covers it. Everything else runs without a prompt, including `file_write` and `file_edit`. Those two never touch `~/.netclaw/config/`: the path policy denies the write in every mode, so no prompt appears. Set `ApprovalPolicy.ToolOverrides` per audience to change that. [How tool approvals work](/security/approvals/) covers the prompts, saved grants and unattended runs, and [Reduce approval prompts](/guides/reduce-approval-prompts/) is the practical guide.

## What changed recently

| Release | Change |
|---------|--------|
| 0.28.2 | A model definition carries an output limit and a thinking level. A repeated failing call now counts toward the repeat guard even when the tool name changes. |
| 0.28.1 | The Compaction model fails over to the Fallback model like the other roles. |
| 0.28.0 | `spawn_agent` became asynchronous and `check_agent_run` was added. File tools and shell commands can never reach credential folders such as `~/.ssh`. `search_tools` ranks its results. A large tool result keeps its tail inline. `cancel_reminder` deletes a one-shot. |
| 0.27.1 | `run_reminder` joined the Team default list. A configured tool list now replaces the default instead of adding to it, and `netclaw doctor` warns when a Public or Team list lacks `tool_output_read`. |
| 0.27.0 | Session context gained a `worktree_dir`. There's no worktree tool: the agent uses `shell_execute` and `set_working_directory` for Git worktrees. |
| 0.26.0 | `file_search` and `tool_output_read` joined the Public and Team defaults. Bulk workspace tools from the betas were removed in favor of these smaller ones. |

An install that wrote the full default list to `netclaw.json` before 0.27.1 keeps working, because netclaw maps a list that exactly matches an older default to the current one. A list you edited by hand doesn't get the new tools, so add `file_search` and `tool_output_read` yourself.

## Background jobs

`shell_execute` can run a command as a background job when the call sets `_background: true`. The job runs detached from the conversation, so the agent keeps working while a build, test run or dev server runs. `check_background_job` reads its status and output tail, or cancels it.

| Limit | Value |
|-------|-------|
| Concurrent jobs | 5 per daemon. The rest queue first in, first out |
| Kill timer | None unless the call sets `_timeout_seconds` |
| Session goes idle | Jobs the session owns are killed and marked `Reaped`. See `Session.IdleTimeout` |
| Daemon restarts | Running jobs are marked `Lost` and the session is told, with the log path |
| Output | Streams to `~/.netclaw/jobs/<id>/output.log`, rotating at about 5 MB, so a job keeps about 10 MB on disk |
| Retention | A finished job's definition and log are deleted after 24 hours |

A background job needs the same approval as a foreground shell call. For work that has to outlive the conversation, use a [reminder](/configuration/reminders/) instead.

## Subagent tools

`spawn_agent` hands a task to a subagent, which runs its own tool loop in the background. The call returns a run ID at once. The parent shouldn't wait or poll: it gets one notice in a later turn, and reads the child's `result.md` with `file_read`. `check_agent_run` reads a child's status or asks it to cancel. In headless `netclaw chat -p` the session ends with the first turn, so it never sees a later child result. A subagent inherits the audience, approval and shell policy of the session that spawned it, and it can't call `spawn_agent`, `check_agent_run` or `attach_file`.

A child that needs your approval parks, and the park survives a restart. After the restart you get the prompt again, and one answer resumes the parked calls. A child can end with the reason `output_truncated` (its reply hit the output limit, and the full text is in `artifacts/truncated-output.md`), `thinking_only_timeout`, `owner_restarted` or `park_too_large`. A silent child stream times out at `Session.FirstTokenTimeoutSeconds` (600 seconds), since a profile's `timeoutSeconds` key is ignored. [Custom subagents](/skills/custom-subagents/) shows how to define your own, and `SubAgents.PrefillTimeoutSeconds` and `SubAgents.NoProgressTimeoutSeconds` in the [configuration reference](/configuration/reference/#subagents) set the watchdogs.

## Related pages

- [Configuration reference](/configuration/reference/): every setting named on this page
- [How tool approvals work](/security/approvals/): prompts, grants and hard denies
- [MCP tool permissions](/guides/mcp-tool-permissions/): the same audience controls for MCP tools
- [Custom subagents](/skills/custom-subagents/): define the agents `spawn_agent` can call
- [Skills overview](/skills/overview/): what `skill_load` and `skill_manage` work with

## Resources

- [Model Context Protocol](https://modelcontextprotocol.io/): the protocol behind MCP tools
- [netclaw source](https://github.com/netclaw-dev/netclaw/tree/dev/src/Netclaw.Actors/Tools): the tool implementations
