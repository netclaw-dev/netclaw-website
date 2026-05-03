---
title: "Hardening"
description: "Lock down MCP permissions and network exposure."
---

The [security model](/security/security-model/) covers what netclaw enforces by default: default-deny, audience scoping, a four-layer invocation stack. This page covers what *you* should do on top of that — especially if you're exposing netclaw to a team, the internet, or running it unattended.

Sections are independent. Work through the ones that apply to your deployment.

## File Permissions

Netclaw stores credentials and webhook secrets in plaintext JSON files. Lock them down:

```bash
# Encrypted secrets — only the daemon user should read this
chmod 600 ~/.netclaw/config/secrets.json

# Webhook route files contain HMAC secrets
chmod 700 ~/.netclaw/config/webhooks/

# Key material — encryption keys for Data Protection
chmod 700 ~/.netclaw/keys/
```

[`netclaw doctor`](/cli/doctor/) checks `secrets.json` permissions and flags unencrypted values. Run it after any manual config edits.

## Shell Access

Shell access is the biggest risk surface you can control. Three modes in `~/.netclaw/config/netclaw.json`:

| Mode | Behavior |
|------|----------|
| `Off` | Shell completely disabled. No `shell_execute` tool available. |
| `SandboxOnly` | Shell runs in a sandboxed environment. |
| `HostAllowed` | Shell runs directly on the host. Approval gates are your only guardrail. |

<!-- TODO: needs user input — SandboxOnly mode appears in config but the sandbox backend isn't implemented yet. What's the current behavior if someone sets SandboxOnly? Does it fall back to Off? -->

Set the mode explicitly:

```json
{
  "SecurityPolicy": {
    "ShellExecutionMode": "Off"
  }
}
```

**For Team and Public postures, shell is off by default.** Only Personal posture enables it, and only with approval gates on `shell_execute`. If you're running Personal posture but don't need shell, turn it off.

### Custom Hard-Deny Patterns

The built-in hard-deny list blocks `sudo`, `rm -rf ~/`, `kill`, fork bombs, and commands that would stop the daemon. Add your own patterns for anything dangerous in your environment:

```json
{
  "Tools": {
    "HardDenyPatterns": [
      "docker rm",
      "kubectl delete namespace",
      "terraform destroy"
    ]
  }
}
```

Custom patterns augment the defaults — they don't replace them. Netclaw tokenizes compound commands (`&&`, `||`, `;`, `|`) and checks each segment independently, so `echo hello && docker rm foo` still triggers the deny.

## MCP Tool Permissions

New MCP servers start with zero tool grants for all audiences — safe by default. The risk comes from granting too much.

Audit your grants per audience:

```bash
netclaw mcp permissions
```

![MCP tool grants for Personal audience showing all tools enabled](/screenshots/output/mcp-tools-personal.png)

Personal audience with all tools granted. Compare against the locked-down Team and Public defaults:

![Team audience with server disabled](/screenshots/output/mcp-tools-team.png)

Team audience — server disabled, no tools granted.

Grant the minimum tools each audience actually needs — don't enable everything for Team because it's faster to configure. For destructive MCP tools (`delete`, `drop`, `write`), set approval mode to `Approval` or `Deny`. Per-tool overrides let you keep the server default on `Auto` while gating the dangerous ones:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "DefaultMode": "Auto",
          "ToolOverrides": {
            "shell_execute": "Approval",
            "mcp:notion:notion-delete-page": "Approval"
          }
        }
      }
    }
  }
}
```

Review `~/.netclaw/config/tool-approvals.json` periodically — persistent "approve always" decisions accumulate there. Remove patterns you no longer need.

See [`netclaw mcp`](/cli/mcp-tools/) for full details on the permissions TUI and CLI.

## Network Exposure

The daemon binds to `127.0.0.1:5199` by default. Keep it that way unless you have a reason not to.

| Mode | Scope | Risk |
|------|-------|------|
| `local` | Loopback only | Minimal — only local processes can connect |
| `tailscale-serve` | Your tailnet | Low — [Tailscale identity](https://tailscale.com/kb/) gates access |
| `tailscale-funnel` | Public internet | High — anyone on the internet can reach it |
| `cloudflare-tunnel` | Public internet | High — requires a [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) policy |

![Exposure mode selection during netclaw init](/screenshots/output/init-09-exposure.png)

The exposure selection during `netclaw init`. Internet-facing modes force explicit confirmation.

If you need remote access, prefer `tailscale-serve`. It limits access to your tailnet. Funnel exposes you to the public internet — a completely different threat model.

For Docker deployments, bind to loopback explicitly:

```bash
docker run -p 127.0.0.1:5199:5199 ...
```

Omitting `127.0.0.1` binds to all interfaces — any machine on your network can reach the daemon.

Changing exposure mode requires a daemon restart. It's excluded from hot-reload on purpose.

<!-- TODO: needs user input — What Cloudflare Access policy configuration is needed from the netclaw side? Is there a config field or is it purely Cloudflare-side? -->

## Slack and Discord Channel Restrictions

Out of the box, Slack uses `MentionOnly: true` (netclaw only responds when @mentioned) and `AllowDirectMessages: false`. Good defaults, but there's more you can lock down.

### Allowlist Channels

Restrict which channels netclaw listens on. Without an allowlist, netclaw can be @mentioned in *any* channel it's been invited to:

```json
{
  "Slack": {
    "AllowedChannelIds": ["C0123ABCDEF", "C0456GHIJKL"],
    "MentionOnly": true
  }
}
```

### Allowlist Users

Without a user allowlist, any workspace member can @mention netclaw and get a response:

```json
{
  "Slack": {
    "AllowedUserIds": ["U0123ABCDEF", "U0456GHIJKL"]
  }
}
```

### DMs and Per-Channel Audiences

Keep DMs off unless you need them. If you enable DMs, restrict which users can DM:

```json
{
  "Slack": {
    "AllowDirectMessages": true,
    "AllowedUserIds": ["U0123ABCDEF"]
  }
}
```

You can also override the audience per channel — useful if you want a specific Slack channel to get Personal-level tool access while everything else stays at Team:

```json
{
  "Slack": {
    "ChannelAudiences": {
      "C0123ABCDEF": "personal",
      "dm": "team"
    }
  }
}
```

Invalid audience values in `ChannelAudiences` result in a deny (fail-closed).

[`netclaw doctor`](/cli/doctor/) warns if Slack is enabled with no channel allowlist and no default channel configured, or if DMs are enabled without an `AllowedUserIds` list.

## Approval Gates

The last layer before a tool actually runs. Configure per audience:

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "ApprovalPolicy": {
          "DefaultMode": "Auto",
          "ToolOverrides": {
            "shell_execute": "Approval"
          }
        }
      },
      "Team": {
        "ApprovalPolicy": {
          "DefaultMode": "Approval"
        }
      },
      "Public": {
        "ApprovalPolicy": {
          "DefaultMode": "Deny"
        }
      }
    }
  }
}
```

