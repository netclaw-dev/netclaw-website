---
title: "netclaw config"
description: "Reentrant, menu-driven editor for everything that isn't part of first-run setup — channels, search, exposure, webhooks, skills, and more."
---

`netclaw config` is the post-install configuration surface. Where [`netclaw init`](/cli/init/) handles first-run setup (provider, identity, security posture, features), `netclaw config` is where you configure everything else — and it's safe to re-run any time.

```bash
netclaw config
```

It opens a menu-driven editor with a live **status-summary dashboard** on entry, so you can see the state of every area at a glance.

<!-- TODO(screenshots): add config-dashboard.png — capture via screenshots/tapes/config.tape after the stable release with netclaw-dev/netclaw#1368; tracked in epic #55 -->

## Dashboard areas

The dashboard lists each configuration domain with a live status summary:

| Area | Example status |
| --- | --- |
| Security & Access | `Team · 4/6 enabled` |
| Channels | `Slack ✓ · Discord ✗ · Mattermost ✗` |
| Search | `Brave ✓` |
| Skill Sources | `3 sources · 12 skills` |
| Telemetry & Alerting | `2 webhooks` |
| Inbound Webhooks | `1 route` |
| Browser Automation | `disabled` |
| Workspaces Directory | `~/netclaw-workspaces` |

Selecting an area opens its editor. **Changes autosave on completion** — there is no separate save step. Press Esc to back out of any area and return to the dashboard.

The Inference Providers and Models rows route out to [`netclaw provider`](/cli/provider/) and [`netclaw model`](/cli/model/), which own those surfaces.

## Channels

Channels (Slack, Discord, Mattermost) are configured here, not in `netclaw init`. Each adapter is independently enabled, has its credentials entered, and has its channel allow-list managed from the Channels area.

Channel entry is **resolve-before-add**: you type channel names or IDs (comma-separated), and Netclaw resolves each against the platform API to its **canonical channel ID before saving**. The stored allow-list holds IDs, not display names; display names are shown dynamically in the editor. Entries that can't be resolved are rejected — they are never silently saved.

:::caution
**Migrating from a hand-edited `netclaw.json`:** the runtime matches incoming messages by channel **ID**. If you previously placed display names in `AllowedChannelIds` (or set `DefaultChannelName`/`DefaultChannelId` by hand), re-enter those channels through `netclaw config → Channels` so they resolve to canonical IDs — otherwise messages are silently dropped.
:::

See the per-platform guides for token setup: [Slack](/channels/slack/), [Discord](/channels/discord/), [Mattermost](/channels/mattermost/).

<!-- TODO(screenshots): add config-channels-menu.png + config-channels-resolve.png — capture via screenshots/tapes/config.tape after the stable release; tracked in epic #55 -->

## Other areas

- **Security & Access** — deployment posture, enabled features, audience profiles, and exposure mode.
- **Search** — backend selection (Brave / SearXNG / DuckDuckGo) with progressive disclosure for the fields each backend needs; the SearXNG endpoint is validated by a reachability probe before saving.
- **Telemetry & Alerting** — a multi-webhook list editor for outbound operational alerts (add/remove webhook URLs).
- **Inbound Webhooks** — enable inbound webhooks and set the execution timeout; route authoring is handled by [`netclaw webhooks`](/cli/webhooks/).
- **Browser Automation** — toggle the Playwright MCP backend.
- **Skill Sources** — local folders and remote skill feeds.
- **Workspaces Directory** — the directory netclaw uses for project workspaces.

<!-- TODO(screenshots): add config-search.png, config-telemetry.png, config-inbound-webhooks.png, config-exposure.png, config-skills.png, config-browser.png, config-workspaces.png — capture via screenshots/tapes/config.tape after the stable release; tracked in epic #55 -->

## Related pages

- [`netclaw init`](/cli/init/) — first-run setup (provider, identity, posture, features)
- [`netclaw provider`](/cli/provider/) — inference providers
- [`netclaw model`](/cli/model/) — model selection
- [`netclaw webhooks`](/cli/webhooks/) — inbound webhook routes
- [`netclaw doctor`](/cli/doctor/) — configuration and connectivity diagnostics
