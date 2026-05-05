---
title: "Secrets Management"
description: "Encrypted credential storage with netclaw secrets."
---

Netclaw encrypts credentials at rest using [ASP.NET Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction). No plaintext secret ever touches disk. Key material lives in `~/.netclaw/keys/`, separate from `secrets.json` — copying the secrets file alone is insufficient to decrypt its values.

:::note
The goal isn't bulletproof encryption — anyone with shell access to the machine can decrypt these values. The goal is preventing the *agent* from accidentally reading raw credentials during tool use. Encryption at rest means `file_read` on `secrets.json` returns ciphertext, not your API keys.
:::

Three layers protect credentials independently: encryption at rest keeps `secrets.json` opaque, ACL denial blocks the agent from reading specific secret files, and output redaction scrubs known secret patterns before the LLM sees them. If one layer fails, the other two still hold.

If you're adding credentials for the first time, start with [`netclaw init`](/cli/init/). To add or rotate keys on an existing install, see [`netclaw secrets`](/cli/secrets/).

## Encryption Architecture

Netclaw wraps the [ASP.NET Data Protection API](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) with an application name of `Netclaw` and a purpose string that scopes encryption to `Netclaw.Secrets.v1` so keys can't be cross-used between subsystems. `DataProtectionSecretsProtector` calls `IDataProtector.Protect()` and `Unprotect()` — standard .NET cryptography, not a custom implementation.

Secrets are encrypted the moment you run `netclaw secrets set` or complete `netclaw init`. Encrypted values are prefixed with `ENC:`:

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

Re-encrypting an already-encrypted value is safe — the writer checks for the `ENC:` prefix and skips values that already have it.

## Storage Layout

| Path | Contents | Permissions |
|------|----------|-------------|
| `~/.netclaw/config/secrets.json` | Encrypted credential values | `chmod 600` (Unix) |
| `~/.netclaw/keys/` | Data Protection key material | Owner-only access (Unix) |

Both paths are required for decryption. `secrets.json` without `~/.netclaw/keys/` is locked ciphertext, and the keys without the secrets file have nothing to decrypt. Back up both together.

On Windows, netclaw relies on user-profile ACLs instead of Unix file modes. Check file properties in the Security tab to verify only your user account has access.

## Configuration Layering

Secrets slot into the standard config priority chain. Highest priority wins:

| Priority | Source | Use Case |
|----------|--------|----------|
| 1 (highest) | `NETCLAW_*` environment variables | CI/CD, containers, temporary overrides |
| 2 | `secrets.json` (encrypted) | Persistent credentials |
| 3 (lowest) | `netclaw.json` (plaintext) | Non-sensitive configuration |

Environment variable names use the `NETCLAW_` prefix with double underscores for nesting, following the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider): `NETCLAW_Slack__BotToken` maps to `Slack.BotToken`. Case matters on Linux.

## Agent Isolation

The [security model's](/security/security-model/) resource hard-deny layer blocks the agent from accessing its own credential storage. These paths are denied for both read and write operations:

- `~/.netclaw/config/secrets.json` — the encrypted credential file
- `~/.netclaw/keys/` — encryption key material
- `~/.netclaw/config/webhooks/` — webhook route configurations with HMAC secrets

Symlinks are resolved before path checks, so `ln -s ~/.netclaw/keys/ ./sneaky` won't bypass the policy. If the agent tries to access a denied path, the operation is blocked and the tool call fails. The agent can *use* the credentials (they're injected into provider connections at startup) but can never read, modify, or exfiltrate the raw values.

Note that `netclaw.json` itself is readable by the agent — only files containing secrets are denied.

## Output Redaction

Even with encryption and path denial, a secret can leak through tool output — an API key echoed in a curl response, a token appearing in a log. `SecretOutputRedactor` scrubs tool output before the LLM sees it, replacing matches with `***REDACTED***`.

Patterns it catches:

