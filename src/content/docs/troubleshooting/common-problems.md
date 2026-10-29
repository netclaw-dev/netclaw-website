---
title: "Troubleshooting by symptom"
description: "Find the error text or behavior you're seeing, get the cause and the fix, and jump to the page that owns the detail."
---

Find the message you're seeing, read the cause and the fix, and follow the link when you need more. This page is an index. Each entry is a short answer, and the linked page has the full story.

## Start here

Three checks work for almost any problem.

1. **Run `netclaw doctor` and `netclaw status`.** Doctor reads `netclaw.json` and the files on disk, so it works with the daemon down. Status asks the running daemon for its health, the active model and each channel's counters. A fresh install with a keyless provider shows `[WARN] Secrets JSON: Secrets file not found`, which is normal. `netclaw daemon status` is the quick check: it exits 0 only when the daemon answers its readiness probe, and 1 with `Daemon is not running.` when it doesn't. See [`netclaw doctor`](/cli/doctor/), [`netclaw status`](/cli/status/) and [`netclaw daemon`](/cli/daemon/).
2. **Read the daemon log.** It's at `~/.netclaw/logs/daemon-YYYY-MM-DD.log`, and a crash writes `crash-*.log` next to it. The daemon deletes both after 14 days by default, so an old failure may already be gone. See [Data retention](/configuration/data-retention/). In Docker, `docker logs` shows only the entrypoint's lines, so read the file with `docker exec <container> sh -c 'tail -n 100 "$(ls -t ~/.netclaw/logs/daemon-*.log | head -1)"'`. Under systemd, `journalctl --user -u netclaw` works too.

   The log rotates at 10 MiB into numbered segments: `daemon-YYYY-MM-DD.log`, then `daemon-YYYY-MM-DD.1.log`, `.2.log` and so on. `grep` over `daemon-*.log` still matches all of them, but pick the newest file by time, not by name, because `.1.log` sorts before the unnumbered file. `Logs:Days` prunes segments too, and `netclaw doctor` reads every segment.
