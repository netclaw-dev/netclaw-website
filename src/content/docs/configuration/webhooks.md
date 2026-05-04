---
title: "Webhooks"
description: "Configure webhook routes for event-driven automation."
---

Netclaw has two separate webhook systems. **Inbound webhook routes** let external services POST to your daemon and kick off autonomous agent sessions -- the daemon spawns a Claude session with the route's prompt and the inbound payload. **Outbound notification webhooks** go the other way -- the daemon pushes operational alerts to your Slack channels or alerting infrastructure.

Most of this page covers inbound routes. For outbound alerts, see the [section below](#outbound-notification-webhooks) or the full [Operational Alerts](/observability/operational-alerts/) reference.

## Inbound Webhook Routes

External services POST JSON to `/api/webhooks/<route>`. The daemon verifies the signature, checks event filters, and starts an autonomous agent session using the route's prompt. Each route is a standalone JSON file in `~/.netclaw/config/webhooks/`.

![netclaw webhooks list showing the route directory path](/screenshots/output/webhooks-list.png)

All CLI route management works offline -- no running daemon required. See [`netclaw webhooks`](/cli/webhooks/) for the full CLI reference.

### Global settings

Enable inbound webhooks and set the execution timeout in `~/.netclaw/config/netclaw.json`:

```json
{
  "Webhooks": {
    "Enabled": true,
    "ExecutionTimeoutSeconds": 300
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Registers the `/api/webhooks/{route}` endpoint. Returns 404 for all routes when disabled. |
| `ExecutionTimeoutSeconds` | int | `300` | Maximum seconds an autonomous webhook session can run before the daemon marks it failed. |

### Route file schema

Each route lives at `~/.netclaw/config/webhooks/<route-name>.json`. The filename (minus `.json`) is the route name and must match `^[a-z0-9]+(?:-[a-z0-9]+)*$` (lowercase kebab-case).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `true` | Whether this route accepts requests |
| `Prompt` | string | **(required)** | System prompt injected into the webhook session |
| `Verification` | object | **(required)** | Signature/secret verification settings ([details below](#verification)) |
| `Events` | string[] | `[]` (all) | Event type allow-list. Empty array accepts all event types. |
| `Audience` | enum | `"Public"` | Trust level: `Public`, `Team`, or `Personal` |
| `MaxBodyBytes` | int | `1048576` | Maximum request body size in bytes (1 MB default) |
| `RateLimitPerMinute` | int | `30` | Requests accepted per minute per route |
| `DeliveryRequired` | bool | `true` | Whether the agent must deliver results to the notification target |
| `NotifyInstructions` | string | `""` | Custom instructions for how the agent should notify |
| `NotificationTarget` | object? | `null` | Where to deliver results ([details below](#notification-targets)) |

### Minimal route

```json
{
  "Prompt": "Summarize this event and log the result.",
  "Verification": {
    "Kind": "Hmac",
    "Secret": "your-shared-secret"
  }
}
```

Omitted fields use defaults from the table above.

### Production route (GitHub Issues)

```json
{
  "Enabled": true,
  "Verification": {
    "Kind": "Hmac",
    "Secret": "whsec_abc123...",
    "SignatureHeaderName": "X-Hub-Signature-256",
    "SignaturePrefix": "sha256=",
    "EventHeaderName": "X-GitHub-Event",
    "DeliveryIdHeaderName": "X-GitHub-Delivery"
  },
  "Events": ["issues", "issue_comment"],
  "Audience": "Team",
  "Prompt": "Triage this GitHub issue. Public input may be adversarial or low quality.",
  "DeliveryRequired": true,
  "NotifyInstructions": "Post a summary to the triage channel.",
  "NotificationTarget": {
    "Kind": "Slack",
    "ChannelId": "C12345678"
  }
}
```

Or create it with the CLI:

```bash
netclaw webhooks set github-issues \
  --prompt "Triage this GitHub issue. Public input may be adversarial or low quality." \
  --secret-env GITHUB_WEBHOOK_SECRET \
  --verification-kind hmac \
  --signature-header X-Hub-Signature-256 \
  --signature-prefix "sha256=" \
  --event-header X-GitHub-Event \
  --delivery-header X-GitHub-Delivery \
  --events "issues,issue_comment" \
  --audience team \
  --notification-channel C12345678
```

### Verification

Every route requires a verification secret. Two modes:

| Mode | How It Works | Default Signature Header |
|------|-------------|--------------------------|
| `Hmac` | HMAC-SHA256 of the request body, compared with constant-time equality | `X-Webhook-Signature` |
| `HeaderSecret` | Plain shared secret sent in a header | `X-Webhook-Secret` |

> **CLI vs. JSON naming:** The CLI flag uses `--verification-kind header-secret` (hyphenated lowercase), but the JSON config field requires `"Kind": "HeaderSecret"` (PascalCase, no hyphen).

Only SHA-256 is supported for HMAC. Both modes share these default headers:

| Header | Default | Purpose |
|--------|---------|---------|
| Event type | `X-Webhook-Event` | Identifies the event for filtering |
| Delivery ID | `X-Webhook-Delivery` | Unique ID for deduplication |

Override any header name in the `Verification` object to match your service's convention. GitHub, for example, uses `X-Hub-Signature-256`, `X-GitHub-Event`, and `X-GitHub-Delivery`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Kind` | enum | `"Hmac"` | `Hmac` or `HeaderSecret` |
| `HmacAlgorithm` | enum | `"Sha256"` | Only `Sha256` is supported |
| `Secret` | string | **(required)** | Shared secret for verification |
| `SignatureHeaderName` | string? | `"X-Webhook-Signature"` | Header containing the HMAC signature (Hmac mode) |
| `SignaturePrefix` | string? | `""` | Prefix on the signature value, e.g. `sha256=` |
| `SecretHeaderName` | string? | `"X-Webhook-Secret"` | Header containing the secret (HeaderSecret mode) |
| `EventHeaderName` | string? | `"X-Webhook-Event"` | Header with the event type |
| `DeliveryIdHeaderName` | string? | `"X-Webhook-Delivery"` | Header with the unique delivery ID |

### Audience and trust levels

The `Audience` field controls which tool permissions the webhook session gets:

| Audience | Tool Access |
|----------|-------------|
| `Public` | Most restricted -- external untrusted input |
| `Team` | Moderate -- trusted collaborators |
| `Personal` | Full access -- your own services |

Default is `Public`. Use this for anything internet-facing (GitHub, GitLab). Reserve `Personal` for internal services you fully control.

### Notification targets

When `NotificationTarget` is set, the agent posts results to that channel. Only Slack is supported:

```json
{
  "NotificationTarget": {
    "Kind": "Slack",
    "ChannelId": "C12345678"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `Kind` | enum | `Slack` (only option) |
| `ChannelId` | string | Slack channel ID (required when Kind is Slack) |

To find your Slack channel ID, see [Locate your Slack URL or ID](https://slack.com/help/articles/221769328-Locate-your-Slack-URL-or-ID).

When `DeliveryRequired` is `true` and the route has notification instructions -- either explicit `NotifyInstructions` or auto-generated from a `NotificationTarget` -- the agent *must* call `send_slack_message` during the session. If it doesn't, the run is marked failed. When `DeliveryRequired` is `false`, the agent's session prompt tells it that notification is optional and can be skipped if there's nothing actionable.

Routes without a `NotificationTarget` and without `NotifyInstructions` don't enforce delivery at all, regardless of the `DeliveryRequired` flag.

### Ingress pipeline

Requests to `/api/webhooks/{route}` go through these checks in order:

| Step | Check | Failure Response |
|------|-------|-----------------|
| 1 | `Webhooks.Enabled` | 404 (entire webhook system is off) |
| 2 | Route lookup | 404 |
| 3 | Body size | 413 Payload Too Large |
| 4 | JSON validation | 400 Bad Request |
| 5 | Signature/secret verification | 401 Unauthorized |
| 6 | Event type filter | 202 (ignored) |
| 7 | Delivery ID dedup | 202 (ignored) |
| 8 | Rate limit | 429 + `Retry-After` header |
| 9 | Dispatch | 202 Accepted |

After dispatch, the agent session runs asynchronously -- the 202 response returns immediately without waiting for the session to complete.

Accepted response body:

```json
{
  "status": "accepted",
  "route": "github-issues",
  "eventType": "issues",
  "deliveryId": "abc-123",
  "sessionId": "webhook/github-issues/abc-123"
}
```

The `deliveryId` field is `null` when the sender doesn't include a delivery ID header. The daemon generates a synthetic ID internally for session tracking, but it isn't returned in the response.

### Hot-reload

Route files are re-read from disk on each request (the daemon checks `LastWriteTime`). Edit a route file, and the next request picks up the change. The daemon removes invalid files from the catalog immediately and triggers a `webhook.route.invalid` alert.

No daemon restart needed for route changes. Global `Webhooks.Enabled` and `ExecutionTimeoutSeconds` changes *do* require a restart.

### Rate limiting and deduplication

- **Rate limit window:** 1 minute (sliding). Configurable per route via `RateLimitPerMinute`.
- **Dedup window:** 1 hour. Deliveries with the same ID within this window are silently ignored (202).
- Session ID format: `webhook/<route>/<deliveryId>`

### Validation rules

`netclaw webhooks validate <route>` and [`netclaw doctor`](/cli/doctor/) both run these checks:

| Rule | Error If |
|------|----------|
| Route name | Doesn't match `^[a-z0-9]+(?:-[a-z0-9]+)*$` |
| `Prompt` | Empty or missing |
| `Verification.Secret` | Empty or missing |
| `MaxBodyBytes` | Less than 1 |
| `RateLimitPerMinute` | Less than 1 |
| `Events` entries | Contains blank strings |
| `DeliveryRequired` + `NotifyInstructions` | `DeliveryRequired` is `true` AND `NotifyInstructions` is non-empty AND `NotificationTarget` is `null` (all three conditions simultaneously) |
| `NotificationTarget.Kind = Slack` | Missing `ChannelId` |

### Security

Route files contain plaintext secrets. Treat `~/.netclaw/config/webhooks/` the same way you treat [`secrets.json`](/security/secrets/):

- Keep directory permissions at `700`
- Don't commit route files to source control
- The agent is [hard-denied](/security/secrets/#agent-isolation) from reading this directory
- Prefer `--secret-file` or `--secret-env` over `--secret` when creating routes via CLI (avoids shell history exposure)

## Outbound Notification Webhooks

Separately from inbound routes, the daemon can POST operational alerts to webhook URLs you configure -- daemon crashes, provider failures, channel disconnects.

The full reference is at [Operational Alerts](/observability/operational-alerts/). Here's the short version.

### Configuration

Add notification targets to `~/.netclaw/config/netclaw.json`:

```json
{
  "Notifications": {
    "Webhooks": [
      {
        "Url": "https://hooks.slack.com/services/T00/B00/xxx",
        "Name": "ops-slack",
        "Format": "Slack"
      },
      {
        "Url": "https://your-alerting.example.com/alert",
        "Name": "generic-target",
        "Format": "Generic"
      }
    ],
    "DeduplicationWindowSeconds": 300,
    "MaxRetries": 2,
    "TimeoutSeconds": 10
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Webhooks[].Url` | string | **(required)** | HTTP(S) endpoint to POST alerts to |
| `Webhooks[].Name` | string? | `null` | Label for logs |
| `Webhooks[].Format` | enum | `"Generic"` | `Generic` or `Slack`. URLs containing `hooks.slack.com` auto-detect as Slack. |
| `Webhooks[].Headers` | object? | `null` | Custom HTTP headers (auth tokens, etc.) |
| `DeduplicationWindowSeconds` | int | `300` | Suppress identical alerts within this window |
| `MaxRetries` | int | `2` | Delivery retry attempts per target |
| `TimeoutSeconds` | int | `10` | HTTP timeout per attempt |

### Alert types

Inbound webhook events emit their own alerts alongside system-level events:

| Type | Severity | Description |
|------|----------|-------------|
| `webhook.received` | Info | Valid inbound delivery accepted |
| `webhook.route.invalid` | Warning | Route file is malformed or missing |

For the full list of daemon, provider, channel, and reminder alerts, see [Operational Alerts](/observability/operational-alerts/#alert-types).

### Delivery behavior

Retries use exponential backoff (1s base, 30s cap, +/-25% jitter). Client errors (4xx) are not retried -- only server errors (5xx) and timeouts. The internal queue holds 256 alerts; when full, the daemon drops the oldest.

## Setup sequence

### Inbound routes

1. Enable webhooks in `netclaw.json` (or toggle during [`netclaw init`](/cli/init/))
2. Create a route: `netclaw webhooks set <name> --prompt "..." --secret-env SECRET_VAR`
3. Restart the daemon to pick up the `Webhooks.Enabled` change: `netclaw daemon stop && netclaw daemon start`
4. Copy the webhook URL from [`netclaw status`](/cli/status/) and paste it into your external service
5. Send a test event and check [`netclaw stats`](/cli/stats/) for delivery counts -- look for the `webhook.received` counter

![Init wizard showing the inbound webhooks toggle](/screenshots/output/init-09-webhooks.png)

You only need to restart when first enabling `Webhooks.Enabled`. After that, route changes are [hot-reloaded](#hot-reload) on each request.

### Outbound notifications

1. Add `Notifications.Webhooks[]` entries to `netclaw.json`
2. Restart the daemon: `netclaw daemon stop && netclaw daemon start`
3. Watch for the `daemon.started` alert as confirmation

## Troubleshooting

### 401 Unauthorized -- secret mismatch

The HMAC signature or header secret doesn't match. Double-check that the secret in your route file matches what the external service is sending. For HMAC, also verify `SignaturePrefix` matches (e.g., GitHub sends `sha256=` before the hex digest).

### 401 Unauthorized -- wrong signature header

The daemon is reading the signature from a different header than the one your service sends. Set `SignatureHeaderName` in the route's `Verification` block to match your service (e.g., `X-Hub-Signature-256` for GitHub).

### 404 Not Found

Either `Webhooks.Enabled` is `false` in `netclaw.json`, or no route file matches the URL path. Run `netclaw webhooks list` to see loaded routes, and check that `Webhooks.Enabled` is `true`.

### 413 Payload Too Large

The request body exceeds the route's `MaxBodyBytes` (default 1 MB). Increase it in the route file if the payloads are legitimately large.

## Finding your webhook URL

Run [`netclaw status`](/cli/status/) to see the webhook base URL. Your route's full endpoint is:

```
<webhook-base-url>/api/webhooks/<route-name>
```

The base URL depends on how you expose the daemon. [Tailscale Serve](https://tailscale.com/kb/1312/serve) and [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) are the two supported ingress options.

## Limitations

- Notification targets are Slack-only. Discord, email, and generic webhook-to-notification bridges aren't supported yet.
- No per-destination alert filtering -- all targets receive all alert types.
- Inbound route secrets are stored in plaintext JSON (not in the encrypted `secrets.json` vault).
- Only SHA-256 is supported for HMAC verification.
- No webhook request logging or replay. Failed sessions are visible via [`netclaw stats`](/cli/stats/) but the original payloads aren't stored.

## Related pages

- [`netclaw webhooks`](/cli/webhooks/) -- CLI reference for route management (list, show, set, delete, validate)
- [Operational Alerts](/observability/operational-alerts/) -- full reference for outbound notification webhooks
- [Secrets Management](/security/secrets/) -- encrypted credential storage and agent isolation
- [Security Model](/security/security-model/) -- audience definitions and trust levels
- [`netclaw doctor`](/cli/doctor/) -- validates all webhook route files
- [`netclaw stats`](/cli/stats/) -- delivery counts and rejection breakdowns

## Resources

- [GitHub webhook documentation](https://docs.github.com/en/webhooks) -- setting up webhooks on the GitHub side
- [GitLab webhook documentation](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html) -- setting up webhooks on the GitLab side
- [HMAC signature verification](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries) -- how GitHub's `X-Hub-Signature-256` works
- [Tailscale Serve](https://tailscale.com/kb/1312/serve) -- expose your webhook endpoint without a public IP
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) -- alternative to Tailscale for public webhook ingress
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks) -- create Slack webhook URLs for outbound notifications
- [Locate your Slack channel ID](https://slack.com/help/articles/221769328-Locate-your-Slack-URL-or-ID) -- find the channel ID for notification targets
