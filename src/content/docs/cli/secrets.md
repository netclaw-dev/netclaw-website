---
title: "netclaw secrets"
description: "Manage encrypted secrets."
---

Store API keys, tokens, and credentials in an encrypted local vault. Values are encrypted at rest using [ASP.NET Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) — no plaintext ever touches disk.

If you haven't run [`netclaw init`](/cli/init/) yet, start there — the wizard stores your initial credentials automatically. Use `secrets set` afterward to rotate keys, add new providers, or script credential injection without re-running the wizard.

## Usage

```bash
netclaw secrets set <key> <value>
```

`set` is the only subcommand — there's no `get`, `list`, or `delete`. Secrets are write-only by design. To remove a key, edit `~/.netclaw/config/secrets.json` directly.

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `<key>` | Dotted key path (e.g., `Slack.BotToken`) | Yes |
| `<value>` | The secret value to encrypt and store | Yes |

## Key Paths

Keys use dotted paths matching the `netclaw.json` hierarchy:

| Key Path | What It Stores |
|----------|---------------|
| `Slack.BotToken` | Slack Bot User OAuth Token (`xoxb-...`) |
| `Slack.AppToken` | Slack App-Level Token (`xapp-...`) |
| `Providers.openrouter.ApiKey` | OpenRouter API key |
| `Providers.ollama.ApiKey` | Ollama API key (if auth enabled) |
| `Search.BraveApiKey` | Brave Search API key |

This isn't exhaustive — any dotted path that corresponds to a field in `netclaw.json` works. See [Configuration](/configuration/managed-providers/) for the full schema.

## Examples

### Store a Slack Bot Token

```bash
netclaw secrets set Slack.BotToken xoxb-1234567890-abcdef
```

```
Set Slack.BotToken (encrypted).
```

### Store a Provider API Key

```bash
netclaw secrets set Providers.openrouter.ApiKey sk-or-v1-your-key-here
```

```
Set Providers.openrouter.ApiKey (encrypted).
```

### Store Multiple Secrets

```bash
netclaw secrets set Slack.BotToken xoxb-...
netclaw secrets set Slack.AppToken xapp-...
netclaw secrets set Providers.openrouter.ApiKey sk-or-v1-...
```

## How Encryption Works

1. The value is encrypted via ASP.NET Data Protection
2. The ciphertext is written to `secrets.json` with an `ENC:` prefix
3. File permissions are set to `600` on Unix

The raw `secrets.json` looks like this:

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

Encryption keys live in `~/.netclaw/keys/`, separate from the secrets file. Both are required to decrypt — one is useless without the other.

## Storage Locations

| Path | Contents |
|------|----------|
| `~/.netclaw/config/secrets.json` | Encrypted credential values |
| `~/.netclaw/keys/` | Data Protection key material |

Both paths are created automatically on first use of `netclaw secrets set` or during `netclaw init`.

## Configuration Layering

Secrets participate in the standard config priority chain (highest priority wins):

```
NETCLAW_* env vars  →  secrets.json  →  netclaw.json
       (highest)                          (lowest)
```

Environment variables override secrets, which override `netclaw.json`. Use env vars in CI or containers while keeping `secrets.json` for local development.

## Output Redaction

Even if a secret leaks into a tool's output at runtime, netclaw's output redactor catches it before it reaches the LLM. It recognizes common secret patterns: API key prefixes (`sk-*`, `xox*-*`, `ghp_*`, `AKIA*`), `Authorization` headers, connection strings with embedded passwords, JWT tokens, and PEM private key blocks.

Secrets are encrypted at rest, decrypted only when needed, and redacted from any tool output before it reaches the LLM.

## Troubleshooting

### Permission denied writing secrets.json

The file requires `chmod 600`. If permissions drifted:

```bash
chmod 600 ~/.netclaw/config/secrets.json
```

### Lost encryption keys

If `~/.netclaw/keys/` is deleted, existing encrypted values in `secrets.json` cannot be recovered. You'll need to re-run `netclaw secrets set` for each credential. Always back up `~/.netclaw/keys/` alongside `secrets.json`.

### Secrets not taking effect

An environment variable with the same path will override `secrets.json`. Run [`netclaw doctor`](/cli/doctor/) to diagnose config issues.

## Related Commands

- [`netclaw init`](/cli/init/) — Stores initial credentials during first-run setup
- [`netclaw doctor`](/cli/doctor/) — Diagnoses config and connectivity issues
- [`netclaw provider`](/cli/provider/) — Manages providers that consume API key secrets

## Further Reading

- [ASP.NET Data Protection overview](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) — The encryption framework netclaw builds on
- [ASP.NET Data Protection key management](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) — How encryption keys are stored and rotated
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) — General best practices for credential storage
