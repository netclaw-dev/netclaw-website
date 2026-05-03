---
title: "netclaw webhooks"
description: "Configure inbound HTTP endpoints that trigger netclaw sessions from GitHub, GitLab, and other services."
---

`netclaw webhooks` manages inbound webhook routes. External services POST to a route, netclaw verifies the signature, runs a session with the route's prompt, and posts results to Slack if configured.

Routes live as individual JSON files in `~/.netclaw/config/webhooks/`. CLI management (`list`, `set`, `validate`, etc.) doesn't need a running daemon. Actually receiving webhook requests does — start the daemon with `netclaw daemon start` or [`netclaw init`](/cli/init/).

## Usage

```bash
netclaw webhooks [subcommand] [options]
```

## `list`

```bash
netclaw webhooks list [--json] [--all]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--json` | JSON output | Off |
| `--all` | Include disabled routes | Off |

![netclaw webhooks list showing no routes configured and the route directory path](/screenshots/output/webhooks-list.png)

With no routes configured, you see the storage path. Once routes exist, the table shows status, audience, verification kind, and delivery requirement per route.

## `show`

```bash
netclaw webhooks show <route> [--json] [--show-secret]
```

Displays full configuration for a single route. Also validates the route file — exits with code 1 if the route has schema errors.

| Flag | Description | Default |
|------|-------------|---------|
| `--json` | JSON output | Off |
| `--show-secret` | Reveal the verification secret | Off |

Secrets are redacted by default. Pass `--show-secret` when you need to copy the secret to a third-party service.

## `set`

Creates or updates a route. Route names must be lowercase alphanumeric with single dashes between segments (`github-issues`, `deploy-v2`). Regex: `^[a-z0-9]+(?:-[a-z0-9]+)*$`.

```bash
netclaw webhooks set <route> [options]
```

### Prompt and secret

New routes require a prompt (choose one) and a secret (choose one):

| Flag | Description |
|------|-------------|
| `--prompt <text>` | Prompt text injected into webhook sessions |
| `--prompt-file <path>` | Read prompt from a file |
| `--secret <value>` | Verification secret — **visible in shell history**; prefer `--secret-file` or `--secret-env` |
| `--secret-file <path>` | Read secret from a file |
| `--secret-env <VAR>` | Read secret from an environment variable |

### Verification

