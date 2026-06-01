# netclaw.dev Documentation Site

Astro 6.2 + Starlight 0.38.4 static site. Dark-mode only. Deployed to Cloudflare Pages.

## Documentation Authoring Workflow

Each doc page follows a repeatable process. When asked to write a doc page, execute these steps in order.

### Step 1: Identify the Page

Read the target markdown stub in `src/content/docs/` to get the title and description. Determine the page type:

| Page Type | Directories | Approach |
|-----------|------------|----------|
| **CLI Reference** | `cli/` | Self-serve from screenshots + interview for non-obvious behavior |
| **Tutorial** | `getting-started/` | Interview-heavy — need the golden path, prerequisites, expected output |
| **Guide** | `guides/` | Mix — problem statement is self-evident, solution steps need interview |
| **Concept** | `architecture/`, `security/` | Interview-heavy — design decisions, rationale, threat models |
| **Configuration** | `configuration/` | Mix — schema/options from interview, examples from screenshots |
| **Integration** | `channels/` | Interview-heavy — third-party setup steps, OAuth flows, permissions |
| **Operations** | `deployment/` | Interview-heavy — runtime requirements, environment variables, health checks |

### Step 2: Gather What You Can

Before asking the user anything, collect available information:

1. **Netclaw source repo** — Clone `https://github.com/netclaw-dev/netclaw` (or locate a local clone). Key paths relative to that repo root:
   - `src/Netclaw.Cli/` — CLI commands, flags, help text
   - `src/Netclaw.Configuration/` — Config schemas, defaults, validation
   - `src/Netclaw.Daemon/` — Daemon architecture, startup, health checks
   - `src/Netclaw.Channels.Slack/` and `Netclaw.Channels.Discord/` — Channel integrations
   - `src/Netclaw.Security/` — Security model, ACLs, approval gates
   - `src/Netclaw.Providers/` — Provider abstraction, model routing
   - `docs/spec/` — Formal specs (runtime boundaries, session lifecycle, ACL policy, CLI contract, onboarding, model providers, MCP integration, daemon architecture)
   - `docs/adr/` — Architecture decision records (tool schemas, context discovery, progressive tool disclosure)
   - `docs/runbooks/` — Operational runbooks (background jobs, behavior debugging, daemon upgrades, memory health, subagents, tool approval gates)
   - `docs/spec/configuration.md` — Configuration specification
   - `CLAUDE.md`, `PROJECT_CONTEXT.md`, `CONTRIBUTING.md` — Project context and conventions
2. **Screenshots** — Check `screenshots/output/` for assets matching the page topic. Map them to the page. Screenshots are served at `/screenshots/output/<filename>`.
3. **Landing page** — `src/pages/index.astro` contains feature descriptions, architecture overview, and product positioning that inform doc content.
4. **Existing docs** — Read related pages that are already written for context and cross-referencing.
5. **Skill server repo** — Clone `https://github.com/netclaw-dev/skill-server` (or locate a local clone). May have relevant API docs or README content for skills-related pages.

Read relevant source files and specs BEFORE interviewing. Document what you found and what gaps remain before proceeding to interview.

### Step 3: Interview Mode

Ask the user **targeted, specific questions** to fill the gaps from Step 2. Rules:

- **Batch questions** — ask 3-7 questions at once, grouped by topic. Don't ask one at a time.
- **Show your work** — tell the user what you already know (from screenshots/landing page) so they don't repeat themselves.
- **Ask for the non-obvious** — don't ask "what does `netclaw status` do?" when you have a screenshot. Ask "what happens when status shows a degraded provider?" or "what's the most common mistake users make here?"
- **Ask for sequencing** — for tutorials/guides, ask "what order should a user do these steps?" and "what should they see at each checkpoint?"
- **Ask for failure modes** — "what goes wrong?" and "what's the fix?" are often the most valuable content.
- **Ask for scope boundaries** — "what should this page NOT cover?" prevents scope creep.
- **One round preferred** — aim to get everything in one interview round. A second round is OK if answers reveal new gaps.

#### Interview Templates by Page Type

**CLI Reference:**
- What flags/options aren't visible in the screenshots?
- What's the most common use case vs. advanced use cases?
- Any gotchas or non-obvious behavior?
- What other commands is this typically used with?

