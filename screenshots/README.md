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

The Mattermost shots aren't a VHS tape — they're browser screenshots driven by
Playwright. Everything lives in `mattermost/`:

| File | Role |
|------|------|
| `docker-compose.mattermost.yml` | the Mattermost (`mattermost-preview`) container |
| `bootstrap.mjs` | seeds admin / team / bot + token / channel / test user via the REST API → `.bootstrap.json` |
| `run.sh` | orchestrator: compose up → bootstrap → start the pinned netclaw image (inference pointed at an OpenAI-compatible endpoint) → post an `@netclaw` message → run `capture.mjs` → tear down |
| `capture.mjs` | Playwright: the System Console bot-accounts setting, the bot + its token, and the live `@netclaw` thread |

Regenerate them with:

```bash
./screenshots/mattermost/run.sh
```

Point inference at your own endpoint/model with `SPARK_ENDPOINT` and `SPARK_MODEL_ID`
(the defaults match the local netclaw instance). `.bootstrap.json` holds a short-lived
bot token and is gitignored.
