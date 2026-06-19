---
title: Operational Alerts
description: Configure outbound webhook notifications for daemon lifecycle events, provider failures, channel disconnects, and more.
---

Netclaw emits operational alerts when something happens that you or your ops tooling should know about — a provider going down, a channel disconnecting, the daemon crashing. Netclaw delivers these as outbound webhook POSTs to URLs you configure, with native Slack Block Kit formatting or a generic JSON envelope.

## Quick Start

1. Run `netclaw config` → **Telemetry & Alerting**.
2. Add a webhook URL and choose `Slack` or `Generic` format.
3. Restart the daemon — you'll get a `daemon.started` alert confirming delivery works.

That's it for most installs. For scripted deployments or headless servers, see [Manual configuration](#manual-configuration) below.

## Alert Types

| Type String | Severity | What Happened |
|-------------|----------|---------------|
| `daemon.started` | Info | Daemon finished startup. Includes PID. |
| `daemon.stopping` | Info | Graceful shutdown initiated. Includes reason. |
| `daemon.crashing` | Critical | Unhandled exception — the process is going down. |
| `update.available` | Info | A newer netclaw binary exists in the release feed. |
| `provider.failover` | Warning | Primary LLM provider failed; traffic moved to fallback. |
| `provider.unreachable` | Critical | All configured LLM providers are unavailable. |
| `channel.disconnected` | Warning | Slack, Discord, or Mattermost connection lost. |
| `mcp.auth.expired` | Warning | MCP OAuth token expired and refresh was rejected. |
| `mcp.server.disconnected` | Warning | Connection to an MCP server dropped. |
| `mcp.server.reconnected` | Info | MCP server reconnected successfully after a previous disconnect. |
| `webhook.received` | Info | A valid inbound webhook delivery was accepted and queued. |
| `webhook.route.invalid` | Warning | A webhook route file is missing or invalid. |
| `reminder.execution.failed` | Warning | A scheduled reminder failed to execute. |
| `reminder.auto_disabled` | Critical | Reminder disabled after repeated consecutive failures. |
| `reminder.schema.invalid_dropped` | Warning | Invalid reminder definitions were dropped at startup. |
| `reminder.schema.legacy_rejected` | Warning | Legacy reminder definitions missing trust fields were rejected at startup. |
| `background-job.schema.legacy_rejected` | Warning | Legacy background job definitions missing trust fields were rejected at startup. |

`provider.auth.expired` is defined but not currently emitted.

All configured destinations receive all alert types — there's no per-destination filtering.

## Configuring Alert Destinations

Use `netclaw config` → **Telemetry & Alerting** to add, edit, or remove webhook targets at any time.

### Manual configuration

For scripted or headless installs, add outbound webhook targets directly in `~/.netclaw/config/netclaw.json`. Merge the `Notifications` block into your existing config if one is already there.

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
        "Url": "https://your-monitoring.example.com/alerts",
        "Name": "pagerduty-relay",
        "Format": "Generic",
        "Headers": {
          "Authorization": "Bearer your-token"
        }
      }
    ],
    "DeduplicationWindowSeconds": 300,
    "MaxRetries": 2,
    "TimeoutSeconds": 10
  }
}
```

Restart the daemon after editing `netclaw.json` for changes to take effect.

Each webhook target has:

| Field | Required | Description |
|-------|----------|-------------|
| `Url` | Yes | Endpoint to POST alerts to |
| `Name` | No | Human-readable label for logs (falls back to the URL if omitted) |
| `Format` | No | `Slack` or `Generic` (default). URLs containing `hooks.slack.com` auto-detect as Slack. |
| `Headers` | No | Custom HTTP headers (auth tokens, API keys) |

Top-level notification settings:

| Field | Default | Description |
|-------|---------|-------------|
| `DeduplicationWindowSeconds` | 300 | Suppress duplicate alerts within this window ([details below](#delivery-behavior)) |
| `MaxRetries` | 2 | Retry attempts for failed deliveries |
| `TimeoutSeconds` | 10 | HTTP timeout per delivery attempt |

## Payload Formats

### Generic JSON

Every alert arrives as a JSON POST with this envelope:

```json
{
  "alertId": "550e8400-e29b-41d4-a716-446655440000",
  "type": "provider.unreachable",
  "severity": "critical",
  "summary": "All LLM providers are unreachable",
  "timestamp": "2026-05-02T14:30:00Z",
  "source": "netclaw",
  "hostname": "claw-prod-01",
  "service": {
    "name": "netclaw-prod",
    "namespace": "ops",
    "instanceId": "claw-prod-01:12345",
    "version": "0.22.1"
  },
  "context": {
    "lastProvider": "anthropic",
    "errorCount": "5"
  }
}
```

The `service` object is the [service identity](/observability/opentelemetry/#service-identity) sourced from the OpenTelemetry environment variables. `instanceId` always has a value (it defaults to `{hostname}:{pid}`); `namespace` appears only when you set it. When several netclaw instances post to the same endpoint, that's how you tell which one fired. The `context` object varies by alert type, carrying whatever extra detail is relevant to that event.

### Slack Block Kit

When `Format` is `Slack`, netclaw sends [Block Kit](https://api.slack.com/block-kit) messages with severity-colored headers and structured fields:

- 🔴 Critical alerts
- ⚠️ Warnings
- ℹ️ Info events

Each message includes a `text` fallback for notification previews. The `blocks` payload has the header, summary, metadata (severity, type, timestamp, hostname), and alert-specific context.

## Delivery Behavior

**Deduplication** — Identical alerts (same type and source) within the deduplication window are suppressed. This prevents notification storms when a provider flaps or a connection drops and reconnects rapidly.

**Retries with backoff** — Failed deliveries retry with exponential backoff and jitter. With the default `MaxRetries` of 2:

| Attempt | Base Delay | Range (with ±25% jitter) |
|---------|-----------|---------------------|
| 1 | 2s | 1.5s – 2.5s |
| 2 | 4s | 3s – 5s |

Backoff caps at 30 seconds for higher retry counts. Netclaw doesn't retry client errors (4xx) — only server errors (5xx) and timeouts trigger retries.

**Bounded queue** — Netclaw buffers alerts in a 256-slot in-memory queue. When the queue fills, the oldest buffered alert is dropped to make room for the new one, so the daemon always accepts new alerts without blocking.

## Further Reading

- [Slack Incoming Webhooks setup guide](https://api.slack.com/messaging/webhooks) — Create the webhook URL you'll paste into the `Url` field
- [Slack Block Kit documentation](https://api.slack.com/block-kit) — Reference for the structured message format netclaw uses for Slack alerts
- [PagerDuty Events API v2](https://developer.pagerduty.com/docs/events-api-v2/overview/) — Set up a PagerDuty service to receive Generic-format alerts
- [OpenTelemetry](/observability/opentelemetry/) — Export metrics via OpenTelemetry Protocol (OTLP) for dashboards and long-term monitoring
- [netclaw status](/cli/status/) — Check current system health interactively
