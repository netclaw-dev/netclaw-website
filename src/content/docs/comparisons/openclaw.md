---
title: "Netclaw vs. OpenClaw"
description: "Why we built netclaw when OpenClaw already exists — and what we do differently."
---

<img src="/assets/openclaw-logo.svg" alt="OpenClaw logo" style="max-width: 280px; margin-bottom: 1.5rem;" />

[OpenClaw](https://openclaw.ai/) pioneered this category: an always-on AI agent that lives in your communication channels, acts autonomously in response to messages and timers, and runs without anyone sitting at a computer. 360K+ GitHub stars, dozens of platform integrations, a massive community. That vision inspired everything we've built.

We built netclaw because OpenClaw's execution philosophy — ship everything, integrate everything, build the biggest ecosystem possible — creates security and complexity debt. The vision is right. The philosophy is wrong.

## Breadth vs. simplicity

OpenClaw competes on scale — stars, contributor count, lines of code, integration breadth. Their pitch is the ecosystem: 50+ platform integrations, 700+ community skills in [ClawHub](https://clawhub.openclaw.ai/), 1,900+ contributors, 430K+ lines of code.

Netclaw competes on simplicity. Our codebase is deliberately small. Our configuration footprint is minimal. When we're tempted to add a feature, the first question is: can this live in an [MCP server](/architecture/design-philosophy/#mcp-first-tooling) someone else maintains instead?

Every feature you add is a feature you have to maintain, test, secure, and explain. Most agent projects treat feature count as proof of progress. We think it's a liability. The [philosophy of no](/architecture/design-philosophy/#the-philosophy-of-no) covers why.

## The security record

OpenClaw starts permissive and adds restrictions after security incidents. In March 2026, [nine CVEs were disclosed in four days](https://openclawai.io/blog/openclaw-cve-flood-nine-vulnerabilities-four-days-march-2026) — including [CVE-2026-32922](https://www.armosec.io/blog/cve-2026-32922-openclaw-privilege-escalation-cloud-security/), a CVSS 9.9 privilege escalation. As of April 2026, [138+ CVEs have been disclosed](https://www.betterclaw.io/blog/openclaw-security-2026) and tracked by the community ([jgamblin/OpenClawCVEs](https://github.com/jgamblin/OpenClawCVEs/)). A February 2026 internet-wide scan found [135,000+ publicly accessible OpenClaw instances](https://conscia.com/blog/the-openclaw-security-crisis/), 63% running without gateway authentication.

This isn't bad luck. Permissive-first architecture creates more attack surface and more trust boundaries to misconfigure.

Netclaw works the other way around. During [`netclaw init`](/cli/init/), you choose an [audience disposition](/architecture/security-model/#audience-as-the-trust-primitive) that sets the baseline for what the agent can do. The [four-layer security model](/architecture/security-model/#four-layers-not-one) — `ShellCommandPolicy`, `ToolPathPolicy`, `ToolAccessPolicy`, `IToolApprovalService` — stacks independent checks so no single misconfiguration gives the agent the keys. Default-deny, fail-closed, [approval gates](/architecture/security-model/#human-in-the-loop-as-a-layer-not-a-crutch) for anything destructive.

## The skills marketplace problem

OpenClaw's [ClawHub](https://clawhub.openclaw.ai/) is an open marketplace where anyone can publish agent skills. In February 2026, [Koi Security audited 2,857 ClawHub skills](https://thehackernews.com/2026/02/researchers-find-341-malicious-clawhub.html) and found 341 that were actively malicious — a **12% malware rate**. 335 of those traced to a single coordinated campaign called [ClawHavoc](https://www.antiy.net/p/clawhavoc-analysis-of-large-scale-poisoning-campaign-targeting-the-openclaw-skill-market-for-ai-agents/). A follow-up scan found [824+ malicious skills out of 10,700+](https://www.esecurityplanet.com/threats/hundreds-of-malicious-skills-found-in-openclaws-clawhub/) total.

[Snyk's broader ToxicSkills study](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub/) across agent skill registries found that 36% of skills contain security flaws, with active malicious payloads capable of going [from SKILL.md to shell access in three lines of markdown](https://snyk.io/articles/skill-md-shell-access/).

An open, unaudited skill marketplace is an inherently dangerous idea when skills can execute shell commands and call external APIs. The attack surface isn't a bug — it's the architecture.

Netclaw doesn't have a public skills marketplace. Skills come from [curated feeds](/skills/skill-feeds/) managed by your organization via [SkillServer](/skills/skill-server/) — a self-hosted registry where you control what your agents can learn. Skills are synced, version-controlled, and SHA-256 verified on download. New or changed skills go through a content scan for prompt injection before they're accepted. You can also connect to trusted third-party feeds, but the decision to trust a feed is yours, not the agent's.

## Model requirements

OpenClaw's documentation recommends using "the strongest latest-generation model available," which in practice means frontier models at $10+ per million input tokens and requires sending your data to a cloud inference provider.

Netclaw runs production workloads on [Qwen 3.6 27B](https://huggingface.co/Qwen/Qwen3.6-27B), tested down to Qwen 3.5 9B. [Progressive tool disclosure](/architecture/design-philosophy/#mcp-first-tooling) reduces prompt complexity so smaller models can navigate tool graphs without misfiring. A $3,000 GPU with 64GB VRAM runs local inference indefinitely — bounded capital expenditure, data never leaves your infrastructure.

## What OpenClaw does better

OpenClaw genuinely does some things better:

- **Platform coverage.** 12+ messaging platforms vs. netclaw's two (Slack and Discord). If you need Teams, Signal, Telegram, or WhatsApp today, OpenClaw has them.
- **Community size.** 1,900+ contributors, extensive third-party tutorials, and a massive ecosystem of community-built integrations.
- **Maturity.** OpenClaw has been around longer and has more production deployments. The rough edges have been found and reported (sometimes painfully).

If you need maximum platform coverage and a large community right now, use OpenClaw.

## Who should choose which

**Choose OpenClaw if** you need broad platform support across many messaging services, prefer a large community with extensive third-party resources, and are comfortable managing the security surface yourself.

**Choose netclaw** for a smaller codebase you can audit, security that defaults to deny instead of permissive-plus-patches, local inference that keeps your data on your hardware, and control over your agent's capabilities.

## Keep reading

- [Design Philosophy](/architecture/design-philosophy/) — why simplicity is a feature
- [Security Architecture](/architecture/security-model/) — the four-layer model in detail
- [Skills Overview](/skills/overview/) — how netclaw's curated skill system works
- [Self-Hosted Providers](/configuration/self-hosted-providers/) — running local inference

## Sources

- [Nine CVEs in Four Days — OpenClaw Blog (March 2026)](https://openclawai.io/blog/openclaw-cve-flood-nine-vulnerabilities-four-days-march-2026)
- [OpenClaw Security 2026: 138+ CVEs — BetterClaw](https://www.betterclaw.io/blog/openclaw-security-2026)
- [CVE-2026-32922: CVSS 9.9 Privilege Escalation — ARMO](https://www.armosec.io/blog/cve-2026-32922-openclaw-privilege-escalation-cloud-security/)
- [jgamblin/OpenClawCVEs — Community CVE Tracker](https://github.com/jgamblin/OpenClawCVEs/)
- [The OpenClaw Security Crisis — Conscia](https://conscia.com/blog/the-openclaw-security-crisis/)
- [341 Malicious ClawHub Skills — The Hacker News (Feb 2026)](https://thehackernews.com/2026/02/researchers-find-341-malicious-clawhub.html)
- [OpenClaw Ships Verified Skill Screening — Reuters (March 2026)](https://www.tradingview.com/news/reuters.com,2026-03-26:newsml_ACN105904:0-openclawd-ships-verified-skill-screening-after-security-researchers-find-12-of-openclaw-marketplace-skills-are-malware/)
- [ToxicSkills and ClawHavoc — Agensi](https://www.agensi.io/learn/toxicskills-clawhavoc-agent-skills-security-crisis-2026)
- [Snyk ToxicSkills Study — 36% of Skills Contain Flaws](https://snyk.io/blog/toxicskills-malicious-ai-agent-skills-clawhub/)
- [From SKILL.md to Shell Access — Snyk](https://snyk.io/articles/skill-md-shell-access/)
- [ClawHavoc Analysis — Antiy Labs](https://www.antiy.net/p/clawhavoc-analysis-of-large-scale-poisoning-campaign-targeting-the-openclaw-skill-market-for-ai-agents/)
- [Hundreds of Malicious Skills — eSecurity Planet](https://www.esecurityplanet.com/threats/hundreds-of-malicious-skills-found-in-openclaws-clawhub/)
- [ClawHub Incident — Termdock](https://www.termdock.com/en/blog/clawhub-malicious-skills-incident)
