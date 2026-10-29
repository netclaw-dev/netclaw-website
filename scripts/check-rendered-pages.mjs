// Post-build guard. Fails the build when a built docs page is empty or missing diagrams.
//
// Why: Mermaid fences are rendered at build time through a headless browser
// (rehype-mermaid, inline-svg). When the browser is not installed the build still
// succeeds, but every page with a diagram ships with an EMPTY body. This script
// catches that, and any other page whose main content collapsed.
//
// Checks, for every page in src/content/docs:
//   1. dist/<slug>/index.html exists
//   2. main content has at least MIN_WORDS words of prose (SVG, scripts and tags stripped)
//   3. each ```mermaid fence in the source has a rendered <svg id="mermaid-...">
//
// Usage: node scripts/check-rendered-pages.mjs [--verbose]
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DOCS = join(ROOT, 'src', 'content', 'docs');
const DIST = join(ROOT, 'dist');
const MIN_WORDS = 150;
const verbose = process.argv.includes('--verbose');

const walk = (dir) =>
  readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

if (!existsSync(DIST)) {
  console.error('dist/ not found. Run `astro build` first.');
  process.exit(2);
}

const failures = [];
const rows = [];

for (const file of walk(DOCS).filter((f) => /\.mdx?$/.test(f))) {
  const slug = relative(DOCS, file).replace(/\.mdx?$/, '').replace(/(^|\/)index$/, '');
  const src = readFileSync(file, 'utf8');
  const fences = (src.match(/^\s*```mermaid\b/gm) || []).length;
  const out = join(DIST, slug, 'index.html');
  if (!existsSync(out)) {
    failures.push(`${slug}: no built page at dist/${slug}/index.html`);
    continue;
  }
  const html = readFileSync(out, 'utf8');
  const start = html.indexOf('class="sl-markdown-content"');
  const end = html.indexOf('</main>', start);
  const main = start === -1 ? '' : html.slice(start, end === -1 ? undefined : end);
  const text = main
    .replace(/<svg[\s\S]*?<\/svg>/g, ' ')
    .replace(/<(script|style)[\s\S]*?<\/\1>/g, ' ')
    .replace(/<[^>]+>/g, ' ');
  const words = (text.match(/\S+/g) || []).length;
  const svgs = (main.match(/<svg[^>]*\bid="mermaid-/g) || []).length;

  rows.push({ slug, fences, svgs, words });
  if (start === -1) failures.push(`${slug}: main content container not found`);
  else if (words < MIN_WORDS) failures.push(`${slug}: main content has only ${words} words (minimum ${MIN_WORDS})`);
  if (svgs < fences) failures.push(`${slug}: ${fences} mermaid fence(s) but ${svgs} rendered SVG(s)`);
}

if (verbose) {
  for (const r of rows.filter((r) => r.fences > 0)) {
    console.log(`  diagram page ${r.slug}: ${r.svgs}/${r.fences} rendered, ${r.words} words`);
  }
}

const diagramPages = rows.filter((r) => r.fences > 0).length;
if (failures.length) {
  console.error(`\ncheck-rendered-pages: ${failures.length} problem(s)`);
  for (const f of failures) console.error('  ' + f);
  console.error(
    '\nIf diagrams are missing, the headless browser is probably not installed: npx playwright install chromium-headless-shell. Astro caches rendered markdown, so after fixing it delete node_modules/.astro and rebuild.',
  );
  process.exit(1);
}
console.log(
  `check-rendered-pages: ${rows.length} pages OK (${diagramPages} with diagrams, min ${Math.min(...rows.map((r) => r.words))} words)`,
);
