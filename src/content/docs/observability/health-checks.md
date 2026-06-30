---
title: "Health Checks"
description: "HTTP health endpoints for monitoring and orchestration."
---

The daemon exposes two HTTP health endpoints for container orchestration, load balancers, and monitoring systems.

## Endpoints

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /api/health/ready` | None | Liveness/readiness probe |
| `GET /api/health/status` | Required | Full subsystem status |

Both listen on the daemon's configured port (default `5199`).

## Readiness probe

```bash
curl -sf http://127.0.0.1:5199/api/health/ready
```

Returns `200 OK` with body `healthy` when the daemon is accepting requests. No authentication, no JSON — just a string. Use this for Docker HEALTHCHECK, Kubernetes liveness probes, and load balancer health checks.

Any non-200 response (or connection refused) means the daemon isn't ready.

### Docker HEALTHCHECK

The official container image uses this:

```dockerfile
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -sf http://127.0.0.1:5199/api/health/ready || exit 1
```

The 30-second start period gives the daemon time to initialize providers and connect channels before the first probe fires.

### Kubernetes

```yaml
livenessProbe:
  httpGet:
    path: /api/health/ready
    port: 5199
  initialDelaySeconds: 30
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 3
```

### Systemd

For systemd-managed daemons, use a `ExecStartPost` check or a watchdog timer:

```ini
[Service]
ExecStartPost=/bin/sh -c 'until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done'
```

## Status endpoint

```bash
curl -s http://127.0.0.1:5199/api/health/status \
  -H "Authorization: Bearer $(netclaw auth token)"
```

Returns a JSON object with the state of every subsystem. This is the same data that [`netclaw status`](/cli/status/) displays — the CLI just formats it as a table.

Requires authentication (bearer token or loopback origin). Returns `401` without valid credentials.

### Response structure

```json
{
  "overall": "healthy",
  "build": {
    "version": "0.4.2",
    "commitHash": "a1b2c3d",
    "buildTimestamp": "2026-05-01T12:00:00Z"
  },
  "process": {
    "pid": 1234,
    "startedAtUtc": "2026-05-05T08:00:00Z",
    "uptimeSeconds": 3600
  },
  "connectors": [
    {
      "key": "slack",
      "displayName": "Slack",
      "enabled": true,
      "status": "healthy",
      "message": null
    },
    {
      "key": "discord",
      "displayName": "Discord",
      "enabled": true,
      "status": "disconnected",
      "message": "Gateway timeout"
    },
    {
      "key": "mcp:github",
      "displayName": "GitHub MCP",
      "enabled": true,
      "status": "healthy",
      "message": null
    }
  ],
  "model": {
    "modelId": "anthropic/claude-sonnet-4",
    "displayName": "Claude Sonnet 4",
    "provider": "openrouter",
    "inputModalities": ["text", "image"],
    "outputModalities": ["text"],
    "contextWindow": 200000
  },
  "persistence": {
    "provider": "sqlite"
  },
  "memory": {
    "provider": "sqlite",
    "status": "healthy",
    "databasePath": "/home/netclaw/.netclaw/memory/netclaw-memory.db",
    "pendingCheckpoints": 0
  },
  "reminders": {
    "scheduledCount": 3,
    "activeExecutions": 0,
    "failedCount": 0
  },
  "telemetry": {
    "enabled": true,
    "otlpEndpoint": "http://localhost:4317"
  },
  "update": {
    "state": "up-to-date",
    "available": false,
    "currentVersion": "0.4.2",
    "latestVersion": "0.4.2"
  }
}
```

### Overall status

The `overall` field is computed from connector states:

| Overall | Condition |
|---------|-----------|
| `healthy` | All enabled connectors are healthy |
| `degraded` | Any enabled connector is `disconnected`, `degraded`, `auth-required`, or `auth-failed` |

The HTTP status code is always `200` — parse the `overall` field to determine health. This avoids false-positive container restarts when a single channel has a transient disconnect.

### Connector statuses

Each connector (Slack, Discord, MCP servers) reports one of:

| Status | Meaning |
|--------|---------|
| `healthy` | Connected and operational |
| `degraded` | Partially functional (e.g., reconnecting) |
| `disconnected` | Connection lost |
| `auth-required` | Needs OAuth flow (MCP servers) |
| `auth-failed` | Credentials rejected |
| `disabled` | Turned off in config |

### Memory status

| Status | Meaning |
|--------|---------|
| `healthy` | Database accessible, checkpoint backlog ≤ 25 |
| `degraded` | Checkpoint backlog growing (> 25 pending) |
| `unavailable` | Database unreachable |

## Monitoring integration

### Prometheus / Grafana

Poll `/api/health/status` on an interval and extract metrics:

```bash
# Simple availability check (no auth needed)
curl -sf http://127.0.0.1:5199/api/health/ready && echo 1 || echo 0
```

For richer metrics, use the [OpenTelemetry](/observability/opentelemetry/) integration which exports to OTLP directly.

### Operational alerts

When a connector transitions to `disconnected` or `auth-failed`, the daemon fires an [operational alert](/observability/operational-alerts/) to configured webhook targets. You don't need to poll the status endpoint to detect failures — alerts push to you.

## Related pages

- [`netclaw status`](/cli/status/) — CLI that formats this endpoint's response as a table
- [`netclaw doctor`](/cli/doctor/) — offline diagnostics for configuration issues
- [Operational Alerts](/observability/operational-alerts/) — push notifications on health state changes
- [OpenTelemetry](/observability/opentelemetry/) — metrics and traces export
- [Docker Deployment](/deployment/docker/) — container health check configuration

## Resources

- [ASP.NET Health Checks](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks) — the framework behind the endpoints
- [Kubernetes Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) — configuring liveness and readiness probes
- [Docker HEALTHCHECK](https://docs.docker.com/reference/dockerfile/#healthcheck) — container health check instruction reference
