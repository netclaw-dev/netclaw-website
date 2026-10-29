# Screenshot and verification stack

Everything that produces an image under `output/` (served at `/screenshots/output/<file>`) or proves a command works runs in containers against the **released** Netclaw image. Docker is the only prerequisite.

**Rule: never use a host `netclaw` binary.** Whatever is on your `PATH` may be a prototype or a dev build. The CLI in every recording and every verification command comes from `ghcr.io/netclaw-dev/netclaw:<version>`.

## Layout

| Path | What it is |
|------|-----------|
| `stack.sh` | Bring up, reset, exec into and tear down a disposable daemon (verification, no recording) |
| `capture.sh` | Record VHS tapes inside the capture container against that daemon |
| `shoot-page.sh` | Screenshot a page of the locally built docs site in the Playwright container |
| `mattermost/run.sh` | Mattermost + daemon + Playwright, all in containers; regenerates `mattermost-*.png` |
| `tapes/*.tape` | [VHS](https://github.com/charmbracelet/vhs) recordings, one per CLI command or flow |
| `capture/` | Capture image: VHS (ttyd, ffmpeg, Chromium) plus the released CLI |
| `playwright/` | Playwright image matching the version locked in `package-lock.json` |
| `compose/` | Compose overlays (`configured.yml`, `ollama.yml`, `forwarder.yml`, `projects.yml`, `skillserver.yml`, `docker-host.yml`); the base is `../docker-compose.screenshots.yml` |
| `scripts/`, `mcp-server/` | Ollama model pull, the seed scripts tapes run out of sight (`seed-*.sh`), a Mattermost API fixture, the third-party redaction script, the demo MCP server |
| `lib.sh`, `.env.example` | Shared settings; copy `.env.example` to `.env` (gitignored) for real inference |

## Pick the release

The image tag comes from one place: `documentedVersion` in `src/version.json`. Override per run:

```bash
NETCLAW_VERSION=0.27.1 ./screenshots/stack.sh up                    # a specific release
NETCLAW_IMAGE=ghcr.io/netclaw-dev/netclaw:dev ./screenshots/stack.sh up   # any image reference
```

`src/version.json` may lag the release you're documenting, so pass `NETCLAW_VERSION=0.27.1` until it's bumped. Every command prints the image it used.

## Verify a command against a clean daemon

```bash
export COMPOSE_PROJECT_NAME=dr04                  # your own name, see "Run several at once"
./screenshots/stack.sh up                         # clean ~/.netclaw, daemon healthy, provider + model + MCP configured
./screenshots/stack.sh exec netclaw doctor        # runs as the netclaw user, like the daemon
./screenshots/stack.sh exec netclaw status
./screenshots/stack.sh daemon-log 100             # the daemon's log file (container stdout is empty)
./screenshots/stack.sh down                       # removes containers, network and volumes
```

Daemon states:

| State | Command | What you get |
|-------|---------|--------------|
| configured (default) | `stack.sh up` | Provider `inference`, model roles and the demo MCP server `demo-utilities`, added with `netclaw provider add`, `netclaw model set` and `netclaw mcp add`, plus the Security section `netclaw init` writes. This is what a user's `netclaw.json` looks like after init. |
| first run | `stack.sh up --fresh` | Healthy daemon, empty `~/.netclaw`, no model. `netclaw status` says "daemon not configured". Use it for `netclaw init`. |
| bare | `stack.sh up --bare` | Like first run, plus the demo MCP server container. Tapes that seed their own config (`scripts/seed-*.sh`) use it. |

`stack.sh reset [--fresh]` wipes `~/.netclaw` and restarts the daemon without rebuilding the rest of the stack. Run `./screenshots/stack.sh` with no arguments for the full command list.

The configured state writes `netclaw.json` instead of setting `NETCLAW_*` env vars because the CLI refuses to run most commands without that file, and the `provider`, `model` and `mcp` TUIs edit it. The 0.25+ env shape still works if you need it for a throwaway daemon:

```bash
docker run -d --name x -e NETCLAW_Providers__inference__Type=ollama \
  -e NETCLAW_Providers__inference__Endpoint=http://ollama:11434 \
  -e NETCLAW_Models__Definitions__main__Provider=inference \
  -e NETCLAW_Models__Definitions__main__ModelId=qwen2:0.5b \
  -e NETCLAW_Models__Roles__Main=main ghcr.io/netclaw-dev/netclaw:0.27.1
```

The Mattermost flow below uses exactly this env shape.

## Inference

| Mode | When | How |
|------|------|-----|
| hermetic (default) | Shots that don't need a real answer | Ollama with `qwen2:0.5b` in the stack. The first `up` of a project pulls the model (about 350 MB), so allow a minute or two. |
| relay | You need real answers in a screenshot | Set `INFERENCE_UPSTREAM` and `INFERENCE_UPSTREAM_MODEL` in `screenshots/.env` (see below). The only mode that keeps the real endpoint and model name out of the config and the frame. |
| external | You need a real reply and nothing is captured that prints the endpoint | Set `INFERENCE_BASE_URL` (an OpenAI-compatible endpoint) and `INFERENCE_MODEL_ID` in the environment or in `screenshots/.env` |

```bash
INFERENCE_BASE_URL=http://llm.example.internal:8080 INFERENCE_MODEL_ID=my-model \
  ./screenshots/stack.sh up
```

External mode writes the endpoint into the daemon's `netclaw.json`, so commands like `netclaw provider list` print it. Capture those screenshots in hermetic mode.

### Real inference without leaking the endpoint

Set `INFERENCE_UPSTREAM` (the real `https://` base URL) and `INFERENCE_UPSTREAM_MODEL` (the model id it serves) in the gitignored `screenshots/.env`. `lib.sh` then switches to relay mode and adds `compose/forwarder.yml`: an nginx container in the stack's network namespace relays port 8081 to the upstream and rewrites the upstream's model id to `demo-model` in every response, and `llm.example.internal` resolves to loopback for everything in the namespace. netclaw only ever sees `http://llm.example.internal:8081` and the model `demo-model`, so provider lists, `netclaw init` and chat status bars are safe to capture, and no real model file name reaches a status bar. Check the first frame of every chat tape anyway.

This is the only relay, and both tape families use it. The seed scripts (`seed-assistant.sh`, `seed-providers.sh`) point their `lab-llama` provider at it, and the configured daemon (`stack.sh up`) registers it as provider `inference`. Ollama stays up alongside it, so `netclaw init` and the provider and model tapes still have a reachable local provider. Without `INFERENCE_UPSTREAM`, tapes that need a real answer (`stats`, `single-shot-cli-execution`, the chat and approval tapes) can't produce one: the 0.5B Ollama model can't call tools.

## Standard tape settings

Every terminal image is shown in a docs column about 650 px wide, so a capture wider than about 1000 px shrinks its text below what a reader can read without the lightbox. Use this block, and change only `Height` (crop by terminal height, not by editing the PNG):

```
Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 540
Set Padding 20
Set TypingSpeed 40ms
```

At `FontSize 16` a character cell is about 10 px wide, so 1000 px holds about 93 columns, and scaled into the column the text lands at about 11 px. Widen a tape only as far as a table needs it (`model.tape` uses 1200 for the long OpenAI-compatible provider label, `doctor.tape` 1700 for its longest check line) and make the page caption say the image can be enlarged.

The status-like tapes (`status`, `doctor`, `stats`, `sessions`, `model`, `provider`, `skill-list`, `skill-sync`, `webhooks`, `reminder-list`, `config`, `single-shot-cli-execution`) all start from `scripts/seed-demo-install.sh`, so the images agree on providers, roles, skills, webhook routes, reminders and the MCP server. Add new status-like captures to that family instead of seeding a separate install.

## Record tapes

```bash
./screenshots/capture.sh status                 # one tape
./screenshots/capture.sh status doctor          # a few
./screenshots/capture.sh                        # all tapes
OUT_DIR=/tmp/shots ./screenshots/capture.sh status   # write elsewhere (default: screenshots/output/)
```

`capture.sh` starts a stack, resets `~/.netclaw` before every tape, runs each tape inside the capture container, copies the results to the output directory owned by you, and always tears the stack down. It exits non-zero if VHS fails or a tape doesn't produce every `Output` and `Screenshot` file it declares.

How the recording reaches the daemon: the capture container shares the daemon container's network namespace and `~/.netclaw` volume, so `netclaw status` typed in a tape talks to `127.0.0.1:5199` exactly like a real user's CLI. Nothing is published to the host, and no `docker exec` shows up in a recording.

Tape conventions:

- Paths are relative to `/work`, so `Output screenshots/output/status.gif` and `Screenshot screenshots/output/status.png` land in the output directory.
- VHS starts bash with a clean `> ` prompt. No hidden preamble is needed unless a tape has to stage state first (see `chat-approval.tape`).
- Put `# stack: fresh` in a tape to run it against the first-run daemon (see `init-wizard.tape`), or `# stack: bare` for the same empty home with the demo MCP server up.
- Setup that isn't the subject of the image runs between `Hide` and `Show`: `bash /work/screenshots/scripts/seed-*.sh` for config, or `Source "/tapes/include/init-personal.tape"` to run the real `netclaw init` wizard (Personal, Ollama). Wait for a seed to finish with `Wait+Screen@4m /seeded: .../` instead of a fixed sleep.
- `# image: 0.27.0` runs one tape against another release (only `update-check.tape` does, to be honestly one version behind). `# host-docker: true` gives a tape the host's Docker socket (only `docker-health.tape`, which filters everything it prints to its own container).
- Only `.png` files are published from a run. A tape still needs an `Output` line for VHS, and its GIF stays in the container.
- VHS applies `Set Width`/`Set Height` once, so size each tape for its tallest screen. `Screenshot` is slightly asynchronous: leave a `Sleep` after every one, and don't issue two in a row.
- Shared setup goes in `tapes/include/*.tape` and is pulled in with `Source "/tapes/include/<name>.tape"`. `capture.sh` only runs top-level tapes. Hide setup with `Hide`/`Show`, and wait for a marker the typed command doesn't contain (`echo SE''EDED`, then `Wait+Screen /SEEDED/`).
- Tapes that need a Git workspace run `scripts/seed-projects.sh` first. It creates `/home/netclaw/projects/website` on a volume the daemon shares (`compose/projects.yml`) and declares it as the workspace root, so shell approval prompts offer "This repository". Skill captures use `scripts/seed-skills.sh`, which publishes demo skills to the stack's skill server (`compose/skillserver.yml`, port 8090) with the `skillserver` CLI baked into the capture image.
- Tapes that drive a real model (`chat-*`, `approvals-*`, `reminder-run`) must make each prompt self-limiting ("then stop, run nothing else") and wait on text the prompt didn't type, such as a tool result line. A model that wanders into an extra tool call leaves a prompt open and the wait times out.
- A trailing `Screenshot` is lost by VHS if nothing follows it, so `capture.sh` appends `Sleep 1s` to the copy it runs. You don't have to.
- In 0.27.1, `Escape` doesn't quit a TUI. Use `Ctrl+Q`.
- The init wizard prints "Step N of 5" until you pick a posture, then "of 4" for Personal. `init-wizard.tape` (Personal) and `init-team.tape` (Team, the fifth step) record that as shown.

## Mattermost and other browser captures

```bash
INFERENCE_BASE_URL=http://llm.example.internal:8080 INFERENCE_MODEL_ID=my-model \
  OUT_DIR=/tmp/shots ./screenshots/mattermost/run.sh
```

Mattermost, the daemon and Playwright share one compose network, and the daemon reaches Mattermost at `http://mattermost:8065`. The flow is: bootstrap Mattermost (`bootstrap.mjs`), start the daemon, store the bot token with `netclaw secrets set Mattermost.BotToken` (no token in env or compose), enable the channel, post an `@netclaw` message as the test user (`post-message.mjs`) and wait for the reply, then capture the System Console, bot account and thread (`capture.mjs`). `run.sh` sets `Mattermost.CallbackUrl` (through a small forwarder sidecar, because the daemon listens on loopback only) and allow-lists the daemon host in Mattermost (`MM_SERVICESETTINGS_ALLOWEDUNTRUSTEDINTERNALCONNECTIONS`), so tool approvals render as buttons. `SCRIPTED_APPROVAL=1 ./screenshots/mattermost/run.sh` needs no model: `scripted-llm.mjs` answers with one `demo-utilities/http_fetch` MCP call (the demo MCP server, gated to `Approval` for the Personal audience; `SCRIPTED_TOOL=shell` requests a `shell_execute` call instead), `approval.mjs` captures the prompt and `frame-approval.mjs` frames it as `approval-prompt.png` (rounded dark card, purple glow, 2x). The normal flow needs external inference (a 0.5B model won't produce a presentable answer). The bootstrap file with the short-lived bot token is deleted on exit.

The Compose-sample screenshots (`mattermost-compose-*.png`, plus the recaptured `mattermost-bot-accounts.png`, `mattermost-create-bot.png`, `mattermost-conversation.png` and the landing page's `public/assets/approval-prompt.png`) come from `mattermost/capture-compose.mjs`, which signs in to the stack in `examples/mattermost-compose/` after `provision.sh` and `configure-netclaw.sh` have run. It needs the admin and `alice` passwords that `provision.sh` printed, and a Git repository for the approval prompt (so "This repository" appears). Token IDs are overwritten in the page before each shot. The Slack and Discord redactions are `scripts/redact-third-party.py`.

Screenshot a page of the docs site you built locally:

```bash
npm run build
./screenshots/shoot-page.sh cli/status          # docs-logs/screenshots/cli-status.png
```

`shoot-page.sh` runs `scripts/screenshot-page.mjs` in the same Playwright image and serves `dist/` itself. To shoot a dev server instead, start it with `npm run dev -- --host 0.0.0.0` and set `SCREENSHOT_BASE_URL=http://host.docker.internal:4321`.

## Run several at once

Every container, network and volume is namespaced by `COMPOSE_PROJECT_NAME`. There are no fixed container names and no published ports, so two agents can run side by side:

```bash
COMPOSE_PROJECT_NAME=dr04 ./screenshots/stack.sh up
COMPOSE_PROJECT_NAME=dr07 ./screenshots/capture.sh status
```

Use your own name every time, and `down` when you're done. The Mattermost flow appends `-mm` to the name, so it doesn't collide with a stack of the same name. Only built images are shared across projects (`netclaw-docs-capture:<version>`, `netclaw-docs-playwright:<version>`, `netclaw-docs-mcp-demo:1`), which is safe because they're deterministic.

## Design notes

- **Why the capture image starts from VHS.** The release image is `ubuntu:24.04` (glibc) and the CLI is a self-contained .NET single-file binary. The VHS image is Debian trixie (glibc 2.41) with ICU and libsodium already installed, so the CLI and its self-dropping launcher are copied out of the release image unmodified. The recorded CLI is byte-for-byte the released one. Putting VHS into the release image would have meant installing Chromium, ttyd and ffmpeg on an Ubuntu base that ships Chromium only as a snap.
- **One network namespace.** A tiny `netns` container owns the stack's network namespace, and the daemon, capture container, Ollama and demo MCP server join it. Everything talks over `127.0.0.1`, the daemon stays in its default loopback-only `local` exposure mode, and the `netclaw init` wizard's default Ollama endpoint (`http://localhost:11434`) just works.
- **Ownership.** The capture container runs the tape as the `netclaw` user (uid 1654, same as the daemon) so it can use the shared home, then copies the files out with your uid and gid.
