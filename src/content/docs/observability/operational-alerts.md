---
title: Operational Alerts
description: "Send outbound webhook notifications for daemon lifecycle events, provider failures, channel disconnects, memory model problems and more."
---

Netclaw emits operational alerts when something happens that you or your ops tooling should know about: a provider going down, a channel disconnecting, the daemon crashing. Netclaw delivers these as outbound webhook POSTs to URLs you configure, with native Slack Block Kit formatting or a generic JSON envelope.

## Quick start

1. Run [`netclaw config`](/cli/config/) → **Telemetry & Alerting**.
2. Add a webhook URL and choose `Slack` or `Generic` format.
3. Save. The daemon restarts itself on the config change, and you'll get a `daemon.started` alert confirming delivery works. Repeats of the same type and source inside the 300-second deduplication window collapse into one alert.

That's it for most installs. For scripted deployments or headless servers, see [Manual configuration](#manual-configuration) below.

## Alert types

| Type String | Severity | What Happened |
|-------------|----------|---------------|
| `daemon.started` | Info | Daemon finished startup. Includes PID. |
| `daemon.stopping` | Info | Graceful shutdown initiated. Includes reason. |
| `daemon.crashing` | Critical | Unhandled exception - the process is going down. |
| `update.available` | Info | A newer netclaw binary exists in the release feed. |
| `provider.failover` | Warning | Primary LLM provider failed; traffic moved to fallback. |
| `provider.unreachable` | Critical | All configured LLM providers are unavailable. |
| `channel.disconnected` | Warning | Slack, Discord, or Mattermost connection lost. |
| `channel.reconnected` | Info | The Slack connection came back after a drop. Slack only. |
| `provider.auth.expired` | Warning | A provider's OAuth credentials couldn't be refreshed. The summary says to run `netclaw provider`, or `netclaw provider add <name> <type> --auth oauth-device` to sign in again. A rejected OpenAI refresh raises it too. |
| `mcp.auth.expired` | Warning | MCP OAuth token expired and refresh was rejected. |
| `mcp.server.disconnected` | Warning | Connection to an MCP server dropped. |
| `mcp.server.reconnected` | Info | MCP server reconnected successfully after a previous disconnect. |
| `webhook.received` | Info | A valid inbound webhook delivery was accepted and queued. |
| `webhook.route.invalid` | Warning | A webhook route file is missing or invalid. |
| `reminder.execution.failed` | Warning | A scheduled reminder failed to execute. A failed reply post on a `current_session` reminder is `reminder.delivery.failed` instead. |
| `reminder.delivery.failed` | Warning | A reminder ran and its session admitted it, but the reply post failed for good. Not retried. Context: `reminderId`, `sessionId`, `channel`, `failureKind`, `error`. |
| `reminder.status.query_failed` | Warning | The 12-hour sweep or startup reconciliation couldn't read the status of a past one-shot reminder. It is left as is and retried on the next pass. |
| `reminder.tombstone.invalid` | Warning | The end record of a finished one-shot reminder under `schedules/reminders/ended/` can't be read, so its history is unreadable and it doesn't run. |
| `reminder.schedule.failed` | Warning | A reminder couldn't be scheduled for its next run. Repeated failures auto-disable it. |
| `reminder.settlement.failed` | Warning | A reminder ran, but recording its outcome failed. |
| `reminder.tool_denied` | Warning | A reminder ran, but one of its tool calls was denied (policy, a hard deny, or an approval with nobody to answer). The run is recorded as `denied`. One alert per reminder per distinct reason, until a run succeeds. |
| `reminder.auto_disabled` | Critical | Reminder disabled after repeated consecutive failures. |
| `reminder.schema.invalid_dropped` | Warning | Invalid reminder definitions were dropped at startup. |
| `reminder.schema.legacy_rejected` | Warning | Legacy reminder definitions missing trust fields were rejected at startup. |
| `background-job.schema.legacy_rejected` | Warning | Legacy background job definitions missing trust fields were rejected at startup. |
| `memory.embedding_model.unavailable` | Warning | The local embedding model couldn't be downloaded or loaded. Recall falls back to lexical search. Fires once per daemon run. |
| `memory.relevance_model.unavailable` | Warning | The relevance-gate model couldn't be downloaded or loaded, so recall isn't filtered by the cross-encoder. Fires once per daemon run. |

All configured destinations receive all alert types - there's no per-destination filtering.

## Configure alert destinations

Use `netclaw config` → **Telemetry & Alerting** to add, edit, or remove webhook targets at any time. In Docker you can set the same fields as environment variables, which need a `docker restart` to take effect:

```bash
-e NETCLAW_Notifications__Webhooks__0__Url=https://alerts.example.com/netclaw \
-e NETCLAW_Notifications__Webhooks__0__Name=ops \
-e NETCLAW_Notifications__Webhooks__0__Format=Generic \
-e NETCLAW_Notifications__Webhooks__0__Headers__X-Api-Key=your-key
```

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

