---
title: "CLI Overview"
description: "Netclaw command-line interface reference."
---

The `netclaw` CLI controls your agent — configuration, diagnostics, chat, daemon lifecycle.

```bash
netclaw <command> [options]
```

The **Daemon** column in each table indicates whether the netclaw daemon (the background process that manages sessions, connectors, and model routing) must be running for that command to work.

## Commands

### Chat & Sessions

| Command | Description | Daemon | TUI |
|---------|-------------|--------|-----|
| [`chat`](/cli/chat/) | Interactive terminal UI chat | Required | Yes |
| `chat -p <text>` | Headless single-prompt mode (supports `--resume` / `-r`, `--json`) | Required | No |
| [`sessions`](/cli/sessions/) | Browse and resume recent sessions | Required | Yes |
| `sessions --once` | List sessions without the terminal UI | Required | No |
| `sessions --json` | JSON output (implies `--once`) | Required | No |

### First Run & Diagnostics

| Command | Description | Daemon | TUI |
|---------|-------------|--------|-----|
| [`init`](/cli/init/) | First-run setup wizard (starts the daemon for you) | Not required | Yes |
| [`doctor`](/cli/doctor/) | Config and connectivity diagnostics; `--fix` for auto-repair | Optional | No |
| [`status`](/cli/status/) | Daemon runtime health, connector status, model info | Required | No |
| [`stats`](/cli/stats/) | Token usage, session counts, memory stats; `--tui` for dashboard | Required | No |

### Daemon Management

| Command | Description |
|---------|-------------|
| `daemon start` | Start daemon as a background process |
| `daemon stop` | Stop daemon gracefully |
| `daemon status` | Show daemon process status |
| [`daemon install`](/deployment/systemd/) | Install systemd user service (Linux) |
| [`daemon uninstall`](/deployment/systemd/#uninstalling) | Remove systemd user service (Linux) |
| `daemon pair` | Generate a pairing code (run on the host machine) |
| `daemon devices` | List paired devices |
| `daemon devices revoke <name>` | Revoke a paired device by name |
| `pair <endpoint>` | Pair this device with a remote daemon using a pairing code (run on the remote device) |

`daemon install` writes a `systemd --user` unit, so the daemon runs under your own user account at the same privilege you have at the shell. No root, no dedicated service identity. See [systemd Service](/deployment/systemd/) for the security model and operational walkthrough.

See the [Pairing Remote Devices](/guides/pairing-remote-devices/) guide for the full walkthrough.

### Configuration

| Command | Description | Daemon | TUI |
|---------|-------------|--------|-----|
| [`provider`](/cli/provider/) | Manage LLM providers | No | Yes (bare invocation) |
| [`model`](/cli/model/) | Manage model role assignments | No | Yes (bare invocation) |
| [`mcp`](/cli/mcp-tools/) | Manage [MCP](https://spec.modelcontextprotocol.io/) (Model Context Protocol) server profiles and tool permissions | Optional | Partial |
| [`webhooks`](/cli/webhooks/) | Manage inbound webhook routes | No | No |
| [`secrets`](/cli/secrets/) | Store encrypted secrets via `secrets set <key> <value>`. See [Secrets](/security/secrets/). | No | No |
| [`reminder`](/cli/reminder/) | Manage scheduled reminders | Required | Yes (`ui` or `tui` subcommand) |
| [`skill`](/cli/skill/) | Manage skills and external skill sources. See [Skills](/skills/overview/). | No | No |

See [Configuration](/configuration/managed-providers/) for field references and config file details.

### Housekeeping

| Command | Description |
|---------|-------------|
| `update` | Check for and install CLI updates; `--check` to check only, `--channel <stable\|beta>` to switch release channel |
| `version` / `--version` / `-V` | Print version, commit hash, and build timestamp |

## First Run

```bash
# First-time setup (starts the daemon automatically)
netclaw init

# Check everything is wired up
netclaw doctor

# Verify the daemon is healthy
netclaw status
```

If `status` shows errors, run `netclaw doctor --fix` to auto-repair common issues.

```bash
# Start chatting
netclaw chat
```

Once you're up and running, head to [First Conversation](/getting-started/first-conversation/) for a walkthrough of your first chat session.

![netclaw status output](/screenshots/output/status.png)

`netclaw status` shows the daemon's health, active model, and connector states.

## Config Files

| File | Purpose |
|------|---------|
| `~/.netclaw/config/netclaw.json` | Main configuration |
| `~/.netclaw/config/secrets.json` | Encrypted credentials overlay |
| `NETCLAW_*` env vars | Highest-priority overrides |

See [Configuration](/configuration/managed-providers/) for field references.

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Validation, policy, or runtime failure |
| `2` | Usage or argument error |

## Background Update Check

Non-TUI commands silently check for updates on startup. TUI commands skip this — run `netclaw update --check` to check manually.

## Version Output

```
netclaw 0.22.1 (commit bc2170d, built 2026-06-01T12:38:11Z)
```

## Related

- [Quickstart](/getting-started/quickstart/) — Get netclaw running from scratch
- [Installation](/getting-started/installation/) — Platform-specific install instructions
- [First Conversation](/getting-started/first-conversation/) — Walk through your first chat session
- [systemd deployment](/deployment/systemd/) — Run the daemon as a system service
- [Docker deployment](/deployment/docker/) — Containerized daemon setup
- [.NET CLI tools documentation](https://learn.microsoft.com/en-us/dotnet/core/tools/) — Background on .NET global tools, which is how netclaw is distributed
- [systemd user services](https://wiki.archlinux.org/title/Systemd/User) — Reference for `daemon install` / `daemon uninstall` on Linux
- [Model Context Protocol spec](https://spec.modelcontextprotocol.io/) — MCP specification
