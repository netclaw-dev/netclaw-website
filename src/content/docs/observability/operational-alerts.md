---
title: Operational Alerts
description: Configure outbound webhook notifications for daemon lifecycle events, provider failures, channel disconnects, and more.
---

Netclaw emits operational alerts when something happens that you or your ops tooling should know about — a provider going down, a channel disconnecting, the daemon crashing. Netclaw delivers these as outbound webhook POSTs to URLs you configure, with native Slack Block Kit formatting or a generic JSON envelope.

## Quick Start

Add a `Notifications` block to `~/.netclaw/config/netclaw.json` and restart the daemon:

```json
{
  "Notifications": {
    "Webhooks": [
      {
        "Url": "https://hooks.slack.com/services/T00/B00/xxx",
        "Name": "ops-slack",
        "Format": "Slack"
      }
    ]
  }
}
```

You'll get a `daemon.started` alert on the next restart, which doubles as confirmation that delivery works.

## Alert Types

| Type String | Severity | What Happened |
|-------------|----------|---------------|
| `daemon.started` | Info | Daemon finished startup. Includes PID. |
| `daemon.stopping` | Info | Graceful shutdown initiated. Includes reason. |
| `daemon.crashing` | Critical | Unhandled exception — the process is going down. |
| `update.available` | Info | A newer netclaw binary exists in the release feed. |
| `provider.failover` | Warning | Primary LLM provider failed; traffic moved to fallback. |
| `provider.unreachable` | Critical | All configured LLM providers are unavailable. |
| `channel.disconnected` | Warning | Slack or Discord connection lost. |
| `mcp.auth.expired` | Warning | MCP OAuth token expired and refresh was rejected. |
| `mcp.server.disconnected` | Warning | Connection to an MCP server dropped. |
| `webhook.received` | Info | A valid inbound webhook delivery was accepted and queued. |
| `webhook.route.invalid` | Warning | A webhook route file is missing or invalid. |
| `reminder.execution.failed` | Warning | A scheduled reminder failed to execute. |
| `reminder.auto.disabled` | Critical | Reminder disabled after repeated consecutive failures. |
| `reminder.schema.dropped` | Warning | Invalid reminder definitions were dropped at startup. |

`provider.auth.expired` is defined but not currently emitted.

All configured destinations receive all alert types — there's no per-destination filtering.

## Configuring Alert Destinations

Add outbound webhook targets in `~/.netclaw/config/netclaw.json`. Merge the `Notifications` block into your existing config if one is already there.

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
| `Name` | Yes | Human-readable label for logs |
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
  "context": {
    "lastProvider": "anthropic",
    "errorCount": "5"
  }
}
```

The `context` object varies by alert type — it carries whatever extra detail is relevant to that event.

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
| 1 | 1s | 0.75s – 1.25s |
| 2 | 2s | 1.5s – 2.5s |

Backoff caps at 30 seconds for higher retry counts. Netclaw doesn't retry client errors (4xx) — only server errors (5xx) and timeouts trigger retries.

**Bounded queue** — Netclaw buffers alerts in a 256-slot in-memory queue. If the queue fills (all webhook targets are slow or down), new alerts drop rather than applying backpressure to the daemon.

## Further Reading

- [Slack Incoming Webhooks setup guide](https://api.slack.com/messaging/webhooks) — Create the webhook URL you'll paste into the `Url` field
- [Slack Block Kit documentation](https://api.slack.com/block-kit) — Reference for the structured message format netclaw uses for Slack alerts
- [PagerDuty Events API v2](https://developer.pagerduty.com/docs/events-api-v2/overview/) — Set up a PagerDuty service to receive Generic-format alerts
- [OpenTelemetry](/observability/opentelemetry/) — Export metrics via OpenTelemetry Protocol (OTLP) for dashboards and long-term monitoring
- [netclaw status](/cli/status/) — Check current system health interactively