**Tutorial:**
- What are the prerequisites (installed software, accounts, API keys)?
- Walk me through the exact sequence — what does the user type, what do they see?
- Where do users most commonly get stuck?
- What does "success" look like at the end?

**Guide:**
- What problem is this solving? When would a user need this?
- What's the step-by-step? Any conditional branches (if X, do Y)?
- Are there multiple valid approaches? Which do we recommend and why?
- What are the failure modes and how do you recover?

**Concept:**
- What's the mental model the user should have?
- What design decisions were made and why?
- What are the boundaries/limitations?
- How does this relate to other parts of the system?

**Configuration:**
- What's the config file format and location?
- What are all the fields, their types, defaults, and valid ranges?
- What's a minimal config vs. a production config?
- What happens when config is invalid?

**Integration:**
- What third-party setup is required (apps, bots, tokens, permissions)?
- What's the OAuth/auth flow?
- What permissions/scopes are needed and why?
- How do you verify the integration is working?

### Step 4: Write the Page

**Writing principles — less is more:**
- Be minimal. Only include what people actually need. If it's obvious, don't explain it.
- Prefer a short page that covers the essentials over a long page that covers everything.
- One sentence that teaches something beats three sentences that elaborate.
- Code examples are worth more than prose. Show, don't tell.
- If the CLI help text already explains a flag well, don't rewrite it — just show the help output.
- No filler paragraphs. No "In this section we will discuss..." No padding.
- Tables over prose for reference material (flags, config fields, alert types).
- Every sentence should either teach something or help the reader do something. Delete the rest.
- **Visuals over text** — If a screenshot, diagram, or image explains something better than prose, use it. A screenshot of the TUI output is worth more than three paragraphs describing it. Architecture pages should have diagrams. CLI pages should have screenshots. Don't describe what you can show.

Write for a technical audience that's new to netclaw but experienced with their platform (Linux, Docker, Slack, etc.).

#### CLI Reference Template

```markdown
---
title: "netclaw <command>"
description: "<one-line description>"
---

<one paragraph: what this command does and when you'd use it>

## Usage

\`\`\`bash
netclaw <command> [options]
\`\`\`

## Options

| Flag | Description | Default |
|------|-------------|---------|
| ... | ... | ... |

## Examples

### <Common use case>

\`\`\`bash
netclaw <command> <args>
\`\`\`

![<description>](/screenshots/output/<file>.png)

<explain what the screenshot shows>

## Related Commands

- [`netclaw <other>`](/cli/<other>/) — <why it's related>
```

#### Tutorial Template

```markdown
---
title: "<action-oriented title>"
description: "<what the user will accomplish>"
---

<one paragraph: what we're building/doing and why>

## Prerequisites

- <specific requirement with version>
- <account/access requirement>

## Steps

### 1. <First action>

<instruction>

\`\`\`bash
<exact command>
\`\`\`

<what to expect / screenshot>

### 2. <Next action>

...

## Verify It Works

<how to confirm success>

## Next Steps

- [<next logical page>](</path/>) — <why>
```

#### Guide Template

```markdown
---
title: "<problem-oriented title>"
description: "<when you'd need this guide>"
---

<one paragraph: the problem this solves>

## Before You Begin

- <prerequisite or assumption>

## <Steps or sections as appropriate>

...

## Troubleshooting

### <Common problem>

<symptoms, cause, fix>
```

#### Concept Template

```markdown
---
title: "<topic>"
description: "<one-line summary>"
---

<2-3 paragraph overview: what this is, why it matters, mental model>

## <Key concept sections>

...

## Limitations

- <what this doesn't do or cover>
```

### Step 5: Screenshot Integration

When including screenshots:

- Use `![alt text](/screenshots/output/<filename>.png)` for static screenshots
- Prefer `.png` over `.gif` unless the animation is essential to understanding
- Write a caption sentence below each screenshot explaining what it shows
- If a screenshot shows a multi-step flow (like `init`), break it into individual step screenshots: `init-01-provider-list.png`, `init-02-security-posture.png`, etc.