The daemon restarts itself after a valid edit to `netclaw.json`.

Each webhook target has:

| Field | Required | Description |
|-------|----------|-------------|
| `Url` | Yes | Endpoint to POST alerts to |
| `Name` | No | Human-readable label for logs. Logs show `(unnamed webhook)` if omitted, never the URL, because URLs can hold secrets |
| `Format` | No | `Slack` or `Generic` (default). URLs containing `hooks.slack.com` auto-detect as Slack. |
| `Headers` | No | Custom HTTP headers (auth tokens, API keys) |

Top-level notification settings:

| Field | Default | Description |
|-------|---------|-------------|
| `DeduplicationWindowSeconds` | 300 | Suppress duplicate alerts within this window ([details below](#delivery-behavior)) |
| `MaxRetries` | 2 | Retry attempts for failed deliveries |
| `TimeoutSeconds` | 10 | HTTP timeout per delivery attempt |

## Payload formats

### Generic JSON

Every alert arrives as a JSON POST with `Content-Type: application/json` and a `User-Agent` of `Netclaw/<version> (+https://netclaw.dev; sha=<commit>)` and `X-Netclaw-Component: webhook`, plus any custom headers you set. This is the `daemon.stopping` alert a Docker container sent on `docker stop`:

```json
{
  "alertId": "ad0d316727bf",
  "type": "daemon.stopping",
  "severity": "info",
  "summary": "Netclaw daemon stopping: daemon-stop",
  "timestamp": "2026-10-07T15:34:12.323848+00:00",
  "source": "netclaw",
  "hostname": "a9fdada82d02",
  "service": {
    "name": "netclawd",
    "instanceId": "a9fdada82d02:33",
    "version": "0.28.2"
  },
  "context": {
    "pid": "33",
    "reason": "daemon-stop",
    "drainOutcome": "drained",
    "activeSessions": "0",
    "drainedSessions": "0",
    "timedOutSessions": "0",
    "restartReminders": "0"
  }
}
```

`alertId` is a short hex string, and every `context` value is a string. When a session doesn't acknowledge a stop or restart drain, `daemon.stopping` also carries `timedOutSessionIds`, a comma-separated list of those session IDs, and `drainOutcome` is `timeout`. The `type` and `severity` values come from the table above, with `severity` in lowercase.

The `service` object is the [service identity](/observability/opentelemetry/#service-identity) sourced from the OpenTelemetry environment variables. `instanceId` always has a value (it defaults to `{hostname}:{pid}`), and `namespace` appears only when you set it. When several netclaw instances post to the same endpoint, that's how you tell which one fired. The `context` object varies by alert type, carrying whatever extra detail is relevant to that event.

### Slack Block Kit

When `Format` is `Slack`, netclaw sends [Block Kit](https://api.slack.com/block-kit) messages with severity-colored headers and structured fields:

- Critical alerts get `:red_circle:`
- Warnings get `:warning:`
- Info events get `:information_source:`

Each message includes a `text` fallback for notification previews. The `blocks` payload has the header, summary, metadata (severity, type, timestamp, hostname), and alert-specific context.

## Delivery behavior

**Deduplication** - Identical alerts (same type and source) within the deduplication window are suppressed. This prevents notification storms when a provider flaps or a connection drops and reconnects rapidly.

**Retries with backoff** - Failed deliveries retry with exponential backoff and jitter. With the default `MaxRetries` of 2:

| Attempt | Base Delay | Range (with ±25% jitter) |
|---------|-----------|---------------------|
| 1 | 2s | 1.5s – 2.5s |
| 2 | 4s | 3s – 5s |

Backoff caps at 30 seconds for higher retry counts. Netclaw doesn't retry client errors (4xx) - only server errors (5xx) and timeouts trigger retries.

**Bounded queue** - Netclaw buffers alerts in a 256-slot in-memory queue. When the queue fills, the oldest buffered alert is dropped to make room for the new one, so the daemon always accepts new alerts without blocking.

## Related pages

- [Health checks](/observability/health-checks/) - poll daemon state instead of waiting for a push
- [OpenTelemetry](/observability/opentelemetry/) - export metrics and logs for dashboards and long-term monitoring
- [`netclaw status`](/cli/status/) - check current system health interactively
- [`netclaw config`](/cli/config/) - the **Telemetry & Alerting** screen
- [Memory and embeddings](/configuration/memory/) - what the memory model alerts mean

## Resources

- [Slack Incoming Webhooks setup guide](https://api.slack.com/messaging/webhooks) - create the webhook URL you'll paste into the `Url` field
- [Slack Block Kit documentation](https://api.slack.com/block-kit) - the structured message format netclaw uses for Slack alerts
- [PagerDuty Events API v2](https://developer.pagerduty.com/docs/events-api-v2/overview/) - set up a PagerDuty service to receive Generic-format alerts
