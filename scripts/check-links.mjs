// Crawls dist/ and verifies every internal link, image and #anchor resolves.
// Complements the external link-validator in CI (which does not check anchors).
// Usage: npm run check-links   (after npm run build)
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIST = join(ROOT, 'dist');
if (!existsSync(DIST)) {
  console.error('dist/ not found. Run `npm run build` first.');
  process.exit(2);
}

const walk = (dir) =>
  readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

const pages = walk(DIST).filter((f) => f.endsWith('.html'));
const ids = new Map(); // abs html path -> Set of ids
const decode = (s) => s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'");

for (const f of pages) {
  const html = readFileSync(f, 'utf8');
  const set = new Set();
  for (const m of html.matchAll(/\s(?:id|name)=("([^"]*)"|'([^']*)'|([^\s>]+))/g)) {
    set.add(decode(m[2] ?? m[3] ?? m[4]));
  }
  ids.set(f, set);
}

function resolveTarget(pathname, fromFile) {
  let p = pathname.startsWith('/') ? join(DIST, pathname) : resolve(dirname(fromFile), pathname);
  try {
    p = decodeURIComponent(p);
  } catch {}
  return [p, join(p, 'index.html'), p + '.html'].find((c) => existsSync(c) && statSync(c).isFile());
}

const problems = [];
let checked = 0;
for (const f of pages) {
  const html = readFileSync(f, 'utf8');
  const rel = '/' + relative(DIST, f).replace(/index\.html$/, '');
  for (const m of html.matchAll(/<(a|img|source)\s[^>]*?(href|src)=("([^"]*)"|'([^']*)')/g)) {
    const raw = decode(m[4] ?? m[5]);
    if (!raw || /^(https?:|mailto:|tel:|data:|javascript:|\/\/)/.test(raw)) continue;
    checked++;
    const [beforeHash, hash] = raw.split('#');
    const [pathname] = beforeHash.split('?');
    const target = pathname === '' ? f : resolveTarget(pathname, f);
    if (!target) {
      problems.push(`${rel}  missing target: ${raw}`);
      continue;
    }
    if (hash && target.endsWith('.html')) {
      let h = hash;
      try {
        h = decodeURIComponent(hash);
      } catch {}
      if (!ids.get(target)?.has(h)) problems.push(`${rel}  missing anchor: ${raw}`);
    }
  }
}

const unique = [...new Set(problems)];
console.log(`Checked ${checked} internal references across ${pages.length} pages.`);
if (unique.length) {
  console.error(`\n${unique.length} broken:`);
  for (const p of unique) console.error('  ' + p);
  process.exit(1);
}
console.log('No broken internal links or anchors.');
