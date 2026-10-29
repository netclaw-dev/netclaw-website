---
title: "Glossary"
description: "Plain-language definitions of the terms netclaw's docs use, from audience and posture to compaction and skill feed, each linked to the page that explains it."
---

Look up a term here, then follow the link for the detail. Terms are grouped by topic, and each definition matches how the linked page uses it.

## Security and access

| Term | Meaning |
|------|---------|
| **Audience** | Who a message is treated as coming from: Personal, Team or Public. netclaw resolves it for each message from the channel or source, and it decides which tools, files and saved grants apply. It isn't a trust level you assign to a person. `Tools.AudienceProfiles` is the config object that holds each audience's tool and file settings. See [Security model](/security/security-model/#trust-audiences). |
| **Posture** | A deployment-wide choice you make once in `netclaw init`: Personal, Team or Public. It sets the shell default (on only for Personal) and caps the audience of every turn and child run, so a channel mapped to Personal under a Team posture runs as Team. See [Deployment postures](/security/security-model/#deployment-postures). |
| **Exposure mode** | How the daemon is reachable over the network: `local`, a reverse proxy, Tailscale Serve, Tailscale Funnel or a Cloudflare Tunnel. `local` is the default. See [Exposure modes](/deployment/exposure-modes/). |
| **Approval** | The decision about whether a tool call runs. A tool's mode is `Auto`, `Approval` or `Deny`, and a call ends as allowed, requires approval, requires correction or denied. See [How tool approvals work](/security/approvals/). |
| **Approval prompt** | The question netclaw asks when a call needs approval, with up to six answers: Once, This chat, Always here, This repository, Always anywhere and Deny. It never times out. See [What each answer does](/security/approvals/#what-each-answer-does). |
| **Saved grant** | An answer of **Always here**, **This repository** or **Always anywhere**, kept in `tool-approvals.json`. It matches a command phrase, a scope (a folder, a repository or anywhere) and an audience. A **This chat** answer is a chat grant instead: it lives in memory for one session. See [`netclaw approvals`](/cli/approvals/). |
| **Trust-verb** | The `netclaw approvals trust-verb` command, which saves a grant for a command phrase such as `git push` before anything asks. See [`netclaw approvals`](/cli/approvals/#trust-verb). |
| **Hard deny** | A rule that blocks a call in every mode, including `Auto`: `sudo`, `rm -rf /`, fork bombs and your own `Tools.HardDenyPatterns`. No answer overrides it. See [Hardening](/security/hardening/). |
| **Reviewed-safe catalog** | A built-in list of read-only commands such as `ls`, `cat`, `grep` and `git status` that run without a prompt. It never includes `git push`, `rm` or `curl`, and you can't extend it. See [What never prompts](/security/approvals/#what-never-prompts). |
| **Control plane** | What netclaw protects from the agent: encryption keys, `secrets.json`, webhook route secrets, the database, lifecycle files and writes to the config directory. Everything else your OS user can read, the agent can read, apart from the credential locations below. See [What netclaw doesn't protect against](/security/security-model/#what-netclaw-doesnt-protect-against). |
| **Credential location** | A folder or file where other tools keep credentials, denied to the agent's file and shell tools: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.azure`, `~/.config/gh`, `~/.config/gcloud`, `~/.docker/config.json`, `~/.netrc` and `~/.git-credentials`. No approval or override lifts the denial. See [Credential locations](/security/security-model/#credential-locations). |
| **Boundary label** | The `boundary:` value recorded on a reminder, memory or session: `boundary:personal`, `boundary:team`, `boundary:public` or `boundary:trusted-instance`. It must be one the audience allows. It isn't a network or architecture boundary, and it isn't the folder check the path policy runs. See [Reminder schema](/configuration/reminders/#reminder-definition-schema). |
| **Secrets** | Credentials in `secrets.json`, encrypted with keys in `keys/`. Written with `netclaw secrets set`. See [Secrets](/security/secrets/). |
| **Pairing** | Linking a CLI on another machine to the daemon: you generate a short-lived code on the daemon host, and the device exchanges it for a bearer token. See [Use the CLI from another machine](/guides/pairing-remote-devices/). |

## Sessions and runs

| Term | Meaning |
|------|---------|
| **Session** | One conversation: a CLI chat, a Slack, Discord or Mattermost thread, a reminder run or a webhook delivery. Each maps to one persistent actor and its own folder. See [Sessions](/architecture/sessions/). |
| **Turn** | One round of work after an input arrives: model calls and tool calls until the model finishes, a repeat guard stops it, a watchdog times it out, a reply is cut off at the output limit, or a person ends an automation turn. A session runs one turn at a time. See [What ends or stalls a turn](/architecture/sessions/#what-ends-or-stalls-a-turn). |
| **Compaction** | Shrinking a session's history when the context window fills. Older messages are summarized, and a background model call writes compaction notes about what was dropped. See [Compaction](/architecture/sessions/#compaction). |
| **Unattended run** | A reminder, webhook or `netclaw chat -p` run with nobody present to answer a prompt. A call that would prompt is denied with `approval_required_unattended`, unless a saved grant or `Auto` covers it. See [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/). |
| **Reminder** | A scheduled prompt netclaw runs on its own: one-shot, interval or cron. It carries its own audience and boundary. A run ends `ok`, `failed` or `denied`. `denied` means a tool call was refused, such as an approval nobody could answer, and it raises a `reminder.tool_denied` alert. A one-shot that has run stays listed as `completed` for 12 days. See [Reminders](/configuration/reminders/). |
| **Webhook route** | A JSON file in `config/webhooks/` that maps `POST /api/webhooks/<route>` to a prompt, with signature verification and event filters. See [Webhooks](/configuration/webhooks/). |
| **Thinking level** | How much reasoning a model does before it answers: `off`, `low`, `medium`, `high` or `max`. Set it per model definition. See [Output limit and thinking level](/configuration/models/#output-limit-and-thinking-level). |
| **Thinking dialect** | How netclaw sends a thinking level to a provider: `ChatTemplateKwargs`, `ReasoningEffort`, `DeepSeek` or `None`. An `openai-compatible` provider sets it in `VendorOptions:ThinkingDialect`. |
| **Automation turn** | A turn started by a reminder, job result, webhook or approval notice rather than by a person. A message from the operator or a trusted person ends it. |
| **Background job** | A shell command started with `shell_execute` in background mode. It belongs to the session that started it and doesn't survive a daemon restart. See [Background jobs](/reference/tools/#background-jobs). |
| **Daemon** | The long-running `netclawd` process that owns sessions, channels, memory and tools. The `netclaw` CLI talks to it. See [Architecture overview](/architecture/overview/). |
| **Channel** | A way into netclaw: the terminal, Slack, Discord or Mattermost. See [Channel troubleshooting](/channels/troubleshooting/). |
| **Gateway** | Three unrelated things. In netclaw's architecture it's the edge component that receives a transport event, runs the audience and allow-list checks and hands the message to a session. Discord's Gateway is the WebSocket API the Discord channel connects to. And a cloud gateway such as Azure AI Foundry is an OpenAI-compatible endpoint you point a provider at. See [Architecture overview](/architecture/overview/). |
| **Data directory** | Everything netclaw owns on disk, in `~/.netclaw` or `$NETCLAW_HOME`: config, sessions, database, keys, models and logs. See [Data directory layout](/reference/data-directory/). |
| **Data retention** | How long the daemon keeps its own daemon and crash logs before deleting them: `Retention.Logs.Days`, 14 by default, `0` to keep them forever. It never deletes session logs or session data. See [Data retention](/configuration/data-retention/). |
| **Config on disk not applied** | The `netclaw status` line, with overall `degraded`, that appears when `netclaw.json` has an invalid `Models` or provider section. The running daemon keeps its previous configuration until you fix the file. See [Troubleshooting by symptom](/troubleshooting/common-problems/#config-on-disk-not-applied). |

## Models

| Term | Meaning |
|------|---------|
| **Provider** | A configured connection to a model service, such as Anthropic, OpenRouter, Ollama or an OpenAI-compatible server, with its endpoint and key. See [`netclaw provider`](/cli/provider/). |
| **Model definition** | A named entry under `Models.Definitions` that pairs a provider with a model ID and optional overrides for context window, modalities, output limit (`MaxOutputTokens`) and thinking level (`Thinking`). See [Definitions and roles](/configuration/models/#definitions-and-roles). |
| **Model role** | A job a model definition fills: Main for every turn, Fallback when Main fails, Compaction for summaries, titles and memory extraction. See [Definitions and roles](/configuration/models/#definitions-and-roles). |
| **Context window** | How many tokens the model can take in one request. netclaw detects it from the provider, and you can pin it. See [Context window and modalities](/configuration/models/#context-window-and-modalities). |

## Memory

| Term | Meaning |
|------|---------|
| **Memory** | What netclaw keeps from past conversations in `netclaw.db`, formed in the background and recalled before each turn. See [Memory model](/architecture/memory-model/). |
| **Memory observer** | The per-session background actor that watches the transcript and distills it into memory proposals when the session goes idle, every few turns and at shutdown. Distillation is what it does, not a separate component. See [Memory model](/architecture/memory-model/#how-memories-form). |
| **Curation** | The stage that checks each proposal before it's written: rules first, then a model call only when a proposal looks like a near-duplicate. The step after the [checkpoint queue](#memory). See [Memory model](/architecture/memory-model/). |
| **Embeddings** | Vector representations of memories, made by two small ONNX models that run inside the daemon. They let recall match meaning, not just words. See [Memory and embeddings](/configuration/memory/). |
| **Recall** | Looking up stored memories. Automatic recall injects the relevant ones before a turn, and the agent can also search with `find_memories`. See [Memory model](/architecture/memory-model/). |
| **Memory checkpoint** | A queued record in the `memory_checkpoints` table that a session produced something worth curating into memory. A backlog of pending checkpoints shows up in `netclaw doctor`. See [`netclaw doctor`](/cli/doctor/). |

## Skills and subagents

| Term | Meaning |
|------|---------|
| **Skill** | A folder with a `SKILL.md` file that teaches the agent a procedure, loaded on demand. See [Skills overview](/skills/overview/). |
| **System skill** | One of the nine skills embedded in the binary, such as `netclaw-operations`. It beats a same-named skill you add. See [System skills](/skills/overview/#system-skills). |
| **Skill server** | A self-hosted registry that serves skills and subagents to every netclaw instance in an organization. See [Skill server](/skills/skill-server/). |
| **Skill feed** | A subscription from the daemon to a skill server, set in `SkillFeeds`. The daemon syncs it and verifies each download. See [Skill feeds](/skills/skill-feeds/). |
| **Native manifest** | A skill server's versioned `/manifest.json`, which carries subagents. Skills come from the vendor-neutral RFC index instead. See [Native manifest](/skills/native-manifest/). |
| **Subagent** | A child agent a session spawns for bounded work such as research, defined as a markdown file in `~/.netclaw/agents/`. `spawn_agent` returns a run ID at once and the child works in the background. The parent gets one notice in a later turn and reads the child's `result.md`. See [Custom subagents](/skills/custom-subagents/). |
| **MCP server** | An external tool server that netclaw connects to over the Model Context Protocol. Its tools get their own approval modes. See [MCP servers](/configuration/mcp-servers/). |

## Which name to use

The docs use these names, and the table says what else you'll see in product output.

| Use | Meaning | Also seen as |
|-----|---------|--------------|
| audience | Personal, Team or Public. Never "trust audience" or "trust level" | `TrustAudience` in code. `shell_requires_personal_context` in a deny reason |
| audience profile | Only the `Tools.AudienceProfiles` config object | |
| approval mode | `Auto`, `Approval` or `Deny` for a tool | "consent mode" in the engineering spec. The key is `ApprovalPolicy` |
| saved grant | An **Always** answer kept in `tool-approvals.json` | "stored grants" in `netclaw doctor` output, "persistent grant" in the engineering spec |
| chat grant | A **This chat** answer, kept in memory for the session | |
| subagent | A child agent a session spawns | `SubAgents` is the config section. `sub-agent` appears in `skillserver` output and some daemon log lines |
| skill server | A running server that publishes skills and subagents | `SkillServer` names the software, its container image and `SKILLSERVER_*` variables. `skillserver` is its CLI |
| skill feed | One `SkillFeeds` entry that points a daemon at a skill server | |
| memory observer | The per-session actor that distills memory proposals | `memory-observer` in logs. "sidecar" in code names and in `Session.SidecarLlmTimeoutSeconds`, which covers the background model calls: titles, memory distillation and compaction notes |
| curation | Rules plus an occasional model call before a proposal is written | "Memory Curation LLM" in `netclaw doctor` |
| `sidecar=` | The subagent pass of a skill sync (`complete`, `absent`, `failed`, `not-run`) | Unrelated to the memory observer |

## Related pages

- [FAQ](/troubleshooting/faq/): short answers that use these terms
- [Troubleshooting by symptom](/troubleshooting/common-problems/): error text, cause and fix
- [Security model](/security/security-model/): audiences, postures and what netclaw enforces
- [Architecture overview](/architecture/overview/): how the daemon, sessions and channels fit together
- [Configuration reference](/configuration/reference/): every key in `netclaw.json`

## Resources

- [Model Context Protocol](https://modelcontextprotocol.io/): the protocol behind MCP servers
- [Agent Skills](https://agentskills.io): the `SKILL.md` format
- [Cloudflare Agent Skills Discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc): the index format skill feeds read
