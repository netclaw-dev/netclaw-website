---
title: "Native Manifest & Sync"
description: "How a skill server exposes skills and subagents to netclaw through the versioned native manifest, alongside the Cloudflare RFC feed."
---

A skill server publishes two discovery feeds. The [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc) feed at `/.well-known/agent-skills/index.json` is the vendor-neutral one — any tool that speaks the RFC can read it. The **native manifest** at `/manifest.json` is a richer, versioned feed for skill-server-aware clients like netclaw: it adds version negotiation, version history, subagents, and archive metadata the RFC feed doesn't carry.

The native manifest is a **sidecar, not a replacement**. It never supersedes the RFC feed — a client that only understands the RFC keeps working, and netclaw reads both. What the native manifest buys netclaw is the extra material: subagent definitions (which never appear in the RFC feed) and bundled-resource archives.

## The two feeds

| | RFC feed | Native manifest |
|---|----------|-----------------|
| Entry point | `/.well-known/agent-skills/index.json` | `/manifest.json` |
| Audience | any RFC-compatible tool | skill-server-aware clients |
| Carries | skills | skills **+ subagents + archive metadata** |
| Versioned | no | yes (API version negotiation) |
| netclaw uses it for | skill discovery, digests | subagents, archives, version history |

## How the manifest is shaped

The manifest is [HATEOAS](https://en.wikipedia.org/wiki/HATEOAS) — clients follow links rather than building URLs by hand. The root at `/manifest.json` lists the available API versions, each with a set of links:

```json
{
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

From there, a client follows `href` values down two collection trees — one for skills, one for subagents — each with its own index, pages, and per-item version history:

```
/skills/v1/index.json                        # skill collection
/skills/v1/{skill}/index.json                # one skill
/skills/v1/{skill}/versions/{version}.json   # a specific version
/subagents/v1/index.json                     # subagent collection
/subagents/v1/{agent}/versions/{version}.json
```

The manifest links point at the REST API under `/api/v1/` for the actual bytes — `/api/v1/skills/{name}/{version}/archive.zip` for a bundled skill, `/api/v1/subagents/{name}/{version}/agent.md` for a subagent. Follow the links; the paths are readable but the server owns pagination boundaries, so don't hard-code them.

:::note
The manifest declares the routes, but the wire paths that matter are the ones the running server serves. If you're scripting against a server directly, read them off `/manifest.json` rather than a spec — the REST content lives under `/api/v1/`, which is easy to miss from the shorthand in the collection trees.
:::

## Version negotiation

`apiVersion` names the version the server recommends; `versions` lists every version it offers. A client picks the newest version it *also* supports:

1. The client knows its own supported versions (netclaw today: `v1`).
2. It reads the server's `versions`.
3. It uses the most recent version in the intersection.
4. If there's no overlap, it falls back to the oldest the server offers.

The payoff is forward compatibility in both directions: when a server ships `v2`, an older netclaw keeps using `v1`, and a newer netclaw automatically prefers `v2` — no coordinated upgrade.

## What netclaw does with it

On each sync, the daemon fetches the RFC index first, then — for feeds served by a skill server — follows the native manifest to pull what the RFC feed can't describe:

- **Subagents.** It walks the subagent collection, downloads each `agent.md`, verifies its digest, checks the frontmatter `name` matches, and writes it under `~/.netclaw/agents/.server-feeds/<feed>/`. See [Custom Subagents](/guides/custom-subagents/).
- **Archives.** When a skill is published as an archive, netclaw pulls the bundled `.zip` instead of individual files. See [Bundling Resources with Skills](/skills/bundled-resources/).

Sync is **fail-soft and prune-after-confirm**: a feed that's unreachable or serves a bad digest doesn't take down the others or wipe your last-good copy, and stale entries are pruned only after a successful sync replaces them. A server that speaks only the RFC feed still works — netclaw just doesn't get subagents or archives from it.

## Limitations

- The native manifest is skill-server-specific. A generic RFC feed won't expose subagents or archive metadata, so those features need a [skill server](/skills/skill-server/).
- Version negotiation covers the manifest API, not skill or subagent content versions — those are tracked per item in the collection trees.
- There's no transitive dependency resolution. A skill's `metadata.subagent` route is a runtime pointer, not a package dependency the manifest resolves for you.

## Related pages

- [Skill Feeds](/skills/skill-feeds/) — configuring a feed and the sync lifecycle
- [Bundling Resources with Skills](/skills/bundled-resources/) — the archive artifacts the manifest points to
- [Custom Subagents](/guides/custom-subagents/) — defining the subagents the manifest distributes
- [Skill Server](/skills/skill-server/) — running the server that publishes it

## Resources

- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc) — the vendor-neutral feed the manifest sits beside
- [HATEOAS](https://en.wikipedia.org/wiki/HATEOAS) — the follow-the-links hypermedia style the manifest uses