3. **Find out why a tool call was denied or prompted.** Every decision is in the same log:

   ```bash
   grep -E 'Tool authorization|Shell policy trace' ~/.netclaw/logs/daemon-*.log | tail -n 20
   ```

   The `reason=` on a `Denied` line names the rule. [How tool approvals work](/security/approvals/#see-why-a-call-prompted) explains how to read the rows.

An edit to `netclaw.json` restarts the daemon by itself. Changes to `secrets.json` or to environment variables don't, so restart after those. The command depends on how you run it:

| Where it runs | Restart |
|---------------|---------|
| Native | `netclaw daemon stop`, then `netclaw daemon start` |
| systemd user unit | `systemctl --user restart netclaw`. `netclaw daemon stop` and `start` use the unit too |
| Docker | `docker restart <container>` |

## Installing and first start

### `Failed to start daemon: process exited with code 134`

**Symptom:** `netclaw init` ends with that line and a stack trace that begins `Process terminated. Couldn't find a valid ICU package installed on the system.` `netclaw daemon start` repeats it.

**Cause:** the daemon needs the ICU library, and minimal Linux images don't ship it. The CLI runs without it, so install and `init` look fine.

**Fix:** install it (`sudo apt-get install libicu74` on Ubuntu 24.04, `libicu` or `icu-libs` elsewhere) and run `netclaw daemon start`. Without package access, `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 netclaw daemon start` works. See [Installation](/getting-started/installation/#failed-to-start-daemon-process-exited-with-code-134).

### `daemon not configured - please run netclaw init`

**Symptom:** `netclaw status` or `netclaw chat` prints this and exits 1, though the daemon is running and a Docker container shows `healthy`.

**Cause:** the CLI refuses to run until `config/netclaw.json` exists. A container configured only with `NETCLAW_*` variables has no such file. The daemon doesn't care, so it runs fine.

**Fix:** run `docker exec -it <container> netclaw init`, or write the config as a file. See [Docker deployment](/deployment/docker/#use-the-cli-put-the-config-in-a-file).

### `netclaw: command not found`

**Symptom:** the install finished and the command isn't there.

**Cause:** your shell started before the installer changed the PATH.

**Fix:** run `. ~/.netclaw/env` or open a new terminal. On a minimal image where the script stops with `Required command 'curl' not found`, install `curl` first. See [Installation](/getting-started/installation/#troubleshooting).

## Config file

### `config on disk not applied`

**Symptom:** you edited `netclaw.json`, nothing changed, and `netclaw status` reports `degraded`:

```text
overall: degraded
config on disk not applied: Models:Roles:Main references unknown definition 'nope'. Defined: stub-stub-model. Fix the name, or run `netclaw model set main <provider> <model>`.
  The daemon is still running the previous configuration. No change from netclaw.json is applied until this is fixed.
```

`netclaw doctor` fails the **Chat Client** check with `Invalid model configuration:` and the same reason.

**Cause:** the `Models` section or a provider entry is invalid. A running daemon refuses the file and keeps its previous config. A daemon that starts with that file exits with code 1 and one line, `error: Models:Roles:Main references unknown definition 'nope'. ...`. In Docker the entrypoint then restarts it every 2 seconds, backing off to 60.

**Fix:** correct the key the message names. The daemon picks up the next valid edit by itself, and a stopped one starts normally. See [Invalid config](/configuration/models/#invalid-config) and, for the restart loop, [Docker deployment](/deployment/docker/#container-keeps-restarting-with-error-modelsroles).

### `Couldn't read netclaw.json`

**Symptom:** `netclaw chat`, `netclaw model list` and every other command that needs the config print one line and exit 1:

```text
Couldn't read netclaw.json: A duplicate key 'configVersion' was found.
```

`netclaw doctor` reports `[FAIL] Config Load` with the same reason and skips the checks that need the config. `netclaw status` prints the line, says it is checking the default port, and carries on. In Docker, the container turns `unhealthy` after a minute or so, because its health check runs `netclaw daemon status`.

**Cause:** `netclaw.json` or `secrets.json` isn't valid JSON. It's empty or cut off, or a key appears twice. The line names the file and the parser's reason. A running daemon stays up on its previous config. A daemon that starts exits with code 1 and prints `error:` plus the same line.

**Fix:** repair the file in an editor, or restore it from a backup. `netclaw update` still works. With a daemon running, `netclaw daemon status` prints `The local daemon address is unknown. No readiness probe was sent. Repair the local configuration and retry.` and exits 1, so the Docker health check reports `unhealthy` until you fix the file. In Docker, copy the file out with `docker cp`, fix it and copy it back. A file with `//` comments or trailing commas is a different case: the CLI reads it, but `netclaw provider add`, `netclaw mcp add` and the other commands that write the file refuse with `Couldn't read netclaw.json: it has comments or trailing commas...` instead of dropping your comments. Remove them first.

## Talking to the model

### `The openai-compatible models API was not found`

**Symptom:** `netclaw model discover` or the `init` provider check ends with the URL it tried:

```text
Error: The openai-compatible models API was not found at http://llm.example.internal:8080/v1/models. Check the endpoint URL, or the service may be down.
```

**Cause:** something answered at that address with a 404, so it isn't an OpenAI-compatible server. A wrong port or a reverse proxy path is the usual reason. netclaw accepts the endpoint with or without a trailing `/v1`.

**Fix:** `curl` the URL from the message on the machine that runs netclaw. When it works there, fix the endpoint with `netclaw provider remove <name>` and add it again. See [Self-hosted providers](/configuration/self-hosted-providers/).

### `Connection failed: Connection refused`

**Symptom:** `Error: Connection failed: Connection refused (llm.example.internal:8080)`. The same line with `Resource temporarily unavailable` means the host name doesn't resolve.

**Cause:** nothing listens on that host and port from where netclaw runs. In a container, `localhost` is the container itself, not your machine.

**Fix:** use an address the container can reach, such as the other container's service name on a shared Docker network. See [Self-hosted providers](/configuration/self-hosted-providers/).

### Turns are slow or time out on a local model

**Symptom:** the first reply takes 30 seconds or more, a tool turn takes minutes, or you see `Context compaction timed out. The session will continue.` or `exceeded watchdog timeout`.

**Cause:** the first turn sends about 10,000 input tokens, and a slow GPU spends most of the time on prompt processing. Compaction and titles have a shorter budget (90 seconds) than the main turn.

**Fix:** wait before assuming it's hung. Raise `Session.SidecarLlmTimeoutSeconds` for compaction timeouts and `Session.NoProgressTimeoutSeconds` for long turns. See [Slow models and timeouts](/configuration/models/#slow-models-and-timeouts).

### The model loops, goes silent or thinks forever

**Symptom:** a channel stays quiet for minutes, the model repeats a tool call, or the reply is raw tool-call XML.

**Cause:** usually the inference server's chat template or tool-call parser, not netclaw. Reasoning models can also produce thinking-only output that never becomes a reply. Netclaw refuses a repeated identical call and stops a turn that keeps failing (see [The turn ended with no error](#the-turn-ended-with-no-error)). `Session.MaxToolIterationsPerTurn` is still read from config but no longer limits a turn.

**Fix:** follow the server-specific checklist: [llama.cpp](/troubleshooting/llama-cpp/#silent-slow-or-endless-thinking) or [vLLM](/troubleshooting/vllm/#silent-or-endless-thinking).

### The turn ended with no error

**Symptom:** a turn stops with whatever text the model had written, and `netclaw chat -p` exits 0.

**Cause:** the loop guard. After two equal rounds, the next identical call is refused and the model gets a nudge. A stronger nudge comes at repeat 5, and at repeat 6 the turn ends quietly. A second counter covers failed calls with no success between them: a nudge at 4, a stronger one at 6, and the turn ends at 8. A success in the batch resets it.

**Fix:** read the session log for the call that repeated and fix what it kept failing on, often a denial or a missing file.

### `The model reply was truncated`

**Symptom:** the turn fails with `The model reply was truncated: the model reached its output limit before it finished. The cut-off text was not posted. Try again with a smaller request.` Headless runs print `[turn:failed] category=model kind=ModelBehavior`, and the log has `turn_reply_truncated`.

**Cause:** the reply hit the output limit. A hosted API gets 32000 tokens by default. A self-hosted server gets a limit only when its context window is known.

**Fix:** ask for less, or change the cap with `netclaw model set <role> <provider> <model> --max-output-tokens N`. A model call that streams only thinking ends the turn at three times `Session.NoProgressTimeoutSeconds` (60 minutes by default).

### The session could not save its progress

**Symptom:** `The session could not save its progress and stopped. Some actions may already have run. Check them before you send your message again.` or the variant `...so this turn failed...`.

**Cause:** the SQLite database stayed locked past the journal write timeout (`Default Timeout` plus 10 seconds) or the disk is full.

**Fix:** free disk space or find the other process holding `netclaw.db`, then check what the turn already did before you resend.

### A thinking level the provider can't send

**Symptom:** the daemon won't start, or `netclaw doctor` fails, with `The <dialect> thinking dialect cannot send thinking level '<level>'. It sends: ...`. A level other than `off` on an Ollama provider with `DisableThinking` fails the same way.

**Cause:** a hand-edited `Thinking` value that the provider dialect can't express.

**Fix:** use `netclaw model set <role> <provider> <model> --thinking <level>`, which lists the levels on offer, or `--clear-thinking`. An `openai-compatible` provider needs `Providers:<name>:VendorOptions:ThinkingDialect` (`ChatTemplateKwargs`, `ReasoningEffort`, `DeepSeek` or `None`) before it can send any level.

### Wrong context window, or images are ignored

**Symptom:** `[compaction]` lines on every turn, `Context window exceeded after compaction`, or a vision model whose images are dropped because `netclaw status` shows `input: Text`.

**Cause:** detection got no data from the provider, or the discovered value became an override.

**Fix:** pin it: `netclaw model set main <provider> <model> --context-window 65536 --input-modalities "Text, Image"`. See [Context window and modalities](/configuration/models/#context-window-and-modalities).

### An OpenAI-compatible cloud endpoint returns HTTP 400

**Symptom:** a turn ends with `LLM provider returned an error (HTTP 400). Please try again.` and headless `netclaw chat -p` exits 1. The session's log under `~/.netclaw/logs/` has the server's reason: `feature 'extra arguments: {"return_progress":true}' is not currently supported`, seen on Azure Foundry and OVHcloud.

**Cause:** netclaw sends a llama.cpp keepalive option that some hosted endpoints reject. It's an open bug, [netclaw#1566](https://github.com/netclaw-dev/netclaw/issues/1566).

**Fix:** see the workaround and its caveats in [Managed providers](/configuration/managed-providers/).

## Tools and approvals

### The chat or bot looks frozen

**Symptom:** a Slack, Discord or Mattermost bot stops replying, or `netclaw chat` sits at `Approval required`.

**Cause:** a prompt is waiting. Approval prompts never time out, and only the person who started the request can answer.

**Fix:** answer it. **Once** or **Deny** end the wait. A sub-agent's prompt takes button clicks only, holds the parent's reminder fires and further `spawn_agent` calls while it's open, and a Mattermost binding with no `CallbackUrl` refuses it. To stop it happening, grant the command ahead of time. See [Reduce or turn off approval prompts](/guides/reduce-approval-prompts/#the-bot-looks-frozen).

### I chose Always and it still asks

**Symptom:** the same command prompts again after an **Always** answer.

**Cause:** a grant matches a command phrase, a scope and an audience, and the next call differs in one of them. Wrappers like `timeout` or `env`, compound commands and a different folder are the usual reasons.

**Fix:** `netclaw approvals list` shows what you saved. Compare it with the call. See [Always doesn't stick](/guides/reduce-approval-prompts/#always-doesnt-stick).

### The prompt only offers Once and Deny

**Cause:** netclaw offers a saved grant only when it can prove a reusable phrase. Commands built from variables, `..` paths that leave a symlink and non-shell tools fall back to Once and Deny.

**Fix:** ask the agent for the command with literal arguments, or pre-grant the plain phrase with [`netclaw approvals trust-verb`](/cli/approvals/).

### `tool_not_allowed_for_audience_profile`

**Symptom:** a tool result says `Tool access denied: tool_not_allowed_for_audience_profile`.

**Cause:** the audience doesn't have that tool. Team and Public have no `shell_execute`, and Public has no reminder or web tools. No grant changes this.

**Fix:** use a Personal session, or change the audience's tool list. See [Unattended runs](/guides/unattended-runs/#tool_not_allowed_for_audience_profile).

### `Access denied: ... is protected`

**Symptom:** a file tool returns `Error: Access denied: '/home/netclaw/.netclaw/config/test.json' is protected (Netclaw control plane, or a credential location such as ~/.ssh, ~/.aws or ~/.kube) and cannot be modified by agent tools, even with approval.` A shell command that names such a path returns `Tool access denied: shell_references_protected_path`.

**Cause:** the agent reached for something netclaw keeps from it. That's the control plane (`~/.netclaw/config/`, the keys, the database, lifecycle files) and these credential locations: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.azure`, `~/.config/gh`, `~/.config/gcloud`, `~/.docker/config.json`, `~/.netrc` and `~/.git-credentials`. The check runs before any approval mode, so `Auto`, `ToolOverrides` and audience profiles can't lift it.

**Fix:** make the change yourself, with `netclaw config`, `netclaw secrets set` or your own shell. `ssh`, `git` and `aws` still use their credentials when the agent runs them. See [Security model](/security/security-model/#credential-locations).

### The shell tool says `command not found` under systemd

**Cause:** the unit's PATH lacks the directory your binaries live in, often `~/.local/bin`.

**Fix:** run `netclaw doctor`, then `netclaw daemon uninstall`, `netclaw daemon install` and `systemctl --user restart netclaw`. See [systemd](/deployment/systemd/#shell-tool-cant-find-netclaw-or-other-user-installed-binaries).

## Reminders and unattended runs

### `Invalid CRON_TZ prefix`

**Symptom:** creating a reminder fails with `[FAIL] Error: Invalid CRON_TZ prefix. Unknown time zone 'Nowhere/Land'. Use an IANA id such as America/Chicago.`

**Cause:** the time zone name is misspelled, or the host has no time zone database. Minimal Linux images lack `tzdata`, and then a valid name such as `America/Chicago` gets the same error.

**Fix:** use an IANA name with no spaces, and install `tzdata` on a minimal host. See [Time zones](/configuration/reminders/#time-zones).

### A reminder run shows `denied`

**Symptom:** `netclaw reminder history <id>` shows `denied` and the work wasn't done:

```text
2026-10-14 03:36:03Z  denied — Tool call denied (shell_execute): Tool access denied: shell_execute needs approval, and nobody can answer a prompt in an unattended run. Save an "Always" grant for this call in a chat with the same audience (for example with /run-reminder), then run it again.
```

The daemon also raises a `reminder.tool_denied` [alert](/observability/operational-alerts/), once per reminder for each distinct reason until a run succeeds. The log has `approval_required_unattended`.

**Cause:** the agent called a tool that needs approval and nobody could answer. A denied run isn't retried and doesn't count toward auto-disable. A denied one-shot ends as failed and deletes itself. Its denial text and prompt stay in a 12-day end record, so run `netclaw reminder status <id>` to read them.

**Fix:** run the reminder once in a chat with `/run-reminder <id>`, answer **Always here** or **Always anywhere**, or pre-grant with `trust-verb`. Then the next scheduled run goes through. See [Run reminders, webhooks and scripts unattended](/guides/unattended-runs/#reminder-shows-denied-and-nothing-happened).

### A webhook returned 202 and nothing happened

**Cause:** the delivery was filtered (`"status":"ignored"` in the body), or the session ran and a tool call was denied.

**Fix:** read the response body, then the webhook's session log. See [Unattended runs](/guides/unattended-runs/#webhook-returned-202-and-nothing-happened).

### A cron reminder fires at the wrong hour

**Cause:** cron runs in UTC unless the expression says otherwise.

**Fix:** prefix it: `CRON_TZ=America/Chicago 0 9 * * *`. See [Reminders](/configuration/reminders/#cron-fires-at-the-wrong-hour).

## Channels

### The bot is connected but never answers

**Symptom:** `netclaw status` shows `recv` rising and `routed` at 0.

**Cause:** an allow-list rejected the message. The log names the reason: `channel_not_allowed` (the most common setup mistake), `user_not_allowed` or `DmNotAllowed`.

**Fix:** add the channel or user ID. See [Channel troubleshooting](/channels/troubleshooting/#the-bot-is-connected-but-silent).

### The bot stopped answering in a thread

**Cause:** `MentionRequiredInThreadByChannel` is on for that channel, so thread replies need an @mention. Channels added as `team` or `public` start with it on.

**Fix:** mention the bot. See [Channel troubleshooting](/channels/troubleshooting/#the-bot-stopped-answering-in-a-thread).

### Approval buttons or letters do nothing

See [Channel troubleshooting](/channels/troubleshooting/#approvals-dont-work). Button approvals on Mattermost need a non-local [exposure mode](/deployment/exposure-modes/).

## Memory

### It keeps repeating something wrong

**Cause:** a bad memory was stored, often from a failed attempt, and recall keeps injecting it. Fixing one memory doesn't stop a new one forming from the same conversation.

**Fix:** ask the agent to find, correct or delete it, and name the `delete` flag of `update_memory` for a deletion. See [Fix a wrong memory](/configuration/memory/#fix-a-wrong-memory).

### Doctor says documents lack a current-model embedding

**Symptom:** `[WARN] Memory Embeddings: <n> of <total> recallable documents lack a current-model embedding.`

**Cause:** memories written while embeddings were off, or under an older embedding model.

**Fix:** the daemon heals the gap at its next startup. To do it now, run `netclaw memory backfill-embeddings`. With embeddings off it prints `Embeddings are disabled (Memory.Embeddings.Enabled is false); nothing to backfill.` and exits 0. See [`netclaw memory`](/cli/memory/).

### Embeddings never become ready

**Symptom:** the daemon log has `memory_embedding_unavailable model=snowflake-arctic-embed-m-int8 reason=Resource temporarily unavailable (huggingface.co:443)`, `netclaw doctor` warns `Embedding model 'snowflake-arctic-embed-m-int8' is not yet provisioned`, and recall falls back to full-text search. With `AutoDownload` off the doctor check fails instead.

**Cause:** the host can't reach `huggingface.co`, where the daemon downloads two models (about 130 MB) on first start. Behind a proxy, set `HTTPS_PROXY` for the daemon.

**Fix:** copy the models in and set `Memory.Embeddings.AutoDownload` to `false`, or turn embeddings off. See [Run offline](/configuration/memory/#run-offline).

## Docker and upgrades

### The container is OOM-killed, exit code 137

**Symptom:** `docker ps` says `running` and `healthy`, but `docker logs` repeats `Killed` and `netclawd exited (code=137)`, and `docker inspect --format '{{.State.OOMKilled}}' <container>` prints `true`.

**Cause:** the memory limit is too low for the embedding models. A 512 MiB limit is OOM-killed again and again while the entrypoint keeps restarting the daemon, so the container never stops. 768 MiB is stable.

**Fix:** set 1 GiB or more, or set `NETCLAW_Memory__Embeddings__Enabled=false`. See [Memory and first start](/deployment/docker/#memory-and-first-start).

### The container restart-loops with `has list items and also a value`

**Symptom:** `docker logs` shows `Fatal error`, `Configuration key 'Tools.AudienceProfiles.Team.AllowedTools' has list items and also a value. One source sets items and another source sets a value.`, then `Aborted (core dumped)` and `restarting in 2s`, with the delay growing to 60 seconds.

**Cause:** an empty `NETCLAW_*` list variable sits next to a list in `netclaw.json`.

**Fix:** set a list in the file or in env vars, never both. Remove the empty variable and recreate the container. See [Docker deployment](/deployment/docker/#use-the-cli-put-the-config-in-a-file).

### The container restart-loops after a restore: `Failed to convert configuration value 'ENC:...'`

**Symptom:** `docker logs` repeats one line and `netclawd exited (code=1)`:

```text
error: Invalid model configuration: Providers:lab is invalid: Failed to convert configuration value 'ENC:...' at 'Providers:lab:ApiKey' to type 'Netclaw.Configuration.SensitiveString'. Fix the Providers section of netclaw.json.
```

**Cause:** `secrets.json` came back without `keys/`, so netclaw can't decrypt the stored secrets.

**Fix:** stop the container, unpack `keys/` from the backup, start it again. If the keys are lost, delete `config/secrets.json` and set each secret again. See [Back up, restore and move](/guides/backup-and-restore/#the-container-is-unhealthy-after-a-restore).

### `Failed to initialize Netclaw directories` on a bind mount

**Symptom:** the container exits at once with `Failed to initialize Netclaw directories under '/home/netclaw/.netclaw'.` and a list of `Access to the path ... is denied`.

**Cause:** the mount is read-only, or the container runs as `user: "1654:1654"` against a directory someone else owns.

**Fix:** make it writable, or `chown -R 1654:1654` the host directory. See [Docker deployment](/deployment/docker/#permission-denied-on-a-bind-mount).

### `netclaw daemon start` does nothing in a container

**Symptom:** it prints `Daemon managed by container supervisor (PID 34).` and starts nothing. With the daemon down it says the supervisor owns startup and exits 1. `netclaw daemon stop` stops the daemon, and the entrypoint brings it back two seconds later.

**Cause:** the image's entrypoint supervises the daemon and restarts it whenever it exits.

**Fix:** use `docker restart <container>`. See [`netclaw daemon`](/cli/daemon/#restart-the-daemon).

### I changed a setting and nothing happened

**Cause:** only an edit to `netclaw.json` restarts the daemon, and only when the file is valid. Secrets, environment variables and the image don't restart it, and an invalid `Models` section is refused (see [`config on disk not applied`](#config-on-disk-not-applied)).

**Fix:** restart with the command in the [table above](#start-here). Env vars also override the file, so a value set with `-e` can't be changed by `netclaw config`.

### A script or app gets 401 on the daemon's own machine

**Symptom:** a request to the daemon returns `401`, and the log has `Refused loopback request: Host is not a loopback name` or `Origin does not match Host`.

**Cause:** in `Local` exposure mode the daemon accepts a request only when `Host` is `localhost` or a loopback IP and any `Origin` matches. Another host name or a browser app on another local port is refused.

**Fix:** call `http://127.0.0.1:<port>` or `http://localhost:<port>`, or [pair the device](/guides/pairing-remote-devices/).

### `Nothing was stopped. PID <pid> is not shown to serve <home>.`

**Symptom:** `netclaw daemon stop` or `netclaw update` prints this and changes nothing.

**Cause:** the CLI sends no signal until it proves the PID serves this home. The proof fails for a stale PID file, a wedged daemon of this home, a lock held with no PID file, or an update from a pre-0.28 daemon on macOS or Windows.

**Fix:** check the PID is the netclaw daemon, run the `kill <pid>` command the message prints (Task Manager on Windows), then run the command again.

### The daemon won't start after an upgrade

**Cause:** the new version rejects something in your config, or a record from an older version failed to load. A `Providers:<name>` error means a provider's stored token or expiry is unusable, so run `netclaw provider` and sign in again. `netclaw doctor --fix` never removes a key under `Models` or a key that holds a credential. It writes `netclaw.json.removed-keys.bak` before it removes keys, and `netclaw.json.retired-oauth-expiry.bak` when it moves an `OAuthTokenExpiry`.

**Fix:** read the `error:` line in `docker logs`, or the newest `logs/crash-*.log` for a crash. Roll back if you can't fix it quickly. See [Upgrade netclaw](/guides/upgrading/#the-daemon-wont-start-after-an-upgrade).

## Related pages

- [FAQ](/troubleshooting/faq/): short answers to the questions people ask first
- [Glossary](/reference/glossary/): the terms these entries use
- [Channel troubleshooting](/channels/troubleshooting/): Slack, Discord and Mattermost symptoms in depth
- [llama.cpp troubleshooting](/troubleshooting/llama-cpp/): template, tool-call and timing problems
- [vLLM troubleshooting](/troubleshooting/vllm/): parser, vision and context problems

## Resources

- [netclaw issue tracker](https://github.com/netclaw-dev/netclaw/issues): search for an error string before filing a new report
- [.NET globalization and ICU](https://learn.microsoft.com/en-us/dotnet/core/extensions/globalization-icu): why the daemon needs ICU
- [Docker health checks](https://docs.docker.com/reference/dockerfile/#healthcheck): how `unhealthy` is decided
