#!/usr/bin/env node
// Docs version-drift guard.
//
// Compares the netclaw version these docs are written against (src/version.json)
// with the latest published release on GitHub. Exits non-zero when the product
// has moved ahead so CI can flag it (and optionally open an issue).
//
// Usage:  node scripts/check-docs-version.mjs
// Offline/no-gh: prints a notice and exits 0 (never blocks a local build).

import { readFileSync } from 'fs';
import { execSync } from 'child_process';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const versionFile = join(__dirname, '..', 'src', 'version.json');

const { documentedVersion, sourceRepo } = JSON.parse(readFileSync(versionFile, 'utf8'));

// Parse "1.2.3" -> [1,2,3]; ignores leading "v" and pre-release/build suffixes.
function parse(v) {
  return String(v).replace(/^v/, '').split('-')[0].split('.').map(n => parseInt(n, 10) || 0);
}
// Returns >0 if a>b, <0 if a<b, 0 if equal.
function cmp(a, b) {
  const x = parse(a), y = parse(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d !== 0) return d;
  }
  return 0;
}

let latest;
try {
  latest = execSync(
    `gh release list --repo ${sourceRepo} --limit 1 --json tagName --jq '.[0].tagName'`,
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
  ).trim();
} catch {
  console.log(`[check-docs-version] gh unavailable or offline — skipping drift check (docs target ${documentedVersion}).`);
  process.exit(0);
}

if (!latest) {
  console.log('[check-docs-version] could not resolve latest release — skipping.');
  process.exit(0);
}

const delta = cmp(latest, documentedVersion);
if (delta > 0) {
  console.error(
    `\n❌ Docs drift detected.\n` +
    `   Documented version : ${documentedVersion}  (src/version.json)\n` +
    `   Latest release      : ${latest}  (${sourceRepo})\n` +
    `   The product is ahead of the docs. Run a content pass and bump src/version.json.\n`,
  );
  process.exit(1);
}

console.log(
  `✅ Docs version OK — documented ${documentedVersion}, latest release ${latest}.`,
);
