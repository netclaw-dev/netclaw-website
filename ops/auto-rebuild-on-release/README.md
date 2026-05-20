# Auto-rebuild netclaw.dev on every release

When a release is published in `netclaw-dev/netclaw`, this workflow fires the
website's `deploy` workflow via `workflow_dispatch`. The site rebuilds
(re-fetching the GitHub Releases API at build time) and the `/changelog` page
picks up the new release within a couple of minutes.

This folder ships the workflow YAML and the wiring instructions. The workflow
itself lives in the **netclaw repo**, not this one.

> **Note on architecture.** netclaw.dev does not use Cloudflare Pages' Git
> integration — it deploys via `wrangler pages deploy` from inside
> `.github/workflows/deploy.yml`. That means a Cloudflare Pages "Deploy Hook"
> wouldn't actually trigger a rebuild. Instead, we cross-fire the existing
> deploy workflow from the netclaw repo using a fine-grained PAT.

## One-time setup

### 1. Create a fine-grained PAT for cross-repo dispatch

1. Go to <https://github.com/settings/personal-access-tokens/new>.
2. **Resource owner:** `netclaw-dev`.
3. **Repository access:** *Only select repositories* → `netclaw-dev/netclaw-website`.
4. **Repository permissions** → set **Actions** to **Read and write**. Leave
   everything else as the default *No access*.
5. Set an expiration (1 year is reasonable; add a calendar reminder if shorter).
6. Click **Generate token** and copy the `github_pat_…` string. You'll only
   see it once.

### 2. Add the token as a secret on the netclaw repo

1. `netclaw-dev/netclaw` → **Settings → Secrets and variables → Actions**.
2. **New repository secret**.
3. **Name:** `WEBSITE_DISPATCH_TOKEN`. **Value:** the PAT from step 1.

### 3. Drop the workflow into the netclaw repo

Copy [`workflow.yml`](./workflow.yml) into the netclaw repo at:

```
.github/workflows/website-rebuild.yml
```

Commit and push to the netclaw default branch. From then on, every published
release fires the rebuild.

## Verify it works

1. In `netclaw-dev/netclaw` → **Actions → Trigger netclaw.dev rebuild**.
2. Click **Run workflow** (the `workflow_dispatch` trigger) on the default
   branch.
3. Watch the run — it prints `Dispatched deploy.yml on
   netclaw-dev/netclaw-website@dev.` on success.
4. In `netclaw-dev/netclaw-website` → **Actions → deploy** — a fresh run
   should appear within seconds, attributed to the PAT's owner.

If the run fails with `WEBSITE_DISPATCH_TOKEN secret is not set`, revisit
step 2. If it fails with `HTTP 403`, revisit step 1 — the PAT either lacks
`Actions: Read and write` on `netclaw-website`, or it was issued by a user
without push access to that repo.

## Notes

- The `release: published` event fires for every non-draft release, **including
  prereleases**. The changelog page already badges prereleases, so this is
  usually what you want. If you'd rather skip prereleases entirely, filter on
  the receiving end (in `src/pages/changelog.astro`) — don't change the
  trigger, or you'll diverge from what `netclaw.dev/changelog` shows.
- Build-time GitHub API calls run on GitHub Actions and inherit the runner's
  rate limit. If you ever see intermittent rate-limit errors, add a `GH_TOKEN`
  environment variable to `.github/workflows/deploy.yml`'s build step — the
  `src/lib/releases.js` helper already picks it up.
- The website's `deploy.yml` now also exposes `workflow_dispatch` directly,
  so you can rebuild manually from the website repo's Actions tab without
  going through the netclaw repo.
