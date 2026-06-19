---
title: "netclaw config"
description: "Reentrant, menu-driven editor for everything that isn't part of first-run setup — channels, search, exposure, webhooks, skills, and more."
---

`netclaw config` is the post-install configuration surface. Where [`netclaw init`](/cli/init/) handles first-run setup (provider, identity, security posture, features), `netclaw config` is where you configure everything else — and it's safe to re-run any time.

```bash
netclaw config
```

If netclaw hasn't been initialized yet, `netclaw config` exits non-zero and tells you to run `netclaw init` first — no TUI opens.

It opens a **Settings Areas** menu with a live status summary for each area, so you can see the state of every domain at a glance.

<!-- TODO(screenshots): add config-dashboard.png — capture via screenshots/tapes/config.tape after the stable release with netclaw-dev/netclaw#1368; tracked in epic #55 -->

## Dashboard areas

The Settings Areas screen lists each configuration domain with a live status summary. Rows appear in this order:

| Area | Example status |
| --- | --- |
| Inference Providers | `2 configured` |
| Models | `claude-sonnet-4-5` |
| Channels | `Slack · 2 channels` |
| Inbound Webhooks | `enabled` |
| Skill Sources | `3 dirs · 2 feeds` |
| Search | `✓ Brave` |
| Browser Automation | `– disabled` |
| Telemetry & Alerting | `OTLP on · 2 webhooks` |
| Security & Access | `Team · 4/6 enabled` |
| Workspaces Directory | `~/netclaw-workspaces` |
| Run Full Doctor | *(terminal — exits and runs `netclaw doctor`)* |
| Quit | *(terminal — exits without changes)* |

Selecting an area opens its editor. **Changes autosave on completion** — there is no separate save step. Press Esc to back out of any area and return to the Settings Areas screen.

**Inference Providers** and **Models** route out to [`netclaw provider`](/cli/provider/) and [`netclaw model`](/cli/model/), which own those surfaces. Backing out of either returns you to the Settings Areas screen.

## Validation and save behavior

Structurally invalid input (wrong type, out-of-range value) **blocks save with no override**. Failed reachability or runtime probes — such as an unreachable SearXNG endpoint or a skill feed that doesn't respond — surface a warning dialog with a **Save anyway** option, so you can persist the config and fix connectivity later.

## Channels

Channels (Slack, Discord, Mattermost) are configured here, not in `netclaw init`. Each adapter is independently enabled, has its credentials entered, and has its channel allow-list managed from the Channels area.

Channel entry is **resolve-before-add**: you type channel names or IDs (comma-separated), and netclaw resolves each against the platform API to its **canonical channel ID before saving**. The stored allow-list holds IDs, not display names; display names are shown dynamically in the editor.

When saving an adapter, any names or IDs that can't be resolved at save time are kept as inert allow-list entries and flagged with a non-blocking `Could not resolve: #name — flagged below; fix or remove them.` warning. The adapter itself saves successfully.

:::caution
**Migrating from a hand-edited `netclaw.json`:** the runtime matches incoming messages by channel **ID**. If you previously placed display names in `AllowedChannelIds` by hand, re-enter those channels through `netclaw config → Channels` so they resolve to canonical IDs — otherwise those channels match nothing and their messages are denied. (`DefaultChannelName` is Slack-only and still resolved to an ID at runtime, so it's unaffected.)
:::

See the per-platform guides for token setup: [Slack](/channels/slack/), [Discord](/channels/discord/), [Mattermost](/channels/mattermost/).

<!-- TODO(screenshots): add config-channels-menu.png + config-channels-resolve.png — capture via screenshots/tapes/config.tape after the stable release; tracked in epic #55 -->

## Other areas

- **Security & Access** — deployment posture, enabled features, audience profiles, and exposure mode.
- **Search** — backend selection (Brave / SearXNG / DuckDuckGo) with progressive disclosure for the fields each backend needs; the SearXNG endpoint is validated by a reachability probe before saving (overridable).
- **Telemetry & Alerting** — OTLP toggle and a multi-webhook list editor for outbound operational alerts; each webhook entry carries a name, URL, optional masked Authorization header, and an auto-detected format shown read-only.
- **Inbound Webhooks** — enable inbound webhooks and set the execution timeout; route authoring is handled by [`netclaw webhooks`](/cli/webhooks/).
- **Browser Automation** — toggle the Playwright MCP backend.
- **Skill Sources** — local folders (added via an interactive directory picker with Ctrl+N to create inline) and remote skill feeds.
- **Workspaces Directory** — the directory netclaw uses for project workspaces, set via an interactive directory picker.

<!-- TODO(screenshots): add config-search.png, config-telemetry.png, config-inbound-webhooks.png, config-exposure.png, config-skills.png, config-browser.png, config-workspaces.png — capture via screenshots/tapes/config.tape after the stable release; tracked in epic #55 -->

## Related pages

- [`netclaw init`](/cli/init/) — first-run setup (provider, identity, posture, features)
- [`netclaw provider`](/cli/provider/) — inference providers
- [`netclaw model`](/cli/model/) — model selection
- [`netclaw webhooks`](/cli/webhooks/) — inbound webhook routes
- [`netclaw doctor`](/cli/doctor/) — configuration and connectivity diagnostics

## Resources

- [Brave Search API](https://brave.com/search/api/) — the managed backend offered in the Search area
- [SearXNG documentation](https://docs.searxng.org/) — self-hosted search backend and its endpoint requirements
- [Playwright MCP](https://github.com/microsoft/playwright-mcp) — the browser-automation backend toggled in Browser Automation
