#!/usr/bin/env node
// Capture a full-page screenshot of a rendered documentation page.
//
// Usage: node scripts/screenshot-page.mjs <page-slug>
// Example: node scripts/screenshot-page.mjs cli/status
//
// Requires: npm run build (must be run first)
// Output: docs-logs/screenshots/<page-slug>.png
// Timeout: 60 seconds total, then kills everything and exits non-zero.

import { chromium } from 'playwright';
import { spawn } from 'child_process';
import { mkdirSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { createServer } from 'net';

const TIMEOUT_MS = 60_000;

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectDir = join(__dirname, '..');
const slug = process.argv[2];

if (!slug) {
  console.error('Usage: node scripts/screenshot-page.mjs <page-slug>');
  console.error('Example: node scripts/screenshot-page.mjs cli/status');
  process.exit(1);
}

const outputDir = join(projectDir, 'docs-logs', 'screenshots');
const outputFile = join(outputDir, slug.replace(/\//g, '-') + '.png');
mkdirSync(outputDir, { recursive: true });

const distDir = join(projectDir, 'dist');
if (!existsSync(distDir)) {
  console.error('dist/ not found — run npm run build first');
  process.exit(1);
}

function findFreePort() {
  return new Promise((resolve, reject) => {
    const srv = createServer();
    srv.listen(0, () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
    srv.on('error', reject);
  });
}

let preview;
const killTimer = setTimeout(() => {
  console.error('Screenshot timed out after 60s');
  if (preview) preview.kill('SIGKILL');
  process.exit(1);
}, TIMEOUT_MS);

try {
  const port = await findFreePort();
  const url = `http://localhost:${port}/${slug}/`;

  preview = spawn('npx', ['astro', 'preview', '--port', String(port)], {
    cwd: projectDir,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  const start = Date.now();
  while (Date.now() - start < 15_000) {
    try {
      const res = await fetch(url);
      if (res.ok) break;
    } catch {}
    await new Promise(r => setTimeout(r, 300));
  }

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 15_000 });
  await page.waitForTimeout(500);
  await page.screenshot({ path: outputFile, fullPage: true });
  await browser.close();

  console.log(outputFile);
} catch (err) {
  console.error('Screenshot failed:', err.message);
  process.exit(1);
} finally {
  clearTimeout(killTimer);
  if (preview) preview.kill('SIGTERM');
}