| Pattern | Examples |
|---------|----------|
| Provider API keys | `sk-*`, `ghp_*`, `AKIA*` (AWS) |
| Slack tokens | `xoxb-*`, `xoxp-*`, `xoxa-*`, `xoxr-*`, `xoxs-*` |
| Auth headers | `Authorization: Bearer <token>` |
| Connection strings | `Password=...;`, `Pwd=...;` |
| JWT tokens | Three-segment base64 starting with `eyJ` |
| PEM private keys | `-----BEGIN * PRIVATE KEY-----` blocks |
| JSON secret fields | Keys matching `api_key`, `token`, `secret`, `password`, `authorization`, `access_token`, `refresh_token`, `client_secret`, `signing_key`, `private_key`, `connection_string`, `credential` |
| Environment variables | `API_KEY=value`, `TOKEN=value`, `PASSWORD=value`, etc. |

This is regex-based pattern matching, not semantic analysis. Custom or unusual secret formats won't be caught.

## Write-Only Vault

There is no `secrets get`, `secrets list`, or `secrets delete` command. Write secrets in, never read them back. This eliminates exfiltration via CLI: even if an attacker triggers a prompt injection, there's no netclaw command to dump credentials.

To remove a secret, delete the key from `~/.netclaw/config/secrets.json` directly. The agent can't touch this file, but you can. To verify secrets are properly stored, run [`netclaw doctor`](/cli/doctor/).

## Doctor Integration

[`netclaw doctor`](/cli/doctor/) validates the secrets subsystem on every run:

| Check | What It Catches |
|-------|----------------|
| File existence | `secrets.json` missing (warning, not error) |
| JSON validity | Malformed JSON that would prevent config loading |
| File permissions | Group or other read/write bits set on Unix (should be `600`) |
| Encryption status | Plaintext values that should be encrypted |

If doctor flags unencrypted values, you'll need the original plaintext to re-encrypt: run `netclaw secrets set <key> <value>` for each one.

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| Secrets at rest on disk | AES encryption via Data Protection API; `chmod 600` file permissions |
| Agent reads its own credentials | Resource hard-deny on `secrets.json`, `keys/`, and `webhooks/` |
| Secret leaks into tool stdout | Regex-based output redaction before LLM ingestion |
| Secret exposed via CLI command | Write-only vault with no read/list/dump commands |
| Encryption keys copied to another machine | Keys and secrets both required — `secrets.json` alone is useless |
| Permission drift after manual edits | `netclaw doctor` flags incorrect file modes |

## Recovery

Back up `~/.netclaw/keys/` alongside `secrets.json`. Without the keys directory, encrypted values are unrecoverable.

If `~/.netclaw/keys/` is deleted or corrupted, re-run `netclaw secrets set` for each credential. There's no other recovery path.

If file permissions have drifted, reset them and verify:

```bash
chmod 600 ~/.netclaw/config/secrets.json
netclaw doctor
```

If a secret isn't taking effect, check for environment variable overrides. `NETCLAW_Slack__BotToken` silently wins over the `secrets.json` value. `netclaw doctor` helps diagnose layering issues.

## Limitations

- Secrets are portable only if you copy both `~/.netclaw/keys/` and `~/.netclaw/config/secrets.json` together. The keys directory contains the Data Protection key ring needed to decrypt values.
- No built-in key rotation. Re-running `secrets set` overwrites the previous value, but there's no automated rotation schedule.
- Windows relies on user-profile ACLs rather than explicit `chmod`, so permission auditing is less straightforward.
- Single-machine vault, not a team secrets manager. No integration with external secret stores (Vault, AWS Secrets Manager, etc.).

## Related Pages

- [`netclaw secrets`](/cli/secrets/) — CLI command reference for setting secrets
- [`netclaw init`](/cli/init/) — stores initial credentials during first-run setup
- [`netclaw doctor`](/cli/doctor/) — validates secrets encryption and file permissions
- [Security Model](/security/security-model/) — default-deny architecture and the invocation stack
- [Hardening](/security/hardening/) — file permission lockdown and operational best practices

## Further Reading

- [ASP.NET Data Protection overview](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) — the encryption framework netclaw builds on
- [ASP.NET Data Protection key management](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) — how encryption keys are stored and rotated
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) — the double-underscore nesting convention
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) — general best practices for credential storage
