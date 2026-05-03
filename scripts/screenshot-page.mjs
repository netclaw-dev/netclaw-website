#!/usr/bin/env node
// Capture a full-page screenshot of a rendered documentation page.
//
// Usage: node scripts/screenshot-page.mjs <page-slug>
// Example: node scripts/screenshot-page.mjs cli/status
//
// Requires: npm run build (must be run first)
// Output: docs-logs/screenshots/<page-slug>.png

import { chromium } from 'playwright';
import { execSync, spawn } from 'child_process';
import { mkdirSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

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

const port = 4322;
const url = `http://localhost:${port}/${slug}/`;

const preview = spawn('npx', ['astro', 'preview', '--port', String(port)], {
  cwd: projectDir,
  stdio: ['ignore', 'pipe', 'pipe'],
});

async function waitForServer(url, timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {}
    await new Promise(r => setTimeout(r, 300));
  }
  throw new Error(`Server not ready after ${timeoutMs}ms`);
}

try {
  await waitForServer(url);

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  await page.screenshot({ path: outputFile, fullPage: true });
  await browser.close();

  console.log(outputFile);
} catch (err) {
  console.error('Screenshot failed:', err.message);
  process.exit(1);
} finally {
  preview.kill('SIGTERM');
}
