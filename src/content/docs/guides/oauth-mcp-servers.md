---
title: "Connect an OAuth MCP server"
description: "Authorize a remote MCP server that uses OAuth: public and confidential clients, hosts with no browser, and what to do when authorization fails."
---

Remote MCP servers like Notion, GitHub and Google Workspace sit behind OAuth. Add the server with `netclaw mcp add`, then run `netclaw mcp auth <name>` to sign in. Netclaw stores the tokens encrypted in `secrets.json`, refreshes them in the background, and survives daemon restarts without asking you to sign in again.

Netclaw uses the OAuth authorization code flow with PKCE. The daemon sends your browser to the provider, and the provider redirects back to `http://127.0.0.1:<port>/api/mcp/oauth/callback` on the daemon's own port (default `5199`, set by `Daemon.Port`). Netclaw doesn't support the device flow, so a headless host uses the paste step described below. That's tracked in [netclaw#1889](https://github.com/netclaw-dev/netclaw/issues/1889).

## Which case are you in?

| Your situation | What to do | Section |
|---|---|---|
| The server supports dynamic client registration ([RFC 7591](https://datatracker.ietf.org/doc/html/rfc7591)) | `netclaw mcp add`, then `netclaw mcp auth`. No client ID needed. | [Public client](#public-client-with-dynamic-registration) |
| The provider makes you register an OAuth app and gives you a client ID and secret (GitHub OAuth Apps, Google "Web application" clients) | Add `--client-id` and `--client-secret` | [Confidential client](#confidential-client-with-a-client-id-and-secret) |
| The daemon runs on a server, container or SSH session with no browser | Open the URL on another device, then paste the redirect URL back | [Host with no browser](#host-with-no-browser) |
| The server lets you connect and list tools without signing in | `netclaw mcp auth` fails (open issue). Use a static token header. | [Servers that allow anonymous access](#servers-that-allow-anonymous-access) |

## Before you begin

- A running daemon. `netclaw mcp auth` talks to it, and the daemon does the token exchange.
- The server's MCP URL (the one that speaks MCP, such as `https://mcp.notion.com/mcp`, not its homepage).
- For a confidential client, an OAuth app registered at the provider with `http://127.0.0.1:5199/api/mcp/oauth/callback` as its redirect URI. If you changed `Daemon.Port`, use that port. Netclaw sends exactly that URI, with `127.0.0.1` and not `localhost`, so register it character for character.

## Public client with dynamic registration

Servers that implement the MCP authorization spec's dynamic client registration ([RFC 7591](https://datatracker.ietf.org/doc/html/rfc7591)) let clients register themselves. Netclaw discovers the authorization server from the MCP URL and registers on its own the first time you authorize.

```bash
netclaw mcp add --transport http notion https://mcp.notion.com/mcp
netclaw mcp auth notion
```

`mcp add` finishes with a hint, since the CLI can't tell in advance whether a server needs OAuth:

```
Next steps:
  - If this server requires OAuth, authorize first: netclaw mcp auth notion
  - Then grant tools: netclaw mcp permissions
```

Until you authorize, `netclaw mcp list` shows `awaiting auth`. `mcp auth` prints an authorization URL and tries to open your browser:

```
Starting OAuth authorization for 'notion'...

Could not open browser automatically (headless environment detected).

Authorization URL: https://...

Redirect URI: http://127.0.0.1:5199/api/mcp/oauth/callback
  A pre-registered OAuth client must list this exact URI at the provider.

Complete the authorization in your browser, then either:
  1. Wait for the callback to be received automatically
  2. Paste the redirect URL below if the callback can't reach this machine

Waiting for authorization....
Authorization complete for 'notion'.
```

When the provider redirects to the daemon, the command finishes on its own. You have five minutes. After that the attempt expires and you run `netclaw mcp auth` again.

:::note
`netclaw mcp add --auth` is in the help text, but it never starts the flow. It adds the server, prints `--auth: daemon API not available` and exits `0`, even with the daemon running. Run `netclaw mcp auth <name>` as a separate step.
:::

Pass `--scope "scope1 scope2"` to `mcp add` if the provider needs scopes beyond its defaults. Netclaw sends them in the authorization request.

## Confidential client with a client ID and secret

Some providers don't offer dynamic registration. You register an app in their developer settings and they give you a client ID and a client secret. Since 0.27.0, `netclaw mcp add` takes both:

```bash
netclaw mcp add --transport http \
  --client-id YOUR_CLIENT_ID --client-secret YOUR_CLIENT_SECRET \
  confidential https://mcp.example.com/mcp
netclaw mcp auth confidential
```

`--client-secret` requires `--client-id` and a non-empty value. A client ID without a secret stays valid for public clients that register out of band.

:::caution
The secret is a command-line argument. Shell history and process listings on the host can expose it. Run the command on a host you trust, or pre-register the app with a secret you can rotate.
:::

### Where the secret goes

`mcp add` writes the client ID to `netclaw.json` and the secret, encrypted, to `secrets.json`:

```json
{
  "McpServers": {
    "confidential": {
      "Transport": "http",
      "Url": "https://mcp.example.com/mcp",
      "OAuthClientId": "YOUR_CLIENT_ID"
    }
  }
}
```

```json
{
  "McpServers": {
    "confidential": {
      "OAuthClientSecret": "ENC:CfDJ8ARAyiJK..."
    }
  }
}
```

`netclaw mcp get confidential` shows `Client secret: configured` and never prints the value.

`netclaw.json` must not contain `OAuthClientSecret`. If it's there, `netclaw doctor` fails the config check:

```
[FAIL] Config Schema: Config does not match schema v1. Errors:
  /McpServers/confidential/OAuthClientSecret: : All values fail against the false schema
```

Delete the line from `netclaw.json` and store the secret with `netclaw secrets set` instead.

### Rotate the secret

```bash
netclaw secrets set McpServers.confidential.OAuthClientSecret NEW_SECRET
```

Secrets changes don't trigger the daemon's self-restart. Restart it yourself (`docker restart <container>`, `systemctl --user restart netclaw`, or `netclaw daemon stop` then `netclaw daemon start`). Token refresh uses the configured client ID and secret after every restart.

You can also rotate by running `netclaw mcp add` again with `--client-id` and the new `--client-secret`. That keeps the server's grants, approval defaults and stored sign-in, and the daemon restarts itself. Leave `--client-secret` out and the stored secret is dropped.

## Host with no browser

The daemon on a server, in a container or over SSH can't open a browser, and the redirect goes to `127.0.0.1` on a machine that isn't the one in front of you. Use the paste step:

1. Run `netclaw mcp auth <name>` in a real terminal. Over Docker that means `docker exec -it <container> netclaw mcp auth <name>`. Without a TTY the paste prompt is disabled and only the automatic callback works.
2. Copy the printed `Authorization URL`. On terminals that support OSC 52, netclaw also copies it to your clipboard.
3. Open it in a browser on any other device and approve.
4. The provider redirects to `http://127.0.0.1:5199/api/mcp/oauth/callback?code=...&state=...`. That page won't load because nothing is listening on your laptop's port 5199. That's expected.
5. Copy the full URL from the browser's address bar and paste it into the waiting terminal.

```
Waiting for authorization.....http://127.0.0.1:5199/api/mcp/oauth/callback?code=...&state=...
Authorization complete for 'demo'.
```

The paste has to arrive within the five-minute window, and the state in the URL has to belong to the current attempt. If you start a second `mcp auth`, use the URL from the newest one.

You can also forward the port instead of pasting: `ssh -L 5199:127.0.0.1:5199 your-host` lets the browser's redirect reach the daemon directly. (Not executed for this guide.)

## Servers that allow anonymous access

Some servers let a client initialize and list tools without a token and only return `401` when a protected tool runs. Netclaw connects to these and shows `connected`, but `netclaw mcp auth` fails:

```
Starting OAuth authorization for 'anon'...
Error: MCP OAuth connection initialization failed. Check daemon logs for details.
```

The daemon expects the server to issue an OAuth challenge during connection, and these servers never do. This is open as [netclaw#2123](https://github.com/netclaw-dev/netclaw/issues/2123). We reproduced it on 0.27.1 and again on a later build, against a local test server that allows anonymous initialization. We haven't tried it against any vendor's hosted server.

What works today is a static bearer token you obtain yourself, sent as a header:

```bash
netclaw mcp add --transport http \
  --header "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  anon https://mcp.example.com/mcp
```

Netclaw stores the header in `secrets.json` and sends it on every request. It doesn't refresh the token, so when it expires you replace it:

```bash
netclaw secrets set McpServers.anon.Headers.Authorization "Bearer NEW_TOKEN"
```

Then restart the daemon. A server with an `Authorization` header doesn't use netclaw's OAuth handling at all, so `mcp auth` doesn't apply to it.

## Check that it worked

```bash
netclaw mcp list
```

```
Name                 Transport  Enabled  Status
conf                 http       yes      connected (2 tools)
```

`netclaw doctor` includes the same result as an `mcp-servers` line (`[PASS] mcp-servers: conf: connected (2 tools)`). The next step is granting tools to Team and Public. Personal gets them automatically. See [MCP tool permissions](/guides/mcp-tool-permissions/).

## Tokens and sign-in lifecycle

| Question | Answer |
|---|---|
| Where are tokens stored? | `McpOAuthTokens.<name>` in `secrets.json`, every value encrypted with the `ENC:` prefix |
| Who refreshes them? | The daemon, with the refresh token, one refresh at a time per server. Refresh tokens that rotate are kept. |
| Do I sign in again after a restart? | No. Netclaw reuses the stored client identity and refresh token. |
| How do I sign in again (new account, revoked grant)? | Run `netclaw mcp auth <name>` again. The new tokens replace the old ones. |
| How do I remove a server? | `netclaw mcp remove <name>`. It also deletes the stored tokens. |

`netclaw mcp remove` deletes the server's `McpOAuthTokens.<name>` record along with its config, grants, approval defaults and saved approvals. If you add the server again, the status reads `awaiting auth` until you run `netclaw mcp auth <name>`. Re-adding without removing keeps the tokens.

Netclaw doesn't revoke the token at the provider. Revoke the grant in the provider's settings if you need it dead.

## Worked examples

### Notion (public client)

Notion's hosted MCP server is at `https://mcp.notion.com/mcp` and uses OAuth with an interactive sign-in, per [Notion's MCP docs](https://developers.notion.com/docs/get-started-with-mcp). That page doesn't say whether the server supports dynamic registration, so the flow assumes it does. If registration fails, ask Notion for a client ID. The netclaw side is the [public client](#public-client-with-dynamic-registration) flow above with that URL. Not executed against Notion for this guide. The same commands were executed against a local server that supports dynamic registration, and it connected with 2 tools.

### Google Docs (confidential client)

[Google's Docs MCP setup](https://developers.google.com/workspace/docs/api/guides/configure-mcp-server) needs a "Web application" OAuth client, the endpoint `https://docsmcp.googleapis.com/mcp/v1`, and the scopes `drive.readonly`, `drive.file`, `documents.readonly` and `documents`. Google's page lists redirect URIs for other clients but not for netclaw. The netclaw callback is `http://127.0.0.1:5199/api/mcp/oauth/callback`. Add it to the client's authorized redirect URIs if Google accepts a loopback address for your client type, which we didn't test. The netclaw command would use `--client-id`, `--client-secret` and a space-separated `--scope`. We don't know whether Google's endpoint allows anonymous initialization. If it does, `netclaw mcp auth` fails for the reason in [the anonymous section](#servers-that-allow-anonymous-access). Not executed (needs a Google Workspace Developer Preview account).

GitHub's remote MCP server (`https://api.githubcopilot.com/mcp/`) is the case that led to confidential-client support ([netclaw#2141](https://github.com/netclaw-dev/netclaw/issues/2141)). GitHub's own page for it doesn't describe its OAuth setup, so this guide doesn't give GitHub steps.

## Troubleshooting

### `auth failed (Authentication rejected by server...)`

**Symptom:** `netclaw mcp list` shows `auth failed (Authentication rejected by server (401 Unauthorized). Check configured credentials or headers.)`.
**Cause:** The provider rejected a token refresh. Typical causes are a revoked grant, an expired refresh token, or a changed client secret.
**Fix:** If you rotated the secret, update it with `netclaw secrets set McpServers.<name>.OAuthClientSecret ...` and restart the daemon, or run `netclaw mcp add` again with the new `--client-secret`. Then run `netclaw mcp auth <name>`.

### `MCP OAuth connection initialization failed: HTTP 401 Unauthorized`

**Symptom:** The browser shows "Authorization failed" after you approve, and the terminal prints this error.
**Cause:** The token exchange was rejected. With a confidential client that's almost always a wrong or missing client secret. We reproduced it with a deliberately wrong secret.
**Fix:** Check the secret against the provider, set it with `netclaw secrets set McpServers.<name>.OAuthClientSecret ...` and restart the daemon (or run `netclaw mcp add` again with the right `--client-secret`), then run `netclaw mcp auth <name>` again.

### The provider says the redirect URI doesn't match

**Symptom:** The authorization page errors with a redirect or `redirect_uri` mismatch.
**Cause:** The OAuth app doesn't list `http://127.0.0.1:<Daemon.Port>/api/mcp/oauth/callback` exactly.
**Fix:** Register that exact URI (`127.0.0.1`, the daemon's port, the full path). `netclaw mcp auth` prints the URI it sends on the `Redirect URI:` line, so copy it from there. `netclaw mcp --help` documents it too, along with `--scope`, `--header` and `--env`.

### The redirect page won't load

**Symptom:** After you approve, the browser shows "can't reach this site" at `127.0.0.1:5199`.
**Cause:** The browser isn't on the machine where the daemon runs. That's normal for a [host with no browser](#host-with-no-browser).
**Fix:** Copy the URL from the address bar and paste it into the waiting terminal.

### Pasting the URL does nothing

**Symptom:** You paste the redirect URL and nothing happens.
**Cause:** stdin isn't a terminal (a `docker exec` without `-it`, a pipe, a CI job), or the five-minute window ended, or the URL belongs to an earlier attempt.
**Fix:** Run `netclaw mcp auth <name>` in a real terminal (`docker exec -it`) and paste the URL from the newest attempt.

### `Error: MCP OAuth connection initialization failed. Check daemon logs for details.`

**Symptom:** `netclaw mcp auth` fails right away on a server that already shows `connected`.
**Cause:** The server allows anonymous initialization. See [netclaw#2123](https://github.com/netclaw-dev/netclaw/issues/2123).
**Fix:** Use a static `Authorization` header, as described [above](#servers-that-allow-anonymous-access).

### A token response can't be parsed (GitHub-style endpoints)

**Symptom:** Authorization fails at the token step against a GitHub-compatible OAuth endpoint.
**Cause:** These endpoints can answer with a form-encoded body when the client doesn't ask for JSON. Netclaw sends `Accept: application/json` on token requests since 0.27.0-beta.4 ([netclaw#2141](https://github.com/netclaw-dev/netclaw/issues/2141)).
**Fix:** Upgrade to 0.27.0 or later (see [`netclaw update`](/cli/update/)).

### `--client-secret requires --client-id`

**Symptom:** `Error: --client-secret requires --client-id.`
**Cause:** A secret is meaningless without the ID of the client it belongs to.
**Fix:** Pass both flags.

## Related pages

- [`netclaw mcp`](/cli/mcp-tools/) - every `mcp` subcommand and flag
- [MCP servers](/configuration/mcp-servers/) - the config schema for the fields used here
- [MCP tool permissions](/guides/mcp-tool-permissions/) - grant tools to Team and Public once the server is connected
- [Secrets management](/security/secrets/) - how `secrets.json` is encrypted
- [`netclaw doctor`](/cli/doctor/) - check MCP server health

## Resources

- [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization) - the OAuth flow MCP clients implement
- [OAuth 2.0 Dynamic Client Registration (RFC 7591)](https://datatracker.ietf.org/doc/html/rfc7591) - how public clients register themselves
- [Notion MCP documentation](https://developers.notion.com/docs/get-started-with-mcp) - the hosted server used in the public client example
- [Google Docs MCP server setup](https://developers.google.com/workspace/docs/api/guides/configure-mcp-server) - OAuth client, redirect URI and scopes for the Google example
