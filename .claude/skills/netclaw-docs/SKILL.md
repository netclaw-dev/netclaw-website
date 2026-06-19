---
name: netclaw-docs
description: Voice and style contract for netclaw.dev docs (Astro + Starlight, dark-mode only). The how-it-should-sound layer on top of CLAUDE.md's authoring process.
---

# netclaw.dev Docs Voice

Write like you're explaining netclaw to a sharp coworker who knows Linux, Docker, and Slack but has never touched netclaw. Confident, casual-technical, code-first. Open by telling the reader what the thing does and when they'd reach for it, then get out of the way and show commands. The published pages earn trust by being correct and dense, not by being long. CLAUDE.md owns the process (page types, templates, the critique/humanizer pipeline); this skill owns the voice.

## Do

- **Open with the payload.** First sentence states what the feature does and when you'd use it. No "In this section" runway. See `getting-started/installation.md`: "Netclaw has two components..."
- **Use direct imperative voice.** "Run `netclaw status`." "Store tokens with `netclaw secrets`." Never "You can run" or "Users may wish to."
- **Show, don't tell.** A config block, command, or screenshot beats a paragraph. If CLI help already explains a flag, show the output instead of rewriting it.
- **Tables for anything with a shape** — flags, config fields (Field / Type / Default / Description), scopes, error→cause→fix, mode comparisons. Prose is for the one idea a table can't hold.
- **Name the #1 mistake.** The best pages flag the common footgun in bold ("This is the number one setup mistake"). Lead readers away from the trap.
- **Use Starlight callouts** `:::caution` / `:::note` for breaking changes, footguns, and security boundaries. Reserve them for things that bite.
- **Comment real screenshots in, stub honest TODOs out.** `<!-- TODO(screenshots): ... -->` and `<!-- TODO: needs user input — <question> -->` are the house pattern; never ship fake "coming soon" prose.
- **Close with cross-links.** End with Related pages + Resources (2+ external links to upstream docs/RFCs).

## Don't

- No filler: "It is important to note that", "This section describes", "The following table shows", "In this guide we will". Cut the sentence; keep the table.
- No hedging: "you may want to", "it is recommended that", "it should be noted". State it.
- No rule-of-three padding ("fast, simple, and powerful") or negative parallelism ("not X, but Y") used for rhythm.
- No inflated symbolism, no "seamless / robust / leverage / delve". Plain verbs.
- Don't explain the obvious. If a reader of this audience already knows it, delete it.
- Don't restate code in prose right after showing it.

## Punctuation

Use the em-dash (`—`). The published docs lean on it heavily and consistently (50+ pages; `security-model.md` alone has ~38) for parenthetical asides and appositives — it is established house voice, not an AI tell here. CONTEXT/TENSION: a memorizer feedback memory ("No em-dashes in customer-facing writing - LLM tell") flags em-dashes in *emails and broadcasts*. That rule is correct for outbound 1:1 and marketing copy; it does **not** govern reference documentation, where the established voice already uses them. Keep that split deliberate. Style notes: surround the em-dash with single spaces ( — ), don't stack more than one per sentence, and don't use it where a colon or period reads cleaner. Some channel pages use ` -- ` (double-hyphen) instead — that's an authoring inconsistency, not a second standard; prefer `—` in new pages.

## Per-page-type quick reference

- **CLI** (`cli/`): one-line intent → `## Usage` → options table → examples with a screenshot each → Related Commands.
- **Tutorial** (`getting-started/`): what we're building → Prerequisites (with versions) → numbered Steps with exact commands + expected output → Verify It Works → Next Steps.
- **Guide** (`guides/`): the problem in one line → Before You Begin → steps (call out conditional branches) → Troubleshooting (symptom / cause / fix).
- **Concept** (`architecture/`, `security/`): 2–3 paragraph mental model → key-concept sections → Limitations.
- **Configuration** (`configuration/`): what routes through this → minimal JSON block → full fields table (Field/Type/Default) → invalid-config behavior → diagnosing-errors table.
- **Integration** (`channels/`): transport in one line → Prerequisites → third-party setup (app/tokens/scopes, scopes table) → Configure netclaw → Access control → Verify it works → Troubleshooting.
- **Operations** (`deployment/`): when you need a non-default mode → modes table → per-mode config → restart/validation behavior → `netclaw doctor` troubleshooting.

## Terminology & product facts

- **netclaw** is lowercase in running prose. CLI is `netclaw`; daemon is `netclawd`.
- Commands and flags go in backticks: `netclaw status`, `--channel beta`. Config keys too: `Search.Backend`, `Daemon.ExposureMode`.
- **`netclaw init`** = focused 5-step first-run setup (provider, identity, security posture, features) that also powers factory reset. Don't pile post-install config into it.
- **`netclaw config`** = the re-entrant, menu-driven dashboard for everything else (channels, search, exposure, webhooks, skills); safe to re-run, autosaves on completion.
- Cross-link slugs: `/cli/<command>/`, `/channels/<platform>/`, `/configuration/<topic>/`, `/deployment/<topic>/`, `/security/<topic>/`, `/getting-started/<page>/`. Trailing slash, lowercase.
- Config lives in `~/.netclaw/config/netclaw.json`; secrets in `~/.netclaw/config/secrets.json` (encrypted at rest, written via `netclaw secrets set`). Env override prefix is `NETCLAW_` with `__` path separators.

## Pre-ship checklist

- [ ] Frontmatter `title` + `description` set.
- [ ] Opens with what/when, not runway. No filler or hedge phrases.
- [ ] Reference material is in tables; code/screenshots carry the weight.
- [ ] netclaw lowercase; commands and config keys backticked; cross-links use correct trailing-slash slugs.
- [ ] No placeholder prose — only `<!-- TODO -->` comments for gaps; all referenced screenshots exist.
- [ ] 2+ external resource links.
- [ ] Every runnable snippet was actually run against the current release.
- [ ] `/humanizer` pass done; `npm run build` passes.
