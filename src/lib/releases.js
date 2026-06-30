// Build-time helper for fetching netclaw GitHub releases. Module-level cache
// keeps the API hit to once per build regardless of how many routes consume it.

import { marked } from 'marked';

export const REPO = 'netclaw-dev/netclaw';
export const REPO_URL = `https://github.com/${REPO}`;

let _cache = null;

export async function getReleases() {
  if (_cache) return _cache;

  const headers = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'netclaw-website-build',
  };
  if (process.env.GH_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GH_TOKEN}`;
  }

  try {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/releases?per_page=100`,
      { headers },
    );
    if (!res.ok) {
      throw new Error(`GitHub API responded ${res.status} ${res.statusText}`);
    }
    const data = await res.json();
    const releases = data
      .filter((r) => !r.draft)
      .sort((a, b) => new Date(b.published_at) - new Date(a.published_at))
      .map((r) => ({
        tag: r.tag_name.replace(/^v/i, ''),
        rawTag: r.tag_name,
        name: r.name && r.name !== r.tag_name ? r.name : null,
        url: r.html_url,
        date: r.published_at,
        prerelease: r.prerelease,
        // Older release notes hard-code the pre-transfer org (Aaronontheweb/netclaw),
        // whose issue/PR paths now 404; rewrite to the current repo so the links resolve.
        bodyHtml: marked.parse(
          (r.body || '_No release notes._').replaceAll('Aaronontheweb/netclaw', REPO),
        ),
      }));
    _cache = { releases, error: null };
  } catch (e) {
    console.warn('[releases] fetch failed:', e.message);
    _cache = { releases: [], error: e.message };
  }

  return _cache;
}

// UTC-locked so a build that happens in a non-UTC timezone (e.g. local dev)
// renders the same date as a Cloudflare Pages build (which is always UTC).
export const formatDate = (iso) =>
  new Date(iso).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC',
  });

export const shortDate = (iso) =>
  new Date(iso).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
