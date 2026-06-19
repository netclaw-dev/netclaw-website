---
title: "Skills Overview"
description: "What skills are and how Netclaw uses them."
---

Skills are markdown files that teach the agent *how to do things*. Rather than hard-coding every behavior into the daemon, you write procedural knowledge as plain text and the agent loads it on demand.

Think of them as cheat sheets. A `commit` skill encodes your team's commit conventions; a `review-pr` skill walks through your code review checklist. The agent sees a one-line-per-skill index on every turn (just names and descriptions), then reads the full content only when it needs it. A large skill library costs almost nothing in context.

All skills follow the [AgentSkills.io](https://agentskills.io) format: a `SKILL.md` file with YAML frontmatter. The format is shared across multiple agent platforms, so skills you write for netclaw can work in Claude Code too.

## How skills reach the agent

The lifecycle has four phases:

1. **Sync** — at startup, the daemon pulls system skills from a CDN and (optionally) syncs skills from private [skill servers](/skills/skill-server/). These land in read-only directories under `~/.netclaw/skills/`.

2. **Scan** — the daemon walks all skill directories (native, server feeds, external), validates frontmatter, and merges results. Native skills take precedence over server feeds, which take precedence over external sources. Netclaw logs name collisions from lower-precedence sources as issues and skips the duplicates. Run `netclaw skill issues` to see them.

3. **Index** — the daemon compresses the merged list into a one-line-per-skill summary and injects it into the agent's system prompt. The agent sees skill names and descriptions but not the full instructions.

4. **Load** — when the agent needs a skill, it calls the `skill_load` built-in tool to read the full `SKILL.md` body and get a listing of resource files (scripts, references, assets). Users can also invoke skills directly via `/skill-name` slash commands.

Changes to skill files trigger a rescan automatically. A file watcher monitors native and external source directories with a 500ms debounce, so edits take effect without a restart. Server feed directories are not watched — they update on the configured sync interval.

## Skill file format

Two layouts work:

**Directory-based** — for skills with supporting resources:

```
commit/
  SKILL.md          # Required — instructions + frontmatter
  scripts/          # Optional — helper scripts
  references/       # Optional — reference material
  assets/           # Optional — images, templates
```

**Flat file** — for self-contained skills:

```
commit.md
```

The file name (or directory name) must match the `name` field in the frontmatter for native skills. External sources are more relaxed — the frontmatter `name` is treated as canonical.

```yaml
---
name: commit
description: Create well-structured git commits with conventional commit messages.
metadata:
  version: 1.0.0
license: MIT
allowed-tools: "bash git"
---

# Commit Changes

Instructions for the agent go here...
```

### Frontmatter fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Lowercase identifier (must match directory/file name for native skills) |
| `description` | Yes | One-line summary (max 1024 chars per the [AgentSkills.io](https://agentskills.io) spec) |
| `metadata.version` | No | [Semver](https://semver.org) version string |
| `license` | No | [SPDX license identifier](https://spdx.org/licenses/) |
| `compatibility` | No | Which agent platforms can use this skill |
| `allowed-tools` | No | Space-delimited list of tools the skill needs (informational — does not grant access) |
| `disable-model-invocation` | No | When `true`, excluded from the LLM index (still invocable via `/name`) |
| `invocable` | No | Default `true`; when `false`, hidden from slash commands |
| `argument-hint` | No | Hint text shown after the slash command in completions |
| `metadata.subagent` | No | Routes execution to a named subagent instead of returning skill content |

The display name shown in `netclaw skill list` comes from the first `#` heading in the markdown body, falling back to title-casing the skill name.

## Quick setup

To add an external skill directory or connect a skill server, run [`netclaw config`](/cli/config/) → Skill Sources. The TUI opens an interactive picker — no manual JSON editing required.

```bash
netclaw config
```

Select **Skill Sources** to add a local folder (e.g., `~/.claude/skills/`) or subscribe to a private [skill server](/skills/skill-server/). Changes take effect on the next scan without a restart.

![Skill Sources editor](/screenshots/output/config-skills.png)

Manual configuration (e.g., for scripted or Docker installs) is covered in [External Skills](/skills/external-skills/) and [Skill Feeds](/skills/skill-feeds/).

## Where skills come from

Four source types, each with different trust and management:

| Source | Location | Managed by | Mutable? |
|--------|----------|-----------|----------|
| **system** | `~/.netclaw/skills/.system/` | Daemon (CDN sync) | No |
| **native** | `~/.netclaw/skills/` | You | Yes |
| **server feeds** | `~/.netclaw/skills/.server-feeds/` | Private [skill servers](/skills/skill-server/) | No |
| **external** | Configured directories | Source tool (Claude Code, etc.) | At source |

Drop a `SKILL.md` into `~/.netclaw/skills/` and it appears on the next scan — that's a native skill. Create, edit, and remove them with [`netclaw skill`](/cli/skill/). Run `netclaw skill validate` to check a skill's frontmatter before using it.

System skills ship from a CDN feed and are read-only. Built-in skills like `netclaw-memory` and `netclaw-operations` land here on first run. For a fully offline setup, set `SkillSync.DisableSystemSkillSync: true` in your `netclaw.json` (see [Configuration](/configuration/models/) for file location).

<!-- TODO: needs user input — What is the full list of built-in system skills that ship from CDN? -->

External skills let netclaw read skill directories from other AI tools. Add a local folder via `netclaw config` → Skill Sources or wire up a well-known alias via the CLI.

Well-known aliases expand to standard paths:

| Alias | Scans |
|-------|-------|
| `claude-code` | `~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/plugins/marketplaces/*/skills/` |
| `open-code` | `~/.open-code/skills/` |

Server feed skills sync from private [skill servers](/skills/skill-server/) that implement the [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc). These are self-hosted registries that distribute skills across your organization. Configure them in `netclaw config` → Skill Sources or add them later via `netclaw skill source add`. See the [netclaw skill-server](https://github.com/netclaw-dev/skill-server) reference implementation for setting up your own.

## Precedence

When multiple sources define a skill with the same name, the highest-precedence source wins:

```
native  >  server feeds  >  external
```

A native skill named `commit` shadows any `commit` from a server feed or external source. You can always override shared skills with your own version.

## Security

Skills are just text, but text that lands in an agent's instructions can carry prompt injection. Netclaw runs a content scanner on both write operations (create, edit, sync) and at load time (every `skill_load` call scans before returning content):

| Verdict | Risk | Action |
|---------|------|--------|
| **Allowed** | None or low risk detected | Skill proceeds normally |
| **Warning** | Medium | Skill loads, but the event is logged |
| **Rejected** | High (prompt injection detected) | Skill is blocked; `netclaw skill issues` surfaces the rejection |

Additional guardrails:

- Symlinks are blocked by default in native and system directories. External sources can opt in via `AllowSymlinks: true` in config.
- Sessions with a [public trust audience](/security/security-model/) cannot load skills. `skill_load` also returns an error when `SkillSync.Enabled` is `false`.
- Skills run through the same [tool access policies](/security/security-model/) as everything else. The `allowed-tools` frontmatter field is informational — actual tool grants are controlled by the security policy.

## Subagent routing

Instead of returning instructions, a skill can hand off to a subagent. Add `metadata.subagent` to the frontmatter:

```yaml
---
name: research
description: Deep research on a topic using multiple sources.
metadata:
  subagent: research-assistant
---
```

When `skill_load` hits this skill, it spawns the named subagent with the skill's body as a system prompt overlay. The caller passes a `task` parameter to the spawned subagent. The target subagent must be registered and user-facing — internal-only subagents cannot be routed to.

## Configuration

Run `netclaw config` to manage skill sources interactively. Two keys in `netclaw.json` also control skill loading directly:

| Key | Default | Description |
|-----|---------|-------------|
| `SkillSync.Enabled` | `true` | Blocks the agent from loading skills via `skill_load` when `false` |
| `SkillSync.DisableSystemSkillSync` | `false` | Skip CDN sync for system skills |

External sources and skill feeds have their own config sections. See [External Skills](/skills/external-skills/) and [Skill Feeds](/skills/skill-feeds/) for details.

## Tracking skill usage

Run [`netclaw stats skills`](/cli/stats/) to see which skills the agent loads most often. Good for spotting which skills pull their weight and which to cut.

## Limitations

- No built-in skill marketplace or discovery beyond what your configured sources provide.
- Skill content scanning uses regex-based heuristics. It catches common prompt injection patterns but is not a comprehensive security boundary.
- The `allowed-tools` frontmatter field is informational. It does not grant tool access — that is controlled entirely by the [security policy](/security/security-model/).
- Skills are text-only. They cannot register tools, modify daemon behavior, or execute code directly.
- No versioning or rollback for native skills. If you overwrite a skill, the old version is gone.

## What to read next

- [`netclaw skill`](/cli/skill/) — CLI reference for managing skills (list, show, validate, search, source management)
- [External Skills](/skills/external-skills/) — configuring external skill directories
- [Skill Feeds](/skills/skill-feeds/) — subscribing to server-synced skill repositories
- [Skill Server](/skills/skill-server/) — running a private skill registry for your org

## Resources

- [AgentSkills.io](https://agentskills.io) — the SKILL.md format specification
- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc) — the protocol behind skill feeds and server-based distribution
- [netclaw skill-server](https://github.com/netclaw-dev/skill-server) — reference implementation of a self-hosted skill registry
