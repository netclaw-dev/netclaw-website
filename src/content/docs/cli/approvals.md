---
title: "netclaw approvals"
description: "Inspect, revoke, and manage persistent tool approvals."
---

When netclaw's [approval gates](/architecture/security-model/#human-in-the-loop-as-a-layer-not-a-crutch) prompt you to allow a tool invocation, your "always allow" choices get saved to `~/.netclaw/config/tool-approvals.json`. This command lets you see what's been approved, revoke entries you no longer want, and add global trust rules. Running `netclaw approvals` with no subcommand opens the [interactive TUI](#tui).

![Approval gate prompt in a Slack thread, with approve and deny options](/assets/approval-prompt.png)

The two "Always" options in the channel prompt — **Always here** (the command's verb, scoped to the current directory) and **Always anywhere** (a global grant) — are what create persistent entries in `tool-approvals.json`.

Audiences (`personal`, `team`, `public`) scope approvals to who's talking to the agent. An approval granted under `personal` doesn't apply when a team member triggers the same command. See [audience dispositions](/architecture/security-model/#audience-as-the-trust-primitive) for background.

Don't hand-edit the JSON file. Use this command instead.

## Usage

```bash
netclaw approvals                         # open TUI
netclaw approvals list [options]          # print approvals
netclaw approvals revoke <pattern> [options]  # remove an approval
netclaw approvals trust-verb <verb> [options] # add a global approval
netclaw approvals tui                     # open TUI (explicit)
netclaw approvals help                    # show help
```

## Subcommands

### list

Show what's currently approved. Filter by audience or tool.

```bash
netclaw approvals list
netclaw approvals list --audience personal
netclaw approvals list --tool shell_execute
netclaw approvals list --json
```

| Flag | Description | Default |
|------|-------------|---------|
| `--audience <name>` | Filter to `personal`, `team`, or `public` | all audiences |
| `--tool <name>` | Filter to a specific tool (e.g., `shell_execute`, `mcp:demo-utilities:write_file`) | all tools |
| `--json` | Machine-readable JSON output | off |

![netclaw approvals list output](/screenshots/output/approvals-list.png)

The `--json` output follows a stable schema — safe to pipe into `jq` for scripting:

```bash
# List all directory-scoped shell approvals
netclaw approvals list --json \
  | jq '.audiences.personal.shell_execute[] | select(.directory != null)'
```

### revoke

Remove a specific approval entry. The pattern format matches the display output from `list`: `<verb> in <directory>` for directory-scoped entries, or `<verb> anywhere` for global approvals.

```bash
netclaw approvals revoke 'git push anywhere'
netclaw approvals revoke 'docker compose in /home/user/repos/netclaw/'
netclaw approvals revoke 'git push anywhere' --audience team
```

Remove all approvals for a tool:

```bash
netclaw approvals revoke --tool shell_execute --all
netclaw approvals revoke --tool mcp:demo-utilities:write_file --all
```

| Flag | Description | Default |
|------|-------------|---------|
| `--audience <name>` | Target audience | `personal` |
| `--tool <name>` | Target tool | `shell_execute` |
| `--all` | Remove all entries for the tool (requires `--tool`) | off |

Changes take effect immediately — no daemon restart needed.

### trust-verb

Add a global-wildcard approval so the verb runs in any working directory without prompting.

```bash
netclaw approvals trust-verb 'git push'
netclaw approvals trust-verb 'npm run' --audience team
netclaw approvals trust-verb 'write_file' --tool mcp:demo-utilities:write_file
```

| Flag | Description | Default |
|------|-------------|---------|
| `--audience <name>` | Target audience | `personal` |
| `--tool <name>` | Target tool | `shell_execute` |

This writes an entry with `directory: null` — an "anywhere" grant in `list` output.

### tui

Open the interactive approvals manager. Same as running `netclaw approvals` with no arguments.

![Approvals TUI showing entries with revoke option](/screenshots/output/approvals-tui.png)

| Key | Action |
|-----|--------|
| Up / Down | Navigate entries |
| Enter, Delete, or R | Revoke selected entry |
| Enter | Confirm revoke (in confirmation dialog) |
| Esc | Cancel revoke confirmation |
| Ctrl+Q | Quit |

The TUI is read-and-revoke only — use `trust-verb` on the command line to add new entries.

![Revoke confirmation dialog in the TUI](/screenshots/output/approvals-tui-revoke-confirm.png)

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | User error or no matching entry for `revoke` |

## File format

Approvals live in `~/.netclaw/config/tool-approvals.json`:

```json
{
  "version": 2,
  "audiences": {
    "personal": {
      "shell_execute": [
        { "verb": "git push", "directory": null },
        { "verb": "docker compose", "directory": "/home/user/repos/netclaw/" }
      ]
    },
    "team": {
      "shell_execute": [
        { "verb": "git pull", "directory": null }
      ]
    }
  }
}
```

Each entry is a verb + optional directory. `directory: null` means the verb is approved in any working directory. A specific directory scopes the approval to that path and its children. The daemon picks up file changes automatically.

## Case sensitivity

Verb and directory matching uses ordinal comparison on Linux/macOS (case-sensitive) and ordinal-ignore-case on Windows. This matches filesystem semantics — `git Push` won't match `git push` on Linux.

## Recovery

If `tool-approvals.json` is malformed, the daemon moves it aside and creates a fresh file:

| Sibling file | Meaning |
|---|---|
| `tool-approvals.json.invalid` | Current file failed to parse — moved aside, fresh file created |
| `tool-approvals.json.v1.bak` | Legacy v1 format — no auto-migration, kept as backup |

To reset completely, delete `tool-approvals.json` and restart the daemon. The next tool invocation that requires approval will recreate the file.

## Recipes

Which directories have you granted shell access to?

```bash
netclaw approvals list --json \
  | jq '.audiences.personal.shell_execute[] | select(.directory != null) | .directory'
```

Wipe all team-level shell approvals and start fresh:

```bash
netclaw approvals revoke --tool shell_execute --all --audience team
```

## Related commands

- [`netclaw init`](/cli/init/) — sets the initial audience disposition and approval policy
- [`netclaw mcp-tools`](/cli/mcp-tools/) — manage per-tool MCP permissions
- [`netclaw secrets`](/cli/secrets/) — manage encrypted credentials

## Resources

- [Security Model](/architecture/security-model/) — how approvals fit into the four-layer security model
- [MCP Tool Permissions](/guides/mcp-tool-permissions/) — MCP-specific approval configuration
