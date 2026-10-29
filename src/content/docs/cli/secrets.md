---
title: "netclaw secrets"
description: "Store API keys and tokens in netclaw's encrypted vault with netclaw secrets set."
---

`netclaw secrets set` writes an API key, token or other credential into an encrypted local vault. Values are encrypted with [ASP.NET Data Protection](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) before they reach disk. The one exception is `Providers.<name>.OAuthTokenExpiry`, which is a date and not a secret, so it's stored as plain text. Use it to rotate keys, add a provider or script credential injection after [`netclaw init`](/cli/init/), which stores your first credentials for you.

## Usage

```bash
netclaw secrets set <key> <value>
netclaw secrets add <key> <value>     # alias for set
```

`set` is the only operation. There's no `get`, `list` or `delete`, so secrets are write-only by design. To remove a key, edit `~/.netclaw/config/secrets.json` directly. Any other subcommand, or none, prints the usage text and exits 0. `set` with fewer than two arguments prints examples and exits 1.

| Argument | Description |
|----------|-------------|
| `<key>` | A dotted path matching the `netclaw.json` hierarchy, such as `Slack.BotToken`. Colons work too: `Discord:BotToken` |
| `<value>` | The secret to encrypt and store |

The value is a command-line argument, so it lands in your shell history and shows in the process list while the command runs. Prefix the command with a space if your shell skips history for those lines, or clear the history entry afterwards.

## Key paths

| Key path | What it stores |
|----------|----------------|
| `Slack.BotToken` | Slack bot user OAuth token (`xoxb-...`) |
| `Slack.AppToken` | Slack app-level token (`xapp-...`) |
| `Discord.BotToken` | Discord bot token |
| `Providers.openrouter.ApiKey` | OpenRouter API key |
| `Providers.ollama.ApiKey` | Ollama API key, if auth is on |
| `Search.BraveApiKey` | Brave Search API key |
| `Providers.<name>.OAuthTokenExpiry` | OAuth access-token expiry, as an ISO 8601 date. Plain text. OAuth sign-in and token refresh write it, so you rarely set it by hand |

Any dotted path that matches a field in `netclaw.json` works. See [Managed providers](/configuration/managed-providers/) for provider keys.

## Examples

Store a Slack bot token:

```bash
netclaw secrets set Slack.BotToken xoxb-1234567890-abcdef
```

```text
Set Slack.BotToken (encrypted).
```

Store a provider key and a colon-style path:

```bash
netclaw secrets set Providers.openrouter.ApiKey sk-or-v1-your-key-here
netclaw secrets set Discord:BotToken your-token-here
```

```text
Set Providers.openrouter.ApiKey (encrypted).
Set Discord.BotToken (encrypted).
```

`OAuthTokenExpiry` is the exception to the encrypted output. `set` says so and writes the bare date, and it rejects anything that isn't an ISO 8601 date before writing:

```text
Set Providers.lab-llama.OAuthTokenExpiry (not encrypted: the token expiry is not a secret).
Error: Providers.lab-llama.OAuthTokenExpiry must be an ISO 8601 date, for example 2026-06-01T01:00:00+00:00.
```

Secrets are read when the daemon starts, and the daemon only restarts itself when `netclaw.json` changes. After a `secrets set`, restart it yourself:

| Install | Restart |
|---------|---------|
| Docker | `docker restart <container>` |
| systemd user unit | `systemctl --user restart netclaw` |
| Native | `netclaw daemon stop`, then `netclaw daemon start` |

## What gets written

Every value except the token expiry is encrypted, prefixed with `ENC:`, and written to `secrets.json` with mode `600` on Unix:

```json
{
  "Slack": {
    "BotToken": "ENC:CfDJ8N2x...long-base64-string..."
  },
  "Providers": {
    "openrouter": {
      "ApiKey": "ENC:CfDJ8K9y...long-base64-string..."
    },
    "my-openai": {
      "OAuthTokenExpiry": "2026-06-01T01:00:00+00:00"
    }
  }
}
```

Encryption keys live in `~/.netclaw/keys/`, separate from the secrets file. Both are created on first use and both are required to decrypt, so back them up together. `netclaw mcp add` also writes MCP server environment variables, headers and OAuth client secrets into `secrets.json` the same way.

## Configuration layering

Highest priority wins:

| Priority | Source |
|----------|--------|
| 1 | `NETCLAW_*` environment variables |
| 2 | `secrets.json` |
| 3 | `netclaw.json` |

An environment variable beats a stored secret with the same path, which is the usual reason a new secret doesn't seem to take effect. Use environment variables in CI and containers, and `secrets.json` for persistent local credentials.

## Troubleshooting

### Permission denied writing secrets.json

**Symptom:** `secrets set` fails to write. **Cause:** permissions on the file or directory drifted. **Fix:**

```bash
chmod 600 ~/.netclaw/config/secrets.json
```

### Lost encryption keys

**Symptom:** the daemon can't decrypt values in `secrets.json`. **Cause:** `~/.netclaw/keys/` was deleted or replaced. **Fix:** the old values are unrecoverable. Re-run `netclaw secrets set` for each credential, and back up `~/.netclaw/keys/` next to `secrets.json` from now on.

### A secret isn't taking effect

**Symptom:** the daemon still uses an old key. **Cause:** an environment variable with the same path overrides `secrets.json`, or the daemon hasn't restarted since you set the value. **Fix:** unset the variable or restart the daemon, then run [`netclaw doctor`](/cli/doctor/).

## Related pages

- [Secrets management](/security/secrets/) - how encryption, path denial and output redaction fit together
- [`netclaw init`](/cli/init/) - stores initial credentials during first-run setup
- [`netclaw doctor`](/cli/doctor/) - checks secrets file permissions and encryption
- [`netclaw provider`](/cli/provider/) - manages the providers that consume API key secrets

## Resources

- [ASP.NET Data Protection overview](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/introduction) - the encryption framework netclaw builds on
- [ASP.NET Data Protection key management](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/implementation/key-management) - how keys are stored and rotated
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) - general credential storage practices
