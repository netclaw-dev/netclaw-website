---
title: "Bundling resources with skills"
description: "How skills ship references, scripts and assets as deterministic archives, and how netclaw downloads, extracts and reads them."
---

A skill is more than its `SKILL.md`. Many carry reference docs the agent can read, scripts it can run and assets it needs. A skill server bundles those into one deterministic archive, so netclaw pulls the whole skill in a single verified download instead of fetching files one at a time.

## Two artifact shapes

A skill server projects every published skill into one of two shapes, depending on whether it has supporting files:

| Shape | When | What's served |
|-------|------|---------------|
| `skill-md` | `SKILL.md` only | The single markdown file |
| `archive` | `SKILL.md` plus supporting files | A `.zip` at `/api/v1/skills/{name}/{version}/archive.zip` |

An archive holds `SKILL.md` at its root and the supporting files under their relative paths, the same layout the author used:

```
my-skill/
├── SKILL.md
├── references/
│   └── api-notes.md
├── scripts/
│   └── check.sh        # executable bit preserved
└── assets/
    └── template.json
```

Archives are deterministic. Entries are ordered, timestamps are fixed and Unix permission bits are preserved (masked to standard bits), so an executable script stays executable and the same skill version always produces a byte-identical archive with the same digest.

## What the author does

Nothing special. Lay the skill out as a directory and publish it. The server decides the shape, so a skill with supporting files becomes an archive automatically. See [Skill server](/skills/skill-server/) and the [`skillserver` CLI](/skills/skillserver-cli/) for publishing.

Skills published before archives existed aren't left behind. On startup the server backfills them: it finds versioned skills with resources but no archive, builds the archive from the stored files and records it. The original `SKILL.md` bytes, digest and per-file routes stay exactly as they were, and a version that already has an archive is skipped.

## How netclaw consumes an archive

The server's RFC index lists each skill with its type, URL and digest. When an entry has type `archive`, netclaw takes the bundle instead of individual files:

1. **Download** the `.zip` from the entry's URL.
2. **Verify** its SHA-256 digest against the index entry before touching the contents. A mismatch is rejected and logged, and nothing gets extracted.
3. **Extract** with hardening. Zip-slip path traversal, symlink entries and duplicate names are refused.
4. **Write** the tree under `~/.netclaw/skills/.server-feeds/<feed>/<skill>/`, keeping the subpaths and Unix modes.

Digest verification covers the archive as a whole, and netclaw extracts only after the whole bundle verifies. A partial or corrupted download never lands on disk.

## How the agent reads and runs bundled files

`skill_load` lists a skill's resource files. The agent reads one with `skill_read_resource`, passing the skill name and a path relative to the skill folder:

```text
skill_read_resource → path: /home/netclaw/.netclaw/skills/hello-greeter/references/tone.md
Warm, brief, no emoji.
```

The first line of the result is the file's absolute path, so the agent can run a bundled script by its real path. The tool reads text files only. It refuses `SKILL.md` (use `skill_load`) and any path that crosses a symlink below the skill root.

The skill folders aren't write-protected, and shell commands can name them. A synced `scripts/check.sh` keeps its executable bit, so the agent can run it through the shell tool. Which sessions can do that depends on the [audience](/security/security-model/): of the default audiences, only Personal includes `shell_execute`, and a Team or Public deployment posture takes it away from the local TUI too.

The agent can also write into a feed skill folder, but it doesn't last. The next sync compares every installed file against the recorded hashes and reinstalls the published version.

:::caution
Bundled resources are content and code from wherever the feed points. netclaw verifies the digest, but it doesn't scan the content (skill scanning is off), and a script you sync from a feed is a script you're trusting. Subscribe only to [skill feeds](/skills/skill-feeds/) you control or trust.
:::

## Limitations

- Archives are `.zip` only.
- Bundling is the server's call. There's no switch to turn a skill into an archive.
- Per-file resource routes remain for compatibility. A client that only understands `skill-md` gets the markdown and misses the extras.
- Subagents can't bundle resources. They publish as a single file.

## Related pages

- [Skill feeds](/skills/skill-feeds/): subscribe to the feeds that carry these skills
- [Native manifest](/skills/native-manifest/): the feed that carries subagents
- [Skill server](/skills/skill-server/): publish skills with resources
- [Images, audio and other file types](/guides/multimodal-files/): how the agent reads other files it pulls

## Resources

- [AgentSkills.io](https://agentskills.io): the open skill format these bundles follow
- [Zip Slip](https://security.snyk.io/research/zip-slip-vulnerability): the path-traversal class netclaw hardens extraction against
