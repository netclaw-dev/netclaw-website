---
title: "netclaw skill"
description: "List, sync, inspect and validate skills, and manage external skill sources."
---

`netclaw skill` shows what skills the agent has loaded, pulls updates from skill servers, checks a skill file before you rely on it, and manages the external directories netclaw reads. `list` and `sync` talk to the running daemon. Every other subcommand reads and writes files and works without it.

For what skills are and how netclaw uses them, see [Skills overview](/skills/overview/).

## Usage

```bash
netclaw skill [subcommand] [options]
```

With no subcommand, `netclaw skill` runs `list`.

## Subcommands

| Subcommand | Needs daemon | Description |
|------------|:------------:|-------------|
| `list` | Yes | List every skill the daemon has loaded (default) |
| `sync` | Yes | Run a skill server sync pass now |
| `show <name>` | No | Show one skill's details and full content |
| `validate <path>` | No | Check a `SKILL.md` or flat `.md` file |
| `remove <name>` | No | Delete a native skill |
| `issues` | No | Show skills with structural problems or shadowed by a higher tier |
| `search <query>` | No | Find skills by name, display name or description |
| `source list` | No | List external skill sources |
| `source add <name> --path <dir>` | No | Add a directory as a source |
| `source add <name> --well-known <alias>` | No | Add a well-known source (`claude-code` or `open-code`) |
| `source remove <name>` | No | Remove a source from config |
| `source enable <name>` | No | Enable a source |
| `source disable <name>` | No | Disable a source without removing it |

The offline subcommands scan the native directory (`~/.netclaw/skills/`) and your external sources. They don't see skills synced from a skill server or MCP prompt skills, so use `list` to see everything.

## Skill classifications

The `SOURCE` column in `list` and `search` takes one of these values:

| Source | Where it comes from | Mutable |
|--------|---------------------|---------|
| `system` | `~/.netclaw/skills/.system/`, restored from the daemon binary on every start | No |
| `native` | `~/.netclaw/skills/`, including skills synced from a skill server | Yes for your own skills |
| `external` | A directory configured with `skill source` | At the source |
| `mcp` | A prompt from a connected [MCP server](/configuration/mcp-servers/), `list` only | No |

