# netclaw + Mattermost on Docker Compose

A private assistant stack: netclaw 0.28.2, Mattermost Team Edition 11.11.1 and
Postgres 17.11 on one Compose network. The full walkthrough, with expected
output at every step, is
[Run netclaw with Mattermost on Docker Compose](https://netclaw.dev/guides/mattermost-docker-compose/).

| File | What it does |
|------|--------------|
| `compose.yaml` | The three services. netclaw publishes no ports and runs read-only with all capabilities dropped. |
| `.env.example` | Copy to `.env`. Passwords and the inference endpoint. |
| `provision.sh` | Creates the admin, a team, a private channel, one member and one bot with a token. Needs bash and curl. |
| `configure-netclaw.sh` | Adds the inference provider, sets the channel audience, stores the bot token in netclaw's vault and restarts. |

```bash
cp .env.example .env && chmod 600 .env   # edit POSTGRES_PASSWORD, INFERENCE_BASE_URL, INFERENCE_MODEL_ID
docker compose up -d --wait
./provision.sh              # prints the generated passwords once
./configure-netclaw.sh
```

Then sign in at <http://localhost:8065> as the member user and mention the bot
in the `assistant` channel.

Everything lives in named volumes. `docker compose down` keeps your data.
`docker compose down -v` deletes it.
