---
title: "skillserver CLI"
description: "Publish, validate, and manage skills and sub-agents on a skill server from the command line."
---

`skillserver` is the command-line tool for publishing and managing skills and sub-agents on a [skill server](/skills/skill-server/). It's what you run by hand during authoring and what your [CI pipeline](/skills/skill-server/) runs on merge. It speaks to the server's REST API, so anything the [gallery](/skills/skill-server/) shows, `skillserver` can do from a terminal.

## Install

```bash
# .NET global tool
dotnet tool install --global Netclaw.SkillServer.Cli

# Or a self-contained binary (Linux/macOS), no .NET runtime needed
curl -fsSL https://raw.githubusercontent.com/netclaw-dev/skill-server/dev/scripts/install-skillserver.sh | bash
```

For CI, pin the version. The install script takes one as an argument (`bash -s -- 0.4.0`), or commit a `dotnet-tools.json` manifest and run `dotnet tool restore`.

## Configure

`skillserver` needs a server URL, and a publish API key for any command that writes. It resolves both from three sources, highest priority first:

| Source | How to set | Use for |
|--------|-----------|---------|
| CLI flags | `--server-url`, `--api-key` | One-off overrides |
| Environment | `SKILLSERVER_URL`, `SKILLSERVER_API_KEY` | CI |
| Config file | `skillserver config init` → `~/.skillserver/config.json` | Local dev |

```bash
skillserver config init          # interactive first-run setup
skillserver config set server-url https://skills.example.com
skillserver config show          # print current config (no secrets)
```

Read-only commands (`list`, `list-subagents`, `versions`, `verify`, `download-subagent`) need only the URL. Everything that writes needs a key.

## Commands

### Publish

```bash
skillserver publish ./my-skill                 # one skill; version from SKILL.md frontmatter
skillserver publish ./my-skill --version 2.0.0 # override the version
skillserver publish-all ./skills               # every skill dir under ./skills
skillserver publish-subagent ./agent.md --version 1.0.0
skillserver publish-subagents ./subagents      # every .md under ./subagents
```

`publish` points at a single skill directory (the one holding `SKILL.md`). `publish-all` points at the *parent* directory and publishes each subdirectory. Both skip versions already on the server unless you pass `--force`. Sub-agents take their version from `--version`, which is required. The markdown frontmatter's `metadata.version` is ignored.

```text
$ skillserver publish-all ./skills
Scanning ./skills...
Found 2 skill(s) to publish.

  hello-greeter@1.0.0    Published
  k8s-log-triage@0.2.0    Published

Results: 2 published, 0 skipped, 0 failed
```

| Flag | Meaning |
|------|---------|
| `--version <v>` | Override the version (required for sub-agents) |
| `--force`, `-f` | Delete the existing version, then re-publish |
| `--dry-run` | Show what would publish without uploading |

### Inspect and download

```bash
skillserver list                     # all skills: name, latest, version count
skillserver list --search kubernetes # full-text search
skillserver versions my-skill        # every version of one skill
skillserver list-subagents
skillserver verify ./my-skill        # local files vs published digests
skillserver download-subagent release-notes-writer 1.0.0 ./agent.md
```

`verify` hashes each local file and compares it to the published version, which is handy in CI to confirm a release matches the repo:

```text
$ skillserver verify ./k8s-log-triage
Verifying k8s-log-triage@0.2.0...
  SKILL.md    match
  scripts/collect-logs.sh    match
  references/kubectl-cheatsheet.md    match
  assets/triage-template.json    match
All files verified
```

### Validate (no server needed)

`lint` runs entirely on local files, with no URL and no key, so it's the natural PR gate.

```bash
skillserver lint ./skills                 # every skill dir under ./skills
skillserver lint subagent ./agent.md      # one sub-agent file
skillserver lint subagents ./subagents    # every sub-agent .md in a dir
```

It checks that frontmatter parses, required fields are present, names are lowercase-kebab, and versions are semver.

:::caution
`lint` only exits non-zero on hard errors: a missing `SKILL.md`, a missing required field, or unparseable frontmatter. Softer problems are warnings that still exit 0, including a `name` that doesn't match its directory and a version that isn't valid semver. A name/directory mismatch is the number one publishing mistake, and `lint` won't fail CI over it, so read the warning output instead of trusting the exit code alone.
:::

### Manage

```bash
skillserver delete my-skill 1.0.0 --yes
skillserver delete-subagent release-notes-writer 1.0.0 --yes
skillserver api-key create --label ci-publish   # prints the secret ONCE
skillserver api-key list                         # ids + labels, never secrets
skillserver api-key delete 2
```

`--yes`/`-y` skips the delete confirmation prompt, so reach for it in scripts. `api-key create` shows the `sk-…` secret a single time, so store it immediately.

## Global flags

| Flag | Description |
|------|-------------|
| `--server-url <url>` | Override the configured URL |
| `--api-key <key>` | Override the configured key |
| `--output <text\|json>` | Output format (default `text`) |
| `--verbose`, `-v` | Detailed progress / upload logs |
| `--help`, `-h` | Command help (works without a server) |
| `--version` | Print the CLI version |

Pass `--output json` to any read command for scripting:

```bash
skillserver list --output json | jq '.[].name'
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Any failure: usage error, unknown command, validation error, auth failure, or a rejected server request |

There's no separate code for usage versus runtime errors. Both are `1`, so scripts should branch on `0` versus non-zero.

## Related pages

- [Skill Server](/skills/skill-server/) - run the server this CLI talks to.
- [Bundling Resources with Skills](/skills/bundled-resources/) - what `publish` packages when a skill has `references/`, `scripts/`, or `assets/`.
- [Native Manifest](/skills/native-manifest/) - the sync feed a netclaw daemon reads from the server.
- [Skill Feeds](/skills/skill-feeds/) - point a netclaw daemon at the published feed.

## Resources

- [skillserver CLI README](https://github.com/netclaw-dev/skill-server/blob/dev/src/Netclaw.SkillServer.Cli/README.md) - upstream reference.
- [AgentSkills.io](https://agentskills.io) - the `SKILL.md` format `lint` validates against.
- [.NET local tools](https://learn.microsoft.com/en-us/dotnet/core/tools/local-tools-how-to-use) - pinning the CLI with `dotnet-tools.json`.
