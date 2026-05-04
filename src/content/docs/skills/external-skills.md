---
title: "External Skills"
description: "Adding custom skill paths and external sources."
---

External skills let netclaw read skill directories owned by other AI tools — Claude Code, Open Code, or any arbitrary directory on disk. Point netclaw at an existing directory and it scans those skills alongside native ones. No copying required.

## Before You Begin

- Netclaw is installed and `netclaw init` has been run (or you're comfortable editing `netclaw.json` directly)
- The external directory you want to add exists on disk (netclaw logs a warning for missing paths but still configures the source)

## Well-Known Sources

Well-known aliases expand to standard paths:

| Alias | Resolves to |
|-------|-------------|
| `claude-code` | `~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/plugins/marketplaces/*/skills/` |
| `open-code` | `~/.open-code/skills/` |

The `claude-code` alias scans marketplace plugin directories alphabetically for stable precedence. If the primary path (`~/.claude/skills/`) doesn't exist, the source still resolves from the remaining paths.

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
        "AllowSymlinks": false
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
| `AllowSymlinks` | bool | `false` | Follow symlinks within the directory |

Each source must set either `Path` or `WellKnown`, not both.

## Managing Sources via CLI

Skip the JSON editing:

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

All skill commands are offline — no daemon required.

## Auto-Detection During Init

The [`netclaw init`](/cli/init/) wizard detects Claude Code and Open Code installations automatically:

![External skills configuration during init](/screenshots/output/init-07-external-skills.png)

Detected sources get enabled by default. Next, the wizard prompts for custom paths:

![Custom skills path input](/screenshots/output/init-07-custom-skills-path.png)

A symlink toggle follows. Leave it off unless your setup requires it (shared filesystems, monorepo layouts with linked skill directories).

## Precedence

When multiple sources define a skill with the same name:

```
native  >  server feeds  >  external
```

Within external sources, order in the `Sources` list determines which wins. Move higher-priority sources earlier in the array. Collisions are logged — run `netclaw skill issues` to see them.

## Runtime Behavior

The daemon puts a [FileSystemWatcher](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher) on every resolved external path. When a `*.md` file changes, the daemon rescans after a 500ms debounce. Drop a new skill file into an external directory and it's available on the next agent turn — no restart.

Missing directories log a warning at startup but don't block the daemon.

## Security

Symlinks are blocked by default because external directories often live outside your control (marketplace plugins, shared mounts). Opt in per source with `AllowSymlinks: true` if you trust the targets.

External skills go through the same content scanner as native skills:

| Verdict | What happens |
|---------|-------------|
| **Allowed** | Skill loads normally |
| **Warning** | Skill loads, event is logged |
| **Rejected** | Skill is blocked — check `netclaw skill issues` |

External skills are subject to the same [tool access policies](/architecture/security-model/) as native ones. The `allowed-tools` frontmatter field is informational only — it doesn't grant tool access.

## Validating External Skills

Catch frontmatter problems before they bite you:

```bash
# Validate a single skill
netclaw skill validate /opt/skills/shared/deploy/SKILL.md

# See all scanning/validation issues across all sources
netclaw skill issues
```

## Troubleshooting

### Source shows 0 skills after adding

The path probably doesn't contain valid `*.md` files with [SKILL.md frontmatter](/skills/overview/). Run `netclaw skill validate <path>` on a file to see what's wrong. Usual culprits: missing `name` or `description` in frontmatter, or the directory has subdirectories but no top-level markdown files.

### "Symlink blocked" warnings in logs

The source has `AllowSymlinks: false` (the default) and the directory contains symlinks. Either restructure the directory or set `AllowSymlinks: true` if you trust where the links point.

### Skills not updating after file changes

Filesystem events are debounced by 500ms, so rapid-fire writes resolve to whatever the final state is. If changes still aren't showing up, check that the daemon is running (`netclaw status`) and the source is enabled (`netclaw skill source list`).

## What to Read Next

- [Skills Overview](/skills/overview/) — skill format, source types, and the full lifecycle
- [Skill Feeds](/skills/skill-feeds/) — server-synced skill repositories
- [`netclaw skill`](/cli/skill/) — full CLI reference for skill management

## Resources

- [AgentSkills.io](https://agentskills.io) — the SKILL.md format specification
- [FileSystemWatcher docs](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher) — how .NET file watching works under the hood
