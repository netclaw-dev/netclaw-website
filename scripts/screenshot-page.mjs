#!/usr/bin/env node
// Capture a full-page screenshot of a rendered documentation page.
//
// Usage: node scripts/screenshot-page.mjs <page-slug>
// Example: node scripts/screenshot-page.mjs cli/status
//
// Run it in the Playwright container so the browser is the pinned, containerized one:
//   ./screenshots/shoot-page.sh cli/status
//
// Serves dist/ itself with a tiny static server (no astro needed), so it runs anywhere
// the `playwright` module resolves. Requires `npm run build` first.
// Output: docs-logs/screenshots/<page-slug>.png
//
// Env:
//   SCREENSHOT_OUT       output directory (default docs-logs/screenshots)
//   SCREENSHOT_BASE_URL  screenshot a running server (e.g. `npm run dev`) instead of dist/
// Timeout: 60 seconds total, then exits non-zero.

import { chromium } from 'playwright';
import { createServer } from 'http';
import { mkdirSync, existsSync, statSync, createReadStream } from 'fs';
import { dirname, join, extname, normalize } from 'path';
import { fileURLToPath } from 'url';

const TIMEOUT_MS = 60_000;

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectDir = join(__dirname, '..');
const slug = process.argv[2];

if (!slug) {
  console.error('Usage: node scripts/screenshot-page.mjs <page-slug>');
  console.error('Example: node scripts/screenshot-page.mjs cli/status');
  process.exit(1);
}

const outputDir = process.env.SCREENSHOT_OUT || join(projectDir, 'docs-logs', 'screenshots');
const outputFile = join(outputDir, slug.replace(/\//g, '-') + '.png');
mkdirSync(outputDir, { recursive: true });

const distDir = join(projectDir, 'dist');
const baseUrl = process.env.SCREENSHOT_BASE_URL?.replace(/\/$/, '');
if (!baseUrl && !existsSync(distDir)) {
  console.error('dist/ not found, run npm run build first');
  process.exit(1);
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.gif': 'image/gif', '.webp': 'image/webp', '.ico': 'image/x-icon', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.txt': 'text/plain', '.xml': 'application/xml',
};

function resolveFile(urlPath) {
  const rel = normalize(decodeURIComponent(urlPath.split('?')[0])).replace(/^(\.\.[/\\])+/, '');
  let file = join(distDir, rel);
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  else if (!existsSync(file) && existsSync(join(file, 'index.html'))) file = join(file, 'index.html');
  return existsSync(file) && statSync(file).isFile() ? file : null;
}

let server;
const killTimer = setTimeout(() => {
  console.error('Screenshot timed out after 60s');
  server?.close();
  process.exit(1);
}, TIMEOUT_MS);

let browser;
try {
  let origin = baseUrl;
  if (!origin) {
    server = createServer((req, res) => {
      const file = resolveFile(req.url);
      if (!file) { res.writeHead(404); res.end('not found'); return; }
      res.writeHead(200, { 'Content-Type': MIME[extname(file)] || 'application/octet-stream' });
      createReadStream(file).pipe(res);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    origin = `http://127.0.0.1:${server.address().port}`;
  }
  const url = `${origin}/${slug}/`;

  browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 15_000 });
  if (!response || !response.ok()) throw new Error(`${url} returned ${response?.status()}`);
  await page.waitForTimeout(500);
  await page.screenshot({ path: outputFile, fullPage: true });

  console.log(outputFile);
} catch (err) {
  console.error('Screenshot failed:', err.message);
  process.exitCode = 1;
} finally {
  clearTimeout(killTimer);
  await browser?.close();
  server?.close();
}