Things to know:

- Headless sessions (reminders, webhooks, `netclaw chat -p "prompt"`) auto-deny all gated tools. There's no human to ask.
- No response within 5 minutes means deny.
- "Approve always" persists to `~/.netclaw/config/tool-approvals.json`. Revoke by editing the file directly.

If nobody is watching the approval prompts in production, set `DefaultMode: "Deny"` for Team and Public. Auto-deny is safer than a 5-minute timeout nobody sees.

## Webhook Security

Each webhook route has its own HMAC secret, audience, body size limit, and rate limit:

```json
{
  "Verification": {
    "Kind": "Hmac",
    "HmacAlgorithm": "Sha256",
    "Secret": "whsec_...",
    "SignatureHeaderName": "X-Hub-Signature-256",
    "SignaturePrefix": "sha256="
  },
  "Audience": "Public",
  "MaxBodyBytes": 1048576,
  "RateLimitPerMinute": 10
}
```

Set the audience to the minimum the webhook actually needs. Most should run as `Public` (fewest tools, session-scoped filesystem, wiped on end). Only use `Team` or `Personal` if the webhook prompt genuinely requires those tools.

Lower `RateLimitPerMinute` from the default 30 if the source won't fire that often — GitHub sends roughly one webhook per event, so 10/min is plenty. Keep `MaxBodyBytes` at 1 MB or lower unless you know the payloads are larger.

Route files contain secrets in plaintext. Keep `~/.netclaw/config/webhooks/` at mode `700` (see [File Permissions](#file-permissions)).

See [`netclaw webhooks`](/cli/webhooks/) for route setup and HMAC verification details.

## Run Doctor

After making changes, validate everything:

```bash
netclaw doctor
```

![netclaw doctor running 16 diagnostic checks](/screenshots/output/doctor.png)

Security-relevant checks include:

| Check | What it catches |
|-------|----------------|
| **Security Policy** | Missing `DeploymentPosture` |
| **Secrets JSON** | Wrong file permissions, unencrypted values |
| **Slack ACL** | No channel allowlist, DMs enabled without user allowlist |
| **Tool Audience Profiles** | Overly permissive tool grants |
| **exposure-mode** | Internet-reachable exposure without valid auth policy |
| **Inbound Webhook Routes** | Schema errors in route files |

Wire it into your deployment pipeline:

```bash
netclaw doctor --format json | jq -e '.exitCode == 0'
```

## Limitations

- Prompt injection detection is regex-based — it catches known patterns (role resets, exfiltration attempts, invisible Unicode) but novel phrasings, Base64 encoding, synonym substitution, and non-English attacks can evade it. Treat it as a tripwire, not a firewall.
- Tool grants are per-audience, not per-channel. `ChannelAudiences` overrides which audience a channel maps to, but you can't give one Slack channel different tools than another Slack channel with the same audience.
- Secret redaction catches `sk-*`, `xoxb-*`, `ghp_*`, JWTs, PEM blocks, and common JSON key names. Custom secret formats won't be redacted — use hard-deny path rules to block file access instead.
- Approval gates only work on interactive channels. Headless mode, reminders, and webhooks auto-deny all gated tools. Design automation workflows with that in mind.
<!-- TODO: needs user input — Are there plans for netclaw acl commands (validate, test, explain)? The CLI contract mentions them but they don't appear to be documented yet. -->

## Related Pages

- [Security Model](/security/security-model/) -- default-deny architecture, audiences, trust layers
- [`netclaw init`](/cli/init/) -- posture and exposure selection wizard
- [`netclaw mcp`](/cli/mcp-tools/) -- MCP tool permissions TUI
- [`netclaw doctor`](/cli/doctor/) -- configuration diagnostics
- [`netclaw webhooks`](/cli/webhooks/) -- webhook route management and HMAC verification
- [`netclaw secrets`](/cli/secrets/) -- encrypted credential storage

## Further Reading

- [OWASP LLM Top 10](https://genai.owasp.org/llm-top-10/) -- prompt injection, insecure output handling, and other LLM attack vectors
- [Tailscale ACLs](https://tailscale.com/kb/1018/acls/) -- network-level access control for `tailscale-serve` deployments
- [Cloudflare Access policies](https://developers.cloudflare.com/cloudflare-one/policies/access/) -- IdP-based access control for `cloudflare-tunnel` deployments
- [GitHub webhook security](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks) -- best practices for HMAC verification and secret rotation
