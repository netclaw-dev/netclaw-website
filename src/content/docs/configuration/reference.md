---
title: Configuration reference
description: Every netclaw.json setting with its type, default and allowed values, plus the environment variable form, precedence, validation and what restarts the daemon.
---

<!--
  The option tables below are generated. Do not edit between the GENERATED markers.
  Regenerate at each release, from the repo root, with the product repo checked out at the release tag:
    node scripts/gen-config-reference.mjs
  The script reads the JSON schema from the product repo (--schema <path> or NETCLAW_SCHEMA) and fills gaps
  from scripts/config-reference-overrides.json, which names the C# file behind each default it supplies.
  The prose in this file is hand-written. Re-check "Removed keys" and "Check a config" by hand.
-->

netclaw reads one JSON file, `netclaw.json`, plus a few overlays. This page lists every key, with its type, default and allowed values, so you can find a setting or confirm what a default is. It describes netclaw 0.28.2. A key that isn't in your file uses the default shown here, and `netclaw init` writes only the settings it asks you about.

## Where config lives

| What | Where |
|------|-------|
| Settings | `~/.netclaw/config/netclaw.json`, or `$NETCLAW_HOME/config/netclaw.json` |
| Secrets (tokens, API keys) | `config/secrets.json` beside it. Write them with [`netclaw secrets set`](/cli/secrets/) so they're encrypted |
| Webhook routes | One file each under `config/webhooks/`, not in `netclaw.json` |

The file needs `"configVersion": 1` at the top level. Everything else is a section, and the section names below are the top-level keys.

### Precedence

Later sources win:

1. Defaults compiled into netclaw (the Default column below)
2. `netclaw.json`
3. `secrets.json`
4. `NETCLAW_` environment variables

### Set a key with an environment variable

Prefix the key path with `NETCLAW_` and join the path segments with `__` (two underscores). Lists take a zero-based index per item, and a map key is just another segment.

```bash
# Daemon.Port
NETCLAW_Daemon__Port=5200

# Tools.WebFetch.HttpAllowList, an array of two hosts
NETCLAW_Tools__WebFetch__HttpAllowList__0=localhost
NETCLAW_Tools__WebFetch__HttpAllowList__1=host.docker.internal

# Slack.ChannelAudiences, a map: the channel ID is the key
NETCLAW_Slack__ChannelAudiences__C0123ABCD=team
```

In Docker Compose these go under `environment:`. Don't set the same list in the file and in the environment. A list from one source and a plain value from the other stops startup.

:::caution
Hyphens are the usual trap. A provider or model named `my-provider` gives the variable `NETCLAW_Providers__my-provider__Type`, which the daemon reads fine but bash refuses to `export` (`not a valid identifier`). Set it with `docker run -e`, a Compose `environment:` entry or `env 'NAME=value' command`. In the container image `docker exec` runs `netclaw` through `/bin/sh`, which drops hyphenated names, so `netclaw doctor` can report an inference error that the daemon doesn't have. Name things with letters and digits when you configure them from the environment.
:::

### Lists replace defaults

