---
title: OpenTelemetry
description: Export metrics and logs from netclaw via OTLP for monitoring token usage, session activity, and system health.
---

Netclaw can push metrics and structured logs to any [OpenTelemetry](https://opentelemetry.io/) Protocol (OTLP) compatible collector. Flip it on, point it at your collector, and your existing backend (Grafana, Datadog, Honeycomb, whatever speaks OTLP) gets per-channel message flow metrics, token consumption counters, and full daemon logs.

## Configuration

Merge a `Telemetry` block into your existing `~/.netclaw/config/netclaw.json`:

```json
{
  "Telemetry": {
    "Enabled": true,
    "Otlp": {
      "Endpoint": "http://127.0.0.1:4317"
    }
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Enabled` | bool | `false` | Turns on the OTLP export pipeline |
| `Otlp:Endpoint` | string | `http://127.0.0.1:4317` | OTLP collector endpoint (gRPC) |

Netclaw uses gRPC OTLP on port 4317, not HTTP/Protobuf (4318). If your collector only accepts HTTP OTLP, you'll get silent failures.

Environment variable overrides follow the [.NET double-underscore convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider):

```bash
export NETCLAW_Telemetry__Enabled="true"
export NETCLAW_Telemetry__Otlp__Endpoint="http://127.0.0.1:4317"
```

Telemetry config changes need a daemon restart. Run [`netclaw doctor`](/cli/doctor/) first to catch config errors before you bounce the daemon:

```bash
netclaw doctor
netclaw daemon stop && netclaw daemon start
```

### Validation

If `Otlp:Endpoint` isn't a valid absolute URI, the daemon refuses to start, even with telemetry disabled:

```
Telemetry:Otlp:Endpoint must be an absolute URI.
```

[`netclaw doctor`](/cli/doctor/) catches this before you hit it at startup. It validates the endpoint format and warns when telemetry is on but no explicit endpoint is set.

## What gets exported

Every signal carries an OpenTelemetry resource identifying the service. The name defaults to `netclawd`, but it — and the rest of the `service.*` attributes — are yours to set; see [Service identity](#service-identity).

Every log line the daemon produces goes to your collector, with full formatting and scope data (`IncludeFormattedMessage`, `IncludeScopes`, `ParseStateValues` all enabled). Two meters cover metrics: one for session-level token usage, one for per-channel message flow. Full reference below.

Distributed tracing is off for now. The cross-actor model produces disconnected spans with no meaningful causality chain, so it's more noise than signal.

## Service identity

Service identity comes from the standard OpenTelemetry environment variables — netclaw keeps no identity config of its own. Set them however you launch the daemon:

```bash
export OTEL_SERVICE_NAME="netclaw-prod"
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=ops,service.instance.id=claw-prod-01"
```

Four attributes end up on every signal and on each [operational alert](/observability/operational-alerts/):

| Attribute | Source | Default |
|-----------|--------|---------|
| `service.name` | `OTEL_SERVICE_NAME` or `OTEL_RESOURCE_ATTRIBUTES` | `netclawd` |
| `service.version` | `OTEL_RESOURCE_ATTRIBUTES`, else the build | the running netclaw version |
| `service.instance.id` | `OTEL_RESOURCE_ATTRIBUTES` | `{hostname}:{pid}` |
| `service.namespace` | `OTEL_RESOURCE_ATTRIBUTES` | unset |

netclaw logs the resolved identity once at startup, so you can confirm the env vars took effect:

```
OpenTelemetry service identity resolved: service.name=netclaw-prod, service.namespace=ops, service.instance.id=claw-prod-01, service.version=0.22.1
```

Give each instance a distinct name (or namespace / instance ID) when several report to the same collector or alert webhook — that's what lets you tell them apart.

:::note
The short-lived `Telemetry:ServiceName` property from 0.18.2 is gone. Since 0.19.0, service identity is sourced only from the OpenTelemetry environment variables above.
:::

## Metrics reference

### Session metrics (`Netclaw.Sessions`)

Token consumption and turn tracking across all sessions.

| Metric | Type | Description |
|--------|------|-------------|
| `netclaw.session.tokens.input` | Counter | Input tokens consumed |
| `netclaw.session.tokens.output` | Counter | Output tokens consumed |
| `netclaw.session.turns.completed` | Counter | Conversation turns completed |

These are aggregate totals across all models and providers, with no per-model or per-provider attribute breakdowns.

### Channel metrics (`Netclaw.Channels`)

Per-channel message pipeline metrics. Each metric name is prefixed with `netclaw.channel.{channel-type}` where channel type is one of: `slack`, `tui`, `headless`, `signalr`, `reminder`, `webhook`, `discord`.

| Metric suffix | Type | Attributes | Description |
|---------------|------|------------|-------------|
| `.events.received` | Counter | `kind` | Inbound events received |
| `.events.dropped` | Counter | `reason` | Events dropped before processing |
| `.events.filtered` | Counter | `reason` | Events filtered by policy |
| `.events.routed` | Counter | `kind` | Events that reached conversation routing |
| `.messages.enqueued` | Counter | — | Messages accepted into session queue |
| `.replies.posted` | Counter | — | Successful replies sent |
| `.replies.rejected` | Counter | `error_code` | Rejected reply attempts |
| `.replies.failed` | Counter | — | Failed reply attempts |
| `.reply.duration.ms` | Histogram | — | Reply post latency in milliseconds (includes both successful and failed attempts) |

> `Netclaw.Webhooks` (the meter behind [`netclaw stats`](/cli/stats/)) is not wired into OTLP. The `netclaw.channel.webhook.*` metrics above cover message flow through the webhook channel; per-route delivery stats only show up in `netclaw stats`.

## Diagnostic queries

| Symptom | What to check |
|---------|---------------|
| No replies | `events.received` > 0 but `replies.posted` = 0. Events arrive, nothing comes back. |
| Looping agent | `turns.completed` climbing without corresponding `replies.posted` |
| Policy dropping messages | `events.dropped` with `reason` attribute showing the cause |

## Collector setup

Point the endpoint at any [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) that accepts gRPC OTLP. A minimal local setup with Docker:

```bash
docker run -d --name otel-collector \
  -p 4317:4317 \
  otel/opentelemetry-collector-contrib:latest
```

Route to your backend (Prometheus, Grafana Cloud, Datadog, etc.) via the collector's [exporter configuration](https://opentelemetry.io/docs/collector/configuration/#exporters).

For a quick local stack, [Grafana OTel-LGTM](https://github.com/grafana/docker-otel-lgtm) bundles the collector, Prometheus, Loki, and Grafana in one container. Good for kicking the tires before committing to a production backend.

## Verifying the pipeline

After restarting the daemon with telemetry enabled:

1. [`netclaw status`](/cli/status/) should show the telemetry row as `enabled` with your endpoint
2. [`netclaw doctor`](/cli/doctor/) validates the endpoint URI format
3. Send a test message through any channel and look for `netclaw.channel.*` metrics in your collector

Once data is flowing, build dashboards around the [diagnostic queries](#diagnostic-queries) above. [Operational Alerts](/observability/operational-alerts/) covers netclaw's built-in webhook notifications, which work alongside OTel-based alerting.

## Related pages

- [Operational Alerts](/observability/operational-alerts/) for outbound webhook notifications
- [`netclaw status`](/cli/status/) shows the telemetry row and OTLP endpoint
- [`netclaw doctor`](/cli/doctor/) validates OTLP endpoint configuration
- [`netclaw stats`](/cli/stats/) has in-process counters, including webhook metrics that aren't in OTLP

## Resources

- [OpenTelemetry Collector documentation](https://opentelemetry.io/docs/collector/) covers setup, configuration, and deployment
- [OTLP specification](https://opentelemetry.io/docs/specs/otlp/) describes the wire protocol netclaw uses
- [Grafana OTel-LGTM Docker image](https://github.com/grafana/docker-otel-lgtm) is an all-in-one local observability stack
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) explains the double-underscore nesting convention
