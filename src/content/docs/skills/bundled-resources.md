---
title: "Bundling Resources with Skills"
description: "How skills ship supporting files — references, scripts, assets — as deterministic archives, and how netclaw downloads and extracts them."
---

A skill is more than its `SKILL.md`. Many carry supporting files: reference docs the agent can read, scripts it can run, assets it needs. A skill server bundles those into a single deterministic archive so netclaw can pull the whole skill in one verified download instead of fetching files one at a time.

## Two artifact shapes

A skill server projects every published skill into one of two shapes, based on whether it has supporting files:

| Shape | When | What's served |
|-------|------|---------------|
| `skill-md` | `SKILL.md` only | the single markdown file |
| `archive` | `SKILL.md` + supporting files | a `.zip` at `/api/v1/skills/{name}/{version}/archive.zip` |

An archive holds `SKILL.md` at its root and the supporting files under their relative paths — the same layout the skill author used:

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

Archives are **deterministic**: entries are ordered, timestamps are fixed, and Unix permission bits are preserved (masked to standard bits), so an executable script stays executable after extraction and the same skill version always produces a byte-identical archive with the same digest.

## What the author does

Nothing special. Lay the skill out as a directory — `SKILL.md` plus optional `references/`, `scripts/`, and `assets/` — and publish it. The server decides the shape: a skill with supporting files becomes an archive automatically. See [Skill Server](/skills/skill-server/) for publishing.

Skills published before archives existed aren't left behind. The server **backfills** them on startup — it scans versioned skills that have resources but no archive, builds the deterministic archive from the stored files, and records it. The backfill is additive and idempotent: the original `SKILL.md` bytes, digest, and per-file routes stay exactly as they were, so nothing you already depend on changes, and a version that already has an archive is skipped.

## How netclaw consumes an archive

When a synced feed offers a skill as an archive, netclaw takes the bundle instead of individual files:

1. **Download** the `.zip` from the archive URL.
2. **Verify** its SHA-256 digest against the manifest before touching the contents. A mismatch is rejected and logged — nothing gets extracted.
3. **Extract** with hardening: zip-slip path traversal, symlink entries, and duplicate names are all refused, and each file is content-scanned for prompt-injection the same way a single `SKILL.md` is.
4. **Write** the tree under `~/.netclaw/skills/.server-feeds/<feed>/<skill>/`, preserving the `references/` and `scripts/` subpaths and the Unix modes.

The agent reads bundled files through the `skill_read_resource` tool, by logical name — it doesn't need to know the on-disk path. And because executable bits survive the round trip, a synced `scripts/check.sh` can be run through the shell tool.

:::caution
Bundled resources are code and content from wherever the feed points. They ride the same trust boundary as any synced skill: digest-verified on the way in, content-scanned, and extracted under hardening — but a script you sync from a feed is a script you're trusting. Only subscribe to [skill feeds](/skills/skill-feeds/) you control or trust, and remember that a `Personal`-audience session is the only one that can run a synced script through the shell.
:::

## Limitations

- Archives are `.zip` only.
- Bundling is the server's call, driven by whether a skill has supporting files — there's no separate "make this an archive" switch.
- Per-file resource routes remain for compatibility, but archives are how netclaw pulls a resourceful skill; a client that only understands `skill-md` still gets the markdown and misses the extras.
- Digest verification covers the archive as a whole. Netclaw extracts only after the whole bundle verifies, so a partial or corrupted download never lands on disk.

## Related pages

- [Native Manifest & Sync](/skills/native-manifest/) — how the archive URL and digest reach netclaw
- [Skill Feeds](/skills/skill-feeds/) — subscribing to the feeds that carry these skills
- [Skill Server](/skills/skill-server/) — publishing skills with resources
- [Images, Audio, and Other File Types](/guides/multimodal-files/) — how the agent reads the files it pulls

## Resources

- [AgentSkills.io](https://agentskills.io) — the open skill format these bundles follow
- [Zip Slip](https://security.snyk.io/research/zip-slip-vulnerability) — the path-traversal class netclaw hardens extraction against
