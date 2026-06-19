# AGENTS.md

netclaw.dev documentation site — Astro 6.2 + Starlight, dark-mode only, deployed to Cloudflare Pages.

Two guides govern work here. Read both before writing or editing any doc page:

- **[CLAUDE.md](./CLAUDE.md)** — the authoring *process*: page types, per-type templates, the screenshot pipeline, the critique + `/humanizer` review steps, and build/preview commands.
- **[`.claude/skills/netclaw-docs/SKILL.md`](./.claude/skills/netclaw-docs/SKILL.md)** — the *voice and style* contract: the "less is more" house voice, punctuation policy, per-page-type quick reference, terminology, and the pre-ship checklist.

CLAUDE.md owns *what* to write and *how to ship it*; the `netclaw-docs` skill owns *how it reads*. Use both.

## Quick reference

- Build: `npm run build` — must pass with no broken links or images before shipping.
- Dev: `npm run dev -- --host 0.0.0.0`.
- Docs track the netclaw release pinned in `src/version.json` (`documentedVersion`); bump it on a refresh.
- Content: `src/content/docs/`. Landing page: `src/pages/index.astro`. Screenshots: `public/screenshots/output/` (capture pipeline under `screenshots/`).
