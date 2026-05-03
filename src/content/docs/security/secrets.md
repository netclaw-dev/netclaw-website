---
title: "Secrets Management"
description: "Encrypted credential storage with netclaw secrets."
---

Netclaw encrypts API keys, tokens, and credentials at rest using [ASP.NET Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction). No plaintext secret ever touches disk. The encryption is machine-bound: keys are tied to the host where they were created and can't be copied to another machine.

Credentials are protected by three independent layers. Encryption at rest keeps `secrets.json` opaque. ACL path denial blocks the agent from reading its own config directory. Output redaction scrubs known secret patterns from tool output before the LLM sees them. If one layer fails, the other two still hold.

For CLI usage and examples, see [`netclaw secrets`](/cli/secrets/).

## Encryption Architecture

Netclaw wraps the [ASP.NET Data Protection API](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) with a purpose string of `Netclaw.Secrets.v1` and an application name of `Netclaw`. Under the hood, `DataProtectionSecretsProtector` calls `IDataProtector.Protect()` and `Unprotect()`. Standard .NET cryptography, not a custom implementation.

Encrypted values get an `ENC:` prefix. The JSON structure stays human-readable; only the leaf string values are opaque:

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

Re-encrypting an already-encrypted value is safe. The writer checks for the `ENC:` prefix and skips values that already have it.

## Storage Layout

| Path | Contents | Permissions |
|------|----------|-------------|
| `~/.netclaw/config/secrets.json` | Encrypted credential values | `chmod 600` (Unix) |
| `~/.netclaw/keys/` | Data Protection key material | `chmod 700` (Unix) |

Both paths are required for decryption. `secrets.json` without `~/.netclaw/keys/` is ciphertext you can't unlock. The keys without the secrets file have nothing to decrypt. Copying one without the other to a new machine is useless.

On Windows, netclaw relies on user-profile ACLs instead of Unix file modes.

## Configuration Layering

Secrets slot into the standard config priority chain. Highest priority wins:

| Priority | Source | Use Case |
|----------|--------|----------|
| 1 (highest) | `NETCLAW_*` environment variables | CI/CD, containers, temporary overrides |
| 2 | `secrets.json` (encrypted) | Local development, persistent credentials |
| 3 (lowest) | `netclaw.json` (plaintext) | Non-sensitive configuration |

Environment variable names use the `NETCLAW_` prefix with double underscores for nesting: `NETCLAW_Slack__BotToken` maps to `Slack.BotToken`. This lets you inject credentials in containers without touching the filesystem.

## Agent Isolation

The [security model's](/security/security-model/) resource hard-deny layer (Layer 2 in the invocation stack) blocks the agent from accessing its own credential storage:

- `~/.netclaw/keys/` — denied for all read and write operations
- `~/.netclaw/config/` — denied for all read and write operations (covers `secrets.json`, `netclaw.json`, webhook routes)

Symlinks are resolved before path checks, so `ln -s ~/.netclaw/keys/ ./sneaky` won't bypass the policy. The agent can *use* the credentials (they're injected into provider connections at startup) but can never read, modify, or exfiltrate the raw values.

## Output Redaction

Even with encryption at rest and path denial, a secret could leak through tool output. An API key in a curl response, a token in a log file. The `SecretOutputRedactor` scrubs tool output before the LLM sees it, replacing matches with `***REDACTED***`.

It catches these patterns:

| Pattern | Examples |
|---------|----------|
| Provider API keys | `sk-*`, `ghp_*`, `AKIA*` (AWS) |
| Slack tokens | `xoxb-*`, `xoxp-*`, `xoxa-*`, `xoxr-*`, `xoxs-*` |
| Auth headers | `Authorization: Bearer <token>` |
| Connection strings | `Password=...;`, `Pwd=...;` |
| JWT tokens | `eyJ*.eyJ*.*` (three-segment base64) |
| PEM private keys | `-----BEGIN * PRIVATE KEY-----` blocks |
| JSON secret fields | Keys matching `api_key`, `token`, `secret`, `password`, `credential`, etc. |
| Environment variables | `API_KEY=value`, `TOKEN=value`, etc. |

This is regex-based pattern matching, not semantic analysis. Think of it as a safety net, not a primary control. Custom or unusual secret formats won't be caught.

## Write-Only Vault

There is no `secrets get`, `secrets list`, or `secrets delete` command. This is deliberate.

`netclaw secrets set` is the only operation. Write secrets in, never read them back. This eliminates an entire class of exfiltration attacks: even if an attacker gains shell access through the agent, there's no command to dump credentials.

To remove a secret, edit `~/.netclaw/config/secrets.json` directly (the agent can't, but you can). To verify secrets are properly stored, run [`netclaw doctor`](/cli/doctor/).

## Doctor Integration

[`netclaw doctor`](/cli/doctor/) validates the secrets subsystem on every run:

| Check | What It Catches |
|-------|----------------|
| File existence | `secrets.json` missing (warning, not error — you might not need it yet) |
| JSON validity | Malformed JSON that would prevent config loading |
| File permissions | Group or other read/write bits set on Unix (should be `600`) |
| Encryption status | Plaintext values that should be encrypted |

If doctor flags unencrypted values, re-set them with `netclaw secrets set <key> <value>` to encrypt.

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| Secrets at rest on disk | AES encryption via Data Protection API; `chmod 600`/`700` file permissions |
| Agent reads its own credentials | Resource hard-deny on `~/.netclaw/keys/` and `~/.netclaw/config/` |
| Secret leaks into tool stdout | Regex-based output redaction before LLM ingestion |
| Secret exposed via CLI command | Write-only vault — no read/list/dump commands exist |
| Encryption keys copied to another machine | Machine-bound Data Protection keys; keys + secrets both required |
| Permission drift after manual edits | `netclaw doctor` flags incorrect file modes |

## Recovery

If `~/.netclaw/keys/` is deleted or corrupted, encrypted values in `secrets.json` are gone. There's no recovery path. Re-run `netclaw secrets set` for each credential. Back up `~/.netclaw/keys/` alongside `secrets.json`.

If file permissions have drifted, reset them and verify:

```bash
chmod 600 ~/.netclaw/config/secrets.json
chmod 700 ~/.netclaw/keys/
netclaw doctor
```

If a secret isn't taking effect, check for environment variable overrides. An env var like `NETCLAW_Slack__BotToken` silently wins over the `secrets.json` value. `netclaw doctor` helps diagnose layering issues.

## Limitations

- Machine-bound encryption means secrets aren't portable between hosts. Each machine needs its own `secrets set` pass.
- Output redaction is pattern-based, not semantic. Custom secret formats with non-standard prefixes won't be caught.
- No built-in key rotation. Re-running `secrets set` overwrites the previous value, but there's no automated rotation schedule.
- Windows relies on user-profile ACLs rather than explicit `chmod`, so permission auditing is less straightforward.
- This is a single-machine vault, not a team secrets manager like HashiCorp Vault or AWS Secrets Manager. No shared secret distribution.

## Related Pages

- [`netclaw secrets`](/cli/secrets/) — CLI command reference for setting secrets
- [`netclaw init`](/cli/init/) — stores initial credentials during first-run setup
- [`netclaw doctor`](/cli/doctor/) — validates secrets encryption and file permissions
- [Security Model](/security/security-model/) — default-deny architecture and the four-layer invocation stack
- [Hardening](/security/hardening/) — file permission lockdown and operational best practices

## Further Reading

- [ASP.NET Data Protection overview](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) — the encryption framework netclaw builds on
- [ASP.NET Data Protection key management](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) — how encryption keys are stored and rotated
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) — general best practices for credential storage
