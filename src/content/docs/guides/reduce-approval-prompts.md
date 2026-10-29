---
title: "Reduce or turn off approval prompts"
description: "Stop netclaw asking you to approve shell commands and tools: pre-approve a command, set a tool to Auto, or turn prompts off for a personal install."
---

Netclaw asks before it runs shell commands on the Personal audience, and before MCP tools you've set to `Approval`. You can stop most of those prompts without turning off the protections underneath. Pick the smallest change from the table. There's no single off switch, and for a solo user the smallest config that gets to "never ask me" is one line, shown [below](#turn-approvals-off-for-a-personal-single-user-install).

:::caution
Turning prompts off doesn't make shell safe. Hard deny and protected paths still apply, and that includes credential folders such as `~/.ssh` and `~/.aws`. Beyond those the agent reads whatever your OS user can read, and runs everything it decides to run. If the machine holds credentials you care about, run netclaw as a separate user or in a container first. See [what netclaw doesn't protect against](/security/security-model/#what-netclaw-doesnt-protect-against).
:::

| I want to | Do this |
|-----------|---------|
| Stop prompts for one command or a family of commands | [`netclaw approvals trust-verb "git push"`](#stop-prompts-for-one-command-or-command-family) |
| Stop all shell prompts for me | [Set `ToolOverrides.shell_execute` to `Auto`](#stop-all-shell-prompts) |
| Stop prompts for file writes to the config directory | [You can't. Those calls are denied, not prompted](#stop-prompts-for-file-writes-to-config) |
| Stop prompts for one MCP server or tool | [`McpServerDefaults` or `ToolOverrides` to `Auto`](#stop-prompts-for-one-mcp-server-or-tool) |
| Let a reminder or webhook use tools unattended | [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/) |
| Turn approvals off entirely on a personal single-user install | [One `shell_execute` override](#turn-approvals-off-for-a-personal-single-user-install) |

To find out why a specific call prompted before you change anything, read the [policy trace](/security/approvals/#see-why-a-call-prompted) in the daemon log.

## Stop prompts for one command or command family

Answer **Always anywhere** the next time the prompt appears, or pre-approve the phrase from the CLI:

```bash
netclaw approvals trust-verb "git config"
netclaw approvals trust-verb mkdir
```

Two or more words cover those words and any arguments after them, so `git config --global user.name x` runs without a prompt and `git remote -v` still prompts. One word covers the program alone. To approve a family, grant its first two words, as in `gh pr` for `gh pr create`, `gh pr merge` and the rest. `trust-verb` accepts one static command, with no flags, redirects, variable assignments or `&&`.

You can check it with a headless call. Before the grant, `git config --global user.name tester` is denied with `approval_required_unattended`, which is what a prompt becomes when nobody can answer. After `trust-verb "git config"` the same call returns `Exit code: 0`, and `git remote -v` is still denied.

**What you give up:** the agent can run that phrase in any directory, with any arguments, without asking. Don't grant `bash`, `sh`, `python3`, `node` or anything else that runs code, because that's the same as turning shell prompts off.

**Undo:** `netclaw approvals list`, then `netclaw approvals revoke 'Bash token-prefix "git config" anywhere'`. See [`netclaw approvals`](/cli/approvals/).

## Stop all shell prompts

On Personal, `shell_execute` is fail-closed. Netclaw checks that rule before it reads `DefaultMode`, so only an exact `shell_execute` entry turns the prompt off:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "ToolOverrides": {
            "shell_execute": "Auto"
          }
        }
      }
    }
  }
}
```

Save it in `~/.netclaw/config/netclaw.json`. The daemon restarts itself shortly after, once active sessions drain. This applies to every Personal-audience session: the TUI, the web client, headless `netclaw chat -p`, and any Slack, Discord or Mattermost channel or DM you've mapped to Personal. Team and Public never get shell.

:::caution
Two things that look like they should work don't:

- **`DefaultMode: "Auto"` alone.** It's already the default, and the fail-closed check runs first. With only `DefaultMode: "Auto"` set, a `mkdir` call is still denied.
- **Deleting the `shell_execute` entry.** Netclaw adds `shell_execute: Approval` for Personal posture itself, so removing your line puts you back to prompting.
:::

With the override in place, a headless call that was denied before (`mkdir /tmp/work`) returns `Exit code: 0`, and so do `git remote -v` and `rm -r /tmp/work`. `sudo true` is still denied with `hard_deny_privilege_escalation`, because hard deny runs before modes.

**What you give up:** every shell command the agent chooses to run executes immediately, including ones a prompt-injected message or document talks it into. On Personal, read-only commands in the reviewed-safe catalog, such as `cat` and `ls`, already run without a prompt on any path your OS user can read. `secrets.json`, netclaw's own control-plane files and credential folders such as `~/.ssh` and `~/.aws` are denied. Other secrets, such as a project `.env`, are readable, and output redaction masks only some of them. So the main change is that writes, installs and network calls now run too. Hard deny and protected paths still apply. `netclaw doctor` warns about this setting.

**Undo:** delete the `shell_execute` line, or set it to `"Approval"`.

## Stop prompts for file writes to config

You can't, and you shouldn't want to. A `file_write` or `file_edit` aimed at `~/.netclaw/config/` isn't a prompt, it's a denial:

```text
Error: Access denied: '/home/netclaw/.netclaw/config/notes.txt' is protected (Netclaw control plane, or a credential location such as ~/.ssh, ~/.aws or ~/.kube) and cannot be modified by agent tools, even with approval. Do not retry through another tool or path. ...
```

The path policy denies writes under the config directory before approval modes are consulted. No override or grant changes that. A `ToolOverrides` key that contains a `:` is ignored (see [Override keys](#override-keys)), and `netclaw doctor` reports it as an error. To change config, edit `netclaw.json` yourself or use the `netclaw` commands that write it.

## Stop prompts for one MCP server or tool

`netclaw mcp add` already sets your Personal mode for a new server to `Auto`. If a server or tool is on `Approval`, set it back in `ApprovalPolicy`:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "McpServerDefaults": {
            "demo-utilities": "Auto"
          },
          "ToolOverrides": {
            "demo-utilities/calculate": "Auto"
          }
        }
      }
    }
  }
}
```

`McpServerDefaults` covers every tool on the server, including ones discovered later. `ToolOverrides` takes `server/tool` and beats the server default, so you can keep a server on `Approval` and open one tool. You can also press `M` on a server row or `P` on a tool row in `netclaw mcp permissions` to set the same thing without editing JSON.

To pre-approve one tool with a saved grant instead, the phrase has to be the canonical tool name:

```bash
netclaw approvals trust-verb demo-utilities/calculate --tool demo-utilities/calculate
```

With the server on `Approval`, a headless call to `demo-utilities/calculate` is denied with `approval_required_unattended`. Adding `"demo-utilities/calculate": "Auto"` to `ToolOverrides` lets that tool return `42` while `demo-utilities/generate_uuid` is still denied. Setting `McpServerDefaults` to `Auto` lets `generate_uuid` run too. `trust-verb calculate --tool demo-utilities/calculate` is refused with exit 1 and prints the command that works, because the phrase isn't the tool's canonical name.

### Override keys

`ToolOverrides` and `McpServerDefaults` keys are tool names (`shell_execute`) or MCP tools as `server/tool` (or `server__tool`). A few rules:

- **Matching ignores case.** `Shell_Execute` and `shell_execute` are the same key. If two keys differ only by case, the stricter mode wins (`Deny` over `Approval` over `Auto`), so spelling can never loosen a restriction.
- **A key with a `:` is ignored.** The configuration binder reads a colon as a section separator, so `file_write:control-plane` creates no override and the tool keeps the audience default. The daemon logs a warning at startup for each such key, and `netclaw doctor` reports an error on `Tool Audience Profiles`. `netclaw doctor --fix` doesn't change these keys. Rename each one to the tool you meant, or delete it.
- **A key with no value is ignored** (`null`, `{}` or `[]`).

:::caution
Upgrading from 0.27.1 or older? There, a key with a `:` set the whole tool to `Auto`. `file_write:control-plane` set the whole `file_write` tool to `Auto`. Remove every `ToolOverrides` key that contains a `:` and use the plain tool name or `server/tool`. See [GHSA-85pr-m799-g776](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-85pr-m799-g776).
:::

**What you give up:** the tool runs with whatever arguments the agent picks. For a tool that deletes or sends things, keep `Approval` and use a saved grant only for the harmless ones.

**Undo:** delete the entries, or set them to `Approval`. Revoke a saved grant with `netclaw approvals revoke --tool demo-utilities/calculate --all`.

See [MCP tool permissions](/guides/mcp-tool-permissions/) for the rest of the MCP keys.

## Let a reminder or webhook use tools unattended

Reminders, webhooks and `netclaw chat -p` can't show a prompt, so a call that would prompt is denied with `approval_required_unattended`. A tool set to `Auto` or covered by a saved "Always" grant still runs. The full recipe, including how to collect grants with `/run-reminder`, is in [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/).

## Turn approvals off for a personal single-user install

There's no `approvals off` setting. No posture, `DefaultMode` value or `netclaw config` screen disables prompts. What exists is per-tool modes, and on a Personal install only two things prompt out of the box: `shell_execute`, and MCP tools you've put on `Approval`. The smallest config that stops all of it is the shell override:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "ToolOverrides": {
            "shell_execute": "Auto"
          }
        }
      }
    }
  }
}
```

Every other Personal tool is `Auto` already, and MCP servers you add with `netclaw mcp add` are `Auto` for Personal. If you've set `DefaultMode` or `McpServerDefaults` to `Approval` yourself, change those too.

Is that reasonable? On a machine that's yours and holds nothing you can't afford the agent to read or run, yes. It's a poor idea if the machine is shared, holds production credentials, or if any Slack or Discord channel is mapped to Personal, because then anyone who can message that channel is driving a shell. In those cases keep prompts on, grant the commands you use with `trust-verb`, or move netclaw into a container or its own OS user and then turn prompts off inside it.

**Undo:** delete the `shell_execute` line.

## Troubleshooting

### Always doesn't stick

**Symptom:** you answered an Always option and the same command prompts again.

**Cause:** a grant matches a phrase, a scope and an audience, and the next call differs in one of them. Check these in order:

- **Scope.** **Always here** saves the folder of the path the command names, and covers that folder and what's under it. When the last name looks like a file (it has an extension), that's the parent folder: approving `touch /srv/app/new.txt` covers `/srv/app/other.txt` too. When it doesn't (`touch /srv/app/notes`), the saved folder is the path itself, so `touch /srv/app/other` prompts again. A command with no path saves its working directory. See [what Always here covers](/security/approvals/#what-always-here-covers). **This chat** isn't saved at all. Pick **This repository** for a Git project you move around in, or **Always anywhere** for a verb you run on many different files.
- **Phrase.** `gh` covers the program alone, so `gh pr view` isn't covered by it. A grant for `git push` doesn't cover `git pull`.
- **A wrapper.** `timeout 5 mkdir x` and `env A=1 mkdir x` are commands whose program is `timeout` and `env`. With a `mkdir` grant saved, both are still denied. Grant the wrapper phrase too, or ask the agent to run the command without it. `cd /tmp && mkdir x` is fine, because `cd` is in the reviewed-safe catalog.
- **Compound commands.** In `make build && make test`, each command needs its own grant, and the prompt names only the uncovered ones. `mkdir -p x && ls x` runs on a `mkdir` grant alone, because `ls` is in the catalog.
- **Audience.** A Personal grant doesn't apply when a Team session makes the call.

**Fix:** run `netclaw approvals list` and compare the label to the call. Grant the phrase you want with `netclaw approvals trust-verb`. If the daemon log shows `approval_store_unavailable`, the grant file is malformed. See [`netclaw approvals`](/cli/approvals/#upgrade-and-repair).

### I only get Once and Deny

**Symptom:** the prompt has no Always options.

**Cause:** netclaw only offers a saved grant when it can prove a reusable phrase. It falls back to Once and Deny for a command with a word that only has a value at run time (`cat "$f"` over a glob result, `git $(echo status) origin`, a command after `cd "$dir"`), or when a `..` in a path leaves a symlink. A loop over a fixed list of literal values doesn't fall back. Each literal command is judged on its own, so your grants apply. Only the unresolved command gets the Once and Deny prompt, and the other commands keep their grants. A non-shell tool never offers **Always here**, and a shallow directory like `/` or `/etc` doesn't either.

**Fix:** ask the agent to run the command with literal arguments, or answer **Once**. `trust-verb` can still grant the plain phrase ahead of time. A program fed fixed text through a quoted heredoc, as in `python3 - <<'EOF'`, isn't one of these cases: it offers the full set of options, though a grant for `python3` runs any code, so answer **Once** unless you mean it.

### The bot looks frozen

**Symptom:** a Slack, Discord or Mattermost bot stops replying in a thread, or `netclaw chat` sits at "Approval required".

**Cause:** a prompt is pending. A prompt has no timeout. The session waits until the person who started the request answers.

**Fix:** answer it with **Once** or **Deny**. Only the requester can answer, unless the request came from verified automation. A new message in the thread doesn't dismiss a live prompt. It queues behind it. After a daemon restart a new message does abandon the waiting call. If you'd rather it never wait, grant the command ahead of time or set the tool to `Auto`.

A sub-agent's prompt is different. It has buttons only, and a text reply such as `A` answers nothing while two or more prompts are open (`N approval prompts are open. Use the buttons on the prompt you mean.`). A prompt withdrawn because the child was cancelled, ended or lost, because of a restart, or because the channel can't show it reads like `This approval request was withdrawn because the task that asked for it was cancelled. Nothing ran.` A Mattermost binding with no `CallbackUrl` has no buttons and refuses child consent requests.

### A grant I made isn't matching

**Symptom:** `netclaw approvals list` shows the grant, and the call still prompts.

**Cause:** read the shell policy trace in `~/.netclaw/logs/daemon-<date>.log`. A `StoredGrantMatch` row with `TokenMismatch`, `OutsideDirectory`, `ShellMismatch` or `Symlink` says what's off. `OutsideDirectory` usually means the working directory moved, and `ShellMismatch` means the grant was made for PowerShell and the call is Bash.

**Fix:** re-grant with the scope you meant, or use `trust-verb --shell bash` to set the shell explicitly. See [How tool approvals work](/security/approvals/#see-why-a-call-prompted) for how to read the trace.

## Related pages

- [How tool approvals work](/security/approvals/) - modes, outcomes and what each answer saves
- [`netclaw approvals`](/cli/approvals/) - list, revoke and pre-approve grants
- [MCP tool permissions](/guides/mcp-tool-permissions/) - per-server and per-tool modes
- [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/) - tool access without a person present
- [Security model](/security/security-model/) - what netclaw enforces and where a sandbox begins

## Resources

- [GHSA-85pr-m799-g776](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-85pr-m799-g776) - the colon override key advisory, fixed in 0.28.0
- [Tool approval gates runbook](https://github.com/netclaw-dev/netclaw/blob/dev/docs/runbooks/tool-approval-gates.md) - the product's operator runbook and FAQ
- [OWASP LLM Top 10](https://genai.owasp.org/llm-top-10/) - excessive agency and prompt injection, the risks approvals contain
- [Shell sandbox tracking issue](https://github.com/netclaw-dev/netclaw/issues/2343) - the planned kernel sandbox for shell commands
