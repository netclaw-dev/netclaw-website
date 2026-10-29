---
title: "netclaw vs. Hermes Agent"
description: "Where we agree with Hermes Agent, where we disagree, and why it matters."
---

<img src="/assets/hermes-agent-icon.png" alt="Nous Research logo" style="max-width: 80px; margin-bottom: 1.5rem;" />

[Hermes Agent](https://hermes-agent.nousresearch.com/) arrived at many of the same instincts as netclaw: small model support, automatic memory synthesis, self-hosted by default. We respect that. These are important beliefs and Nous Research got them right.

But we draw different conclusions about how much autonomy an agent should have over its own capabilities, how much background work it should do without being asked, and what the right relationship is between the agent and the human operating it.

## What we agree on

**Small models work.** Both projects prove you don't need frontier models for production agent workloads. Hermes runs great on small models, and that's exactly the philosophy we've got.

**Memory matters.** Automatic memory formation and cross-session recall are essential, not optional. Both projects invested heavily here. netclaw's recall is local semantic search: memories are embedded on your own CPU with an ONNX model, and a second small model gates weak matches out so most turns inject nothing. No cloud embedding service is involved.

**Self-hosted is the right default.** Your data stays on your infrastructure. Both projects are designed for local deployment.

On these fundamentals, they're right.

## The philosophical split: self-improving vs. human-controlled

Hermes Agent's tagline is "The Agent That Grows With You." The core idea: the agent creates skills autonomously, evaluates their performance, archives underperformers, consolidates overlapping ones, and improves over time with minimal human involvement. The agent manages its own capability surface.

netclaw inverts this. The human decides what the agent knows how to do. Skills come from your own skills directory and from [curated feeds](/skills/skill-feeds/) managed by your organization, not from the agent's autonomous judgment. The agent can write or edit a skill with its `skill_manage` tool, but nothing in netclaw scores, archives, consolidates, or rewrites skills in the background, and a human or a managed feed is still the source for everything else it learns.

This is a trust boundary, not a capability gap.

## The Curator: a case study

Hermes Agent shipped a 2,200-line "Curator" system (April 2026) that:

- Tracks skill usage frequency across sessions
- Moves skills through active → stale → archived lifecycle states automatically
- Spawns auxiliary LLM reviews to propose skill consolidations
- Requires users to manually specify which skills the system *shouldn't* auto-archive

That last point inverts the trust relationship. The agent acts by default, and the human intervenes to prevent. If you don't notice a skill got archived, it's gone.

netclaw's approach is opt-in. Skills are version-controlled, synced from feeds, and managed by humans. The agent can write a skill with `skill_manage`, and it lands in your skills directory like any other. There's no background skill creation, no autonomous archival, no "oops the agent deleted something I needed."

## The token cost of autonomy

Every background process the Curator runs (usage tracking, lifecycle transitions, auxiliary LLM reviews for consolidation proposals) is an inference call. On self-hosted hardware, that's GPU time you're already paying for. On a paid inference provider like [OpenRouter](https://openrouter.ai/) or [Nous Portal](https://portal.nousresearch.com/), it's real money on your bill.

netclaw's memory observer makes one LLM call when a session goes idle (or every five turns in a long one) to distill observations, and a curation call happens mainly when a new memory looks like a near-duplicate of one already stored, or when the rules can't decide. Embedding and relevance scoring run locally and use no provider tokens at all. The Curator runs continuous background evaluations across all skills. The difference compounds.

Worth noting: [Nous Research sells inference](https://portal.nousresearch.com/models) as a core part of their business, with [20 models available via API](https://pricepertoken.com/pricing-page/provider/nousresearch). An agent architecture that burns more tokens through autonomous background processes aligns with that revenue model. That's not a flaw in their design. It's incentive alignment.

## Release velocity

Hermes Agent publishes impressive numbers per release: 864 commits, 588 merged PRs, 128K insertions in v0.13.0 alone. They present this as a feature.

We see it as a risk signal. Hundreds of PRs per release means massive churn, harder review, and more surface for regressions. The [biggest threat to any project is its own complexity](/architecture/design-philosophy/#simplicity-is-a-feature). netclaw ships what's necessary and nothing more.

## Security posture

Hermes Agent has no audience system. There's no way to scope what the agent can do based on who's talking to it or which channel the message came from. No equivalent to netclaw's [four-layer security model](/architecture/security-model/#four-layers-not-one) or [approval gates](/architecture/security-model/#human-in-the-loop-as-a-layer-not-a-crutch).

For personal use on your own machine, this is probably fine. For team or organizational deployment, where multiple people with different levels of access interact with the same agent, it's a gap. netclaw's [audiences](/architecture/design-philosophy/#lightweight-access-control-without-an-identity-provider) exist precisely for this use case.

## MCP integration

Hermes Agent doesn't make [MCP](https://modelcontextprotocol.io/) central to its design. netclaw does: [progressive tool disclosure](/architecture/design-philosophy/#mcp-first-tooling), server-level and tool-level grants, OAuth for MCP servers (including pre-registered confidential clients), server prompts you can invoke as skills, and a [two-gate security model](/architecture/security-model/#mcp-security-two-gate-model) for external tool servers.

MCP is how you give non-technical users agent capabilities without shell access. It's where the ecosystem is heading. Building around it now means less retrofitting later.

## What Hermes Agent does better

The autonomous learning loop is genuinely innovative. It reduces operator toil: the agent gets better at its job without you managing skill inventories.

Hermes also has strong research backing from Nous Research, and their model alignment work is excellent. Small model performance is comparable to netclaw's.

If you want an agent that actively improves itself with minimal human intervention and you're comfortable with the tradeoffs, Hermes is purpose-built for that.

## Who should choose which

**Choose Hermes Agent if** you want autonomous self-improvement, trust the agent to manage its own skill lifecycle, and prefer minimal operator involvement in capability management.

**Choose netclaw** for human control over agent capabilities, [audience-scoped security](/architecture/security-model/#audience-as-the-trust-primitive), MCP-first tooling, and a smaller codebase where you can see exactly what the agent is doing and why.

## Related pages

- [Design philosophy](/architecture/design-philosophy/) - why simplicity and human control matter
- [Security architecture](/architecture/security-model/) - audience dispositions and approval gates
- [Skills overview](/skills/overview/) - how netclaw's curated skill system works
- [Memory model](/architecture/memory-model/) - netclaw's approach to automatic memory

## Resources

- [Hermes Agent](https://hermes-agent.nousresearch.com/) - Nous Research's autonomous agent
- [Nous Portal model API](https://portal.nousresearch.com/models) - Nous Research's inference API
- [Nous Research API pricing](https://pricepertoken.com/pricing-page/provider/nousresearch) - 20 models, $0.02 to $1.00 per million input tokens
- [Nous Research on OpenRouter](https://openrouter.ai/nousresearch) - API access via OpenRouter