A list you configure is the whole list. Before 0.27.1 netclaw added your items to the built-in ones, so you couldn't narrow a grant. This applies to `AllowedTools`, the `Roots` lists, `GlobalReadRoots`, `ChannelAttachments.AllowedCategories` and `WebFetch.HttpAllowList`:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Team": { "AllowedTools": ["file_read", "file_list", "tool_output_read"] }
    }
  }
}
```

That Team profile now has three tools and nothing else. `[]` gives an empty list. A `null` or `{}` value gives an empty list and a startup warning. A value that isn't a list stops the daemon at startup with `Configuration key '...' must be a list, but it has a scalar value`. If you narrow a Public or Team list, keep `tool_output_read`, because spilled tool output tells the model to call it. `netclaw doctor` warns when it's missing.

An older list that exactly matches a default from an earlier release is treated as the current default, and `netclaw doctor --fix` deletes it so the audience follows future defaults. An older list you edited is applied as written.

### When the daemon restarts

The daemon restarts itself, after draining sessions, whenever `netclaw.json` changes. That includes `Daemon.Port`, `Daemon.Host` and `Daemon.ExposureMode`. Nothing else triggers it. A change to `secrets.json` or to an environment variable needs a manual restart: `docker restart <container>` in Docker, `systemctl --user restart netclaw` for the systemd unit, or `netclaw daemon stop` then `netclaw daemon start` natively.

### Check a config

Run `netclaw doctor` after every edit. It validates `netclaw.json` against the schema, checks `secrets.json`, and reports tool profile problems with the exact key. The daemon's check before a restart doesn't catch a malformed `Tools` list, so such a file restarts the daemon and then crashes it at startup. In Docker the entrypoint retries with a growing delay and the container keeps running while the daemon doesn't, so `docker logs <container>` shows the error.

These stop startup:

| Cause | Message starts with |
|-------|---------------------|
| A `Tools` list that isn't a list, or an invalid enum item in one | `Configuration key 'Tools...` |
| A `Persistence` section | `Persistence configuration is not supported` |
| Inline `Models.Main` mixed with `Models.Definitions` and `Models.Roles` | `Models configuration mixes legacy inline roles` |
| An unknown `Daemon.ExposureMode` or `Daemon.UpdateChannel` | `Unknown ExposureMode value` or `Unknown UpdateChannel value` |
| A `Telemetry.Otlp.Endpoint` that isn't an absolute URI | `Telemetry:Otlp:Endpoint must be an absolute URI` |
| An invalid `Models` or `Providers` section: a bad role reference, a provider with no credential or endpoint, an unknown type, a `MaxOutputTokens` that isn't below `ContextWindow`, or a `Thinking` level the provider dialect can't send | One line naming the key. The daemon exits 1, and a running daemon refuses to reload such a file and keeps its config. [Models](/configuration/models/#invalid-config) lists each case |

:::caution
`netclaw doctor` flags a key the schema doesn't list as a disallowed property, and `netclaw doctor --fix` removes it. Before it changes the file, `--fix` copies the original to `netclaw.json.removed-keys.bak` beside it (numbered if one exists), and it never removes anything under `Models` or any credential. Run `netclaw doctor --fix --dry-run` first to see the diff.
:::

### Read the tables

- A dotted path is the JSON nesting: `Memory.Recall.VectorWeight` is `{ "Memory": { "Recall": { "VectorWeight": 0.7 } } }`.
- `<name>`, `<server>` and `<audience>` stand for a key you choose or one of `Public`, `Team` and `Personal`. `[]` marks an array item.
- `unset` means the key is absent or `null` and netclaw picks the behavior described. `required` means netclaw or the schema rejects the entry without it.
- Keys marked `secret` go in `secrets.json`, not `netclaw.json`.

## Options by section

<!-- BEGIN GENERATED: config-reference (scripts/gen-config-reference.mjs). Do not edit by hand. -->

### Slack

The Slack adapter. [Set up Slack](/channels/slack/) walks through the app manifest and tokens.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Slack.Enabled` | boolean | `false` | - | Start this channel adapter. Needs the bot token in `secrets.json`. |
| `Slack.BotToken` | string (secret) | unset | - | Bot token, `xoxb-`. Lives in `secrets.json`: `netclaw secrets set Slack.BotToken <token>`. |
| `Slack.AppToken` | string (secret) | unset | - | App-level token, `xapp-`, for Socket Mode. Lives in `secrets.json`. |
| `Slack.SocketMode` | boolean | `true` | - | Connect over Slack Socket Mode. Needs the app-level token (`Slack.AppToken`). |
| `Slack.DefaultChannelId` | string (nullable) | unset | - | Default channel for messages the bot starts itself, such as reminder deliveries. It also counts as an allowed channel. |
| `Slack.DefaultChannelName` | string (nullable) | unset | - | A channel name the daemon resolves to an ID at startup when `DefaultChannelId` is unset. An unresolved name logs a warning. The `netclaw config` Slack editor deletes it and writes the ID. |
| `Slack.MentionOnly` | boolean | `true` | - | Respond in channels only when the bot is mentioned. |
| `Slack.AllowDirectMessages` | boolean | `false` | - | Accept direct messages. DMs use the audience mapped to the `dm` key in `ChannelAudiences`. |
| `Slack.MentionRequiredInDm` | boolean | `false` | - | Require a mention in DMs too. Applies only when `AllowDirectMessages` is `true`. |
| `Slack.MentionRequiredInThreadByChannel` | map of boolean | `{}` | - | Per-channel switch, keyed by channel ID. `true` requires a mention in thread replies even when the thread already has an active session. A channel with no entry doesn't. |
| `Slack.AllowedChannelIds` | array of string | `[]` | - | Channel IDs the bot responds in, in addition to `DefaultChannelId`. Messages from any other channel are denied. |
| `Slack.AllowedUserIds` | array of string | `[]` | - | User IDs allowed to talk to the bot. An empty list allows every user in an allowed channel. A listed user is treated as a trusted internal principal. |
| `Slack.ChannelAudiences` | map of string | `{}` | values: `personal`, `team`, `public` | Audience per channel, keyed by channel ID or `dm`. Unmapped channels fall back to the ACL heuristic. The audience picks the `Tools.AudienceProfiles` entry that applies. |

### Discord

The Discord adapter. [Set up Discord](/channels/discord/) covers the bot, intents and tokens.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Discord.Enabled` | boolean | `false` | - | Start this channel adapter. Needs the bot token in `secrets.json`. |
| `Discord.BotToken` | string (secret) | unset | - | Bot token. Lives in `secrets.json`: `netclaw secrets set Discord.BotToken <token>`. |
| `Discord.DefaultChannelId` | string (nullable) | unset | - | Default channel for messages the bot starts itself, such as reminder deliveries. It also counts as an allowed channel. |
| `Discord.AllowDirectMessages` | boolean | `false` | - | Accept direct messages. DMs use the audience mapped to the `dm` key in `ChannelAudiences`. |
| `Discord.MentionOnly` | boolean | `true` | - | Respond in channels only when the bot is mentioned. |
| `Discord.MentionRequiredInDm` | boolean | `false` | - | Require a mention in DMs too. Applies only when `AllowDirectMessages` is `true`. |
| `Discord.MentionRequiredInThreadByChannel` | map of boolean | `{}` | - | Per-channel switch, keyed by channel ID. `true` requires a mention in thread replies even when the thread already has an active session. A channel with no entry doesn't. |
| `Discord.AllowedChannelIds` | array of string | `[]` | - | Channel IDs the bot responds in, in addition to `DefaultChannelId`. Messages from any other channel are denied. |
| `Discord.AllowedUserIds` | array of string | `[]` | - | User IDs allowed to talk to the bot. An empty list allows every user in an allowed channel. A listed user is treated as a trusted internal principal. |
| `Discord.ChannelAudiences` | map of string | `{}` | values: `personal`, `team`, `public` | Audience per channel, keyed by channel ID or `dm`. Unmapped channels fall back to the ACL heuristic. The audience picks the `Tools.AudienceProfiles` entry that applies. |

### Mattermost

The Mattermost adapter. [Set up Mattermost](/channels/mattermost/) covers the bot account and callback URL.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Mattermost.Enabled` | boolean | `false` | - | Start this channel adapter. Needs the bot token in `secrets.json`. |
| `Mattermost.BotToken` | string (secret) | unset | - | Bot access token. Lives in `secrets.json`: `netclaw secrets set Mattermost.BotToken <token>`. |
| `Mattermost.ServerUrl` | string (nullable) | unset | - | Base URL of the Mattermost server, for example `https://mm.example.com`. |
| `Mattermost.CallbackUrl` | string (nullable) | unset | - | URL Mattermost can reach for interactive button callbacks, for example `http://netclaw-host:5199/api/mattermost/actions`. When unset, approvals fall back to text replies, except for a subagent's approval request, which needs buttons: the binding refuses it and the session withdraws it. |
| `Mattermost.DefaultChannelId` | string (nullable) | unset | - | Default channel for messages the bot starts itself, such as reminder deliveries. It also counts as an allowed channel. |
| `Mattermost.AllowDirectMessages` | boolean | `false` | - | Accept direct messages. DMs use the audience mapped to the `dm` key in `ChannelAudiences`. |
| `Mattermost.MentionOnly` | boolean | `true` | - | Respond in channels only when the bot is mentioned. |
| `Mattermost.MentionRequiredInDm` | boolean | `false` | - | Require a mention in DMs too. Applies only when `AllowDirectMessages` is `true`. |
| `Mattermost.MentionRequiredInThreadByChannel` | map of boolean | `{}` | - | Per-channel switch, keyed by channel ID. `true` requires a mention in thread replies even when the thread already has an active session. A channel with no entry doesn't. |
| `Mattermost.AllowedChannelIds` | array of string | `[]` | - | Channel IDs the bot responds in, in addition to `DefaultChannelId`. Messages from any other channel are denied. |
| `Mattermost.AllowedUserIds` | array of string | `[]` | - | User IDs allowed to talk to the bot. An empty list allows every user in an allowed channel. A listed user is treated as a trusted internal principal. |
| `Mattermost.ChannelAudiences` | map of string | `{}` | values: `personal`, `team`, `public` | Audience per channel, keyed by channel ID or `dm`. Unmapped channels fall back to the ACL heuristic. The audience picks the `Tools.AudienceProfiles` entry that applies. |

### Logging

Daemon log level and console output. Logs go to `daemon-<date>.log` under the data directory regardless of these keys, rolling into numbered segments at 10 MiB.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Logging.LogLevel.Default` | string | `"Information"` | `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`, `None` | Minimum level written to `daemon-<date>.log`. An unset or unrecognized value gives `Information`. Other keys under `Logging.LogLevel` (for example `Microsoft`) set per-category levels. |
| `Logging.Console.Enabled` | boolean | `false` | - | Also write single-line log output to the console. Docker and systemd capture it. |

### Telemetry

OpenTelemetry export. [OpenTelemetry](/observability/opentelemetry/) shows how to wire a collector.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Telemetry.Enabled` | boolean | `false` | - | Export metrics and logs over OTLP. netclaw has no tracing exporter. |
| `Telemetry.Otlp.Endpoint` | string | `"http://127.0.0.1:4317"` | - | OTLP collector base URL. Must be an absolute URI. Over HTTP/protobuf netclaw posts to `v1/logs` and `v1/metrics` under it, and reduces a full signal URL to its base. gRPC uses the URL unchanged. |

### Session

Per-conversation timeouts, compaction and memory-capture timing. The timeout keys take whole seconds, `IdleTimeout` takes `HH:mm:ss`. [Sessions](/architecture/sessions/) explains the lifecycle these keys tune.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Session.MaxToolIterationsPerTurn` | integer | `60` | 1 to 500 | Legacy key kept so existing files still load. It is validated (1 to 500) but no longer limits a turn. netclaw refuses a call that repeats the same work, and the watchdog timeouts bound the rest. |
| `Session.MemoryObserverIdleSeconds` | integer | `90` | 10 or more | Seconds of quiet before the memory observer distills the conversation into memories. |
| `Session.IdleTimeout` | string | `"01:00:00"` | - | How long a session sits idle before it saves a snapshot and passivates. Format `HH:mm:ss`. `00:00:00` disables passivation. Background jobs owned by the session are killed when it passivates. |
| `Session.TurnLlmTimeoutSeconds` | integer | `180` | 1 or more | Timeout for the main per-turn model call. Also feeds the `FirstTokenTimeoutSeconds` fallback. |
| `Session.ToolExecutionTimeoutSeconds` | integer | `90` | 1 or more | Inactivity budget per tool call. The call must produce its first result within this time and each later streamed item resets it. A stuck tool fails alone without affecting the others in the batch. Background shell jobs aren't bound by it. |
| `Session.SidecarLlmTimeoutSeconds` | integer | `90` | 1 or more | Timeout for background model calls: title generation, memory distillation and compaction notes. Raise it for slow models. |
| `Session.FirstTokenTimeoutSeconds` | integer | `600` | 10 to 1800 | Maximum silence between streamed deltas once the first one arrives. Subagent runs use it too, since agent definitions no longer carry `timeoutSeconds`. If unset, it uses `TurnLlmTimeoutSeconds` when you changed that, otherwise 600. |
| `Session.PrefillTimeoutSeconds` | integer | `1800` | 60 to 7200 | Maximum wait for the first streamed delta. Covers queue wait and prompt prefill, which can take minutes on self-hosted backends. |
| `Session.NoProgressTimeoutSeconds` | integer | `1200` | 60 to 7200 | Hard ceiling on time without a real output token. Keepalive heartbeats don't reset it, so a backend that heartbeats forever without producing a token is killed when it elapses. The value also sets the thinking cap: one model call that streams only thinking, with no answer text and no tool call, stops at three times this value. |
| `Session.CompactionThreshold` | number | `0.75` | 0.1 to 1 | Fraction of the context window that triggers compaction. Same as `Session.Tuning.CompactionThreshold`. The `Tuning` value wins when both are set. |
| `Session.SnapshotInterval` | integer | `20` | 1 or more | Turns between persistence snapshots. Same as `Session.Tuning.SnapshotInterval`. |
| `Session.KeepRecentToolResults` | integer | `3` | 0 or more | Recent tool call and result pairs kept in full when compaction clears older results. Same as `Session.Tuning.KeepRecentToolResults`. |
| `Session.MaxInlineToolResultChars` | integer | `12000` | 100 or more | Largest tool result placed inline in the conversation. For longer output the last this-many characters stay inline, the rest is dropped from the inline text, and the full output goes to a session file the model reads with `tool_output_read`. `shell_execute` has its own smaller budget of 2,000. Same as `Session.Tuning.MaxInlineToolResultChars`. |
| `Session.DiscoveredToolRetentionTurns` | integer | `3` | 0 or more | User turns a tool loaded with `load_tool` stays available. `0` makes the model load it again every turn. Same as `Session.Tuning.DiscoveredToolRetentionTurns`. |
| `Session.DiscoveredToolMaxCount` | integer | `12` | 0 or more | Most loaded deferred or MCP tools kept across turns. The oldest are evicted first. Same as `Session.Tuning.DiscoveredToolMaxCount`. |
| `Session.KeepRecentMessages` | integer | `6` | 1 or more | Recent messages kept verbatim after compaction summarizes the rest. Counts raw messages, not turn pairs. Same as `Session.Tuning.KeepRecentMessages`. |
| `Session.TitleGenerationInterval` | integer | `10` | 0 or more | Turns between session title refreshes. The title is always generated on turn 1. `0` disables refreshes. Same as `Session.Tuning.TitleGenerationInterval`. |
| `Session.DeterministicRetrievalEnabled` | boolean | `true` | - | Plan automatic memory recall deterministically on each turn. Scheduled for removal, leave it on. Same as `Session.Tuning.DeterministicRetrievalEnabled`. |
| `Session.MemoryDistillationTurnInterval` | integer | `5` | 0 or more | Same as `Session.Tuning.MemoryDistillationTurnInterval`. |
| `Session.MinimumRecallCompositeScore` | number (nullable) | unset | 0 or more | Same as `Session.Tuning.MinimumRecallCompositeScore`. |
| `Session.MaxToolDescriptionChars` | integer | `2048` | 0 or more | Same as `Session.Tuning.MaxToolDescriptionChars`. |
| `Session.MaxToolSchemaWarnChars` | integer | `8000` | 0 or more | Same as `Session.Tuning.MaxToolSchemaWarnChars`. |
| `Session.Tuning` | object | - | - | Internal tuning. Every key here has a same-named key directly under `Session`, and the `Tuning` value wins. |
| `Session.Tuning.CompactionThreshold` | number | `0.75` | 0.1 to 1 | See `Session.CompactionThreshold`. |
| `Session.Tuning.SnapshotInterval` | integer | `20` | 1 or more | See `Session.SnapshotInterval`. |
| `Session.Tuning.KeepRecentToolResults` | integer | `3` | 0 or more | See `Session.KeepRecentToolResults`. |
| `Session.Tuning.MaxInlineToolResultChars` | integer | `12000` | 100 or more | See `Session.MaxInlineToolResultChars`. |
| `Session.Tuning.DiscoveredToolRetentionTurns` | integer | `3` | 0 or more | See `Session.DiscoveredToolRetentionTurns`. |
| `Session.Tuning.DiscoveredToolMaxCount` | integer | `12` | 0 or more | See `Session.DiscoveredToolMaxCount`. |
| `Session.Tuning.KeepRecentMessages` | integer | `6` | 1 or more | See `Session.KeepRecentMessages`. |
| `Session.Tuning.TitleGenerationInterval` | integer | `10` | 0 or more | See `Session.TitleGenerationInterval`. |
| `Session.Tuning.DeterministicRetrievalEnabled` | boolean | `true` | - | See `Session.DeterministicRetrievalEnabled`. |
| `Session.Tuning.MemoryDistillationTurnInterval` | integer | `5` | 0 or more | Completed turns between memory distillation passes, regardless of idle state, so memories form during long active sessions. `0` leaves distillation to `MemoryObserverIdleSeconds`. |
| `Session.Tuning.MaxToolDescriptionChars` | integer | `2048` | 0 or more | Longest MCP tool description kept at registration. Longer ones are truncated to protect the context window. `0` turns truncation off. |
| `Session.Tuning.MaxToolSchemaWarnChars` | integer | `8000` | 0 or more | Size of an MCP tool's JSON schema that triggers a warning in the log. The schema itself is never truncated, so this only reports bloated tool definitions. `0` turns the warning off. |
| `Session.Tuning.MinimumRecallCompositeScore` | number (nullable) | unset | 0 or more | Minimum composite score for a memory to be injected by automatic recall. Unset uses the coordinator's built-in floor. Lower values let weaker matches through, `0` removes the floor. |
| `Session.Tuning.MaxRecallInjectedChars` | integer | `2000` | 0 or more | Character budget for memory text injected by automatic recall in one turn. Whole items are dropped rather than truncated. `0` removes the budget. |
| `Session.Tuning.StreamingRetryPolicy` | object | - | - | Retry policy for transient streaming LLM failures (HTTP 408, 429 and 5xx). It applies only before the first streamed data arrives. |
| `Session.Tuning.StreamingRetryPolicy.MaxRetries` | integer | `3` | 0 or more | Maximum number of retries after the first attempt. |
| `Session.Tuning.StreamingRetryPolicy.BaseDelay` | string | `"00:00:01"` | `HH:mm:ss` | Delay before the first retry in HH:mm:ss format. The delay doubles on each retry, with jitter. |
| `Session.Tuning.StreamingRetryPolicy.MaxDelay` | string | `"00:00:30"` | `HH:mm:ss` | Upper limit on the delay between retries in HH:mm:ss format. |

A value below a key's minimum fails `netclaw doctor` schema validation. The daemon itself enforces a 1 second minimum on `TurnLlmTimeoutSeconds`, `ToolExecutionTimeoutSeconds` and `SidecarLlmTimeoutSeconds`.

### Security

Deployment posture and shell mode, which choose the default tool profiles. [Security model](/security/security-model/) explains the three postures.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Security.DeploymentPosture` | string (nullable) | unset | `Public`, `Team`, `Personal` | Who talks to this install: `Personal` (you), `Team` or `Public`. `netclaw init` writes it. When it's unset and `StrictDefaults` is `true`, netclaw behaves as `Public` and denies `shell_execute`. It selects the default tool profiles and shell mode, and it narrows the audience of every turn: a channel mapped to `Personal` under a `Team` posture runs as `Team`. |
| `Security.ShellExecutionMode` | string (nullable) | unset | `Off`, `SandboxOnly`, `HostAllowed` | Whether `shell_execute` can run. Unset gives `HostAllowed` for a `Personal` posture and `Off` for the others. `Tools.ShellMode` overrides it. `SandboxOnly` denies every shell call with `shell_requires_sandbox_backend`. |
| `Security.StrictDefaults` | boolean | `true` | - | Fail closed when posture or shell mode is unset. Set `false` only to get `Personal` and `HostAllowed` as the implicit defaults. |

### Tools

Tool grants per audience, file roots, approval policy and `web_fetch` limits. A configured list replaces the default list, so a list with one tool grants one tool. [Built-in tools](/reference/tools/) lists the tools and defaults, and [How tool approvals work](/security/approvals/) covers `ApprovalPolicy`.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Tools.ShellMode` | string (nullable) | unset | `Off`, `SandboxOnly`, `HostAllowed` | Overrides `Security.ShellExecutionMode` for the shell tools. Unset follows the security setting. |
| `Tools.MaxOutputChars` | integer | `256000` | 1 or more | Most output a tool call captures in memory for the spill file. It isn't what the model sees inline, which is `Session.MaxInlineToolResultChars`. Output past the ceiling is discarded. |
| `Tools.AudienceProfiles` | object | - | - | Per-audience tool, file and MCP grants. Public, Team and Personal share one shape. A list you set replaces the default list and doesn't merge with it. |
| `Tools.AudienceProfiles.<audience>` | object | - | - | One entry each for `Public`, `Team` and `Personal`. |
| `Tools.AudienceProfiles.<audience>.ToolsMode` | string | `Allowlist` (Personal: `All`) | `Allowlist`, `All` | `Allowlist` grants only the tools in `AllowedTools`. `All` grants every profile-managed tool. |
| `Tools.AudienceProfiles.<audience>.AllowedTools` | array of string | Public and Team defaults, see [Built-in tools](/reference/tools/#default-allow-lists) | - | Profile-managed tools this audience can call. Tools outside the profile-managed set are always available. Setting the key replaces the default list, and a value that isn't a list stops startup. |
| `Tools.AudienceProfiles.<audience>.McpServersMode` | string | `Allowlist` (Personal: `All`) | `Allowlist`, `All` | `Allowlist` exposes only the servers in `AllowedMcpServers`. `All` exposes every configured server. |
| `Tools.AudienceProfiles.<audience>.AllowedMcpServers` | array of string | `[]` | - | MCP server names this audience can use when `McpServersMode` is `Allowlist`. MCP stays off for Public and Team until you add a server. |
| `Tools.AudienceProfiles.<audience>.McpServerToolGrants` | map of array (nullable) | unset | - | Per-server tool allowlists. A server listed here exposes only the named tools. A server not listed exposes all of its tools. Ignored when `McpServersMode` is `All`. |
| `Tools.AudienceProfiles.<audience>.ReadFiles.Mode` | string | `Roots` (Personal: `All`) | `None`, `Roots`, `All` | `None` blocks it, `Roots` limits it to `Roots`, `All` allows any path that isn't protected. For the `Personal` audience, `file_read`, `file_list`, `file_search` and `attach_file` reach at least as far as `WriteFiles` does. |
| `Tools.AudienceProfiles.<audience>.ReadFiles.Roots` | array of string | `["{session_dir}"]` | - | Directories used when `Mode` is `Roots`. Tokens: `{session_dir}`, `{skills_dir}`, `{identity_dir}`, `{workspaces_dir}`. |
| `Tools.AudienceProfiles.<audience>.WriteFiles.Mode` | string | `Roots` (Personal: `All`) | `None`, `Roots`, `All` | Same values as `ReadFiles.Mode`, for `file_write` and `file_edit`. |
| `Tools.AudienceProfiles.<audience>.WriteFiles.Roots` | array of string | `["{session_dir}"]` | - | Directories used when `Mode` is `Roots`. Same tokens as `ReadFiles.Roots`. |
| `Tools.AudienceProfiles.<audience>.AttachFiles.Mode` | string | `Roots` (Personal: `All`) | `None`, `Roots`, `All` | Same values as `ReadFiles.Mode`, for `attach_file`. |
| `Tools.AudienceProfiles.<audience>.AttachFiles.Roots` | array of string | `["{session_dir}"]` | - | Directories used when `Mode` is `Roots`. Same tokens as `ReadFiles.Roots`. |
| `Tools.AudienceProfiles.<audience>.ApprovalPolicy` | object | unset (Personal posture: `shell_execute` is `Approval`) | - | Which tools need a human to approve each call. See [How tool approvals work](/security/approvals/). |
| `Tools.AudienceProfiles.<audience>.ApprovalPolicy.DefaultMode` | string | `"Auto"` | `Auto`, `Approval`, `Deny` | Mode for tools with no override. |
| `Tools.AudienceProfiles.<audience>.ApprovalPolicy.ToolOverrides` | map of string | `{}` | values: `Auto`, `Approval`, `Deny` | Mode per tool. Keys are tool names (`shell_execute`) or MCP tools as `server/tool` (or `server__tool`), matched without regard to case. If two keys differ only by case, the more restrictive mode wins. A key that contains `:` or has no value is ignored, so the tool keeps the audience default, and `netclaw doctor` reports it. Writes to the config directory are denied before any approval mode is read. |
| `Tools.AudienceProfiles.<audience>.ApprovalPolicy.McpServerDefaults` | map of string | `{}` | values: `Auto`, `Approval`, `Deny` | Mode for every tool of one MCP server, keyed by server name and matched without regard to case. An exact `ToolOverrides` entry wins. A key that contains `:` is ignored and `netclaw doctor` reports it. |
| `Tools.AudienceProfiles.<audience>.ChannelAttachments` | object | - | - | Which files from chat messages this audience can send in. |
| `Tools.AudienceProfiles.<audience>.ChannelAttachments.AllowedCategories` | array of string | Public: `Image`. Team: `Image`, `Pdf`, `Document`, `Archive`, `Media`. Personal: those plus `Other`. | items: `Image`, `Pdf`, `Document`, `Archive`, `Media`, `Other` | Attachment categories accepted. An empty list rejects every attachment. |
| `Tools.AudienceProfiles.<audience>.ChannelAttachments.MaxFileBytes` | integer | `26214400` | 0 or more | Largest file accepted, in bytes (25 MiB). Must be above 0 when any category is allowed. |
| `Tools.AudienceProfiles.<audience>.ChannelAttachments.MaxFilesPerMessage` | integer | `10` | 0 or more | Most files accepted on one message. A message over the limit loses all its attachments. Must be above 0 when any category is allowed. |
| `Tools.AudienceProfiles.GlobalReadRoots` | array of string | `["{skills_dir}", "{identity_dir}", "{workspaces_dir}"]` | - | Directories every audience can read, so skill loading, identity files and project discovery work under Team and Public. Setting the key replaces the list. |
| `Tools.WebFetch.RequireHttps` | boolean | `true` | - | Reject plain `http://` URLs in `web_fetch` unless the host is in `HttpAllowList`. |
| `Tools.WebFetch.HttpAllowList` | array of string | `["localhost", "127.0.0.1", "::1", "[::1]"]` | - | Hosts that may use plain HTTP when `RequireHttps` is `true`. Setting the key replaces the list, so keep the loopback entries if you still need them. |
| `Tools.HardDenyPatterns` | array of string | `[]` | - | Extra shell verb-chain prefixes that are always blocked and can't be approved. They add to the built-in hard-deny list, they don't replace it. |

### Providers

Where each model is served. [Managed providers](/configuration/managed-providers/) and [self-hosted providers](/configuration/self-hosted-providers/) have one example per provider type.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Providers` | map of object | `{}` | - | LLM provider connections keyed by a name you choose. `Models.Definitions` entries refer to these names. |
| `Providers.<name>` | object | - | - | One provider connection. The name is yours to choose and `Models.Definitions` entries refer to it. |
| `Providers.<name>.Type` | string | `"ollama"` | - | Provider type: `anthropic`, `deepseek`, `github-copilot`, `ollama`, `openai`, `openai-compatible`, `openrouter` or `veniceai`. |
| `Providers.<name>.Endpoint` | string | `""` (the provider type supplies its own default URL) | - | Base URL of the provider API. |
| `Providers.<name>.AuthMethod` | string | `"None"` | `None`, `ApiKey`, `OAuthDevice`, `OAuthPkce` | How netclaw authenticates to the provider. |
| `Providers.<name>.ApiKey` | string (secret) | unset | - | API key. Lives in `secrets.json`: `netclaw secrets set Providers.<name>.ApiKey <key>`. |
| `Providers.<name>.OAuthAccessToken` | string (secret) | unset | - | OAuth access token. netclaw writes it to `secrets.json` when you sign in with an OAuth auth method. |
| `Providers.<name>.OAuthRefreshToken` | string (secret) | unset | - | OAuth refresh token. netclaw writes it to `secrets.json` when you sign in with an OAuth auth method. |
| `Providers.<name>.OAuthAccountId` | string (secret) | unset | - | OAuth account identifier. netclaw writes it to `secrets.json` when you sign in with an OAuth auth method. |
| `Providers.<name>.OAuthTokenExpiry` | string (secrets.json, unencrypted) | unset | - | Expiry time of the OAuth access token, ISO 8601. netclaw writes it to `secrets.json` beside the tokens when you sign in with an OAuth auth method. It is the one value there that isn't encrypted. A key left in `netclaw.json` is retired: `netclaw doctor` reports it and `netclaw doctor --fix` moves it, after a backup. |
| `Providers.<name>.VendorOptions` | object | unset | - | Provider-specific non-secret options, for example `GitHubHost` and `GitHubApiBase` for `github-copilot`, `ThinkingDialect` for `openai-compatible`, `DisableThinking` for `ollama`, `ExcludeReasoning` for `openrouter` and `IncludeVeniceSystemPrompt` for `veniceai`. Each provider type defines its own keys. |
| `Providers.<name>.VendorOptions.ThinkingDialect` | string | unset | `ChatTemplateKwargs`, `ReasoningEffort`, `DeepSeek`, `None` | `openai-compatible` only. How netclaw sends a thinking level to the server. Without it only the output limit works. `netclaw model set` saves `ReasoningEffort` when it detects llama.cpp. Set it by hand for vLLM, SGLang or a proxy. |

### Models

Which model plays Main, Fallback and Compaction, and each definition's context window, modalities, output limit and thinking level. [Model configuration](/configuration/models/) has examples. The older inline shape (`Models.Main`, `Models.Fallback`, `Models.Compaction` as objects) still loads. Mixing it with `Definitions` and `Roles` stops startup.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Models.Definitions` | object | - | - | Model definitions keyed by a name you choose, at least one. Names are case-insensitive and must be unique. |
| `Models.Definitions.<name>` | object | - | - | One model: which provider serves it and how it behaves. |
| `Models.Definitions.<name>.Provider` | string | required | - | Key into `Providers`. |
| `Models.Definitions.<name>.ModelId` | string | required | - | Model identifier sent to the provider. |
| `Models.Definitions.<name>.ContextWindow` | integer | detected | - | Context window in tokens. When set, it caps the value the provider reports. |
| `Models.Definitions.<name>.Provenance` | string (nullable) | unset | - | Where the model data came from: `Live`, `Defaults` or `Manual`. netclaw sets it. You don't need to. |
| `Models.Definitions.<name>.InputModalities` | string | detected | comma-separated `Text`, `Image`, `Audio`, `Video` | Manual override for what the model accepts, comma-separated from `Text`, `Image`, `Audio`, `Video`. Turns off automatic detection. |
| `Models.Definitions.<name>.OutputModalities` | string | detected | comma-separated `Text`, `Image`, `Audio`, `Video` | Manual override for what the model produces. Same format as `InputModalities`. |
| `Models.Definitions.<name>.MaxOutputTokens` | integer | unset | 1 or more | Output limit in tokens for every call of this model. Thinking tokens count inside it. Must be below `ContextWindow` when that is set. Unset sends 32000, clamped per call to the model maximum and to the context window minus the estimated prompt. |
| `Models.Definitions.<name>.Thinking` | string | unset | `Off`, `Low`, `Medium`, `High`, `Max` | Provider-neutral thinking level for every call of this model. `Max` is the highest level the provider offers. A level the provider dialect can't send fails startup. Unset uses the model's default. |
| `Models.Roles` | object | - | - | Which definition plays each role. Values are names from `Definitions`. |
| `Models.Roles.Main` | string | required | - | Model for all interactions. |
| `Models.Roles.Fallback` | string (nullable) | unset | - | Failover model. Falls back to `Main` when unset. |
| `Models.Roles.Compaction` | string (nullable) | unset | - | Cheaper or faster model for compaction. Falls back to `Main` when unset. |

### Memory

Cross-session memory, embeddings and recall. [Memory and embeddings](/configuration/memory/) explains how the pieces fit together. The embedding model downloads on first start unless `Embeddings.AutoDownload` is `false`.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Memory.Enabled` | boolean | `true` | - | When false, the entire cross-session memory subsystem is disabled. |
| `Memory.RecallTimeoutMs` | integer | `300` | 50 to 10000 | Automatic recall timeout budget in milliseconds. |
| `Memory.AutoRecallMaxItems` | integer | `3` | 1 to 10 | Maximum number of memory items auto-injected per turn. |
| `Memory.Embeddings` | object | - | - | Local ONNX embedding model for semantic memory. |
| `Memory.Embeddings.Enabled` | boolean | `true` | - | When true, the daemon provisions the embedding model, computes embeddings, uses semantic curation nomination and hybrid recall, and enables the relevance gate unless explicitly disabled. |
| `Memory.Embeddings.ModelId` | string | `"snowflake-arctic-embed-m-int8"` | - | Embedding model to use. Allowed ids are `snowflake-arctic-embed-m-int8`, `snowflake-arctic-embed-m` and `mxbai-embed-large-v1`. An id outside the allowlist is a configuration error. Changing it re-embeds existing memories under the new id. |
| `Memory.Embeddings.AutoDownload` | boolean | `true` | - | When true, downloads the model artifact at daemon startup if not already provisioned. When false, a missing model degrades loudly instead of fetching over the network. |
| `Memory.Curation` | object | - | - | How new memories are checked against existing ones before they're saved. |
| `Memory.Curation.NominatorSimilarityThreshold` | number | `0.86` | 0 to 1 | Embedding cosine similarity threshold above which an existing memory is nominated for the curation call to adjudicate. |
| `Memory.Curation.NominatorK` | integer | `5` | 1 to 50 | Maximum number of nearest-neighbor nominees the kNN nominator shortlists per proposal. |
| `Memory.Curation.LlmMaxOutputTokens` | integer | `4096` | 1 or more | Maximum output tokens for the curation LLM call. Sized generously: the token cap is a defense-in-depth bound, not the primary control. |
| `Memory.Curation.LlmTimeoutSeconds` | integer | `60` | 1 to 300 | Wall-clock timeout in seconds for the curation LLM call. |
| `Memory.Recall` | object | - | - | How automatic recall ranks and filters memories, mixing keyword and vector scores. |
| `Memory.Recall.VectorWeight` | number | `0.7` | 0 to 1 | Weight applied to a candidate's cosine similarity in the hybrid fusion score. |
| `Memory.Recall.LexicalWeight` | number | `0.3` | 0 to 1 | Weight applied to a candidate's squashed lexical selector score in the hybrid fusion score. |
| `Memory.Recall.MinCosineSimilarity` | number (nullable) | unset (follows the model, 0.24 for the default) | 0 to 1 | Cosine floor for automatic recall. Candidates below it are dropped before ranking. The meaning is specific to the active embedding model, so recalibrate before you set it. |
| `Memory.Recall.RecencyHalfLifeDays` | number | `30` | 1 to 3650 | Half-life in days for the recency-decay multiplier applied to a candidate's fused score in hybrid mode, floor-bounded at 0.85. |
| `Memory.Recall.RelevanceGate` | object | - | - | Post-floor cross-encoder relevance gate settings (memory-relevance-gate). |
| `Memory.Recall.RelevanceGate.Enabled` | boolean (nullable) | unset (follows `Memory.Embeddings.Enabled`) | - | Run the cross-encoder relevance gate on recall candidates. Set it explicitly to turn the gate on or off independently of embeddings. |
| `Memory.Recall.RelevanceGate.Threshold` | number (nullable) | unset (model default, 0.02) | 0 to 1 | Score below which the gate drops a candidate. Unset uses the calibrated value for the provisioned relevance model. |

Set `Memory.Enabled` to `false` and the memory tools and automatic recall disappear for every audience.

### Search

The `web_search` backend. [Search providers](/configuration/search-providers/) covers Brave and SearXNG setup.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Search.Enabled` | boolean | `true` | - | When false, the web search subsystem is disabled. |
| `Search.Backend` | string | `"duckduckgo"` | `duckduckgo`, `brave`, `searxng` | Search backend identifier. |
| `Search.BraveApiKey` | string (nullable) | unset | - | Brave Search API token. Required when `Backend` is `brave`. Lives in `secrets.json`: `netclaw secrets set Search.BraveApiKey <token>`. |
| `Search.SearXngEndpoint` | string (nullable) | unset | - | SearXNG instance base URL, for example `http://searxng.local:8080`. Required when `Backend` is `searxng`. |

### SkillSync

Switch for the skill index tools. [Skills overview](/skills/overview/) explains where skills come from.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `SkillSync.Enabled` | boolean | `true` | - | When false, skill index tools are unavailable to the session. |

### ExternalSkills

Skill directories from other tools, such as Claude Code. [External skills](/skills/external-skills/) has the setup.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `ExternalSkills.Sources` | array of object | `[]` | - | Ordered list of external skill sources. Earlier entries win name collisions and native netclaw skills always win. |
| `ExternalSkills.Sources[].Name` | string | required | - | Unique name for the source, for example `claude-code`. |
| `ExternalSkills.Sources[].Path` | string (nullable) | unset | - | Absolute path to the skill directory. Mutually exclusive with WellKnown. |
| `ExternalSkills.Sources[].WellKnown` | string (nullable) | unset | `claude-code`, `open-code` | Well-known source alias. Resolves to a standard path automatically. |
| `ExternalSkills.Sources[].Enabled` | boolean | `true` | - | Whether this source is active. |
| `ExternalSkills.Sources[].AllowSymlinks` | boolean | `false` | - | Whether to follow symlinks in this directory. Resolved paths are still validated to stay within the source root. |

### SkillFeeds

Private skill servers that netclaw syncs from at startup and on a timer. [Skill feeds](/skills/skill-feeds/) has the setup.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `SkillFeeds.SyncIntervalMinutes` | integer | `60` | 0 to 1440 | How often (in minutes) to re-check feeds for updated skills. 0 disables periodic sync. |
| `SkillFeeds.Feeds` | array of object | `[]` | - | Ordered list of skill server feeds. Earlier feeds win name collisions. |
| `SkillFeeds.Feeds[].Name` | string | required | pattern `^[a-z0-9-]+$` | Unique feed name, lowercase letters, digits and hyphens. Used as the directory name. |
| `SkillFeeds.Feeds[].Url` | string | required | - | Skill server base URL. |
| `SkillFeeds.Feeds[].ApiKey` | string (nullable) | unset | - | Optional Bearer token for authenticated access. Supports ENC: prefix. |
| `SkillFeeds.Feeds[].Enabled` | boolean | `true` | - | Whether this feed is active. |
| `SkillFeeds.Feeds[].TimeoutSeconds` | integer | `30` | 1 to 300 | HTTP timeout in seconds for requests to this feed. |

### SubAgents

Switches and watchdogs for `spawn_agent`. [Custom subagents](/skills/custom-subagents/) shows how to define agents.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `SubAgents.Enabled` | boolean | `true` | - | When false, the subagent subsystem is disabled. |
| `SubAgents.PrefillTimeoutSeconds` | integer | `1800` | 5 to 3600 | Longest wait for a subagent's first streamed token, which covers queue wait and prompt prefill. Same idea as `Session.PrefillTimeoutSeconds`. After the first token the `Session.FirstTokenTimeoutSeconds` budget applies. An agent definition can override it with `prefillTimeoutSeconds` in its frontmatter. |
| `SubAgents.NoProgressTimeoutSeconds` | integer | `1200` | 60 to 7200 | Hard ceiling on a subagent run with no real output token. Keepalives don't reset it. Like `Session.NoProgressTimeoutSeconds`, it also sets the thinking cap at three times the value. |

### Notifications

Where operational alerts go. [Operational alerts](/observability/operational-alerts/) lists the alert types.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Notifications.Webhooks` | array of object | `[]` | - | Targets that receive operational alerts by HTTP POST. Empty means alerts only go to the log. |
| `Notifications.Webhooks[].Url` | string | required | - | HTTP or HTTPS endpoint to POST alerts to. |
| `Notifications.Webhooks[].Name` | string (nullable) | unset | - | Display name used in logs. |
| `Notifications.Webhooks[].Headers` | map of string (nullable) | unset | - | Static headers sent with every POST, for example `Authorization`. |
| `Notifications.Webhooks[].Format` | string | `"Generic"` | `Generic`, `Slack` | Payload format: `Generic` is a JSON envelope, `Slack` is Slack Block Kit. |
| `Notifications.DeduplicationWindowSeconds` | integer | `300` | 0 to 3600 | Minimum interval in seconds between duplicate alerts of the same type. |
| `Notifications.MaxRetries` | integer | `2` | 0 to 10 | Number of delivery retries per webhook target before giving up. |
| `Notifications.TimeoutSeconds` | integer | `10` | 1 to 60 | HTTP timeout in seconds for each webhook POST attempt. |

### Webhooks

The inbound webhook endpoint. The routes themselves aren't in `netclaw.json`: each one is a file under `config/webhooks/`, managed with `netclaw webhooks` or the webhook tools. [Webhooks](/configuration/webhooks/) covers routes and verification.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Webhooks.Enabled` | boolean | `false` | - | Register the inbound webhook endpoint and the `set_webhook`, `list_webhooks` and `delete_webhook` tools. |
| `Webhooks.ExecutionTimeoutSeconds` | integer | `300` | 1 to 3600 | Longest a webhook-triggered run can take before the daemon marks it failed. |

### Scheduling

Switch for reminders and scheduled tasks. [Reminders](/configuration/reminders/) covers creating and running them.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Scheduling.Enabled` | boolean | `true` | - | When false, the scheduling subsystem is disabled. Reminder and scheduling tools are not registered. |

Set `Scheduling.Enabled` to `false` and the five reminder tools aren't registered.

### Retention

How long the daemon keeps log files before a scheduled clean-up deletes them. [Data retention](/configuration/data-retention/) explains what is and isn't deleted.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Retention.Logs.Days` | integer | `14` | 0 to 36500 | Days to keep `daemon-yyyy-MM-dd.log`, its numbered segments `daemon-yyyy-MM-dd.N.log` (the daemon starts a new segment at 10 MiB) and `crash-*.log` files in the logs directory. The daemon deletes older files 30 seconds after it starts and every 12 hours after that. The newest 3 daemon logs, segments counted as files, and the newest 3 crash logs are always kept. `0` keeps them forever. Per-session logs are never touched. See [Data retention](/configuration/data-retention/). |

### Daemon

Bind address, port and how the daemon is exposed to the network. Changing any of these in `netclaw.json` restarts the daemon. [Exposure modes](/deployment/exposure-modes/) explains each mode and [Docker](/deployment/docker/) covers the container settings.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Daemon.Host` | string | `"127.0.0.1"` | - | IP address the daemon binds to. Defaults to loopback (127.0.0.1). |
| `Daemon.Port` | integer | `5199` | 1 to 65535 | TCP port the daemon listens on. Defaults to 5199. |
| `Daemon.ExposureMode` | string | `"local"` | `local`, `reverse-proxy`, `tailscale-serve`, `tailscale-funnel`, `cloudflare-tunnel` | Tunnel infrastructure in front of the daemon. Defaults to local (loopback only, no tunnel). |
| `Daemon.TrustedProxies` | array of string | `[]` | - | Explicitly trusted reverse-proxy source IPs or CIDR ranges. Required for reverse-proxy mode. |
| `Daemon.SkipTunnelProcessCheck` | boolean | `false` | - | When true, skips the local tunnel-process prerequisite check for tunnel-backed exposure modes. Use only for sidecar or host-managed tunnel topologies. |
| `Daemon.DisableSelfUpdate` | boolean | `false` | - | When true, in-place binary self-update via 'netclaw update' is blocked. Update availability checks still run. Intended for container deployments where the image tag is the version. |
| `Daemon.UpdateChannel` | string | `"stable"` | `stable`, `beta` | Release channel the update check follows. `stable` only sees stable releases. `beta` also sees prereleases and moves to a stable release once one supersedes the beta. |

The Docker image's health check probes port 5199. A container with a different `Daemon.Port` reports `unhealthy` even though the daemon is up, so override the health check when you change the port.

In `Local` exposure mode the daemon answers 401 to a request whose `Host` isn't `localhost` or a loopback IP literal (`127.0.0.1`, `[::1]`), or whose `Origin`, when present, isn't `http://` plus the same host. A client that reaches the daemon by another host name, or a browser app on another port, is refused. `Daemon.Host` as a bind value still accepts spellings such as `127.1`.

### Workspaces

Where netclaw looks for your project repositories. [Context structure](/architecture/context-structure/) explains how projects feed the prompt.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `Workspaces.Directory` | string | `~/.netclaw/workspaces` | - | Root for project workspaces. Projects are Git repositories with an `AGENTS.md`, at any depth. A leading `~` expands to your home directory. |

### McpServers

MCP server profiles keyed by name. Add them with `netclaw mcp add` or edit the file. [MCP servers](/configuration/mcp-servers/) has the walkthrough and [MCP tool permissions](/guides/mcp-tool-permissions/) covers per-audience access.

| Key | Type | Default | Allowed values | Description |
|-----|------|---------|----------------|-------------|
| `McpServers.<server>` | object | - | - | MCP server profiles keyed by name. |
| `McpServers.<server>.Transport` | string | `"stdio"` | `stdio`, `sse`, `http` | How netclaw connects: `stdio` runs `Command`, `sse` and `http` connect to `Url`. |
| `McpServers.<server>.Command` | string (nullable) | unset | - | Executable to run for `stdio`. |
| `McpServers.<server>.Arguments` | array of string (nullable) | unset | - | Arguments for `Command`. |
| `McpServers.<server>.Url` | string (nullable) | unset | - | Endpoint for `sse` and `http`. |
| `McpServers.<server>.EnvironmentVariables` | map of string (nullable) | unset | - | Environment variables passed to the `stdio` process. Values stored in `secrets.json` are decrypted first. |
| `McpServers.<server>.Headers` | map of string (nullable) | unset | - | HTTP headers for `sse` and `http`. Values stored in `secrets.json` are decrypted first. |
| `McpServers.<server>.Enabled` | boolean | `true` | - | Disabled servers are skipped at startup. |
| `McpServers.<server>.GrantCategory` | string (nullable) | `mcp:<server>` | - | Tool metadata category for the server's tools. Authorization doesn't read it: use the audience's `AllowedMcpServers` and `McpServerToolGrants`. |
| `McpServers.<server>.OAuthClientId` | string (nullable) | unset | - | Static OAuth client ID for servers without dynamic client registration. |
| `McpServers.<server>.OAuthClientSecret` | string (secret) | unset | - | Client secret for a pre-registered confidential OAuth client. Vault only: the schema rejects it in `netclaw.json`, so doctor fails the Config Schema check. Set it with `netclaw mcp add --client-id <id> --client-secret <secret>` or `netclaw secrets set`, which store it in `secrets.json`. Needs `OAuthClientId`. |
| `McpServers.<server>.OAuthScope` | string (nullable) | unset | - | Space-separated OAuth scopes to request, overriding the server's defaults. |

<!-- END GENERATED: config-reference -->

## Removed keys

These keys no longer do anything. `netclaw doctor` reports each one as a disallowed property.

| Key | Removed in | What to do |
|-----|------------|------------|
| `Persistence` (the whole section) | 0.27.0 | Delete it. netclaw always uses its single SQLite database, and the daemon refuses to start while the section exists. |
| `SkillSync.DisableSystemSkillSync` | 0.27.0 | Delete it, or run `netclaw doctor --fix`. System skills now ship inside the binary and restore on every start. |
| `Providers.<name>.OAuthTokenExpiry` in `netclaw.json` | 0.28.0 | Run `netclaw doctor --fix`, which moves it to `secrets.json` after saving `netclaw.json.retired-oauth-expiry.bak`. Until then it still binds and logs a startup warning. |
| `timeoutSeconds` in a subagent definition | 0.28.0 | Delete it. The file still loads and the daemon logs a warning each time it reloads, but the key is ignored. Subagent runs use `Session.FirstTokenTimeoutSeconds`, 600 seconds by default, so a profile that used 60 to 180 seconds now waits longer. |
| `Session.MaxToolIterationsPerTurn` | 0.28.0 | Still valid and still validated, but no longer limits a turn. |
| `Tools.ShellTimeoutSeconds` | 0.24.0 | Delete it. A foreground shell call is bound by `Session.ToolExecutionTimeoutSeconds`, and a background job by the `_timeout_seconds` the model passes. |

## Related pages

- [Built-in tools](/reference/tools/): every tool, its default audiences and approval behavior
- [How tool approvals work](/security/approvals/): what `ApprovalPolicy` changes
- [Docker deployment](/deployment/docker/): environment variables and restarts in a container
- [`netclaw doctor`](/cli/doctor/): the checks behind validation
- [`netclaw secrets`](/cli/secrets/): where tokens and API keys go

## Resources

- [netclaw configuration schema](https://github.com/netclaw-dev/netclaw/tree/dev/src/Netclaw.Configuration/Schemas): the JSON schema this page is generated from
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider): why `__` separates path segments
- [Compose environment variables](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/): setting `NETCLAW_` variables on a service
