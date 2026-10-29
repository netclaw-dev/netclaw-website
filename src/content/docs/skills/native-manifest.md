---
title: "Native manifest and subagent sync"
description: "How a skill server publishes subagents through its versioned native manifest, and how netclaw reads it."
---

A skill server publishes two discovery feeds. The [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc) feed at `/.well-known/agent-skills/index.json` is the vendor-neutral one, and any tool that speaks the RFC can read it. The **native manifest** at `/manifest.json` is a versioned feed for skill-server-aware clients. It carries subagents, which the RFC has no place for.

The two feeds sit side by side. netclaw takes skills from the RFC index, archives included, and takes subagents from the native manifest.

## The two feeds

| | RFC feed | Native manifest |
|---|----------|-----------------|
| Entry point | `/.well-known/agent-skills/index.json` | `/manifest.json` |
| Audience | Any RFC-compatible tool | Skill-server-aware clients |
| Carries | Skills, with type (`skill-md` or `archive`), URL and digest | Skills and subagents, with version history |
| netclaw uses it for | Every skill, including archive downloads | Subagents only |

## How the manifest is shaped

The manifest is [HATEOAS](https://en.wikipedia.org/wiki/HATEOAS): clients follow links instead of building URLs by hand. This is the root from a running 0.4.1 server:

```bash
curl -s http://localhost:8080/manifest.json
```

```json
{
  "$schema": "https://schemas.netclaw.dev/skillserver/manifest/0.1.0",
  "apiVersion": "v1",
  "versions": {
    "v1": {
      "self":           { "href": "/manifest.json" },
      "skills":         { "href": "/skills/v1/index.json" },
      "subagents":      { "href": "/subagents/v1/index.json" },
      "skillSearch":    { "href": "/api/v1/skills" },
      "subagentSearch": { "href": "/api/v1/subagents" }
    }
  }
}
```

From there, two collection trees each have an index, pages and a per-item history:

```
/subagents/v1/index.json                          collection index, lists its pages
/subagents/v1/pages/all.json                      the items
/subagents/v1/{agent}/index.json                  one subagent and its versions
/subagents/v1/{agent}/versions/{version}.json     one version: type, url, digest
/skills/v1/...                                    the same shape for skills
```

A version document tells a client where the bytes are and what digest to expect:

```json
{
  "kind": "subagent-version",
  "name": "changelog-reviewer",
  "version": "1.0.0",
  "type": "agent-md",
  "url": "http://skills.example.com/api/v1/subagents/changelog-reviewer/1.0.0/agent.md",
  "digest": "sha256:c914b9938fc543aa1f52753cfa62f14abe7c58dfcb50c2959b49929d8a6ea991"
}
```

The bytes live under `/api/v1/`. Follow the links and don't hard-code page names, because the server owns pagination.

## Version negotiation

`apiVersion` names the version the server recommends, and `versions` lists every version it offers. A client library can pick the newest one it also supports. netclaw doesn't negotiate. The daemon requests the `v1` subagent index directly and follows the links in what comes back.

## What netclaw does with it

On every sync pass, after the skills for a feed are installed, the daemon runs a subagent pass:

1. Fetch `/subagents/v1/index.json`, then each page it lists.
2. For each subagent, follow its identity document to the latest version, then to the version document.
3. Accept only type `agent-md`. Download the file and verify its digest.
4. Parse it as an agent definition. The frontmatter `name` has to equal the name the server advertised.
5. Write it to `~/.netclaw/agents/.server-feeds/<feed>/<name>.md` and record the version and digest in `.sync-state.json`.

The pass reports its outcome as `sidecar=` on the [`netclaw skill sync`](/cli/skill/#sync-feeds-now) line. A server with no native manifest answers 404 and reports `absent`.

A subagent that fails any step leaves the previous file in place. When the server stops advertising a subagent, netclaw deletes its local file, but only if every page and item synced cleanly in that pass.

Unlike skills, netclaw doesn't restore a synced subagent file you edited by hand. The file is replaced when the server publishes a new version. Edit your own agents in `~/.netclaw/agents/` instead, where a local definition always beats a feed copy. See [Distributing subagents](/skills/distributing-subagents/).

## Limitations

- The native manifest is specific to skill servers. A generic RFC feed serves skills only.
- Subagents travel as a single `agent-md` file. There's no archive form for them, so a subagent can't bundle resource files.
- There's no dependency resolution. A skill's `metadata.subagent` route is a runtime pointer. Publishing the skill doesn't publish the subagent it names.

## Related pages

- [Skill feeds](/skills/skill-feeds/): configure a feed and run a sync
- [Distributing subagents](/skills/distributing-subagents/): publish a subagent end to end
- [Bundling resources with skills](/skills/bundled-resources/): the archive form skills use
- [Skill server](/skills/skill-server/): run the server that publishes the manifest

## Resources

- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc): the vendor-neutral feed the manifest sits beside
- [HATEOAS](https://en.wikipedia.org/wiki/HATEOAS): the follow-the-links style the manifest uses
- [Native manifest spec](https://github.com/netclaw-dev/skill-server/blob/dev/docs/specs/native-manifest.md): the server's own description
