---
title: "External skills"
description: "Read skills from Claude Code, Open Code or any directory on disk without copying them."
---

External skills let netclaw read skill directories owned by other AI tools: Claude Code, Open Code, or any directory on disk. Point netclaw at an existing directory and it scans those skills alongside its own. No copying required.

External skills use the [SKILL.md format](https://agentskills.io) with `description` in the frontmatter and a markdown body. See [Skills overview](/skills/overview/) for the format and where external skills rank.

## Add a source

To add Claude Code's skills:

```bash
netclaw skill source add claude-code --well-known claude-code
```

For any other directory, use `--path`:

```bash
netclaw skill source add team-skills --path /opt/skills/shared
```

Adding a source changes `netclaw.json`, so the daemon restarts itself in-process and picks up the new directory. You can also run `netclaw config`, open **Skill Sources** and choose **+ Add local folder** to browse for one.

The directory has to exist. `skill source add --path` refuses a missing one with `[FAIL] directory not found`.

## Well-known sources

An alias expands to a standard set of paths:

| Alias | Reads |
|-------|-------|
| `claude-code` | `~/.claude/skills/`, `~/.claude/commands/`, and `~/.claude/plugins/marketplaces/*/skills/` for each marketplace folder that exists |
| `open-code` | `~/.open-code/skills/` |

The `claude-code` alias reads marketplace folders in alphabetical order, so precedence stays stable. It works out the list of marketplace folders when the daemon starts. Install a new marketplace and you need to restart the daemon (any config change does it) before netclaw sees it. New skill files inside a folder netclaw already watches show up live.

The alias reads skills only. It doesn't read Claude Code plugin commands, agents, hooks or MCP servers, and it skips `~/.claude/plugins/cache/`. Flat `.md` files in `~/.claude/commands/` count as skills even without frontmatter. netclaw takes the name from the file name and the description from the first line.

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
        "AllowSymlinks": false
      }
    ]
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Name` | string | - | Unique identifier for the source |
| `Path` | string | none | Absolute path to a skill directory. Set this or `WellKnown`, not both. |
| `WellKnown` | string | none | Well-known alias. Set this or `Path`, not both. |
| `Enabled` | bool | `true` | Whether the source is active |
| `AllowSymlinks` | bool | `false` | Follow symlinks inside the directory. `skill source add --well-known` sets it to `true`. |

## Manage sources from the CLI

```bash
netclaw skill source list                    # show configured sources
netclaw skill source disable team-skills     # keep it in config, stop scanning
netclaw skill source enable team-skills
netclaw skill source remove team-skills      # config entry only, files stay
```

These commands edit `netclaw.json` and don't need the daemon. A running daemon restarts itself when the file changes. Skill servers aren't managed here. See [Skill feeds](/skills/skill-feeds/).

![The Skill Sources screen with one local folder, Claude Code at /home/netclaw/.claude/skills showing 1 skill, one remote skill server, Corp Skills, and the Add local folder, Add skill server, Rescan all and Done rows](/screenshots/output/config-skills.png)

The Claude Code folder is the well-known source added with `netclaw skill source add`. In the Skill Sources screen, **+ Add local folder** opens a directory picker (Ctrl+N makes a new folder) and **+ Add skill server** connects a remote feed.

## Precedence

```
system  >  native  >  server feeds  >  external
```

External sources always rank last. Within them, the order of the `Sources` array decides, so put the one you want to win first. A shadowed skill shows up as a `DuplicateName` issue in `netclaw skill issues`.

## Live changes

The daemon watches every external path. When a `*.md` file changes, it rescans after a 500 ms pause, so several quick writes cause one rescan. A new skill file in an external directory is available to new sessions without a restart. A path that doesn't exist at startup is logged and skipped.

## Security

netclaw doesn't scan external skills for prompt injection. Skill scanning is off for every tier, so point netclaw only at directories you trust.

- Symlinks are blocked unless the source sets `AllowSymlinks: true`. Well-known aliases get it automatically because their standard paths often include symlinks. A custom path defaults to `false`.
- `allowed-tools` is informational and grants nothing. Tool access follows the [security model](/security/security-model/).
- Frontmatter has to parse and include a `description`. A skill without one is rejected with `MissingDescription`.

## Validate a skill

```bash
netclaw skill validate /opt/skills/shared/deploy/SKILL.md
netclaw skill issues
```

`validate` applies the native rules: the frontmatter `name` must match the directory name, and symlinks aren't followed. A skill that the daemon loads happily from an external source can still fail `validate` for either reason. `netclaw skill issues` scans the native and external sources and lists everything it rejected or shadowed.

## Troubleshooting

### A source shows 0 skills

- **Symptom:** `netclaw skill list` shows nothing from the source.
- **Cause:** The directory holds no `SKILL.md` directories or `.md` files with a `description`, or the source is disabled.
- **Fix:** Run `netclaw skill source list`, then `netclaw skill issues`. Missing `description` is the usual cause.

### Symlink blocked

- **Symptom:** `netclaw skill issues` or the daemon log reports a blocked symlink.
- **Cause:** The source has `AllowSymlinks: false` and the directory contains links.
- **Fix:** Restructure the directory, or set `AllowSymlinks: true` if you trust where the links point.

### Edits don't show up

- **Symptom:** You changed a skill, but the agent still sees the old one.
- **Cause:** The daemon isn't running, the source is disabled, or the session started before the change.
- **Fix:** Check `netclaw status` and `netclaw skill source list`, then start a new session.

## Related pages

- [Skills overview](/skills/overview/): format, tiers and precedence
- [Skill feeds](/skills/skill-feeds/): skills from a skill server
- [`netclaw skill`](/cli/skill/): the full command reference
- [Slash commands](/reference/slash-commands/): run any skill with `/name`

## Resources

- [AgentSkills.io](https://agentskills.io): the `SKILL.md` format specification
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code): Claude Code setup and its skill and plugin folders
- [FileSystemWatcher](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher): the .NET file watcher netclaw uses
