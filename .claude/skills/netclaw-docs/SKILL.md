---
name: netclaw-docs
description: Voice and style contract for netclaw.dev docs (Astro + Starlight, dark-mode only). The how-it-should-sound layer on top of CLAUDE.md's authoring process.
---

# netclaw.dev docs voice

Write like you're explaining netclaw to a sharp coworker who knows Linux, Docker, and Slack but has never touched netclaw. Confident, casual-technical, code-first. Open by saying what the thing does and when you'd reach for it, then show commands. The pages earn trust by being correct and dense, not long. CLAUDE.md owns the process (page types, templates, critique and humanizer steps). This skill owns how the page reads.

## Relationship to aarons-voice and humanizer

For anything under `src/content/docs/`, this skill supersedes `aarons-voice` and both humanizer skills. It already contains the parts of `aarons-voice` that apply to product docs, so don't load it alongside this one. Deliberately not carried over: bare URLs (use markdown links with descriptive text), the no-bold rule (see Bold), first-person "I", exclamation points, and the email phrase list. Humanizer runs on prose only. Where it disagrees with this skill, this skill wins.

## Two registers

- **Reference** (`cli/`, `configuration/`, `channels/`, `deployment/`, `observability/`, most `guides/`): "you" plus imperative. netclaw is the subject of behavior sentences ("netclaw resolves symlinks first"). No "we", no "I". Opinions stop at "use X unless Y". Exact beats charming.
- **Narrative** (design philosophy, comparisons, tutorials, the landing page): "we" is fine for the project's decisions and opinions. State opinions as opinions. A little roughness is fine. Still never "I".

A page is one or the other. If a reference page needs a "why", link to the narrative page.

## Do

- **Open with the payload.** First sentence says what the feature does and when you'd use it.
- **Lead guides with the answer.** Put an "I want / do this" table first where it fits, then explain.
- **Use the words people search for.** Titles and headings say "turn off", "stop asking", "disable", not internal names.
- **Name the thing.** "Slack, Discord, or Mattermost", not "your chat app".
- **Show, don't tell.** A config block, command or screenshot beats a paragraph. Tables for anything with a shape. Prose is for the one idea a table can't hold, and never restates the table.
- **Name the number one mistake**, once per section at most.
- **Use `:::caution` and `:::note`** for breaking changes, footguns and security boundaries only.
- **One concept page, one guide, one reference per topic.** Other pages link instead of re-explaining.
- **Stub honestly.** `<!-- TODO(screenshots): ... -->` and `<!-- TODO: needs user input - <question> -->`. Never ship "coming soon" prose.

## Don't

- No filler ("It is important to note", "This page covers", "The following table shows") and no hedging ("you may want to", "it is recommended").
- No "No X, no Y, no Z" more than once per page. No slogan triads or punchline fragments for rhythm ("That's unrealistic.").
- No screenshot captions shaped like `Label - fragment; fragment`. A caption is one sentence.
- Cut: "surface" as a noun, "just" as a minimiser, "walks through", "the full breakdown", "out of the box" (say "by default"), "first-class", "at a glance", "worth knowing".
- Don't explain what this audience already knows. Don't restate code in prose after showing it.
- Don't sand good sentences flat to chase a clean score. Fix the tell and keep the sentence. A page that passes every check and reads like a compliance form is worse than one with a stray dash.

## Punctuation

- **Contractions everywhere:** it's, don't, you'll, can't. Spell out "do not" or "cannot" only inside a `:::caution` or a security boundary statement, where the stiffness is the point.
- **No semicolons in prose.** Write two sentences.
- **No exclamation points.** No emoji, except status glyphs that mirror real CLI output.
- **Sentence-case headings:** `## Related pages`, `## Before you begin`. Proper nouns and command names keep their case.
- **No em dashes at all.** Pick the replacement by position:
  - List separators and table cells: ` - ` or a colon. An empty cell is `-`.
  - Headings: a colon (`### 401 Unauthorized: secret mismatch`). Heading edits change anchors, so check inbound links.
  - Prose: rewrite with a period, colon or comma first. Keep ` - ` for a real aside, about once per paragraph at most, never after a terminal `.`, `?` or `!`.
  - Don't search-and-replace. Forty em dashes turned into forty spaced hyphens is a new tic. Normalize ` -- ` the same way.

