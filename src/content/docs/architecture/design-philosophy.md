---
title: "Design philosophy"
description: "Why netclaw exists, what we believe about agents, and the tradeoffs we chose."
---

We built netclaw because we disagreed with the direction every other open-source agent project was heading. [OpenClaw](https://openclaw.ai/) (the most popular open-source personal AI assistant, 360K+ GitHub stars, dozens of platform integrations) and [Hermes Agent](https://hermes-agent.nousresearch.com/) (Nous Research's autonomous agent with a self-improving skill system) proved the category and inspired this project. We respect the hell out of what they've built. But we think their philosophies are bad for their projects long-term, and that's why we built something new.

## Simplicity is a feature

[Petabridge](https://petabridge.com/) has maintained [Akka.NET](https://getakka.net/) since 2014. A decade of shepherding a large open-source framework through breaking changes, security patches, and community demands taught us one thing: **the biggest threat to any project is its own complexity.**

Every feature you add is a feature you have to maintain, test, secure, and explain. The most productive thing a maintainer can do is say no. Most agent projects treat feature count and velocity as proof of progress: hundreds of PRs per release, thousands of community integrations, autonomous skill lifecycle management. We think that's antithetical to how you should build software.

The codebase is deliberately small. So is the configuration footprint. When we're tempted to add a feature, the first question is always: can this live in an MCP server someone else maintains instead?

### What we don't build

You'll probably never see voice mode in netclaw. That's a property of the model you're using and something your operating system will handle natively. We don't build web dashboards for daily interaction. Your chat app already has auth, threading, mobile apps, notifications, and search. We don't build an autonomous skill lifecycle that generates, scores, archives, and rewrites skills without human oversight. The agent has a tool to create and edit skills, but nothing in netclaw curates them behind your back.

A feature we never build can't break, can't have a CVE, and can't confuse your deployment.

## Chat-first interaction

Your chat app is the interface. Slack, Discord, Mattermost, whatever your team already uses. Every thread you spin up with the agent is its own session: reentrant (pick up where you left off), persisted to disk, and recoverable across daemon restarts. The agent doesn't need its own UI because it lives where your team already works.

At the session layer, the source of a message is irrelevant. Slack, a webhook, a scheduled timer, a CLI chat: they all produce the same kind of message routed to the same kind of [actor](https://en.wikipedia.org/wiki/Actor_model). The [architecture overview](/architecture/overview/#everything-is-just-input) covers how this works mechanically, but the philosophy is simple. The agent shouldn't care how you talk to it, and you shouldn't have to learn a new interface to use it.

This means adding a new channel, whether Signal or a web UI for remote management, never touches session logic. The codebase stays small because the transport layer is someone else's problem.

## Default-deny security

Giving an LLM shell access and tool-calling ability is giving it the keys to your infrastructure. The question isn't whether something will go wrong, it's what happens when it does.

Most agent frameworks start permissive and add restrictions after security incidents. This project works the other way around. During [`netclaw init`](/cli/init/), you choose an [audience](/architecture/security-model/#audience-as-the-trust-primitive) (Personal, Team, or Public) and that choice sets the baseline for what the agent can do. Some common operations are allowed by default, but anything potentially destructive requires explicit approval. You can approve a tool call for the current session or persistently, and the agent makes the distinction clear with a structured approval prompt in the TUI or in your chat channel.

![Netclaw Setup, Step 3 of 5, Security Posture, offering Personal, Team and Public](/screenshots/output/init-02-security-posture.png)

The choice is made once, in the third step of setup.

This is the [principle of least privilege](https://csrc.nist.gov/glossary/term/least_privilege) applied to an LLM agent.

When something fails or is misconfigured, it fails loudly. Fallbacks hide bugs, and on security-relevant paths they can silently escalate privileges. Inbound message checks run in the [gateway boundary](/architecture/overview/#three-boundaries) before messages ever reach the session layer. The security model stacks four independent layers (hard denies, path restrictions, audience-scoped grants, and human approval gates) so no single check is the only thing between the agent and a destructive action. The [security architecture](/architecture/security-model/) covers the full stack.

### Determinism boundaries

Traditional service architecture thinks in terms of service boundaries. Agent architecture needs to think in terms of **determinism boundaries**: where is it safe for an LLM to operate non-deterministically, and where isn't it?

LLMs are inherently non-deterministic: same input, different output, every time. That's fine for research, summarization, and conversation. It's not fine for `git push --force` or deleting a database.

The operating principle is **reversibility**. If the agent is about to perform an action that can't be undone, that action needs a deterministic gate, an [approval prompt](/architecture/security-model/#human-in-the-loop-as-a-layer-not-a-crutch) where a human confirms intent. If you want to [turn those gates off](/guides/reduce-approval-prompts/), that's your decision. You live with the consequences.

## Lightweight access control without an identity provider

The real-world use case that drove this: a bot in a team Slack channel that can answer questions about live service status for anyone, but only operators (the IT folks) can trigger high-privilege actions like exporting log dumps or restarting services.

Traditional role-based access control solves this, but it requires a fully managed identity provider, something most self-hosted deployments don't have and shouldn't need. To keep netclaw simple and self-hostable, we distilled two lightweight primitives that are adjacent to RBAC without the infrastructure dependency:

1. **Audience dispositions** classify trust by deployment topology and channel type. Personal (you at your machine), Team (your Slack, Discord or Mattermost workspace), or Public (untrusted sources). The disposition determines what tools are visible, what memory is accessible, and whether approval gates are active.

2. **Listing owners** are the specific user IDs in each channel who actually operate the bot. They get elevated trust within their audience tier.

| Audience | Trust | Typical source |
|----------|-------|----------------|
| **Personal** | Full access | Local TUI, operator at the machine |
| **Team** | Scoped access | Slack, Discord or Mattermost workspace |
| **Public** | Minimal access | Unknown or untrusted channels |

In [`netclaw config`](/cli/config/), you assign each connected channel to an audience tier. The same Slack workspace can have DMs classified as Personal and a shared ops channel classified as Team:

![netclaw config Channels & Permissions screen for Mattermost, listing the Assistant and Ops Room channels as Team, Lunch as Public and direct messages as Personal](/screenshots/output/config-channel-audiences.png)

The screen is Mattermost's, and Slack and Discord use the same layout. Left and right set a channel's audience, and a public lunch channel can sit next to a team ops room.

We're not claiming this beats RBAC. It's a pragmatic simplification that lets you deploy an agent with meaningful access control today, on your own hardware, without standing up Entra or Okta first. Every other security decision flows from the audience. See [audience scoping](/architecture/security-model/#audience-as-the-trust-primitive) for how it works in practice.

## MCP-first tooling

LLMs calling command-line tools is powerful and composable, especially when those tools are in the model's training data or expose their own help documentation. But shell access is where the security problems come from. Agents deleting production databases, sending unauthorized emails, running destructive commands: that's shell territory.

For operators and developers, shell access makes sense. netclaw supports it with strong [approval gates](/architecture/security-model/#human-in-the-loop-as-a-layer-not-a-crutch) that extract verb-chains from commands (so approving `git push` covers `git push origin main`) and make shell access as safe as possible.

But for everyone else in an organization? Shell access is a non-starter. The accounting team isn't going to install the Google Cloud CLI on a sandboxed VM over SSH, and shouldn't have to.

[MCP](https://modelcontextprotocol.io/) solves this. It lets you deploy agents that connect to remote tool servers with scoped permissions: read-only access to your CRM, delegated service accounts for cloud resources, controlled access to internal APIs. The agent gets purpose-built tools without shell exposure, and every tool call goes through the same [approval gates](/architecture/security-model/#mcp-security-two-gate-model) as shell commands.

What makes MCP work at scale is [progressive tool disclosure](/architecture/overview/#tool-system). The agent sees server-level summaries (browser tools, CRM tools, and so on) and loads specific tools on demand. This keeps the prompt small and prevents the model from misfiring on similarly named tools across servers.

If an MCP server definition changes and new tools appear, operators can set the default approval status for unknown tools: auto-deny, auto-approve, or require human confirmation. MCP provides a deterministic security boundary that shell calling fundamentally cannot.

The use cases that benefit most have nothing to do with coding: generating invoices, updating a CRM, triaging support tickets, syncing project management tools. MCP is how you give non-technical team members the benefits of an agent without the risks of shell access.

## Small models are enough

Most agent platforms assume frontier models. OpenClaw's documentation recommends using "the strongest latest-generation model available," which in practice means 70B+ parameter models or paid API access to GPT-4, Claude, or similar. That means your data leaves your network.

We think that's the wrong default. If your agent is working deals in a CRM, responding to GitHub webhooks, generating invoices, or triaging support tickets, you don't need a frontier model at $10 per million input tokens.

netclaw runs production workloads on [Qwen 3.6 27B](https://huggingface.co/Qwen/Qwen3.6-27B). We've tested with models as small as Qwen 3.5 9B and gotten reliable tool-calling results. The architecture is designed to make this work:

Progressive tool disclosure cuts the noise in the prompt, so smaller models can navigate tool graphs without misfiring. Compressed skill and tool indexes keep the system prompt lean, and server-first MCP discovery means the model picks "which server" before it ever sees individual tool definitions. That's a much simpler decision space.

There's an economic argument here too. A $3,000 GPU with 64GB VRAM runs local inference indefinitely: bounded capital expenditure instead of unbounded API billing. Local inference also means your data never leaves your infrastructure, which matters when the agent handles contracts, financials, or internal communications. [Self-hosted providers](/configuration/self-hosted-providers/) covers the setup.

For tasks that genuinely need frontier capabilities, like complex agentic coding or multi-step research across large codebases, netclaw delegates to tools like [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) or [OpenCode](https://opencode.ai/) in headless mode via skills. Use your existing subscriptions for frontier work. Use local models for everything else.

## Automatic memory formation

Agents that forget everything between conversations aren't useful for real work. But agents that require users to manually save context don't get used either.

netclaw forms memories automatically. A per-session memory observer watches the conversation and, when the session goes idle or every few turns, distills key facts, decisions, and project context into durable memory. That's a background call that never sits inside your turn. A curation pipeline validates proposals, deduplicates against existing memories, blocks secret content, and persists what survives to SQLite.

Before each turn, in any session, netclaw recalls the memories that bear on what you just said. It combines full-text search with semantic search that runs on your own CPU, on two small ONNX models (on by default since 0.27.0). A relevance gate throws out weak matches, so most turns inject nothing, and what does get through arrives as context the model sees before it starts generating, not as a tool call. There's no external vector database, no cloud embedding service, and no third party in the recall path. The one network touch is a model download from huggingface.co on first start, and you can [pre-provision the files](/configuration/memory/#run-offline) to skip it. The agent remembers that your project uses PostgreSQL, that you prefer Terraform over Pulumi, that the deploy target changed last Tuesday, because it observed those facts and stored them.

The cost is RAM. With embeddings on, the daemon sits around 480 MB at idle instead of about 235 MB, and you can [turn them off](/configuration/memory/#turn-embeddings-off) if that matters more to you than semantic recall.

This is the kind of feature that belongs in core, not in a plugin. Memory touches the session lifecycle, the compaction pipeline, the security model (public sessions get no memory access), and context assembly. Pushing it to the edges would mean every integration reimplements it badly. The [memory architecture](/architecture/memory-model/) covers the full system.

## The philosophy of no

Open-source maintainers tend to say yes too much. Every accepted contribution is a maintenance commitment. Every feature that lands in core is a feature that can't be pushed to a plugin, an MCP server, or a skill that someone else maintains.

netclaw takes the opposite approach: functionality belongs at the edges unless there's a strong reason to centralize it. Want voice mode? That's a model capability and an OS integration, not an agent framework feature. Want a custom skill marketplace? Run your own [skill feed](/skills/skill-feeds/) or [skill server](/skills/skill-server/). Want a specialized tool for your workflow? Build an MCP server and connect it.

The core stays small, and so does the surface area for bugs, CVEs, and breaking changes. When your competitors' complexity is the source of their security vulnerabilities, your simplicity is your security story.

## Related pages

- [Architecture overview](/architecture/overview/) - how these principles become a running system
- [Security architecture](/architecture/security-model/) - the four-layer security model in detail
- [Memory model](/architecture/memory-model/) - the full memory system behind the section above
- [Quickstart](/getting-started/quickstart/) - try it yourself
- [MCP tool permissions](/guides/mcp-tool-permissions/) - practical guide to scoping MCP access

## Resources

- [Actor model](https://en.wikipedia.org/wiki/Actor_model) - the concurrency model behind netclaw's session architecture
- [Akka.NET](https://getakka.net/) - the actor framework that implements it, maintained by Petabridge since 2014
- [Model Context Protocol specification](https://modelcontextprotocol.io/) - the open standard for agent tool integration
- [Principle of Least Privilege (NIST)](https://csrc.nist.gov/glossary/term/least_privilege) - the access control philosophy behind default-deny
- [OWASP LLM Top 10](https://genai.owasp.org/llm-top-10/) - the attack taxonomy netclaw's security model is designed against
