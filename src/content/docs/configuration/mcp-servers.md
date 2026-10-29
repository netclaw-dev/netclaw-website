---
title: "MCP servers"
description: "Configure MCP tool servers: transports, every field, OAuth settings, per-audience access, and what happens with invalid config."
---

Netclaw connects to [Model Context Protocol](https://modelcontextprotocol.io/) servers to give the model tools (browsing, Notion, memory stores, whatever the server exposes) and prompts. Server definitions live in the `McpServers` section of `~/.netclaw/config/netclaw.json`. Credentials live in [`secrets.json`](/security/secrets/).

At startup the daemon connects to every enabled server in parallel, discovers its tools and prompts, and enforces [per-audience permissions](#per-audience-access-control) on what each session can call. A server that fails to connect doesn't stop the others.

`netclaw mcp add` and `netclaw mcp permissions` write this JSON for you, and editing the file directly works too. See [`netclaw mcp`](/cli/mcp-tools/) for the command reference and [Connect an OAuth MCP server](/guides/oauth-mcp-servers/) for sign-in.

## Minimal config

One stdio server with every default:

```json
{
  "McpServers": {
    "memorizer": {
      "Command": "uvx",
      "Arguments": ["memorizer-mcp"]
    }
  }
}
```

`Transport` defaults to `"stdio"` and `Enabled` to `true`. The server name (`memorizer`) is what appears as `mcp:memorizer` in [`netclaw status`](/cli/status/) and in permission settings. The CLI resolves names without regard to case, so `netclaw mcp add Memorizer` while `memorizer` exists updates `memorizer`. If you edit the file by hand, don't create two keys that differ only by case: the loader reads them as duplicates and every `netclaw` command prints `Couldn't read netclaw.json` until you remove one.

## Fields

Each entry under `McpServers` is keyed by server name. The block is closed: unknown fields fail the schema check in `netclaw doctor`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `Transport` | string | `"stdio"` | `"stdio"`, `"sse"` or `"http"` |
| `Command` | string | none | Executable for stdio. Required for stdio. |
| `Arguments` | string[] | none | Arguments passed to the stdio command |
| `Url` | string | none | Endpoint for sse and http. Required for both. |
| `EnvironmentVariables` | object | none | Environment overlay for the stdio process |
| `Headers` | object | none | Extra HTTP headers for sse and http |
| `Enabled` | bool | `true` | Disabled servers aren't started |
| `GrantCategory` | string | `mcp:<name>` | A label on the server's tools. It has no effect on access. |
| `OAuthClientId` | string | none | Pre-registered OAuth client ID, for servers without dynamic registration |
| `OAuthClientSecret` | string | none | Client secret for a confidential OAuth client. Allowed only in `secrets.json`. |
| `OAuthScope` | string | none | Space-separated OAuth scopes to request |

`EnvironmentVariables`, `Headers` and `OAuthClientSecret` hold credentials. Put them in `secrets.json`, where netclaw stores them encrypted. `netclaw mcp add --env`, `--header` and `--client-secret` do that split for you.

:::caution
`OAuthClientSecret` in `netclaw.json` is a config error. The schema forbids it and `netclaw doctor` fails the Config Schema check. Set it with `netclaw mcp add --client-secret` or `netclaw secrets set McpServers.<name>.OAuthClientSecret <value>`.
:::

A server that sends an `Authorization` header (from `Headers`) opts out of netclaw's OAuth handling. Netclaw won't try to authorize it or refresh anything.

`GrantCategory` is carried on each tool as a label, but authorization never reads it. Control access with `McpServersMode`, `AllowedMcpServers` and `McpServerToolGrants` below. The old advice to group servers under one shared category doesn't work.

## Transports

### stdio

Launches a local process. The daemon starts it on startup and stops it on shutdown.

```json
{
  "McpServers": {
    "memorizer": {
      "Transport": "stdio",
      "Command": "uvx",
      "Arguments": ["memorizer-mcp"]
    }
  }
}
```

[`uvx`](https://docs.astral.sh/uv/) runs Python-packaged MCP servers. `Command` must be on the daemon's `PATH`. stdio servers can't use OAuth.

### http

Streamable HTTP, the current MCP transport. Use it for remote servers.

```json
{
  "McpServers": {
    "notion": {
      "Transport": "http",
      "Url": "https://mcp.notion.com/mcp"
    }
  }
}
```

If the server needs OAuth, run `netclaw mcp auth notion` after adding it. Add `OAuthClientId` (and the secret in `secrets.json`) only when the server doesn't support dynamic client registration:

```json
{
  "McpServers": {
    "github": {
      "Transport": "http",
      "Url": "https://api.githubcopilot.com/mcp/",
      "OAuthClientId": "Iv1.example",
      "OAuthScope": "repo read:org"
    }
  }
}
```

### sse

The older Server-Sent Events transport, for servers that don't offer streamable HTTP.

```json
{
  "McpServers": {
    "legacy": {
      "Transport": "sse",
      "Url": "https://mcp.example.com/sse",
      "Headers": { "X-Team": "platform" }
    }
  }
}
```

Tokens belong in `secrets.json`. Use `netclaw mcp add --header "Authorization: Bearer ..."` and it goes there for you.

## Browser automation profiles

`netclaw init` can add one of two browser automation servers. Both are ordinary stdio entries you can edit.

| Server name | Package | Needs |
|-------------|---------|-------|
| `browser_playwright` | `@playwright/mcp@latest` | Node.js and a Playwright browser |
| `browser_chrome_devtools` | `chrome-devtools-mcp@latest` | Node.js and local Chrome |

```json
{
  "McpServers": {
    "browser_playwright": {
      "Transport": "stdio",
      "Command": "npx",
      "Arguments": [
        "-y", "@playwright/mcp@latest",
        "--isolated", "--headless",
        "--image-responses", "omit",
        "--snapshot-mode", "none",
        "--browser", "chromium"
      ]
    }
  }
}
```

The `--browser` value comes from what `netclaw init` finds installed.

## OAuth fields

`OAuthClientId`, `OAuthClientSecret` and `OAuthScope` apply to http and sse servers without an `Authorization` header. Without them, netclaw discovers the authorization server from the MCP URL and registers itself through [dynamic client registration](https://datatracker.ietf.org/doc/html/rfc7591).

| You have | Set |
|----------|-----|
| A server with dynamic registration | Nothing |
| A pre-registered public client | `OAuthClientId` |
| A pre-registered confidential client | `OAuthClientId` in `netclaw.json`, `OAuthClientSecret` in `secrets.json` |
| Scopes beyond the provider's defaults | `OAuthScope` |

A secret without a client ID is invalid. Tokens are stored in `secrets.json` under `McpOAuthTokens.<name>` and refreshed by the daemon. The full flow, including hosts with no browser, is in [Connect an OAuth MCP server](/guides/oauth-mcp-servers/).

### Redirect URI

Register this redirect URI (also called a callback URL) in the provider's OAuth app settings:

```
http://127.0.0.1:<Daemon.Port>/api/mcp/oauth/callback
```

With the default port, that's `http://127.0.0.1:5199/api/mcp/oauth/callback`.

:::caution
**A mismatched redirect URI is the number one setup mistake.** Providers compare it to the registered value character for character, and most show only a generic error page when it doesn't match. Use `127.0.0.1`, not `localhost`. Ignore any port or path from the provider's own setup guide, because the daemon owns the callback. If you change `Daemon.Port`, update the registered URI too.
:::

`netclaw mcp auth` prints the authorization URL, and its `redirect_uri` parameter is the exact value netclaw sends.

## MCP prompts as skills

Since 0.26.0, prompts that an MCP server publishes show up as skills named `mcp__<server>__<prompt>` (lowercased) with source `mcp` in `netclaw skill list`. The agent can load them like any other skill, and the prompt's arguments become the skill's arguments. They're only visible to audiences that can reach the server, and a prompt name that another server already owns is rejected. A prompt skill never overrides a skill file with the same name. `netclaw skill list` needs the daemon running to show them.

### GitHub MCP server

GitHub's official remote MCP server (`https://api.githubcopilot.com/mcp/`) uses OAuth, but it [doesn't support dynamic client registration](https://github.com/github/github-mcp-server/blob/main/docs/host-integration.md). You have two options.

**Option 1: register your own GitHub App or OAuth App.** GitHub recommends a GitHub App: you pick its exact permissions, and its tokens expire. Both app types need a client ID *and* a client secret.

1. On GitHub, go to **Settings → Developer settings**, then **GitHub Apps → New GitHub App** or **OAuth Apps → New OAuth App**.
2. Set the callback URL to the [redirect URI](#redirect-uri): `http://127.0.0.1:5199/api/mcp/oauth/callback` with the default port. The homepage URL can be anything.
3. For a GitHub App, clear **Webhook → Active** (otherwise GitHub requires a webhook URL), choose the repository and organization permissions the agent needs, and install the app on the accounts or repositories it should reach. You don't need a private key.
4. Register the app, then generate a client secret.
5. Save the client ID and secret with `netclaw mcp add`. They go on `add`, not on `auth`:

   ```bash
   netclaw mcp add github https://api.githubcopilot.com/mcp/ --transport http \
     --client-id <client-id> --client-secret <client-secret>
   ```

   If `github` already exists, this updates its connection settings and keeps its tool grants. The daemon restarts itself when the config changes, so give it a few seconds.
6. Authorize in the browser:

   ```bash
   netclaw mcp auth github
   ```

With an OAuth App, add `--scope` to request fewer GitHub scopes than the server default (for example, `--scope "repo read:org"`). A GitHub App ignores scopes; its permissions come from the app settings.

:::caution
Netclaw 0.28.2 and earlier can't find GitHub's OAuth metadata, and `netclaw mcp auth github` fails with `HTTP 404 NotFound`. On those versions, use option 2.
:::

**Option 2: a personal access token.** Skip OAuth and send the token as a header:

```bash
netclaw mcp add github https://api.githubcopilot.com/mcp/ --transport http \
  --header "Authorization: Bearer <token>"
```

The header goes to `secrets.json`. A fine-grained token lets you limit the server to specific repositories. Unlike OAuth, the token doesn't refresh, so replace it before it expires.

:::caution
The GitHub server exposes write tools such as `merge_pull_request`, `delete_file`, and `push_files`. When you add it as a new server, the Personal audience gets every tool with auto-approval. Run `netclaw mcp permissions` to trim the grants or require approval before an agent uses them. See [per-audience access control](#per-audience-access-control).
:::

## Per-audience access control

Netclaw gates MCP access per [audience](/security/security-model/#trust-audiences) (Personal, Team, Public) in `Tools.AudienceProfiles` of `netclaw.json`:

| Audience | Default `McpServersMode` | Default behavior |
|----------|--------------------------|------------------|
| Personal | `"All"` | Every server and tool allowed |
| Team | `"Allowlist"` | Servers must be listed in `AllowedMcpServers` |
| Public | `"Allowlist"` | Servers must be listed in `AllowedMcpServers` |

Each profile decides which servers are visible, which of their tools can run, and whether each tool runs on its own, asks first, or is blocked.

```json
{
  "Tools": {
    "AudienceProfiles": {
      "Personal": {
        "McpServersMode": "All",
        "ApprovalPolicy": {
          "DefaultMode": "Auto",
          "McpServerDefaults": { "memorizer": "Approval" },
          "ToolOverrides": { "memorizer/delete_memory": "Deny" }
        }
      },
      "Team": {
        "McpServersMode": "Allowlist",
        "AllowedMcpServers": ["memorizer"],
        "McpServerToolGrants": { "memorizer": ["search_memories"] },
        "ApprovalPolicy": { "DefaultMode": "Approval" }
      }
    }
  }
}
```

`McpServerToolGrants` only applies to `Allowlist` audiences. Under `"All"` it's ignored, so disable a single tool for Personal with a `Deny` entry in `ToolOverrides`, keyed `server/tool`. Leaving a server out of `McpServerToolGrants` exposes all of its tools to that audience, and an empty list exposes none. Keys in `ToolOverrides` and `McpServerDefaults` match without regard to case. Write an MCP tool as `server/tool` or `server__tool`. A key that contains a colon, or has no value, is ignored and the tool keeps the audience default. `netclaw doctor` reports the colon case as an error.

`netclaw mcp add` leaves Personal open (every tool, `Auto`) and closes Team and Public. They get an empty grant list for the server and `Approval` (Team) or `Deny` (Public) as its default approval mode. Use `netclaw mcp permissions` to manage grants, or `netclaw mcp add --grant-all` to skip the empty grant lists when you first add the server. `netclaw mcp tools <server> --grant <tool> --audience <audience>` grants tools and adds the server to that audience's `AllowedMcpServers` in one step. Adding the same server again keeps its grants, defaults and enabled state, and `netclaw mcp remove` deletes them along with the server's OAuth tokens and saved approvals. See [MCP tool permissions](/guides/mcp-tool-permissions/) for a walkthrough.

![MCP Permissions server list with one connected server, demo-utilities, and its tool count of 10](/screenshots/output/mcp-tools-server-list.png)

Each server gets a row with its connection state and discovered tool count, and selecting one opens its per-audience grants.

## Server status

`netclaw mcp list` and `netclaw doctor` report live status from the daemon:

| Status | Meaning | Action |
|--------|---------|--------|
| `connected (N tools)` | Connected, N tools discovered | None |
| `connected but not responding (N cached tools)` | Connected, but catalog refreshes keep failing | Check the server, then `netclaw doctor` |
| `awaiting auth` | OAuth sign-in needed | `netclaw mcp auth <name>` |
| `auth failed (...)` | The server rejected the credentials | Re-run `netclaw mcp auth <name>`, or fix the header or secret |
| `unreachable - ...` | Connection failed or timed out | `netclaw doctor` |
| `disabled` | `Enabled` is `false` | `netclaw mcp enable <name>` |
| `status unavailable - restart daemon to load this config` | The daemon hasn't loaded a server you just added. It reloads on its own within seconds. | Run `netclaw mcp list` again. Restart only if it persists. |

`netclaw status` lists the same servers as `mcp:<name>` connectors.

## Invalid config

`netclaw doctor` checks each entry. A bad entry is reported and the rest of the servers still load.

| Condition | Result |
|-----------|--------|
| `Transport` isn't `stdio`, `sse` or `http` | Config Schema and `mcp-servers` checks fail |
| stdio with no `Command` | `mcp-servers` check fails: `stdio transport requires 'Command'` |
| sse or http with no `Url` | `mcp-servers` check fails: `<transport> transport requires 'Url'`, for example `sse transport requires 'Url'` |
| `OAuthClientSecret` in `netclaw.json` | Config Schema check fails |
| An unknown field | Config Schema check fails |

We loaded a config with an unknown transport, a stdio entry with no command, an http entry with no URL and an unknown field, on 0.27.1 and again on a later build. The daemon started, `netclaw doctor` named each one, and `netclaw status` showed each as `disconnected`.

## Environment variable overrides

Override any field with `NETCLAW_` variables. Double underscores separate path segments, per the [.NET configuration convention](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider):

```bash
export NETCLAW_McpServers__notion__Enabled="true"
```

Environment variables take priority over `netclaw.json` and `secrets.json`. They apply to the daemon only. `netclaw mcp list` and `netclaw mcp get` read the files, so a server you enable by environment variable still shows as `disabled` there while `netclaw status` shows it loaded. Env changes need a manual daemon restart.

## Applying changes

The daemon restarts itself, after draining sessions, when `netclaw.json` changes. Secrets changes (`netclaw secrets set`, `--client-secret` rotation) don't trigger that. Restart the daemon yourself: `docker restart <container>`, `systemctl --user restart netclaw`, or `netclaw daemon stop` then `netclaw daemon start`.

```bash
netclaw mcp list    # config plus live status
netclaw status      # MCP connector health
```

## Related pages

- [`netclaw mcp`](/cli/mcp-tools/) - every MCP subcommand and flag
- [Connect an OAuth MCP server](/guides/oauth-mcp-servers/) - sign in, confidential clients, headless hosts
- [MCP tool permissions](/guides/mcp-tool-permissions/) - grant tools per audience
- [Secrets management](/security/secrets/) - how `secrets.json` is encrypted
- [Security model](/security/security-model/) - audiences and what each can do

## Resources

- [Model Context Protocol specification](https://modelcontextprotocol.io/specification) - the protocol netclaw implements
- [MCP server registry](https://github.com/modelcontextprotocol/servers) - community-maintained list of MCP servers
- [uv documentation](https://docs.astral.sh/uv/) - the package manager behind `uvx`
- [.NET environment variable configuration](https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-providers#environment-variable-configuration-provider) - the double-underscore nesting convention