## Bold

Four uses only: UI labels the reader looks for, one warning per section, Symptom / Cause / Fix labels, and a term where it's defined. No bolded thesis sentences. No bold-label bullet lists where a table or subheadings would do.

## Structure

- Every page ends with exactly `## Related pages` (three to five internal links) then `## Resources` (two or more external links). No "Next steps", "See also" or "Keep reading". Tutorials may put `## What's next` before them.
- Every screenshot has the instruction before it and a one-sentence caption after it that says something the alt text doesn't.
- Page-type shapes:
  - **CLI:** intent, `## Usage`, options table, examples with a screenshot each.
  - **Tutorial:** goal, prerequisites with versions, numbered steps with expected output, verify it works.
  - **Guide:** problem in one line, before you begin, steps, troubleshooting (Symptom / Cause / Fix).
  - **Concept:** two or three paragraphs of mental model, key sections, limitations.
  - **Configuration:** what routes through it, minimal JSON, fields table (Field / Type / Default), invalid-config behavior.
  - **Integration:** transport in one line, prerequisites, third-party setup, configure netclaw, access control, verify, troubleshooting.
  - **Operations:** when you need a non-default mode, modes table, per-mode config, restart behavior, `netclaw doctor`.

## Terminology and product facts (0.27.1)

- netclaw is lowercase in running prose. The CLI is `netclaw`, the daemon is `netclawd`. Commands, flags and config keys go in backticks.
- `netclaw init` is first-run bootstrap only: provider, identity, security posture, then health check. That's four steps for Personal and five for Team or Public, which add a feature-selection step. Channels, search, exposure, webhooks and skill sources live in `netclaw config`, the re-entrant menu dashboard.
- Default base directory is `~/.netclaw`, or `$NETCLAW_HOME` if set. Config is `config/netclaw.json`, secrets are `config/secrets.json` (written with `netclaw secrets set`). Env overrides use the `NETCLAW_` prefix with `__` between path segments.
- `Ctrl+Q` quits every TUI. Escape is per screen: it never quits the config, provider, model, init or chat screens (in chat it denies a pending approval), but it does quit from the `netclaw mcp` server list. State keys per screen from the key-handling code, never as a global rule.
- There is no `netclaw daemon restart`. The daemon restarts itself, after draining sessions, when `netclaw.json` changes. Nothing else triggers it, so secrets and environment changes need a manual restart:
  - native: `netclaw daemon stop`, then `netclaw daemon start`
  - systemd user unit: `systemctl --user restart netclaw`
  - Docker: `docker restart <container>` (the image's entrypoint supervises the daemon)
- Screenshots and command output come from the release container (`ghcr.io/netclaw-dev/netclaw:<version>`), never a host binary. No private hostnames in samples or screenshots. Use `llm.example.internal` or a named public provider.
- Cross-link slugs are lowercase with a trailing slash: `/cli/<command>/`, `/channels/<platform>/`, `/configuration/<topic>/`.

## Pre-ship checklist

- [ ] Frontmatter `title` and `description` set. Headings in sentence case and built from search words.
- [ ] Opens with what and when. Guides lead with the answer. No filler, hedges or cut-list phrases.
- [ ] No em dashes, ` -- `, or semicolons in prose. ` - ` within budget. Contractions used.
- [ ] Reference page has no "we". No page has "I". Bold only in the four permitted uses.
- [ ] Tables carry reference material and aren't restated in prose.
- [ ] Every screenshot has an instruction before it and a one-sentence caption after it, and the file exists.
- [ ] Ends with `## Related pages` then `## Resources` (2+ external links).
- [ ] Every runnable snippet was run against the release container. No private hostnames.
- [ ] No placeholder prose. Only `<!-- TODO -->` comments for gaps.
- [ ] `humanizer:humanizer` pass done on prose only. `npm run build` passes.
