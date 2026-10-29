---
title: "Secrets management"
description: "How netclaw encrypts credentials at rest, keeps the agent away from them, and scrubs them from tool output."
---

Netclaw encrypts the credentials in `secrets.json` at rest using [ASP.NET Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction). Key material lives in `~/.netclaw/keys/`, separate from `secrets.json`, so copying the secrets file alone isn't enough to decrypt it. The one exception is webhook route files, which hold each route's HMAC verification secret in plain JSON and are protected by path denial rather than encryption.

:::note
The goal isn't bulletproof encryption. Anyone with shell access to the machine as the same user can decrypt these values. The goal is to stop the *agent* from reading raw credentials during tool use. Encryption at rest means a copy of `secrets.json`, such as a backup or a leaked volume, is ciphertext and not your API keys. The agent can't read the file at all: `file_read` and shell reads of it are denied.
:::

Three layers protect credentials. Encryption keeps `secrets.json` opaque, and path denial blocks the agent from reading netclaw's secret files. Output redaction is a third, much weaker layer: it masks known token formats and secret-named variables in tool output and shouldn't be counted on for anything beyond that.

To add credentials for the first time, use [`netclaw init`](/cli/init/). To add or rotate keys on an existing install, use [`netclaw secrets`](/cli/secrets/).

## How encryption works

Netclaw wraps the [ASP.NET Data Protection API](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) with the application name `Netclaw` and a purpose string of `Netclaw.Secrets.v1`, so keys can't be cross-used between subsystems. It's standard .NET cryptography through `IDataProtector.Protect()` and `Unprotect()`, not a custom scheme.

Secrets are encrypted the moment you run `netclaw secrets set`, complete `netclaw init` or add an MCP server with env vars, headers or an OAuth client secret. Encrypted values carry an `ENC:` prefix:

```json
{
  "Slack": {
    "BotToken": "ENC:CfDJ8N2x...long-base64-string..."
  },
  "Providers": {
    "openrouter": {
      "ApiKey": "ENC:CfDJ8K9y...long-base64-string..."
    }
  }
}
```

Re-encrypting an already encrypted value is safe. The writer skips values that already have the prefix.

## Storage layout

| Path | Contents | Permissions |
|------|----------|-------------|
| `~/.netclaw/config/secrets.json` | Encrypted credential values, plus each provider's `OAuthTokenExpiry` date in plain text | `chmod 600` on Unix |
| `~/.netclaw/keys/` | Data Protection key material | Owner-only on Unix |

The expiry date is the one plain-text value on purpose. It is refresh timing, not a credential, and the config binder can't read an encrypted date. A token refresh writes it to `secrets.json` and doesn't touch `netclaw.json`, so it no longer restarts the daemon. `netclaw secrets set` rejects an expiry that isn't an ISO 8601 date. If `netclaw.json` still holds an old `OAuthTokenExpiry`, `netclaw doctor --fix` moves it.

You need both to decrypt. `secrets.json` without `keys/` is locked ciphertext, and the keys without the file have nothing to decrypt. Back them up together. On Windows, netclaw relies on user-profile ACLs instead of file modes.

## Configuration layering

The highest priority wins:

| Priority | Source | Use |
|----------|--------|-----|
| 1 | `NETCLAW_*` environment variables | CI, containers, temporary overrides |
| 2 | `secrets.json` (encrypted) | Persistent credentials |
| 3 | `netclaw.json` (plaintext) | Non-sensitive configuration |

Environment variable names use the `NETCLAW_` prefix with double underscores for nesting, following the [.NET convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider). `NETCLAW_Slack__BotToken` maps to `Slack.BotToken`, and case matters on Linux.

## Agent isolation

