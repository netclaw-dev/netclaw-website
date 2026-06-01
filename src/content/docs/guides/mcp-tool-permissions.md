---
title: "MCP Tool Permissions"
description: "Configure tool audience grants for Personal, Team, and Public."
---

You've added MCP servers to netclaw but the tools aren't showing up in Team or Public sessions. That's by design -- new servers start fully locked down.

For the full TUI and CLI reference, see [`netclaw mcp`](/cli/mcp-tools/). For the config schema, see [MCP Servers](/configuration/mcp-servers/).

## Before You Begin

- At least one MCP server added (`netclaw mcp add`) and the daemon running -- run `netclaw mcp list` to confirm your servers are connected
- Familiarity with netclaw's three [audiences](/security/security-model/#trust-audiences): Personal (TUI, SignalR web client), Team (Slack), Public (unknown channels)

## How Audience Defaults Work

Each audience starts with different MCP access:

| Audience | Servers allowed | Tools granted |
|----------|----------------|---------------|
| **Personal** | All | All |
| **Team** | None (allowlist, empty) | None |
| **Public** | None (allowlist, empty) | None |

No audience has approval gates configured by default -- all granted tools run automatically. `netclaw init` recommends adding `shell_execute: Approval` for the Personal audience, but that's an opt-in step during setup.

Personal gets everything out of the box. Team and Public get nothing -- you opt in server by server, tool by tool.

## Grant Permissions with the TUI

```bash
netclaw mcp permissions
```

Use the TUI for interactive setup when you want to explore what's available.

### Pick a server

![MCP Permissions server list showing three connected servers](/screenshots/output/mcp-tools-server-list.png)

The server list shows connection status and tool count for each configured server. Select one to manage its grants.

### Grant tools per audience

![Personal audience with all tools granted and Auto approval](/screenshots/output/mcp-tools-personal.png)

Personal audience -- all tools granted, Auto approval mode. Use `←`/`→` on the Audience row to switch between Personal, Team, and Public.

![Team audience with server disabled and no tools granted](/screenshots/output/mcp-tools-team.png)

Team audience -- server not enabled, nothing granted. Same defaults apply to Public.

To open up a server for Team:

1. Press `E` to enable the server for this audience
2. Press `A` to toggle all tools on, or `Space` on individual tools
3. Press `M` to cycle the server's default approval mode (Auto / Approval / Deny)
4. Press `P` on any row to set a per-tool approval override
5. Press `Enter` to save

Changes write to `~/.netclaw/config/netclaw.json`. Run `netclaw daemon restart` to apply.

## Grant Permissions via JSON

For automation or version-controlled config, edit `netclaw.json` directly.

### Enable a server for an audience

Add the server name to `AllowedMcpServers`:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Team": {
        "McpServersMode": "Allowlist",
        "AllowedMcpServers": ["memorizer", "notion"]
      }
    }
  }
}
```

### Grant specific tools

Use `McpServerToolGrants` to control which of a server's tools are visible. Omit a server from this map to pass all its tools through:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Team": {
        "McpServersMode": "Allowlist",
        "AllowedMcpServers": ["notion"],
        "McpServerToolGrants": {
          "notion": ["notion-search", "notion-fetch", "notion-create-pages"]
        }
      }
    }
  }
}
```

Team users see only `notion-search`, `notion-fetch`, and `notion-create-pages`. Everything else on the Notion server is invisible to the model.

## Grant Permissions via CLI

Skip the TUI for quick one-off changes:

```bash
# Grant specific tools for team
netclaw mcp tools notion --audience team \
  --grant "notion-search,notion-fetch,notion-create-pages"

# Snapshot all currently discovered tools into grants
netclaw mcp tools memorizer --snapshot
```

## Set Approval Policies

Approval policies control whether granted tools run automatically or need human confirmation:

| Mode | Behavior |
|------|----------|
| `Auto` | Runs immediately, no prompt |
| `Approval` | Human must confirm before execution |
| `Deny` | Always blocked, no prompt offered |

### Precedence

Netclaw resolves the effective mode in order:

1. **Exact tool override** -- `ToolOverrides["notion/notion-delete-page"]`
2. **Server default** -- `McpServerDefaults["notion"]`
3. **Audience default** -- `DefaultMode`

First match wins.

