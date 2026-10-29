---
title: "Security model"
description: "What netclaw enforces: audiences, postures, the order of checks, protected paths and shell policy, and where the boundary ends and a sandbox begins."
---

Netclaw is default-deny. Every tool call, file access and shell command starts blocked and must be permitted by your configuration. Any policy failure, such as an exception in the policy engine or a channel it can't identify, ends in a denial. This page is the operator's reference for what netclaw enforces. For the reasoning behind the design, see [Security architecture](/architecture/security-model/). For how prompts work, see [How tool approvals work](/security/approvals/).

:::caution
Netclaw protects its own control plane and gates the tools the agent calls. It isn't a sandbox. Beyond that and a fixed list of credential folders, the agent can read anything your OS user can read. See [what netclaw doesn't protect against](#what-netclaw-doesnt-protect-against) before you run it on a machine that holds other credentials.
:::

## Trust audiences

Every inbound message resolves to one of three audiences. Personal is the most trusted and Public the least. The [deployment posture](#deployment-postures) is a ceiling on top of that: the audience a turn runs with, and the audience of any sub-agent it starts, is the narrower of the posture's audience and the source audience. The table below lists the source audience.

| Source | Audience |
|--------|----------|
| TUI (`netclaw chat`), web client (SignalR), headless (`netclaw chat -p`), console, manual | Personal |
| Slack, Discord, Mattermost | Per channel or DM from `ChannelAudiences`. Otherwise Team for an allowlisted channel or user, Public for anything else |
| Webhook | The route's `Audience`, default Public |
| Reminder | The audience of the session that created it, or a lower one the reminder sets |
| Unknown channel type | Public |

For chat channels, the order is: the channel's own entry in `ChannelAudiences`, then the `dm` entry for direct messages, then the allowlist rule. A DM from a user who isn't on `AllowedUserIds` resolves to Public, not Team. [`netclaw init`](/cli/init/) and [`netclaw config`](/cli/config/) write the `ChannelAudiences` entries: a regular channel defaults to Team (Public on a Public posture), and a DM defaults to Personal when one user is allowlisted, and otherwise follows the posture (a Personal posture means Personal DMs). See [Hardening](/security/hardening/#channel-access-restrictions) for the access-control keys.

If netclaw can't resolve an audience for a tool call, it denies the call with `audience_unresolved`. It never substitutes Public.

### Reminder tools and audiences

The reminder tools only see reminders at or below the caller's audience. A reminder outside that scope reads as `not found`, and `set_reminder` can't overwrite it.

| Caller (effective audience) | Reminders it can list, run, cancel, read history for and update |
|--------|------------------------------------------------------------------|
| Personal chat | Personal, Team, Public |
| Team chat | Team, Public |
| Public chat | Public |
| CLI and HTTP API (operator) | All |

A reminder created before 0.28.0 under a narrower posture (for example a Team posture with Slack DMs mapped to Personal) keeps its Personal audience. `run_reminder` refuses it and a narrower chat doesn't list it, so recreate it from a chat. [Reminders](/configuration/reminders/#audience-scoping) covers which tool groups each audience gets and how to test a reminder at its own audience.

## Deployment postures

You pick a posture during [`netclaw init`](/cli/init/). It sets the shell default for the deployment and caps the tools every turn can use.

![Netclaw Setup, Step 3 of 5, Security Posture, offering Personal, Team and Public with a one-line summary of each](/screenshots/output/init-02-security-posture.png)

The posture screen. Personal is the only choice that turns shell on.

| Posture | Shell default |
|---------|---------------|
| Personal | `HostAllowed`, with approval prompts |
| Team | `Off` |
| Public | `Off` |

With no config file, or no `DeploymentPosture`, netclaw resolves to Public with shell off. That applies to `netclaw chat` too: a config with no posture gives the TUI Public tools, and a `shell_execute` call is denied.

Posture is a deployment-wide choice you make once, and audience is resolved per message from the channel. The two combine by taking the narrower. A Team posture runs `netclaw chat` with Team tools (no `shell_execute`, no webhook tools), and a Public posture runs it with Public tools. A Personal posture changes nothing, so a Slack channel mapped to Team stays Team. The admission gate, the shell check, the approval mode, the filesystem roots, tool search and every sub-agent read the narrowed audience. The tool lists themselves come from the [audience profiles](#per-audience-permissions).

Three keys control shell, in this order of precedence: `Tools.ShellMode`, then `Security.ShellExecutionMode`, then the posture default. `netclaw init` writes both of the first two, so to change shell on an installed system set both. Values are `Off` and `HostAllowed`. `SandboxOnly` is accepted but there's no sandbox backend, so it denies shell entirely with `shell_requires_sandbox_backend`.

## Per-audience permissions

| | Personal | Team | Public |
|-|----------|------|--------|
| Tools | All, including `shell_execute` | `file_read`, `file_list`, `file_search`, `tool_output_read`, `file_write`, `file_edit`, `attach_file`, `web_search`, `web_fetch`, `skill_manage`, reminder tools, `set_working_directory` | `file_read`, `file_list`, `file_search`, `tool_output_read`, `attach_file` |
| MCP servers | All | None until listed in `AllowedMcpServers` | None until listed |
| Filesystem | Everything except protected paths. File reads reach at least as far as writes do | Session directory, plus read-only skills, identity and workspaces roots | Its session directory only |
| Memory | Full | Full | Disabled, not just defaulted off |
| Attachments | Image, PDF, Document, Archive, Media, Other | Image, PDF, Document, Archive, Media | Image only |

File reads on Personal follow the write profile, so the agent can read what its shell writes, for example under `/tmp`. With `ReadFiles.Mode = Roots` and a wider `WriteFiles`, Personal reads (including unattended reminders and webhooks) get wider with no prompt. `netclaw doctor` warns when any audience can write wider than it can read. Protected paths stay denied, and Team and Public are unchanged.

Shell is Personal-only. A Team or Public call to `shell_execute` is denied, whatever the posture says. The webhook tools (`set_webhook`, `list_webhooks`, `delete_webhook`) are also Personal-only.

Adjust a list in `Tools.AudienceProfiles.<audience>.AllowedTools`. Since 0.27.1 a configured list replaces the default, so write out every tool you want, including `tool_output_read`. `netclaw doctor` warns when a list copies an old default, and `netclaw doctor --fix` removes it so the audience follows the current default. See [Memory model](/architecture/memory-model/#audience-scoping) for how stored memories carry audience context.

## Layers in order

One authorizer applies these rules to every tool call, first match wins. The same list covers built-in tools, MCP tools, `shell_execute`, subagents and unattended runs.

| # | Question | If not satisfied | Set by |
|---|----------|------------------|--------|
| 1 | Does the audience profile allow this tool, and for MCP this server and tool? | `tool_not_allowed_for_audience_profile` | `AllowedTools`, `AllowedMcpServers`, `McpServerToolGrants` |
| 2 | For shell: is the audience Personal and the shell mode on? | `shell_requires_personal_context`, `shell_requires_sandbox_backend` | Posture, `Tools.ShellMode` |
| 3 | Is the command on the hard-deny list? | `hard_deny_<category>` | Built in, plus `Tools.HardDenyPatterns` |
| 4 | Does the call name a protected path (control plane or credential location), or reach one with a glob, brace or symlink? | `shell_references_protected_path`, `shell_path_protected`, `path_access_denied` | Built in |
| 5 | Is every path inside the audience's trusted roots? | `shell_path_outside_trusted_roots` | `ReadFiles`, `WriteFiles` in the profile |
| 6 | Is the tool's approval mode `Deny`? | Denied | `ApprovalPolicy` |
| 7 | Can the agent fix the call itself? | Requires correction | Built in |
| 8 | Is the mode `Auto`? | Allowed | `ApprovalPolicy` |
| 9 | Does a saved grant, a this-chat answer or the reviewed-safe catalog cover it? | Prompt, or `approval_required_unattended` when nobody can answer | Grants, [`netclaw approvals`](/cli/approvals/) |

Steps 1 through 5 can't be answered away. Steps 6 through 9 are the approval system. Steps 3 and 4 run before any grant lookup, so a saved grant never reaches a hard-denied command or a protected path. Non-shell tools run the same list without steps 2, 3 and 5, and with file-path checks in step 4.

### Hard deny

| Category | Blocked |
|----------|---------|
| Self-destructive | `netclaw daemon stop`, `systemctl stop netclaw`, `systemctl kill netclaw`, and `kill`, `killall`, `pkill` or `Stop-Process` when the command names netclaw (`pkill netclawd`). Other kills prompt like any command |
| Privilege escalation | `sudo`, `su`, `doas`, and a PowerShell `-Verb RunAs` start |
| System destruction | `rm -rf /`, `rm -rf ~/`, `mkfs*` |
| Fork bombs | `:(){ :|:& };:` and the no-space form `:(){:|:&};:`. Other fork bombs aren't detected |

Add your own with `Tools.HardDenyPatterns` in `netclaw.json` or an optional `~/.netclaw/config/hard-deny-overrides.json`. Both add to the defaults and never replace them.

```json
{
  "Tools": {
    "HardDenyPatterns": ["docker rm", "kubectl delete namespace"]
  }
}
```

Compound commands (`&&`, `||`, `;`, `|`) are split and each command is checked, so `echo hi && docker rm foo` still matches.

### Protected paths

Read and write have separate lists. Netclaw resolves symlinks first, and it denies globs, brace words and ANSI-C quoted spellings that could reach a protected path. A glob that crosses a symlinked folder is checked against where the link points too, so a protected path behind a link is refused.

| Operation | Denied |
|-----------|--------|
| Read | `secrets.json`, the `keys/` directory, webhook route files in `config/webhooks/`, the SQLite database and its sidecars, process-control files (PID, lock, restart manifest), the tooling shadow directory, [credential locations](#credential-locations) |
| Write | Everything under `~/.netclaw/config/`, `keys/`, the database and sidecars, process-control files, the tooling shadow directory, skill-feed sync state, [credential locations](#credential-locations) |

The agent can read `netclaw.json` and the other config files, but not write them. No approval mode or grant changes that for `file_write` or `file_edit`. `ToolOverrides` keys that contain a colon (such as the old `file_write:control-plane`) are ignored, and `netclaw doctor` reports them. A shell program that only reads its operands (`cat`, `head`, `tail`, `wc`, `grep`, `jq`, `diff`) can read a config file by exact path. Any other shell command that names a config file meets write protection.

### Credential locations

From 0.28.0, the well-known folders and files where other tools keep credentials are denied to the agent's tools too, for read and for write:

| Location | Denied |
|----------|--------|
| `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.azure` | The whole folder |
| `~/.config/gh`, `~/.config/gcloud` | The whole folder, and the same folders under `XDG_CONFIG_HOME` when it points elsewhere |
| `~/.docker/config.json` | That file only. Other files in `~/.docker` stay readable |
| `~/.netrc`, `~/.git-credentials` | The files |

On Windows the list adds `~/_netrc`, `%APPDATA%\gcloud`, `%APPDATA%\GitHub CLI`, `%APPDATA%\gnupg` and `%PROGRAMDATA%\ssh`.

These are the results on 0.28.2, with a credentials file planted in each folder:

| Call | Result |
|------|--------|
| `file_read` of `~/.ssh/id_rsa` | `Error: Access denied: '/home/netclaw/.ssh/id_rsa' is protected ... and cannot be read by agent tools, even with approval.` |
| `file_write` or `file_edit` in `~/.ssh` or `~/.aws` | The same denial, ending "cannot be modified by agent tools" |
| `file_list` of `~/.aws` | The same denial. A listing of `~` leaves these entries out |
| `file_search` rooted at `~` | Skips the folders, so a match inside them never shows up |
| `shell_execute` of `cat ~/.aws/credentials`, `ls ~/.aws`, `echo x > ~/.ssh/config` | `Tool access denied: shell_references_protected_path`, including for the read-only catalog commands that never prompt |
| `cat ~/.docker/contexts.json` | Runs: only `config.json` is on the list |

No approval, `ToolOverrides` entry or audience profile changes a denial. The programs that need these files still work: `ssh`, `git` and `aws` read their own credentials as the process netclaw starts, and no path in the command line names them. The check is on the paths a command names, so it protects against the agent reading a credential folder directly. It doesn't turn netclaw into a sandbox. See [what netclaw doesn't protect against](#what-netclaw-doesnt-protect-against).

### Private temp folder

On Linux and macOS each run gets its own temp folder at `/tmp/netclaw-<uid>/<key>/p` (`/private/tmp` on macOS), created with mode `0700`, and `TMPDIR`, `TMP` and `TEMP` point at it. Netclaw refuses a shell launch, `file_write` or `file_edit` below it when the owner, the mode or a link is wrong, and it doesn't fall back to another folder. A Team or Public session can reach only its own key folder, even if a configured root covers `/tmp`.

### Shell policy

Netclaw parses each shell command and judges every command in a pipeline or list separately. The prompt names only the commands that remain uncovered. A command it can't parse into a reusable phrase can still run once if you approve it, but can't be saved as a grant. Headless and unattended runs follow the same rules, with prompts turned into denials. See [How tool approvals work](/security/approvals/) for grants, the reviewed-safe catalog and what each answer saves.

## Approval gates

Approvals decide whether a permitted tool runs without asking. On Personal, `shell_execute` prompts unless you opt it out with an explicit override. Everything else is `Auto`. Writes under the config directory aren't a prompt case. The path policy denies them. MCP servers get a mode at `netclaw mcp add`. The mechanics, the modes and the saved-grant store are on [How tool approvals work](/security/approvals/), and the "stop asking" recipes are in [Reduce or turn off approval prompts](/guides/reduce-approval-prompts/).

## MCP defaults

`netclaw mcp add` seeds each audience:

| Audience | Servers | Tool grants | Approval mode |
|----------|---------|-------------|---------------|
| Personal | All | All tools | `Auto` |
| Team | Must be in `AllowedMcpServers` | None until granted | `Approval` |
| Public | Must be in `AllowedMcpServers` | None until granted | `Deny` |

A server absent from `McpServerToolGrants` exposes all its tools to an audience that can reach the server. Personal is therefore open by default, so review it first. See [MCP tool permissions](/guides/mcp-tool-permissions/).

## Secret redaction

The redactor replaces secret-shaped text in tool output with `***REDACTED***` before the model sees it. It's a tripwire for accidental leaks, not a control. Don't rely on it to keep credentials out of model context.

It masks:

- **Known token formats** wherever they appear, whatever the name around them: OpenAI and Anthropic `sk-` keys, Slack `xox*-` and `xapp-` tokens, GitHub `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` and `github_pat_` tokens, AWS `AKIA` and `ASIA` key IDs, Stripe live keys and `whsec_` signing secrets, Google `AIza` keys, npm and PyPI tokens, Discord bot tokens, JWTs, `Authorization: Bearer` headers and Slack webhook URLs. A token followed by `-` or `.` is still masked
- **PEM private key blocks**, so `cat` of an OpenSSH or PEM key comes back as `***REDACTED***`
- **JSON fields** whose name starts with `api_key`, `token`, `secret`, `password`, `passwd`, `authorization`, `client_secret`, `private_key`, `connection_string`, `credential` or `passphrase`
- **`NAME=value` pairs** where the name starts with one of those words (`API_KEY`, `PASSWORD`, `TOKEN_X`) or has one as a whole underscore-separated segment (`DB_PASSWORD`, `GITHUB_TOKEN`, `AWS_SECRET_ACCESS_KEY`). The whole value is masked
- **Connection strings** with `Password=` or `Pwd=`
- **URL credentials**: the password in any `scheme://user:password@host` URL, whatever the name around it
- **Option values** after a secret option, such as `--password hunter2`, `--token x` or `--api-key x`. Options like `--password-file`, `--no-password` and `--next-token` are left alone
- **Header lines** that carry secrets: `Authorization` and `Proxy-Authorization` (the scheme stays), `Cookie`, `Set-Cookie`, and names such as `X-Api-Key` or anything ending in `-token`

Prefixed names skip the settings that carry those words without being secrets: names ending in a descriptor such as `_FILE`, `_PATH`, `_URL` or `_LENGTH` (`GH_TOKEN_FILE`), `max_tokens`, pagination cursors like `NEXT_PAGE_TOKEN`, and values that are references (`${{ secrets.GITHUB_TOKEN }}`, `$VAR`).

In a test on 0.28.2, `cat .env` in the shell came back with `API_KEY`, `DB_PASSWORD`, `GITHUB_TOKEN`, `AWS_SECRET_ACCESS_KEY` and `SLACK_BOT_TOKEN` masked, and the `DATABASE_URL` line as `DATABASE_URL=postgres://app:***REDACTED***@db.internal:5432/app`. It left `SESSION_KEY=abcdef123456` and `MYTOKEN=abc` as written. A secret in a custom format passes the same way.

Two tools aren't masked at all. `file_read` returns file text as it is, so a read-edit-write cycle doesn't write `***REDACTED***` into your file. MCP tool results pass through too, because MCP servers are integrations you configured. The same `.env` read with `file_read` came back unmasked. Tool-call arguments in the logs are redacted too, and the full output behind `tool_output_read` is always the redacted text.

For encryption at rest, see [Secrets management](/security/secrets/).

## Prompt injection detection

Netclaw scans inbound Slack, Discord and Mattermost messages, and thread history it pulls in, with regex patterns. A high-risk match blocks the message. Medium and low matches are logged and allowed through. Patterns cover instruction overrides, secret exfiltration, ACL or privilege manipulation, `rm -rf /` and disk destruction (high), and role assumption, `DROP TABLE`, mass deletion and invisible Unicode (medium or low). Skill content isn't scanned, so install only skills you trust.

## Content validation

Before accepting an upload, netclaw checks that the MIME type is on the audience's allowlist, the file is at most 25 MiB, and the file header matches the declared type, so renaming `malware.exe` to `photo.png` doesn't work.

## Network exposure

Exposure mode controls who can reach the daemon and is separate from audience and posture. The default `local` binds loopback only and trusts a loopback request as the operator only when its `Host` is `localhost` or a loopback address and any `Origin` matches. Other requests get a 401, which blocks DNS rebinding and cross-site requests from a browser. See [Hardening](/security/hardening/#network-exposure). A Personal posture exposed through Tailscale Funnel is internet-reachable but still applies Personal rules to the TUI and Team rules to Slack. See [Exposure modes](/deployment/exposure-modes/).

## Fail-closed behavior

- A malformed `Tools` list, such as a scalar where a list belongs, stops the daemon at startup with an error naming the key.
- A policy rule that throws denies the call.
- An unresolved audience denies the call (`audience_unresolved`).
- No config file, or no `DeploymentPosture`, means Public posture with shell off, for the TUI too.
- A `netclaw.json` the CLI can't read leaves the local daemon address unknown. The CLI says so and sends no local control traffic instead of guessing the default address.
- Invalid model or provider configuration stops the daemon at startup, and a running daemon refuses to reload an invalid file.
- A prompt nobody can answer in an unattended run is denied (`approval_required_unattended`).
- A malformed or newer-version grant store denies every call that needs a grant (`approval_store_unavailable`).

There's no permissive mode. Access is granted explicitly or not at all.

## What netclaw doesn't protect against

Item 2 applies from 0.28.0. Earlier releases have no credential-location rule.

1. **Netclaw protects its own control plane.** That's the credential store (encryption keys, `secrets.json` and webhook route secrets), the netclaw database, the process-control files and writes to the netclaw configuration. The agent can't read or change them, in any command form it tries.
2. **It also denies a fixed list of credential locations.** `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.azure`, `~/.config/gh`, `~/.config/gcloud`, `~/.docker/config.json`, `~/.netrc` and `~/.git-credentials` are off limits to the agent's file tools and to shell commands that name them. See [credential locations](#credential-locations). The list is short on purpose: no list of folders covers every secret on a machine.
3. **Everything else, the agent reads as your user.** A `.env` file in a project, a token in a shell history file or a key in a folder that isn't on the list is readable, and the read-only catalog commands such as `cat` run without a prompt on any path the audience can read. Output redaction masks some of what comes back, not all of it.
4. **Approvals aren't a sandbox.** Approvals control which commands the agent runs. They don't limit what a command can read. If you give an "Always anywhere" grant to `bash`, `python3` or `node`, the agent can run any code as the same user as netclaw, and that code can open files the command line never names. Path denial can't see inside a program.
5. **Run netclaw in a sandbox when this matters.** Run it as a separate OS user and give that user only the files netclaw needs, or run it in a container. Netclaw has no built-in kernel sandbox for shell commands yet. The work is tracked in [netclaw-dev/netclaw#2343](https://github.com/netclaw-dev/netclaw/issues/2343).

The container route is the one the [Docker deployment](/deployment/docker/) page covers. The image runs the daemon as the non-root `netclaw` user, so the agent sees only what you mount into the container.

## Other limitations

- Prompt injection detection is regex-based. Novel phrasings evade it. Treat it as a tripwire.
- Secret redaction catches known token formats and secret-named variables only. `file_read` and MCP results aren't masked. A custom secret format needs a path or hard-deny rule.
- Content validation checks magic bytes and doesn't deep-scan file contents.
- Releases through 0.27.1 had gaps that are now closed, such as TUI keystrokes written to a temp file and colon keys in `ToolOverrides`. See [Security advisories](/security/hardening/#security-advisories).
- Tool grants are per audience, not per channel. Two Slack channels with the same audience get the same tools.
- There's no per-user identity inside a channel. Everyone in an allowed channel gets that channel's audience.

## Related pages

- [How tool approvals work](/security/approvals/) - modes, outcomes, grants and prompts
- [Reduce or turn off approval prompts](/guides/reduce-approval-prompts/) - stop prompts safely
- [Hardening](/security/hardening/) - lock down a team or internet-facing install
- [Secrets management](/security/secrets/) - encryption at rest and the write-only vault
- [Security architecture](/architecture/security-model/) - why the model is shaped this way

## Resources

- [OWASP LLM Top 10](https://genai.owasp.org/llm-top-10/) - the risk taxonomy netclaw's model is designed against
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework) - federal guidance on AI system risk
- [Model Context Protocol specification](https://modelcontextprotocol.io/specification) - the protocol behind MCP tool servers
- [Shell sandbox tracking issue](https://github.com/netclaw-dev/netclaw/issues/2343) - the planned kernel sandbox for shell commands