Available screenshot sets:
- `init-*` — Full `netclaw init` wizard flow (10+ steps)
- `status.*` — System status display
- `doctor.*` — Health check diagnostics
- `stats.*` — Usage statistics
- `provider.*` / `provider-manager.png` — Provider management
- `model.*` / `model-manager.png` — Model management
- `mcp-tools.*` / `mcp-tools-*.png` — MCP tool server management
- `webhooks.*` / `webhooks-list.png` — Webhook configuration
- `reminder.*` / `reminder-list.png` — Reminder management

### Step 6: Critique (3 parallel agents)

After writing the draft, spawn three review agents in parallel. Pass each the full draft content.

**Agent 1 — Technical Accuracy:**
- Compare every claim against the source code and specs
- Flag any incorrect flag names, default values, or behavior descriptions
- Verify all code examples would actually work
- Check that command output descriptions match what the screenshots show

**Agent 2 — Reader Empathy:**
- What would a human reader find missing or confusing?
- Are there prerequisites the page assumes but doesn't state?
- Would a reader know what to do next after finishing this page?
- Identify 2-4 external links that would be useful (official docs for third-party tools, relevant RFCs, related tutorials)
- Flag any jargon that isn't defined on this page or linked to a page that defines it

**Agent 3 — Humanizer:**
- Does this read like a person wrote it or like a manual was generated?
- Flag robotic phrasing: "It is important to note that...", "This section describes...", "The following table shows..."
- Flag unnecessary hedging: "you may want to", "it is recommended that"
- Prefer direct voice: "Run `netclaw status`" not "You can run `netclaw status`"
- Check for variety in sentence structure — not every paragraph should start the same way
- The tone should be confident and casual-technical, like explaining to a coworker

### Step 7: Humanizer Pass

Run `/humanizer` on the drafted page. This is mandatory — no page ships without it. The humanizer catches AI writing patterns that slip through manual review: over-explaining, passive voice, hedge words, repetitive structure, and generic filler that makes documentation feel soulless.

### Step 8: Revise

Incorporate all critique feedback and humanizer output in a single pass:
- Fix technical inaccuracies
- Add missing context, prerequisites, and "what's next" links
- Insert external resource links where the reader empathy agent identified gaps
- Rewrite robotic or hedging language
- Ensure cross-links to other netclaw docs use correct slugs

### Step 9: Quality Check

Before declaring the page done:

- [ ] Frontmatter `title` and `description` are set
- [ ] Page follows the correct template for its type
- [ ] All referenced screenshots exist in `screenshots/output/`
- [ ] No placeholder text ("Content coming soon", "TODO", "TBD")
- [ ] Cross-links to related pages use correct slugs
- [ ] Code examples are complete and copy-pasteable
- [ ] At least 2 external links to relevant resources
- [ ] No robotic phrasing or unnecessary hedging
- [ ] `npm run build` passes with no errors
- [ ] **Every runnable example actually runs.** Any `docker run`, `docker compose`, or shell snippet a reader is told to execute MUST be run locally against the current release first and verified crash-free — the container reaches `healthy` and `docker logs` shows no fatal error / `Aborted (core dumped)`. Never ship a command you haven't executed. (This is how the stale `Daemon.Host=0.0.0.0` Docker example shipped a guaranteed startup crash.)

## Autonomous Doc Writing Mode

When invoked with a page slug (e.g., `cli/status`), run the full pipeline without user interaction:

1. Skip Step 3 (Interview) — use only source material from Step 2
2. If critical information is missing, write the best page you can and leave a `<!-- TODO: needs user input — [specific question] -->` comment
3. Run all critique agents (Step 6) and revise (Step 7)
4. Run `npm run build` to verify
5. Stage and commit the single page with message: `docs: write <section>/<page>`

The netclaw source repo is expected at `~/repositories/stannardlabs/netclaw/`. If not found, check common locations or skip source-dependent content.

## Build & Preview

```bash
npm run dev -- --host 0.0.0.0   # Dev server with Tailscale access
npm run build                    # Production build (43 pages)
```

## Project Structure

```
src/
  content/docs/     # Markdown documentation pages
  pages/            # index.astro (landing page)
  components/       # Starlight overrides (Header, Footer, ThemeSelect)
  styles/           # custom.css (brand tokens)
  assets/           # Logo SVG for Starlight
public/
  assets/           # Static assets (images, favicons)
  screenshots/      # Copied from repo root at build time
screenshots/        # VHS capture pipeline output (source of truth)
```