### Example: Auto for reads, Approval for writes

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "DefaultMode": "Auto",
          "McpServerDefaults": {
            "notion": "Auto"
          },
          "ToolOverrides": {
            "notion/notion-delete-page": "Approval",
            "notion/notion-update-page": "Approval",
            "shell_execute": "Approval"
          }
        }
      }
    }
  }
}
```

MCP tool override keys use the format `"{serverName}/{toolName}"` -- e.g., `"notion/notion-delete-page"`.

### Server defaults for new tools

Newly discovered tools on a server inherit its `McpServerDefaults` entry automatically:

```json
"McpServerDefaults": {
  "browser_playwright": "Approval"
}
```

Every tool on `browser_playwright` now requires approval unless you add an explicit `ToolOverrides` entry for it.

## Verify It Works

After changing permissions, restart the daemon and confirm:

```bash
netclaw daemon restart
netclaw mcp tools notion --audience team
```

The output lists every tool the Team audience can see on the `notion` server, along with the effective approval mode for each.

## Persistent Approvals

When a user picks one of the "Always" options — **Always here** (the command's verb, scoped to a directory) or **Always anywhere** (a global grant) — at an approval prompt, the decision persists to `~/.netclaw/config/tool-approvals.json`. These approvals survive daemon restarts.

To revoke a persistent approval, edit the file directly:

```json
{
  "audiences": {
    "personal": {
      "shell_execute": ["git push", "npm install"]
    }
  }
}
```

Remove entries you no longer want auto-approved. `netclaw doctor` warns about stale approvals for disabled audiences.

If `tool-approvals.json` becomes corrupt, netclaw quarantines it to `tool-approvals.json.invalid` and starts with an empty store. Fail-closed -- no approvals carry over until you fix the file.

## Headless Mode and Approval Gates

Approval gates only work on interactive channels. Non-interactive sessions auto-deny all gated tools immediately -- there's no human to ask.

| Channel | Supports approval? |
|---------|-------------------|
| TUI (`netclaw chat`) | Yes |
| Slack | Yes |
| SignalR (web client) | Yes |
| Headless (`netclaw chat -p`) | No -- auto-deny |
| Reminders | No -- auto-deny |
| Webhooks | No -- auto-deny |

If your reminders, webhooks, or headless sessions need a tool, that tool must be set to `Auto` approval mode or it won't execute.

Interactive channels that don't respond within 5 minutes also auto-deny. The model receives a generic tool-execution error with no indication that approval was the cause.

## Troubleshooting

### Tools blocked for Team/Public even after granting

Check three things in order:

1. Is the server in `AllowedMcpServers` for the audience (or `McpServersMode` set to `"All"`)?
2. Does `McpServerToolGrants` list the tool, or is the server omitted entirely (which passes all tools through)?
3. Is the tool set to `Deny` in `ToolOverrides`? A denied tool is blocked even if granted.

Run `netclaw mcp tools <server> --audience team` to see exactly what's granted.

### `netclaw mcp list` shows `awaiting auth`

The server needs authentication before you can grant tools. Run `netclaw mcp auth <name>` to complete the OAuth or token flow, then retry your grants.

### Approval prompts never appear in automation

Expected behavior. Headless, reminders, and webhooks auto-deny all approval-gated tools. Set those tools to `Auto` for the relevant audience, or accept that they won't run unattended.

### Persistent approvals not working after daemon restart

Check that `~/.netclaw/config/tool-approvals.json` exists and is valid JSON. If it was quarantined (you'll see a `.invalid` file alongside it), the original was corrupt. Inspect the quarantined copy and recreate the approvals you need.

### `netclaw doctor` warns about stale approvals

You have persistent approvals for an audience or server that's been disabled. Clean up `tool-approvals.json` by removing entries for servers or audiences you no longer use.

## Next Steps

- [`netclaw mcp`](/cli/mcp-tools/) -- full TUI keybinding reference and CLI subcommands
- [MCP Servers config](/configuration/mcp-servers/) -- server schema, transports, OAuth setup
- [Security model](/security/security-model/) -- the four-layer invocation stack and audience system
- [Hardening](/security/hardening/) -- production lockdown recommendations including MCP tool policy

## External Resources

- [Model Context Protocol specification](https://spec.modelcontextprotocol.io/) -- the wire protocol behind MCP tool servers
- [MCP server registry](https://github.com/modelcontextprotocol/servers) -- community-maintained list of available MCP servers
- [Notion MCP server](https://github.com/makenotion/notion-mcp-server) -- official Notion MCP server for search, fetch, and page management
