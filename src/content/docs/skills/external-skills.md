---
title: "External Skills"
description: "Adding custom skill paths and external sources."
---

External skills let netclaw read skill directories owned by other AI tools — Claude Code, Open Code, or any arbitrary directory on disk. Point netclaw at an existing directory and it scans those skills alongside its own. No copying required.

Skills must follow the [SKILL.md format](https://agentskills.io) (frontmatter with `name` and `description` fields, markdown body). See [Skills Overview](/skills/overview/) for details on the format and lifecycle.

## Quick Start

Already have Claude Code installed? The [`netclaw init`](/cli/init/) wizard detects it and configures the source automatically. To add it manually:

```bash
netclaw skill source add claude-code --well-known claude-code
```

That's it. The daemon picks up the change via its file watcher — no restart needed.

## Before You Begin

- Netclaw is installed and `netclaw init` has been run (or you're comfortable editing `netclaw.json` directly — it lives at `~/.netclaw/config/netclaw.json` by default)
- The external directory you want to add exists on disk (netclaw logs a warning for missing paths but still configures the source)

## Well-Known Sources

Well-known aliases expand to standard paths:

| Alias | Resolves to |
|-------|-------------|
| `claude-code` | `~/.claude/skills/`, `~/.claude/commands/`, plus marketplace paths discovered dynamically (`~/.claude/plugins/marketplaces/*/skills/`) |
| `open-code` | `~/.open-code/skills/` |

The `claude-code` alias scans marketplace plugin directories alphabetically for stable precedence. Marketplace paths are discovered at runtime — if you install a new plugin, it gets picked up on the next scan. Missing one of those paths is fine — the alias resolves whichever ones exist.

## Configuration

External sources live under `ExternalSkills.Sources` in `netclaw.json`:

```json
{
  "ExternalSkills": {
    "Sources": [
      {
        "Name": "claude-code",
        "WellKnown": "claude-code",
        "Enabled": true,
        "AllowSymlinks": true
      },
      {
        "Name": "team-skills",
        "Path": "/opt/skills/shared",
        "Enabled": true,
        "AllowSymlinks": true
      }
    ]
  }
}
```

### Source fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Name` | string | — | Unique identifier for this source |
| `Path` | string | null | Absolute path to a skill directory (mutually exclusive with `WellKnown`) |
| `WellKnown` | string | null | Well-known alias (mutually exclusive with `Path`) |
| `Enabled` | bool | `true` | Whether the source is active |
| `AllowSymlinks` | bool | `false` | Follow symlinks within the directory. Well-known sources like `claude-code` default to `true` when added via CLI or init wizard. |

Each source must set either `Path` or `WellKnown`, not both.

## Managing Sources via CLI

Add and remove sources without editing `netclaw.json`:

```bash
# List configured sources
netclaw skill source list

# Add a well-known source
netclaw skill source add claude-code --well-known claude-code

# Add a custom path
netclaw skill source add team-skills --path /opt/skills/shared

# Disable a source without removing it
netclaw skill source disable team-skills

# Re-enable
netclaw skill source enable team-skills

# Remove entirely
netclaw skill source remove team-skills
```

All `netclaw skill source` commands work without the daemon running. CLI changes are picked up by a running daemon automatically via its file watcher.

## Auto-Detection During Init

The [`netclaw init`](/cli/init/) wizard detects Claude Code and Open Code installations automatically:

![External skills configuration during init](/screenshots/output/init-07-external-skills.png)

Detected sources get enabled by default. Next, the wizard prompts for custom paths:

![Custom skills path input](/screenshots/output/init-07-custom-skills-path.png)

A symlink toggle follows. Leave it off unless your setup requires it (shared filesystems, monorepo layouts with linked skill directories).

## Precedence

When multiple sources define a skill with the same name:

```
native skills  >  server feeds  >  external sources
```

[Native skills](/skills/overview/) are skills authored directly through netclaw's agent. [Server feeds](/skills/skill-feeds/) are remotely-synced skill repositories. External sources always have lowest priority.

Within external sources, order in the `Sources` array determines which wins — higher-priority sources go first. Collisions are logged; run `netclaw skill issues` to see them.

## Runtime Behavior

The daemon watches every resolved external path for changes. When a `*.md` file changes, it rescans after a 500ms debounce — so multiple rapid writes only trigger one rescan. Drop a new skill file into an external directory and it's available on the next agent turn. No restart needed.

The daemon logs a warning for missing directories at startup but keeps running.

## Security

Well-known sources (like `claude-code`) have `AllowSymlinks: true` set automatically because their standard paths include symlinked marketplace plugins. Custom sources default to `AllowSymlinks: false` — opt in per source if you trust the targets.

External skills loaded from disk go through:

- **Frontmatter validation** — `name` and `description` are required; malformed YAML is rejected
- **Symlink/path safety** — blocked unless `AllowSymlinks: true` for that source
- **[Tool access policies](/security/security-model/)** — same restrictions as native skills; the `allowed-tools` frontmatter field is informational only and doesn't grant tool access

External skills do NOT go through the prompt injection content scanner (that only runs on skills authored through the `skill_manage` tool). The assumption is that external skill files are user-curated.

## Validating External Skills

Validate skills before loading them:

```bash
# Validate a single skill
netclaw skill validate /opt/skills/shared/deploy/SKILL.md

# See all scanning/validation issues across all sources
netclaw skill issues
```

## Troubleshooting

### Source shows 0 skills after adding

The path doesn't contain valid `*.md` files with [SKILL.md frontmatter](https://agentskills.io). Run `netclaw skill validate <path>` on a file to see what's wrong. Common causes: missing `name` or `description` in frontmatter, or the directory has subdirectories but no top-level markdown files.

### "Symlink blocked" warnings in logs

The source has `AllowSymlinks: false` and the directory contains symlinks. Either restructure the directory or set `AllowSymlinks: true` if you trust where the links point.

### Skills not updating after file changes

Filesystem events are debounced by 500ms. If changes still aren't showing up, check that the daemon is running (`netclaw status`) and the source is enabled (`netclaw skill source list`).

## What to Read Next

- [Skills Overview](/skills/overview/) — skill format, source types, and the full lifecycle
- [Skill Feeds](/skills/skill-feeds/) — server-synced skill repositories
- [`netclaw skill`](/cli/skill/) — full CLI reference for skill management

## Resources

- [AgentSkills.io](https://agentskills.io) — the SKILL.md format specification
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) — Claude Code setup and commands reference
- [FileSystemWatcher docs](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher) — the .NET file watching API netclaw uses
