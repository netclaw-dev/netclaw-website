---
title: "Health checks"
description: "The daemon's HTTP health endpoints for Docker, Kubernetes, load balancers and monitoring, and how to read the status response."
---

The daemon serves two HTTP health endpoints on its port (default `5199`). Use `/api/health/ready` for container and load balancer probes, and `/api/health/status` when you want to know what's wrong.

## Endpoints

| Endpoint | Auth | Purpose |
|----------|------|---------|
| `GET /api/health/ready` | None | Liveness and readiness probe |
| `GET /api/health/status` | Required, except from a loopback call in `local` mode | Full subsystem status |

## Readiness probe

```bash
curl -si http://127.0.0.1:5199/api/health/ready
```

```text
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Netclaw-Generation: 1

"healthy"
```

The body is the JSON string `"healthy"`, quotes included. Any other response, or a refused connection, means the daemon isn't accepting requests. `X-Netclaw-Generation` counts in-process restarts since the process started, so it goes up each time a config edit restarts the daemon. It's how the init wizard confirms it's talking to the daemon that picked up the change.

The probe reports that the process is up. It stays `200` when a connector is down or no model is configured. Read `/api/health/status` for those.

### Docker

The official image uses this check:

```dockerfile
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD netclaw daemon status >/dev/null || exit 1
```

`netclaw daemon status` exits `0` when the process is up and `/api/health/ready` answers. It exits `1` when the daemon isn't running, the probe gets no answer, the PID in `netclaw.pid` isn't shown to serve this home, or `netclaw.json` or `secrets.json` can't be read (`The local daemon address is unknown. No readiness probe was sent. Repair the local configuration and retry.`). It reads the endpoint from `netclaw.json`, `NETCLAW_*` variables or the default, so a custom `Daemon.Port` doesn't break the check.

The 30-second start period covers provider setup and the first-start model download. Check the result with `docker inspect --format '{{.State.Health.Status}}' <container>`.

### Kubernetes

Kubernetes ignores the image's `HEALTHCHECK`, so define a probe yourself. In `local` mode the daemon only listens on the pod's loopback, and an `httpGet` probe comes from the kubelet to the pod IP, so it's refused. Use an `exec` probe that runs the image's own command, `netclaw daemon status`. In `reverse-proxy` mode with `Daemon.Host` set to `0.0.0.0`, the endpoint is reachable and anonymous, so `httpGet` on port `5199` works. These probes haven't been run on a cluster, so test them before you rely on them. See [Run netclaw in Docker](/deployment/docker/#kubernetes) for the other requirements.

### systemd

To hold the service in "activating" until the daemon accepts requests, add a drop-in with an `ExecStartPost` check:

```ini
[Service]
ExecStartPost=/bin/sh -c 'until curl -sf http://127.0.0.1:5199/api/health/ready; do sleep 2; done'
```

## Status endpoint

```bash
curl -s http://127.0.0.1:5199/api/health/status
```

It returns the state of every subsystem. [`netclaw status`](/cli/status/) shows the same data as a table. Once you're authorized, the HTTP status is always `200`, so parse `overall`. A fresh container with no model shows `overall: degraded` and `degradedReason: no main model configured (Models:Main missing)`.

On the daemon host in `local` mode, loopback requests need no credentials, as long as they look local. The `Host` must be `localhost` or a loopback IP such as `127.0.0.1`, and an `Origin` header, if present, must be `http://` plus that same host. A request through another host name, or from a browser page on another local port, gets `401`. Don't send an `Authorization` header from loopback, because an invalid token returns `401`. In every other mode, loopback isn't trusted and callers need a paired device's token as `Authorization: Bearer <token>`. A remote monitor that only needs liveness should use `/api/health/ready`.

### Response structure

This is the response from a daemon with one local model, embeddings on and the other connectors disabled:

