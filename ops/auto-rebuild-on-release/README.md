# Auto-rebuild netclaw.dev on every release

When a release is published in `netclaw-dev/netclaw`, this workflow pings a
Cloudflare Pages deploy hook for the `netclaw-website` project. The site
rebuilds (re-fetching the GitHub Releases API at build time) and the
`/changelog` page picks up the new release within a couple of minutes.

This folder ships the workflow YAML and the wiring instructions. The
workflow itself lives in the **netclaw repo**, not this one.

## One-time setup

### 1. Create a Cloudflare Pages deploy hook

1. Cloudflare dashboard → **Workers & Pages** → `netclaw-website` project.
2. **Settings → Builds & Deployments → Deploy Hooks → Add Deploy Hook**.
3. Name it `release-trigger`. Branch: `dev` (or whichever branch Pages
   deploys to production from).
4. Copy the generated URL — it looks like
   `https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/<uuid>`.
   Treat it as a secret; anyone with this URL can trigger a build.

### 2. Add the URL as a secret on the netclaw repo

1. `netclaw-dev/netclaw` → **Settings → Secrets and variables → Actions**.
2. **New repository secret**.
3. Name: `WEBSITE_DEPLOY_HOOK`. Value: the URL from step 1.

### 3. Drop the workflow into the netclaw repo

Copy [`workflow.yml`](./workflow.yml) into the netclaw repo at:

```
.github/workflows/website-rebuild.yml
```

Commit and push to the netclaw default branch. From then on, every
published release fires the rebuild.

## Verify it works

After the workflow file is in place:

1. Go to `netclaw-dev/netclaw` → **Actions → Trigger netclaw.dev rebuild**.
2. Click **Run workflow** (the `workflow_dispatch` trigger) on the default
   branch.
3. Watch the run. A successful run prints `Cloudflare Pages deploy hook
   responded: HTTP 200` and a JSON body containing the new deployment ID.
4. Check Cloudflare Pages → **Deployments** — a new build should appear
   labelled with the deploy hook source.

If the run fails with "WEBSITE_DEPLOY_HOOK secret is not set", revisit
step 2.

## Notes

- `release: published` fires for every non-draft release, **including
  prereleases**. The changelog page renders prereleases with a "Pre-release"
  badge — if you don't want prereleases to ship to the public site at all,
  filter them out in `src/pages/changelog.astro` instead of changing the
  trigger.
- Build-time GitHub API calls on Cloudflare's build infrastructure are
  unauthenticated by default (60 req/hr/IP, shared). If you ever see
  intermittent rate-limit errors, add a `GH_TOKEN` environment variable to
  the Pages project (a fine-grained PAT with `Contents: read` on
  `netclaw-dev/netclaw` is enough) — `changelog.astro` already picks it up.
