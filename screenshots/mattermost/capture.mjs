#!/usr/bin/env node
// Drives Playwright against the bootstrapped Mattermost to capture the
// channels/mattermost.md screenshots: the System Console settings, the bot
// account, and a live netclaw conversation. Reads .bootstrap.json.
//
// Each shot is independent (try/catch) so one failure doesn't lose the rest.
// Usage: node capture.mjs

import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const boot = JSON.parse(readFileSync(join(__dirname, '.bootstrap.json'), 'utf8'));
const OUT = join(__dirname, '..', 'output');
mkdirSync(OUT, { recursive: true });
const BASE = boot.serverUrl;

const shot = (page, name) => page.screenshot({ path: join(OUT, name) }).then(() => console.log(`  ✓ ${name}`));

async function dismissModals(page) {
  // Clear the "Welcome to Mattermost" onboarding overlay and any tutorial tips.
  const labels = [/no thanks/i, /i'?ll figure it out/i, /skip/i, /got it/i, /not now/i, /take a tour later/i];
  for (const rx of labels) {
    for (const role of ['link', 'button']) {
      try {
        const el = page.getByRole(role, { name: rx }).first();
        if (await el.isVisible({ timeout: 400 })) { await el.click({ timeout: 1000 }); await page.waitForTimeout(400); }
      } catch {}
    }
    try {
      const t = page.getByText(rx).first();
      if (await t.isVisible({ timeout: 300 })) { await t.click({ timeout: 1000 }); await page.waitForTimeout(400); }
    } catch {}
  }
  // Generic close icon (the circular ✕ on the onboarding card).
  try {
    const c = page.locator('button[aria-label="Close"], .close, .icon-close, button:has(.icon-close)').first();
    if (await c.isVisible({ timeout: 300 })) await c.click({ timeout: 800 });
  } catch {}
  try { await page.keyboard.press('Escape'); } catch {}
  await page.waitForTimeout(400);
}

async function login(page, loginId, password) {
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' }).catch(() => {});
  // Mattermost shows an "Open in App / View in Browser" interstitial first.
  for (const rx of [/view in browser/i, /continue in browser/i]) {
    try {
      const link = page.getByText(rx).first();
      if (await link.isVisible({ timeout: 3000 })) { await link.click(); await page.waitForTimeout(1000); break; }
    } catch {}
  }
  // mattermost-preview hydrates the form slowly; wait for the password input.
  await page.waitForSelector('input[type="password"]', { timeout: 30000 });
  await page.locator('input[type="text"], input[type="email"]').first().fill(loginId);
  await page.locator('input[type="password"]').first().fill(password);
  await page.getByRole('button', { name: /log in|sign in/i }).first().click();
  // Confirm we actually left the login page.
  await page.waitForURL(u => !/\/login/.test(new URL(u).pathname), { timeout: 15000 })
    .catch(() => { throw new Error(`login as ${loginId} did not navigate away from /login`); });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await dismissModals(page);
}

const browser = await chromium.launch();

// 1 + 2: admin System Console settings
try {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 } });
  const page = await ctx.newPage();
  await login(page, boot.admin.username, boot.admin.password);

  await page.goto(`${BASE}/admin_console/integrations/bot_accounts`, { waitUntil: 'networkidle' }).catch(() => {});
  await page.waitForTimeout(1500);
  await dismissModals(page);
  // Clip to the settings rows; the lower System Console nav is dead space.
  await page.screenshot({ path: join(OUT, 'mattermost-bot-accounts.png'), clip: { x: 0, y: 0, width: 1280, height: 430 } });
  console.log('  ✓ mattermost-bot-accounts.png');

  // The user-facing bot accounts page (create + token live here)
  await page.goto(`${BASE}/${boot.team.name}/integrations/bots`, { waitUntil: 'networkidle' }).catch(() => {});
  await page.waitForTimeout(1500);
  await dismissModals(page);
  await shot(page, 'mattermost-create-bot.png');
  await ctx.close();
} catch (e) { console.error('  ✗ admin shots:', e.message); }

// 3: live conversation as the test user
try {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 } });
  const page = await ctx.newPage();
  await login(page, boot.testuser.username, boot.testuser.password);
  await page.goto(`${BASE}/${boot.team.name}/channels/${boot.channel.name}`, { waitUntil: 'networkidle' }).catch(() => {});
  await page.waitForTimeout(2000);
  await dismissModals(page);
  // netclaw replies in a thread. Find its reply via the API and open the
  // permalink, which deterministically opens the thread panel (RHS).
  let replyId = null;
  try {
    const res = await fetch(`${BASE}/api/v4/channels/${boot.channel.id}/posts`, { headers: { Authorization: `Bearer ${boot.bot.token}` } });
    const data = await res.json();
    for (const id of data.order) {
      const p = data.posts[id];
      if (p.user_id === boot.bot.userId && p.root_id) { replyId = id; break; }
    }
  } catch {}
  if (replyId) {
    // Onboarding modal was already cleared above; don't dismiss again here —
    // dismissModals presses Escape, which would close the thread panel.
    await page.goto(`${BASE}/${boot.team.name}/pl/${replyId}`, { waitUntil: 'networkidle' }).catch(() => {});
    await page.waitForTimeout(2500);
  }
  try { await page.getByText(/I'?m Netclaw/i).first().waitFor({ timeout: 20000 }); } catch {}
  await page.mouse.move(400, 300); // move off any hover tooltip
  await page.waitForTimeout(1000);
  await shot(page, 'mattermost-conversation.png');
  await ctx.close();
} catch (e) { console.error('  ✗ conversation shot:', e.message); }

await browser.close();
console.log('Done.');