```json
{
  "overall": "healthy",
  "configNotApplied": null,
  "build": {
    "version": "0.28.2",
    "commitHash": "7419d84",
    "buildTimestamp": "2026-10-29T00:10:12Z"
  },
  "process": {
    "pid": 33,
    "startedAtUtc": "2026-10-07T15:28:19.0289154+00:00",
    "uptimeSeconds": 284
  },
  "connectors": [
    {
      "key": "slack",
      "displayName": "Slack",
      "enabled": false,
      "status": "disabled",
      "message": "Slack connector is disabled in configuration."
    },
    {
      "key": "tui",
      "displayName": "TUI",
      "enabled": true,
      "status": "healthy",
      "message": null
    }
  ],
  "persistence": {
    "provider": "Sqlite"
  },
  "telemetry": {
    "enabled": false,
    "otlpEndpoint": "http://127.0.0.1:4317",
    "channels": []
  },
  "model": {
    "modelId": "/models/example-model.gguf",
    "displayName": "/models/example-model",
    "provider": "ollama",
    "inputModalities": "Text, Image",
    "outputModalities": "Text",
    "contextWindow": 131072,
    "degraded": false,
    "degradedReason": null
  },
  "update": {
    "available": false,
    "selfUpdateDisabled": true,
    "state": "up-to-date",
    "currentVersion": "0.28.2",
    "latestVersion": null,
    "releaseNotesUrl": null,
    "errorDetail": null
  },
  "memory": {
    "provider": "sqlite",
    "status": "healthy",
    "databasePath": "/home/netclaw/.netclaw/netclaw.db",
    "pendingCheckpoints": 0,
    "embeddings": {
      "status": "ok",
      "modelId": "snowflake-arctic-embed-m-int8",
      "degradedReason": null
    }
  },
  "reminders": {
    "scheduledCount": 1,
    "activeExecutions": 0,
    "failedCount": 0
  }
}
```

The `connectors` list also holds `discord`, `mattermost`, one `mcp:<server>` entry per configured MCP server, and a `provider:<name>` entry (display name `Provider/<name>`) while an OAuth provider's refresh token is rejected. Its status is `auth-failed`, so `overall` turns `degraded`, and its message says to run `netclaw provider`. `inputModalities` and `outputModalities` are comma-separated strings, not arrays. `telemetry.channels` carries the per-channel counters that `netclaw status` prints. `selfUpdateDisabled` is `true` in the Docker image.

### Overall status

| Overall | Condition |
|---------|-----------|
| `degraded` | The daemon has no usable chat model (`model.degraded` is `true`), or an enabled connector is `disconnected`, `degraded`, `auth-required` or `auth-failed`, or the daemon refused a change to `netclaw.json` (`configNotApplied` holds the reason) |
| `healthy` | Everything else |

`configNotApplied` is `null` when the file on disk is the configuration the daemon runs. It carries a one-line reason, such as `Models:Roles:Main references unknown definition 'nope'. Defined: stub-stub-model. ...`, after a hand edit left `Models` or a provider invalid. The daemon keeps its previous configuration and applies nothing from the file until you fix it. [`netclaw status`](/cli/status/) prints it as `config on disk not applied: <reason>`. A restart with that file exits `1` with the same line.

The HTTP status stays `200` either way. That avoids restarting a container because one channel had a transient disconnect.

### Connector statuses

Each connector (Slack, Discord, Mattermost, the TUI and MCP servers) reports one of:

| Status | Meaning |
|--------|---------|
| `healthy` | Connected and operational |
| `degraded` | Partially functional, for example reconnecting |
| `disconnected` | Connection lost |
| `auth-required` | Needs an OAuth flow (MCP servers) |
| `auth-failed` | Credentials rejected, including an OAuth provider that needs a new sign-in |
| `disabled` | Turned off in config |
| `unknown` | The connector hasn't reported a state |

### Memory status

| Field | Values |
|-------|--------|
| `memory.status` | `healthy` when the database answers, `degraded` when the check throws, `unavailable` when there's no store |
| `memory.embeddings.status` | `ok` (models loaded), `degraded` (provisioning or loading failed, so recall is lexical only), `disabled` (`Memory.Embeddings.Enabled` is `false`) |
| `update.state` | `up-to-date`, `update-available` or `unknown` (the check failed or hasn't run) |

A backlog of memory checkpoints isn't part of this status. [`netclaw doctor`](/cli/doctor/) has a check for it.

## Monitoring integration

For a simple availability check, poll the readiness probe:

```bash
curl -sf http://127.0.0.1:5199/api/health/ready && echo 1 || echo 0
```

For metrics, use the [OpenTelemetry](/observability/opentelemetry/) export. When a connector drops, an [operational alert](/observability/operational-alerts/) pushes to your webhooks, so you don't need to poll the status endpoint to catch it.

## Related pages

- [`netclaw status`](/cli/status/) - the CLI view of this endpoint
- [`netclaw doctor`](/cli/doctor/) - offline diagnostics for configuration issues
- [Operational alerts](/observability/operational-alerts/) - push notifications on health changes
- [OpenTelemetry](/observability/opentelemetry/) - metrics and logs export
- [Run netclaw in Docker](/deployment/docker/) - container health and restarts

## Resources

- [Docker HEALTHCHECK](https://docs.docker.com/reference/dockerfile/#healthcheck) - the instruction the image uses
- [Kubernetes probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) - liveness, readiness and startup probes
- [systemd.service ExecStartPost](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html#ExecStartPost=) - run a command after the service starts
