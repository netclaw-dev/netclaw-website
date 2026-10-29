---
title: Search Providers
description: Pick and configure the web search backend (SearXNG, Brave, or DuckDuckGo) behind netclaw's web_search tool, or turn search off.
---

The `web_search` tool routes through one configured search backend. netclaw supports three: a self-hosted SearXNG instance, the managed Brave Search API, and DuckDuckGo as a scraper. With no config at all you get DuckDuckGo. `web_fetch` doesn't use the backend: it fetches a URL directly under its own policy (see [Fetching pages](#fetching-pages)).

## Quick start

Run [`netclaw config`](/cli/config/) and select **Search** to pick a backend and enter credentials:

```bash
netclaw config
```

![The netclaw config Search screen listing DuckDuckGo, Brave and SearXNG, with DuckDuckGo active and a note that it may hit bot detection](/screenshots/output/config-search.png)

The wizard walks you through backend selection and credential entry. For SearXNG, a reachability probe checks the endpoint before saving. If the instance is unreachable, the editor warns you and offers a "Save anyway" override. For Brave, it prompts for your API key and stores it in `secrets.json` (encrypted at rest).

Once you save, the daemon restarts itself to apply the change.

:::note
A misconfigured SearXNG instance can look like a healthy one to the LLM, and the agent keeps retrying instead of reporting a failure. The most common cause is JSON output missing from `settings.yml`. See [Diagnosing Search Errors](#diagnosing-search-errors).
:::

## Provider summary

| Backend | Shape | Required config | Notes |
|---------|-------|-----------------|-------|
| `searxng` | Self-hosted | `Search.SearXngEndpoint` | Operator runs the instance. JSON output must be enabled. |
| `brave`   | Managed | `Search.BraveApiKey` (in `secrets.json`) | API key from [api.search.brave.com](https://api.search.brave.com/). |
| `duckduckgo` | Scraped | None | The default. Least reliable, and may hit bot detection. |

## SearXNG

[SearXNG](https://docs.searxng.org/) is a privacy-focused metasearch engine you self-host. It aggregates results from upstream search engines and returns them through a uniform API. netclaw queries the `/search` endpoint and parses the JSON response.

### Manual configuration

For scripted installs, Docker deployments, or any environment where `netclaw config` isn't available, set `Search.Backend` and `Search.SearXngEndpoint` directly in `~/.netclaw/config/netclaw.json`:

```json
{
  "Search": {
    "Backend": "searxng",
    "SearXngEndpoint": "https://searxng.internal.example/"
  }
}
```

No credentials go in `secrets.json` for SearXNG today. Authenticated instances are tracked as a future feature (see [Limitations](#limitations)).

### Required `settings.yml`

netclaw queries `?format=json` and parses the response as JSON, so your SearXNG instance must have JSON in its enabled output formats:

```yaml
# /etc/searxng/settings.yml
search:
  formats:
    - html
    - json
```

If JSON is not enabled, SearXNG returns either `HTTP 403 Forbidden` or a HTML body on a 200 response, and netclaw surfaces a terminal error pointing back at this section. There's no retry, because the instance configuration is wrong and retrying won't change the outcome.

### Reverse proxy and limiter behavior

Most production SearXNG deployments sit behind a reverse proxy (nginx, Caddy, Cloudflare). Two requirements matter for netclaw's traffic.

First, allow a non-empty `User-Agent`. netclaw sends `Netclaw/{version} (+https://netclaw.dev; sha={shortSha})` on every request. Many reverse proxies bot-wall empty-UA traffic before it ever reaches SearXNG, while non-empty UAs pass.

Second, use standard HTTP rate-limit semantics. When the upstream throttles, netclaw expects `HTTP 429 Too Many Requests`, optionally with a `Retry-After` header. Both delta-seconds and HTTP-date forms are honored. netclaw makes up to 3 attempts on 429, waiting 5 seconds and then 10 seconds when no `Retry-After` is present. Non-standard limiter responses (a redirect to a captcha page, a silent body swap to HTML) are treated as terminal errors.

SearXNG's own bot-detection limiter is behavioral and IP-list based, backed by Valkey. If your instance runs the limiter and you want to whitelist netclaw, the documented mechanism is the [`pass_ip` allowlist](https://docs.searxng.org/admin/searx.limiter.html) in `limiter.toml`.

### Connectivity

netclaw applies a 15-second per-request timeout. Across the 3 attempts the worst case is roughly 45 seconds plus any waits before you see an error. If your SearXNG instance routinely takes longer than that to respond, the upstream search engines are likely the bottleneck. Look at the `engines:` configuration before tuning the client.

### Limitations

netclaw doesn't support authenticated SearXNG instances: no Bearer tokens, HTTP Basic, custom headers, or mTLS. If your instance is gated behind authentication, either expose it on a network the daemon can reach unauthenticated, or follow [issue #912](https://github.com/netclaw-dev/netclaw/issues/912) for first-class auth support.

netclaw also only parses JSON. HTML and RSS responses are not supported.

## Brave Search

The [Brave Search API](https://brave.com/search/api/) is a managed search backend. It requires an API key. `netclaw config`, then Search, prompts for the key and stores it encrypted, which is the easiest path for interactive installs.

### Manual configuration

For scripted or headless installs, set `Search.Backend` in `~/.netclaw/config/netclaw.json` and store the key with [`netclaw secrets`](/cli/secrets/):

```json
{
  "Search": {
    "Backend": "brave"
  }
}
```

```bash
netclaw secrets set Search.BraveApiKey your-key-here
```

Get a key from [api.search.brave.com](https://api.search.brave.com/). The free tier is sufficient for personal use, and paid tiers raise the rate limit.

### Behavior

Brave returns gzip-compressed JSON, which netclaw decompresses. On `HTTP 401`, netclaw reports an authentication error pointing at `Search.BraveApiKey`. On `HTTP 429`, it makes up to 3 attempts, honoring the API's `Retry-After`, then returns a rate-limit error. From there you wait or upgrade the plan.

## DuckDuckGo

DuckDuckGo is the default backend and needs no configuration. It scrapes the lite HTML interface, which is fragile by design, and DuckDuckGo's bot detection regularly trips on automated traffic. Select it in `netclaw config` under Search, or set it in `~/.netclaw/config/netclaw.json`:

```json
{
  "Search": { "Backend": "duckduckgo" }
}
```

Use it when you have neither a SearXNG instance nor a Brave API key, and expect periodic failures.

## Diagnosing search errors

When the LLM reports a search failure, the error message includes the actionable cause:

| Error fragment | Cause | Fix |
|---|---|---|
| `settings.yml` / `search.formats` | SearXNG JSON output not enabled | Add `json` to `search.formats` in `settings.yml`, restart SearXNG |
| `rate limit exceeded` (SearXNG) | Limiter or reverse proxy throttling | Reduce concurrency, whitelist netclaw's IP, or check `limiter.toml` |
| `endpoint unreachable` | Network / DNS / wrong URL | Verify `Search.SearXngEndpoint` resolves and is reachable from the daemon host |
| `request timed out` | Upstream search engines slow or unreachable | Check SearXNG's `engines:` configuration |
| `Brave Search API authentication failed` | Missing or invalid Brave API key | Update `Search.BraveApiKey` in `secrets.json` |
| `Brave Search API rate limit exceeded` | Brave API throttling | Wait or upgrade your Brave plan |

## Turn search off

Set `Search.Enabled` to `false` and netclaw doesn't register the search tools for any audience:

```json
{
  "Search": { "Enabled": false }
}
```

## Fetching pages

`web_fetch` retrieves a URL you or the agent name, and it follows its own policy under `Tools.WebFetch`:

| Key | Default | Meaning |
|-----|---------|---------|
| `Tools.WebFetch.RequireHttps` | `true` | Reject plain `http://` URLs unless the host is on the allow list |
| `Tools.WebFetch.HttpAllowList` | `localhost`, `127.0.0.1`, `::1`, `[::1]` | Hosts allowed over plain HTTP. A list you set replaces this one |

## Related pages

- [Managed Providers](/configuration/managed-providers/) - LLM provider config (where API keys for managed services live)
- [Self-Hosted Providers](/configuration/self-hosted-providers/) - running inference on your own hardware
- [Secrets Management](/security/secrets/) - how `secrets.json` encrypts credentials at rest

## Resources

- [SearXNG documentation](https://docs.searxng.org/)
- [SearXNG limiter configuration](https://docs.searxng.org/admin/searx.limiter.html)
- [Brave Search API](https://brave.com/search/api/) - overview and pricing
- [Brave Search API key dashboard](https://api.search.brave.com/) - get a key
