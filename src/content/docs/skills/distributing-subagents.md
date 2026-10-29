---
title: "Distribute subagents with a skill server"
description: "Publish a subagent to a skill server once and have every netclaw instance install it, update it and drop it."
---

To share a subagent across your team, publish it to a [skill server](/skills/skill-server/) with `skillserver publish-subagent`, and subscribe each netclaw instance to the server as a feed. The daemon installs the definition under `~/.netclaw/agents/.server-feeds/<feed>/`, replaces it when you publish a new version, and deletes it when you remove it from the server. A subagent a user wrote in `~/.netclaw/agents/` always wins over a feed copy of the same name.

## Before you begin

- A running skill server and an API key that can publish. See [Skill server](/skills/skill-server/#create-a-publishing-key).
- The [`skillserver` CLI](/skills/skillserver-cli/#install) on the machine you publish from.
- netclaw 0.25.0 or later, the first stable release that syncs subagents, with the server configured as a feed. See [Skill feeds](/skills/skill-feeds/#add-a-feed).
- A subagent definition. See [Custom subagents](/skills/custom-subagents/#the-agent-file).

The examples use `https://skills.example.com`. Swap in your own server.

## 1. Write the definition

A subagent is one markdown file in the format described in [Custom subagents](/skills/custom-subagents/#the-agent-file). The server publishes it as an `agent-md` artifact, the same file, byte for byte.

```markdown
---
name: changelog-reviewer
description: Review a changelog entry for clarity and missing user impact
modelRole: Compaction
---

You review changelog entries. Given a draft entry, point out vague wording and
missing user impact. Reply with a short bulleted list.
```

Two rules differ from a local agent:

- The `name` is 1 to 64 lowercase letters, digits and single hyphens. The server rejects `Bad_Agent`. A file you keep locally isn't checked this strictly.
- The version isn't in the file. You pass it when you publish. Frontmatter `metadata.version` is ignored for subagents.

## 2. Lint it

`lint` runs on local files and needs no server or key, so it also works as a pull request check:

```bash
skillserver lint subagent ./subagents/changelog-reviewer.md
skillserver lint subagents ./subagents
```

```text
Linting sub-agents in './subagents'...
Found 1 markdown file(s).

All sub-agents valid (1 passed, 0 warning(s))
```

It fails on a bad `name` or an out-of-range `prefillTimeoutSeconds`. The skill server still checks `timeoutSeconds` if a file sets it, but netclaw ignores that key, so leave it out. The server applies the same checks when you upload.

## 3. Publish it

Set the server URL and key, then publish with an explicit version:

```bash
export SKILLSERVER_URL=https://skills.example.com
export SKILLSERVER_API_KEY=sk-...        # a key from `skillserver api-key create`
skillserver publish-subagent ./subagents/changelog-reviewer.md --version 1.0.0
```

```text
Publishing sub-agent changelog-reviewer@1.0.0...
Published sub-agent changelog-reviewer@1.0.0
  sha256:c914b9938fc543aa1f52753cfa62f14abe7c58dfcb50c2959b49929d8a6ea991
  https://skills.example.com/api/v1/subagents/changelog-reviewer/1.0.0/agent.md
```

Leave out `--version` and the command stops with `--version <version> is required for sub-agent publication`.

To publish a whole directory, use `publish-subagents`. It takes one `--version` and applies it to every file in the directory, and it skips versions that already exist, so you can run it on every push:

```bash
skillserver publish-subagents ./subagents --version 1.0.0
```

```text
  changelog-reviewer@1.0.0    Skipped (Already published)
  release-notes-writer@1.0.0    Published

Results: 1 published, 1 skipped, 0 failed
```

Because a batch shares one version number, publish agents that change on different schedules one at a time.

Confirm what the server holds:

```bash
skillserver list-subagents
```

```text
NAME                  LATEST  VERSIONS  UPDATED
changelog-reviewer    1.0.0   1         2026-10-07
release-notes-writer  1.0.0   1         2026-10-07
```

## 4. Sync it to netclaw

The daemon picks subagents up on its next sync pass: at startup, on the timer, or when you ask. To pull now, run:

```bash
netclaw skill sync
```

```text
Skill sync pass ddf5b142f67241dfae5ec80af287ecdb
corp-skills: ok changed=0 unchanged=2 rejected=0 failed=0 sidecar=complete
Inventory: ok accepted=13 rejected=0
```

`sidecar=complete` means the subagent pass finished. The `changed` count covers skills only, so a new subagent doesn't move it. The proof is on disk:

```bash
ls ~/.netclaw/agents/.server-feeds/corp-skills/
```

```text
changelog-reviewer.md
```

The next turn lists `changelog-reviewer` among the available subagents, and the agent can `spawn_agent` it. The run starts in the background, and the result comes back in a later turn. No restart is needed.

## 5. Update or remove it

Publish a higher version to update. The next sync downloads it, verifies its digest and replaces the file:

```bash
skillserver publish-subagent ./subagents/changelog-reviewer.md --version 1.1.0
```

To remove one, delete it from the server. The next sync deletes the local file, as long as every page and item in that pass synced cleanly:

```bash
skillserver delete-subagent changelog-reviewer 1.0.0 --yes
```

Don't hand-edit files under `.server-feeds/`. netclaw doesn't hash-check subagent files the way it does skills, so your edit stays until the next version replaces it. To change a shared agent for one machine, copy it to `~/.netclaw/agents/` under the same name. That copy wins, and netclaw logs a warning that it skipped the feed version.

## Pair a skill with a subagent

A skill can hand its work to a subagent with `metadata.subagent`. Publishing the skill doesn't publish the agent, so publish both:

```yaml
---
name: changelog-check
description: Have the changelog reviewer check an entry before it ships.
argument-hint: "<changelog entry>"
metadata:
  version: 1.0.0
  subagent: changelog-reviewer
---

# Changelog check

Review the changelog entry the user gives you. Flag vague wording and missing user impact.
```

```bash
skillserver publish-all ./skills
```

After a sync, `/changelog-check <entry>` starts the subagent in the background with this skill's body as extra instructions and your text as the task. The target has to be `user-facing`, and if it's missing the skill reports an unknown target. See [routing in the overview](/skills/overview/#how-skills-get-used).

## Publish from CI

A repository with `skills/` and `subagents/` folders can publish on every merge. Both commands skip what's already published, so the job is safe to re-run:

```yaml
- name: Lint
  run: |
    skillserver lint ./skills
    skillserver lint subagents ./subagents
- name: Publish
  env:
    SKILLSERVER_URL: https://skills.example.com
    SKILLSERVER_API_KEY: ${{ secrets.SKILLSERVER_API_KEY }}
  run: |
    skillserver publish-all ./skills
    skillserver publish-subagents ./subagents
```

`publish-subagents` publishes every file in the folder at the `version` in its frontmatter. Give each agent file its own version and bump it in the file you changed:

```markdown
---
name: changelog-reviewer
description: Review a changelog entry for clarity and missing user impact
version: 1.1.0
---
```

Publishing a version that already exists is a no-op, so only the agents you bumped get republished, and only those re-download on each netclaw instance. Netclaw ignores the `version` key when it loads the agent. A file without one fails the publish unless you pass `--version` as a default. Keep `publish-subagent <file> --version <v>` for a one-off publish by hand.

## Trust

A subagent definition is a system prompt, and it runs with the tools and approvals of the session that spawns it. Whoever can publish to the feed can change how your agents behave.

- netclaw verifies the digest of every file it downloads and rejects a mismatch. It doesn't scan the prompt text, since content scanning is off.
- Every valid API key can publish. There's no publish-only scope or per-feed ACL, so limit who holds keys and keep the server on a private network.
- A synced subagent can't widen its own permissions. It gets the parent's audience tools, minus `spawn_agent`, `check_agent_run` and `attach_file`, and gated tools still ask for approval. See [Tools and approvals](/skills/custom-subagents/#tools-and-approvals).
- Review a definition before you publish it. A prompt that tells the agent to run commands or write files does what it says.

## Troubleshooting

### The subagent doesn't appear after sync

- **Symptom:** The folder under `~/.netclaw/agents/.server-feeds/` is empty or the agent isn't spawnable.
- **Cause:** The sync line shows `sidecar=absent` (no native manifest at the URL), `sidecar=failed`, or `not-run` because the skill index request failed.
- **Fix:** Open `<server>/subagents/v1/index.json` in a browser or with `curl`. If it 404s, the URL isn't a skill server. Check the daemon log for `Rejected native sub-agent` lines.

### Sync rejects the file

- **Symptom:** `sidecar=failed`, and the log says the frontmatter name differs from the advertised name, or the file isn't valid UTF-8.
- **Cause:** The `name` in the file doesn't match the name it was published under, or the definition fails the loader's rules.
- **Fix:** Run `skillserver lint subagent` on the file and publish a corrected version.

### The local copy keeps winning

- **Symptom:** You published an update, but `spawn_agent` still behaves the old way.
- **Cause:** A file in `~/.netclaw/agents/` has the same `name` and shadows the feed copy.
- **Fix:** Delete or rename the local file. The daemon log says `declares duplicate name ... earlier definition wins`.

## Related pages

- [Custom subagents](/skills/custom-subagents/): the file format, limits and approvals
- [Skill feeds](/skills/skill-feeds/): configure the feed and run syncs
- [Native manifest](/skills/native-manifest/): how the daemon discovers subagents on the server
- [`skillserver` CLI](/skills/skillserver-cli/): every publish and management command
- [Skill server](/skills/skill-server/): run the server and manage keys

## Resources

- [skill-server subagent specification](https://github.com/netclaw-dev/skill-server/blob/dev/docs/specs/subagents.md): the `agent-md` artifact and publication model
- [Semantic Versioning](https://semver.org): version numbers for published artifacts