Skills synced from a [skill server](/skills/skill-feeds/) live in `~/.netclaw/skills/.server-feeds/<feed>/`, so `list` labels them `native`. They aren't yours to edit. `skill_manage` refuses them, and the next sync restores any file you change. `skill source` doesn't manage them either. Add servers in `netclaw config` or `SkillFeeds` in `netclaw.json`. See [Skill feeds](/skills/skill-feeds/#add-a-feed).

## Examples

### List loaded skills

```bash
netclaw skill list
```

```text
NAME                                      SOURCE      VERSION     STATUS
------------------------------------------------------------------------
flat-note                                 native      -           ok
hello-greeter                             native      1.0.0       ok
incident-summary                          native      1.1.0       ok
k8s-log-triage                            native      0.2.0       ok
agent-coordination                        system      1.5.3       ok
netclaw-memory                            system      1.14.3      ok
netclaw-operations                        system      2.144.0     ok
netclaw-projects                          system      1.4.0       ok
run-reminder                              system      1.0.2       ok
search-citation                           system      1.1.4       ok
skill-authoring                           system      1.12.0      ok
subagent-authoring                        system      1.6.2       ok
web-content-retrieval                     system      1.0.0       ok

13 skill(s)
```

![netclaw skill list output with a table of 13 skills, four native and nine system, all with status ok](/screenshots/output/skill-list.png)

The four native rows are two local skills and two from a skill-server feed, and the nine system skills ship with netclaw. MCP prompt skills join the same table when a server provides them.

`list` reads the daemon's live registry, which is the only view that includes MCP prompt skills. It lists accepted skills only, so `STATUS` is always `ok`. Use `netclaw skill issues` for rejected ones. If the daemon isn't reachable, `list` prints `Daemon unavailable: ...` and exits 1. There's no fallback to a disk scan. Start it with `netclaw daemon start`, or `docker restart <container>` in Docker.

### Sync feeds now

```bash
netclaw skill sync
```

```text
Waiting for the daemon's skill sync pass. Press Ctrl+C to stop this wait.
Skill sync pass a304191e2ce04fc28782ad22f8385c2d
corp-skills: ok changed=0 unchanged=2 rejected=0 failed=0 sidecar=complete
Inventory: ok accepted=13 rejected=0
```

![netclaw skill sync output reporting one feed, corp-skills, with two unchanged skills, and an inventory of 13 accepted](/screenshots/output/skill-sync.png)

The feed line counts what changed on this pass, and the inventory line is the daemon's total after the refresh.

`sync` starts a pass for every enabled [skill feed](/skills/skill-feeds/) right away instead of waiting for `SkillFeeds.SyncIntervalMinutes`. If a pass is already running, it waits for that one. It takes no flags and saves no config. Ctrl+C stops the wait, not the pass.

It exits 1 when a feed reports `failed` or `rejected` above zero, when the inventory refresh fails, or when the daemon is unreachable. Each feed's `sidecar=` value (`complete`, `absent`, `failed`, `not-run`) reports the subagent pass. See [Skill feeds](/skills/skill-feeds/#when-syncs-run) for what each means.

### Show a skill

```bash
netclaw skill show hello-greeter
```

```text
Name:        hello-greeter
Display:     Hello Greeter
Source:      native
Version:     1.0.0
Category:    -
License:     -
Path:        /home/netclaw/.netclaw/skills/hello-greeter/SKILL.md
Flat file:   False
Resources:   references/tone.md, scripts/stamp.sh
Description: Greet the user by name and mention today's weekday.

--- content ---
(full SKILL.md follows)
```

`Resources:` appears when the skill has supporting files. `show` finds skills by name in the native and external directories, so a feed skill answers `[FAIL] skill 'name' not found`.

### Validate a skill file

```bash
netclaw skill validate ./my-skill/SKILL.md
```

```text
[OK] Valid skill file.
  Name:        my-skill
  Description: Does something useful.
  Version:     1.0.0
  License:     -
```

A bad file says what's wrong and exits 1:

```text
[FAIL] MissingDescription: Skill frontmatter must include a non-empty description.
```

`validate` applies the native rules: the frontmatter `name` must match the directory (or file) name, and symlinks aren't followed. A skill that loads fine from an external source can still fail here for either reason.

Once a skill validates, put it in `~/.netclaw/skills/` as `name/SKILL.md` or `name.md`. The daemon rescans when files change, so `list` shows it without a restart.

### Check for problems

```bash
netclaw skill issues
```

```text
NAME                      KIND                            MESSAGE
------------------------------------------------------------------
broken-skill              MissingDescription              Skill frontmatter must include a non-empty description.

1 issue(s)
```

`issues` is an offline structural scan of the native and external directories. It reports bad frontmatter, name mismatches, symlinks and skills shadowed by a higher tier. A copy shadowed by a system skill shows as `DuplicateName`. It doesn't report skill server rejections. Those go to the daemon log and the counts in `skill sync`.

### Search skills

```bash
netclaw skill search greeter
```

```text
NAME                      SOURCE      VERSION     DESCRIPTION
----------------------------------------------------------
hello-greeter             native      1.0.0       Greet the user by name and mention today's weekday.

1 match(es)
```

### Remove a skill

```bash
netclaw skill remove my-old-skill
```

`remove` deletes native skills only. A system skill fails with `cannot remove system skill`, and an external skill fails with `cannot remove external skill`. Delete the files at the source. Removal is permanent, because native skills have no history.

## Manage external sources

`skill source` manages local directories. It edits `netclaw.json`, and the running daemon restarts itself to pick up the change. See [External skills](/skills/external-skills/) for the config shape and the plugin scope of the `claude-code` alias.

```bash
netclaw skill source list
netclaw skill source add my-claude --well-known claude-code
netclaw skill source add team-skills --path /opt/company/skills
netclaw skill source disable team-skills
netclaw skill source enable team-skills
netclaw skill source remove team-skills
```

| Alias | Reads |
|-------|-------|
| `claude-code` | `~/.claude/skills/`, `~/.claude/commands/`, and `~/.claude/plugins/marketplaces/*/skills/` |
| `open-code` | `~/.open-code/skills/` |

`--path` fails with `[FAIL] directory not found` if the directory doesn't exist. Names have to be unique. `--well-known` sources get `AllowSymlinks: true`, and `--path` sources don't. `remove` deletes the config entry and leaves your skill files alone. With no sources configured, `source list` prints any well-known directories it finds on disk and the command to add them.

With no action, `netclaw skill source` lists your sources. An unknown action prints the usage text.

## Frontmatter

The `SKILL.md` format, including the `invocable` key and its default, is in [Skills overview](/skills/overview/#what-a-skill-looks-like). Unknown keys are ignored without a warning. A skill with `user-invocable: false` stays a `/` command, because the key is `invocable`.

## Related pages

- [Skills overview](/skills/overview/): tiers, precedence, formats and trust
- [Skill feeds](/skills/skill-feeds/): configure skill servers and read the sync output
- [External skills](/skills/external-skills/): local directories and the Claude Code alias
- [`netclaw config`](/cli/config/): the Skill Sources screen
- [`netclaw stats`](/cli/stats/): `stats skills` shows which skills the agent loads

## Resources

- [AgentSkills.io](https://agentskills.io): the `SKILL.md` format specification
- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc): the discovery protocol behind skill feeds
- [netclaw skill-server](https://github.com/netclaw-dev/skill-server): the self-hosted skill registry