The [security model's](/security/security-model/#protected-paths) protected-path rules keep the agent away from credential storage:

- `~/.netclaw/config/secrets.json` is denied for read and write.
- `~/.netclaw/keys/` is denied for read and write.
- `~/.netclaw/config/webhooks/` is denied for read and write, because route files hold HMAC secrets.
- The SQLite database, process-control files and the tooling shadow directory are also read-denied.
- From 0.28.0, the credential folders of other tools are denied for read and write as well: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.kube`, `~/.azure`, `~/.config/gh`, `~/.config/gcloud`, `~/.docker/config.json`, `~/.netrc` and `~/.git-credentials`. `cat ~/.aws/credentials` is denied with `shell_references_protected_path`, and `file_read` returns an access-denied error. `ssh`, `git` and `aws` still use those files when they run.

Netclaw resolves symlinks before checking, so `ln -s ~/.netclaw/keys/ ./sneaky` doesn't bypass the rule. It also denies glob, brace and ANSI-C quoted spellings that could reach a protected path, such as `cat ~/.netclaw/k*/*.xml`. A denied call fails and the agent gets an error.

The agent can use credentials, because they're injected into provider connections at startup. It can't read, modify or exfiltrate the raw values. The rest of `~/.netclaw/config/` is readable but not writable, so the agent can read `netclaw.json` and the other config files. Only the files that hold secrets are read-denied.

Path denial protects netclaw's store and that fixed list. It doesn't protect credentials kept anywhere else on the machine, such as a project `.env` file. See [what netclaw doesn't protect against](/security/security-model/#what-netclaw-doesnt-protect-against).

## Output redaction

A secret can still leak through tool output, such as an API key echoed in a curl response or a token in a log. The output redactor replaces secret-shaped text in tool output with `***REDACTED***` before the model sees it. It's a tripwire. Don't rely on it to keep credentials out of model context.

| Pattern | Examples |
|---------|----------|
| Known token formats | `sk-*`, `xox*-*`, `xapp-*`, `ghp_*`, `github_pat_*`, `AKIA*` and `ASIA*` (AWS), Stripe `sk_live_*` and `whsec_*`, Google `AIza*`, `npm_*`, PyPI, Discord bot tokens |
| Slack webhook URLs | `https://hooks.slack.com/services/...` |
| Auth headers | `Authorization` and `Proxy-Authorization` with Basic, Bearer, Token and similar schemes (the scheme stays), `Cookie`, `Set-Cookie`, `X-Api-Key` and other `*-token` or `*-key` header lines |
| URL credentials | The password in `scheme://user:password@host` |
| Option values | `--password hunter2`, `--token x`, `--api-key x`. Not `--password-file`, `--no-password` or `--next-token` |
| Connection strings | `Password=...;`, `Pwd=...;` |
| JWTs | Three base64 segments starting with `eyJ` |
| PEM private keys | `-----BEGIN * PRIVATE KEY-----` blocks |
| JSON secret fields | Field names that **start with** `api_key`, `token`, `secret`, `password`, `passwd`, `authorization`, `access_token`, `refresh_token`, `client_secret`, `signing_key`, `private_key`, `connection_string`, `credential` or `passphrase` |
| Env-style pairs | `API_KEY=value`, `TOKEN=value`, `PASSWORD=value`. Also names with the word as a segment, such as `DB_PASSWORD`, `GITHUB_TOKEN` and `AWS_SECRET_ACCESS_KEY`, with the whole value masked |

Settings that merely carry those words stay readable: `GH_TOKEN_FILE=/run/secrets/gh`, `MAX_TOKENS=4096`, `NEXT_PAGE_TOKEN=abc` and references like `${{ secrets.GITHUB_TOKEN }}`. In a test on 0.28.2, `cat .env` in the shell came back with `API_KEY`, `DB_PASSWORD`, `GITHUB_TOKEN` and `AWS_SECRET_ACCESS_KEY` masked, the `DATABASE_URL` line as `postgres://app:***REDACTED***@db.internal:5432/app`, and `SESSION_KEY=abcdef123456` as written. This is regex matching, not semantic analysis, so custom secret formats aren't caught.

`file_read` and MCP tool results are the exceptions: they come back unmasked. `file_read` returns the file as it is so an edit doesn't write placeholders into it, and MCP servers are integrations you configured. The tool-call arguments in the daemon and session logs are redacted too, and the spill file behind `tool_output_read` always holds the redacted text.

## Write-only vault

There's no `secrets get`, `secrets list` or `secrets delete`. You write secrets in and never read them back. That removes exfiltration through the CLI: even a successful prompt injection has no netclaw command to dump credentials. To remove a secret, delete the key from `secrets.json` directly. The agent can't touch that file, but you can. To check that secrets are stored properly, run [`netclaw doctor`](/cli/doctor/).

Provider OAuth tokens follow the same rule. The daemon's OAuth status endpoint returns no tokens. During `netclaw provider` sign-in the CLI reads them once from a local-control endpoint, and only with a proof tied to that sign-in. Keep the CLI and daemon on the same version, because a newer CLI with an older daemon shows an upgrade message ([GHSA-fmjr-hw4g-337j](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-fmjr-hw4g-337j)).

## Doctor integration

[`netclaw doctor`](/cli/doctor/) validates the secrets subsystem on every run:

| Check | What it catches |
|-------|-----------------|
| File existence | `secrets.json` missing (a warning, not an error) |
| JSON validity | Malformed JSON that would block config loading |
| File permissions | Group or other bits set on Unix (should be `600`) |
| Encryption status | Plaintext values that should be encrypted (the `OAuthTokenExpiry` date doesn't count) |

If doctor flags an unencrypted value, you need the original plaintext to re-encrypt it. Run `netclaw secrets set <key> <value>` for each one. The value is a command-line argument, so it lands in your shell history.

## Threat model

| Threat | Mitigation |
|--------|------------|
| Secrets at rest on disk | Data Protection encryption and `chmod 600` |
| Agent reads its own credentials | Read and write denial on `secrets.json`, `keys/` and `webhooks/` |
| Secret leaks into tool output | Partial: regex redaction of known token formats and secret-named variables. Not a control to rely on |
| Secret exposed through the CLI | Write-only vault with no read, list or dump command |
| Keys copied to another machine | Both `keys/` and `secrets.json` are required |
| Permission drift after manual edits | `netclaw doctor` flags incorrect modes |
| Keystrokes logged to disk by the TUI | Fixed in 0.28.0. On older installs delete `netclaw-*-trace.log` from the temp folder ([GHSA-mh95-h6p6-c9j3](https://github.com/netclaw-dev/netclaw/security/advisories/GHSA-mh95-h6p6-c9j3)) |

## Recovery

Back up `~/.netclaw/keys/` with `secrets.json`. Without the keys directory, encrypted values are unrecoverable. If `keys/` is deleted or corrupted, re-run `netclaw secrets set` for each credential. There's no other recovery path.

If permissions have drifted, reset them and verify:

```bash
chmod 600 ~/.netclaw/config/secrets.json
netclaw doctor
```

If a secret isn't taking effect, check for an environment variable override first. `NETCLAW_Slack__BotToken` silently beats the `secrets.json` value. The daemon also reads secrets at startup and only restarts itself when `netclaw.json` changes, so restart it after `secrets set`. An OAuth token refresh writes `secrets.json` at run time and doesn't trigger a restart.

## Limitations

- Secrets are portable only if you copy `keys/` and `secrets.json` together.
- There's no built-in key rotation. Running `secrets set` again overwrites a value, but nothing rotates on a schedule.
- Windows relies on user-profile ACLs instead of `chmod`, so permission auditing is less direct.
- It's a single-machine vault, not a team secrets manager. There's no integration with Vault, AWS Secrets Manager or similar.
- Webhook route files aren't encrypted. Keep `~/.netclaw/config/webhooks/` at mode `700`.

## Related pages

- [`netclaw secrets`](/cli/secrets/) - the command reference for setting secrets
- [`netclaw init`](/cli/init/) - stores initial credentials during setup
- [`netclaw doctor`](/cli/doctor/) - validates secrets encryption and permissions
- [Security model](/security/security-model/) - audiences, the order of checks and protected paths
- [Connect an OAuth MCP server](/guides/oauth-mcp-servers/) - where OAuth tokens for MCP servers are stored and refreshed
- [Hardening](/security/hardening/) - file permission lockdown and isolation

## Resources

- [ASP.NET Data Protection overview](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) - the encryption framework netclaw builds on
- [ASP.NET Data Protection key management](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) - how keys are stored and rotated
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) - the double-underscore nesting convention
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) - general credential storage practices
