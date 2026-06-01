# Screenshot capture pipeline

Source of truth for every image under `output/` (served at `/screenshots/output/<file>`).

## Layout

| Path | What it is |
|------|-----------|
| `capture.sh` | Orchestrator: brings up the Docker stack, runs every VHS tape, tears down |
| `tapes/*.tape` | [VHS](https://github.com/charmbracelet/vhs) recordings — one per CLI command/flow |
| `scripts/` | Helpers (`ollama-init.sh` model pull, `seed-approvals.sh` fixture seeding) |
| `mcp-server/` | Demo MCP server used by the `mcp-tools` capture |
| `output/` | Generated PNGs/GIFs (committed; consumed by the docs) |

The daemon image and the demo Ollama model come from `../docker-compose.screenshots.yml`.

## Regenerate everything (VHS / TUI shots)

```bash
./screenshots/capture.sh
```

The daemon image is **pinned to the documented release**: `capture.sh` reads
`src/version.json` and pins `ghcr.io/netclaw-dev/netclaw:<documentedVersion>`. To
capture against a different build, override before running:

```bash
NETCLAW_VERSION=0.22.1 ./screenshots/capture.sh        # a specific release
NETCLAW_IMAGE=ghcr.io/netclaw-dev/netclaw:dev ./screenshots/capture.sh   # bleeding edge
OLLAMA_MODEL=qwen2:0.5b ./screenshots/capture.sh       # demo inference model
```

Keep `src/version.json` in step with the release you profiled — the
`docs_version_check` workflow opens an issue when the docs fall behind.

## Mattermost capture (web setup + live conversation)

The Mattermost integration shots aren't a VHS tape — they're browser screenshots
driven by Playwright against the netclaw repo's Aspire demo
(`samples/Netclaw.Demo.AppHost`), which auto-bootstraps a full Mattermost workspace
(admin, team, bot + token, channel, test user) and runs the daemon. Inference is
pointed at a real endpoint so the bot's replies look production-grade. See
`playwright/README.md` for the runner. *(Added in the Mattermost docs phase.)*
