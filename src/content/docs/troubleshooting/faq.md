---
title: "FAQ"
description: "Short answers to the questions people ask first about netclaw: approvals, safety, cost, models, teams, backups, upgrades and what isn't supported yet."
---

Each answer is two to five sentences and links to the page that owns the detail. Where the honest answer is "not yet", it says so.

## Approvals and safety

### How do I stop it asking me to approve things?

Answer with **Always here** or **Always anywhere** instead of **Once**, and the grant is saved. To cover a command before it's asked, use `netclaw approvals trust-verb`. To stop shell prompts entirely on a solo install, set `Tools.AudienceProfiles.Personal.ApprovalPolicy.ToolOverrides.shell_execute` to `"Auto"`. `DefaultMode: "Auto"` alone doesn't cover shell. See [Reduce or turn off approval prompts](/guides/reduce-approval-prompts/).

### Is it safe to turn approvals off?

On a machine you own, with only you talking to it, the risk is what the model might run as your user. Hard-deny rules (`sudo`, `rm -rf /`, fork bombs), the protection of netclaw's own config, keys and database, and the denial of credential folders like `~/.ssh` still apply in `Auto`. Don't do it for Team or Public audiences, and prefer a container or a separate OS user when the host holds anything you care about. See [How tool approvals work](/security/approvals/#what-never-runs-whatever-you-answer).

### What does netclaw protect, and what doesn't it?

It protects its own control plane (secrets, keys, the database, config writes), denies agent tools a fixed list of credential locations (`~/.ssh`, `~/.aws`, `~/.netrc` and a few more), gates tool calls by audience and approval mode, masks well-known token formats and secret-named variables in tool output, and checks inbound channel messages for prompt injection. It isn't a sandbox. Anything else your OS user can read, the agent can, such as a project's `.env` file, and an **Always** grant for `bash` or `python3` lets it run code that opens files the command line never names. There's no kernel sandbox for shell commands yet, tracked in [netclaw#2343](https://github.com/netclaw-dev/netclaw/issues/2343). See [Security model](/security/security-model/#what-netclaw-doesnt-protect-against).

### Are skills scanned for malicious content?

No. Skill content scanning is disabled, so a skill from an external source or a skill server is trusted as written. Prompt-injection detection does still run on inbound channel messages. Read a skill before you install it, and see the tracking issue, [netclaw#976](https://github.com/netclaw-dev/netclaw/issues/976). See [Skills overview](/skills/overview/).

## Models and cost

### What does it cost to run, and how do I see usage?

netclaw itself is free to run, and you pay your model provider. `netclaw stats` shows tokens in and out since the daemon started (`--days N` adds a daily breakdown), turns and sessions, and headless `netclaw chat -p` prints a `[usage]` line per reply. There are no spend caps, token budgets, per-user quotas or dollar totals, so set limits at the provider, such as an OpenRouter key limit or a console spend cap. Nothing bounds a long productive turn except deadlines and cancellation. The loop guard refuses repeated identical calls and stops a failure streak, but `Session.MaxToolIterationsPerTurn` no longer limits a turn, and a turn that does new work each round can run past 60 rounds. A hosted API with no `MaxOutputTokens` set gets a 32000-token output limit per call, so cost per call can be higher than a short cap would suggest. See [Usage and cost](/configuration/models/#usage-and-cost) and [`netclaw stats`](/cli/stats/).

### Which model should I use?

netclaw needs reliable tool calling and a context window of at least 32k, because the first turn alone sends about 10,000 tokens. Use the best tool-calling model you can afford as Main, and add a smaller Compaction model and a Fallback from a different provider only if you need them. There's no published minimum local model. Qwen3.8 27B at Q4 on llama.cpp ran tool calls and image inspection in our tests. See [Choosing a model](/configuration/models/#choosing-a-model).

### Can it run fully offline with local models?

The model side, yes: point it at Ollama, llama.cpp or vLLM. Three things still reach the network by default. The daemon downloads two embedding models (about 130 MB) from `huggingface.co` on first start, it checks `releases.netclaw.dev` for a new version at startup and periodically, and it looks up model capabilities from OpenRouter and Hugging Face when your server doesn't report them. We watched a fresh daemon with a local provider request exactly the first two. Copy the embedding models in and set `Memory.Embeddings.AutoDownload` to `false`, or turn embeddings off. A failed update check is logged and ignored. There's no setting to switch the update check off. System skills are embedded in the binary, and a skill server, web search and MCP servers only connect if you configure them. See [Run offline](/configuration/memory/#run-offline).

### How much memory and CPU does it need?

Plan for about 800 MB. In Docker, the daemon idled at about 485 MiB with embeddings on and about 220 MiB with them off, after a first minute and a half near 300 MiB. A 512 MiB limit gets the daemon OOM-killed over and over while the container still shows `running`, and 768 MiB is stable, so set 1 GiB or more. The binaries are self-contained, 160 MB on disk, plus about 130 MB of embedding models. There's no CPU sizing guidance beyond that. One user hit a crash in the embedding runtime on a Xeon E5 v3 in a Windows VM ([netclaw#2245](https://github.com/netclaw-dev/netclaw/issues/2245)). Turning embeddings off stops the daemon loading that runtime, but we haven't verified it on that hardware. See [Memory and first start](/deployment/docker/#memory-and-first-start).

### Can it run behind a corporate proxy or with a private CA?

Yes for the proxy, and we checked both halves. We pointed `HTTP_PROXY` and `HTTPS_PROXY` at a logging proxy in front of the daemon, and its model-server request, its model-capability lookup on `openrouter.ai`, the embedding download from `huggingface.co` and the update check on `releases.netclaw.dev` all went through it. The CLI honors the same variables plus `NO_PROXY`, `SSL_CERT_FILE` and `SSL_CERT_DIR`: with a dead proxy `netclaw model discover` failed with `Connection refused`, and with empty certificate paths it failed with `The SSL connection could not be established`. Only the CLI's calls to the local daemon skip the proxy.

We didn't test the Slack and Discord socket connections or a private CA on the daemon side, and netclaw doesn't publish an outbound allow-list. The hostnames the daemon contacted in our run were your model server, `openrouter.ai`, `huggingface.co` and `releases.netclaw.dev`, plus whatever channel, search or MCP endpoints you configure.

## Platforms

### Can it run on macOS and Windows, and as a background service there?

It runs on both, and there's no background service on either. macOS needs Apple Silicon, and Windows is x64 only. Start the daemon with `netclaw daemon start` after each reboot. It detaches from the terminal but doesn't come back by itself. The Linux systemd user unit is the only service. See [Installation](/getting-started/installation/#requirements) and [systemd](/deployment/systemd/#not-on-linux).

### Does it support Microsoft Teams?

Not shipped. The channels are Slack, Discord and Mattermost, plus the terminal. Teams support is requested in [netclaw#1401](https://github.com/netclaw-dev/netclaw/issues/1401), which is open. See [Channels](/channels/slack/).

### Are there plugins or a marketplace?

Not shipped. There's no `netclaw plugin` command and no public skill marketplace. You extend netclaw with skills, subagents and MCP servers, and an organization can distribute skills and subagents from its own [skill server](/skills/skill-server/). An extension API is requested in [netclaw#2017](https://github.com/netclaw-dev/netclaw/issues/2017). See [Skills overview](/skills/overview/) and [MCP servers](/configuration/mcp-servers/).

### Can I build my own client against the daemon?

There's no public API reference, and no stability promise for the interface. The daemon exposes a SignalR hub at `/hub/session` (the one the CLI uses) and REST endpoints under `/api/`, and devices authenticate by [pairing](/guides/pairing-remote-devices/). The hub contract is described only in the product repo's internal spec, [SPEC-011](https://github.com/netclaw-dev/netclaw/blob/dev/docs/spec/SPEC-011-daemon-architecture.md), which can lag the code. The maintainers' answer to an extension API is open in [netclaw#2017](https://github.com/netclaw-dev/netclaw/issues/2017). For scripting, `netclaw chat -p --json` is the supported route. See [Scripting headless sessions](/guides/scripting-sessions/).

## Running it for other people

### How do I set it up for a team instead of just me?

There's no single walkthrough. The pieces are: pick a Team or Public [posture](/security/security-model/#deployment-postures) in `netclaw init`, then connect a channel and restrict it with allow-lists. Give each channel an audience with `ChannelAudiences`, and decide which tools each audience gets. Everyone in an allowed channel shares that channel's audience, because netclaw has no per-user identity inside a channel. See [Security model](/security/security-model/#trust-audiences), the [Slack](/channels/slack/#audience-overrides), [Discord](/channels/discord/) and [Mattermost](/channels/mattermost/) pages, [MCP tool permissions](/guides/mcp-tool-permissions/) and [Hardening](/security/hardening/).

### How do I give it access to my repo or files?

On a Personal audience the agent can already read and write any path your user can, except netclaw's protected ones, so tell it the project directory and it calls `set_working_directory`. Team sessions read only their session folder plus `GlobalReadRoots`, and write only their session folder. Add a folder to `GlobalReadRoots`, or set `ReadFiles` and `WriteFiles` roots for the audience. A list you set replaces the defaults, so copy them. See [File access](/guides/unattended-runs/#file-access).

## Operating it

### How do I back it up or move it?

Stop the daemon, copy the whole data directory including `keys/` (without it `secrets.json` can't be read) and start it again. You can also back up live, using SQLite's online backup for `netclaw.db`. Restoring at a different path needs no fix. The daemon maps stored session paths onto the new data directory. See [Back up, restore and move netclaw](/guides/backup-and-restore/).

### How do I upgrade, and can I roll back?

On a host, `netclaw update`. In Docker, pull the new tag and recreate the container. Upgrading is forward-only. A newer version migrates the database, and an older binary can't safely read it. After 0.28, never start 0.27.1 or older on the database. Upgrade while no turn or sub-agent is running, copy `netclaw.db` first, and roll back by restoring that copy. See [Upgrade netclaw](/guides/upgrading/#upgrade-from-0271-to-028) and [`netclaw update`](/cli/update/).

### How do I see what it did and why?

netclaw has no separate audit store. The daemon log records every tool decision, and each session has its own log. `netclaw sessions` lists sessions and lets you resume one, `netclaw reminder history <id>` gives a reminder's session ID, and `netclaw stats` shows usage. To see why a call prompted or was denied, grep the daemon log for `Tool authorization`. See [Troubleshooting by symptom](/troubleshooting/common-problems/#start-here), [`netclaw sessions`](/cli/sessions/) and [OpenTelemetry](/observability/opentelemetry/).

### How do I fix a wrong memory?

Ask the agent to find it with `find_memories`, then to correct it with `update_memory`. To delete, say "use update_memory with delete set to true". A model that wasn't told about the flag once overwrote the body with "DELETED", and the memory stayed recallable. There's no CLI to list or edit memories. See [Fix a wrong memory](/configuration/memory/#fix-a-wrong-memory).

## Related pages

- [Troubleshooting by symptom](/troubleshooting/common-problems/): error text, cause and fix
- [Glossary](/reference/glossary/): audience, posture, grant and the other terms
- [Security model](/security/security-model/): what netclaw enforces and where a sandbox begins
- [Quickstart](/getting-started/quickstart/): install and a first message
- [Configuration reference](/configuration/reference/): every key in `netclaw.json`

## Resources

- [netclaw releases](https://github.com/netclaw-dev/netclaw/releases): release notes, including known issues
- [netclaw discussions](https://github.com/netclaw-dev/netclaw/discussions): ask a question that isn't here
- [.NET proxy environment variables](https://learn.microsoft.com/en-us/dotnet/api/system.net.http.httpclient.defaultproxy): how .NET picks up `HTTPS_PROXY` and `NO_PROXY`