| Flag | Description | Default |
|------|-------------|---------|
| `--verification-kind <kind>` | `hmac` or `header-secret` | `hmac` |
| `--signature-header <name>` | Header containing the [HMAC](https://en.wikipedia.org/wiki/HMAC) signature | — |
| `--signature-prefix <prefix>` | Prefix on the signature value (e.g. `sha256=`) | — |
| `--secret-header <name>` | Header containing the secret (header-secret mode) | — |
| `--event-header <name>` | Header with the event type name | — |
| `--delivery-header <name>` | Header with the unique delivery ID (for deduplication) | — |

### Behavior

`--audience` controls which [tool audience](/architecture/overview/) the webhook session runs under. `public` gets the most restricted tool access, `personal` gets the most permissive.

| Flag | Description | Default |
|------|-------------|---------|
| `--events <list>` | Comma-separated event type allow-list (empty = all) | All |
| `--audience <level>` | `public`, `team`, or `personal` | `public` |
| `--max-body <bytes>` | Maximum request body size | `1048576` (1 MB) |
| `--rate-limit <N>` | Requests per minute | `30` |
| `--enabled` / `--disabled` | Enable or disable the route | Enabled |

### Notifications

When a notification target is configured, the agent posts results to that Slack channel. This requires [Slack to be configured](/cli/init/) in netclaw.

| Flag | Description | Default |
|------|-------------|---------|
| `--notify-instructions <text>` | Instructions for agent notification behavior | — |
| `--notify-instructions-file <path>` | Read notification instructions from a file | — |
| `--delivery-required` / `--no-delivery-required` | Require notification delivery | `true` |
| `--notification-channel <id>` | Slack channel ID for notifications | — |

### Modifiers

| Flag | Description |
|------|-------------|
| `--dry-run` | Validate and print the route without saving |
| `--create-only` | Fail if the route already exists |
| `--update-only` | Fail if the route doesn't exist |

### Examples

#### GitHub issues route

```bash
netclaw webhooks set github-issues \
  --prompt "Triage this GitHub issue. Summarize it and suggest a priority label." \
  --secret-env GITHUB_WEBHOOK_SECRET \
  --verification-kind hmac \
  --signature-header X-Hub-Signature-256 \
  --signature-prefix "sha256=" \
  --event-header X-GitHub-Event \
  --delivery-header X-GitHub-Delivery \
  --events "issues,issue_comment" \
  --audience team \
  --notification-channel C0123SLACK
```

#### Preview without saving

```bash
netclaw webhooks set github-issues --rate-limit 10 --dry-run
```

#### Create-only (fail if exists)

```bash
netclaw webhooks set deploy-notify \
  --prompt "Summarize this deployment and post a status update." \
  --secret-env DEPLOY_SECRET \
  --create-only
```

## `delete`

```bash
netclaw webhooks delete <route> [--force | -f]
```

Prompts for confirmation unless `--force` is passed.

## `validate`

```bash
netclaw webhooks validate <route>
```

Checks the route file for syntax errors and schema violations. These are the same checks [`netclaw doctor`](/cli/doctor/) runs across all routes automatically. The backtick-quoted names below are JSON fields in the route file:

- Route name must match `^[a-z0-9]+(?:-[a-z0-9]+)*$`
- `Prompt` is required and non-empty
- `Verification` section is required with a non-empty `Secret`
- `MaxBodyBytes` and `RateLimitPerMinute` must be >= 1
- `Events` list can't contain blank entries
- If `DeliveryRequired` is true and `NotifyInstructions` is set, `NotificationTarget` is required
- If `NotificationTarget.Kind` is `Slack`, `NotificationTarget.ChannelId` is required

## Route files

Each route is stored as `~/.netclaw/config/webhooks/<route-name>.json`. A GitHub Issues route looks like this:

```json
{
  "Enabled": true,
  "Prompt": "Triage this GitHub issue. Summarize it and suggest a priority label.",
  "Verification": {
    "Kind": "Hmac",
    "HmacAlgorithm": "Sha256",
    "Secret": "whsec_abc123...",
    "SignatureHeaderName": "X-Hub-Signature-256",
    "SignaturePrefix": "sha256=",
    "EventHeaderName": "X-GitHub-Event",
    "DeliveryIdHeaderName": "X-GitHub-Delivery"
  },
  "Events": ["issues", "issue_comment"],
  "Audience": "Team",
  "MaxBodyBytes": 1048576,
  "RateLimitPerMinute": 30,
  "DeliveryRequired": true,
  "NotifyInstructions": "Post a summary to the triage channel.",
  "NotificationTarget": {
    "Kind": "Slack",
    "ChannelId": "C0123SLACK"
  }
}
```

Note the casing difference: CLI flags use lowercase (`--verification-kind hmac`, `--audience team`) while route files use PascalCase (`"Kind": "Hmac"`, `"Audience": "Team"`).

Route files contain secrets in plaintext. Keep `~/.netclaw/config/webhooks/` mode `700` and don't commit these files to source control.

## Request lifecycle

When a POST hits `/api/webhooks/{routeName}`:

1. The daemon loads the route file (hot-reloaded per request — no restart needed after changes)
2. Verifies the request using the route's HMAC signature or header secret
3. Checks rate limits and body size constraints
4. Filters by event type if the route has an allow-list
5. Creates a new `Webhook` session with the route's prompt injected as context
6. If a notification target is configured, the agent posts results to that Slack channel. Without a notification target, the session still runs — output is stored in the session log

Rejected requests return the appropriate HTTP status. Missing or malformed route files return 404. To see delivery and rejection counts, run [`netclaw stats`](/cli/stats/).

## Finding your webhook URL

After creating a route, you need the full URL to give your external service. Run [`netclaw status`](/cli/status/) — the output includes your webhook base URL (set during [`netclaw init`](/cli/init/)). Your route's endpoint is:

```
<your-webhook-base-url>/api/webhooks/<route-name>
```

The webhook URL depends on how you've exposed your daemon. [Tailscale Serve](https://tailscale.com/kb/1312/serve) or [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) are the two supported options for making your daemon reachable from external services.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Route not found, validation error, or other failure |

## What's next

After setting up a route, restart the daemon and run [`netclaw status`](/cli/status/) to confirm the webhook endpoint is healthy. Then paste the full webhook URL into your external service's webhook settings.

To debug webhook issues: [`netclaw stats`](/cli/stats/) shows delivery counts and rejection breakdowns, and [`netclaw doctor`](/cli/doctor/) validates all route files.

## Related commands

- [`netclaw doctor`](/cli/doctor/) — validates all webhook route files and flags format issues
- [`netclaw stats`](/cli/stats/) — webhook delivery counts and rejection breakdowns
- [`netclaw init`](/cli/init/) — sets up webhook URL identity during onboarding
- [`netclaw status`](/cli/status/) — live daemon health including webhook endpoint availability

## Resources

- [GitHub webhook documentation](https://docs.github.com/en/webhooks) — setting up webhooks on the GitHub side
- [GitLab webhook documentation](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html) — GitLab's webhook configuration
- [HMAC signature verification](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries) — how GitHub's `X-Hub-Signature-256` works
- [Tailscale Serve](https://tailscale.com/kb/1312/serve) — expose your webhook endpoint without a public IP
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — alternative to Tailscale for public webhook ingress
