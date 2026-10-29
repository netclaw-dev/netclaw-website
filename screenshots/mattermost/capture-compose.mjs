#!/usr/bin/env node
// Captures the Mattermost screenshots for channels/mattermost.md and
// guides/mattermost-docker-compose.md from the stack in examples/mattermost-compose/
// (provisioned with provision.sh, wired with configure-netclaw.sh).
//
// One consistent look: Chromium, 1280x800 viewport, device scale factor 2, the Onyx
// dark theme, no browser chrome (page screenshots, cropped to the relevant region).
// Token IDs on screen are overwritten in the page before the screenshot is taken.
//
// Usage (Playwright container or any Node with playwright installed):
//   MM_URL=http://localhost:8065 ADMIN_PASSWORD=... ALICE_PASSWORD=... \
//     node capture-compose.mjs [step ...]
// Steps (default: all): admin bots thread approval
// Env:   TEAM (home), CHANNEL (assistant), OUT_DIR (../output),
//        REPO_DIR (directory the approval prompt runs in), REPLY_TIMEOUT_SECONDS (300)

import { chromium } from 'playwright';
import { mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const BASE = (process.env.MM_URL || 'http://localhost:8065').replace(/\/$/, '');
const TEAM = process.env.TEAM || 'home';
const CHANNEL = process.env.CHANNEL || 'assistant';
const OUT = process.env.OUT_DIR || join(here, '..', 'output');
const REPO_DIR = process.env.REPO_DIR || '~/.netclaw/projects/website';
const TIMEOUT_MS = Number(process.env.REPLY_TIMEOUT_SECONDS || 300) * 1000;
const ADMIN = { username: 'admin', password: process.env.ADMIN_PASSWORD };
const ALICE = { username: 'alice', password: process.env.ALICE_PASSWORD };
if (!ADMIN.password || !ALICE.password) { console.error('ADMIN_PASSWORD and ALICE_PASSWORD are required'); process.exit(2); }
mkdirSync(OUT, { recursive: true });

const steps = new Set(process.argv.slice(2).length ? process.argv.slice(2) : ['admin', 'bots', 'thread', 'approval']);
const VIEWPORT = { width: 1280, height: 800 };
const MASK = 'x'.repeat(26);

// Mattermost's Onyx theme.
const ONYX = {
  type: 'Onyx', sidebarBg: '#18181a', sidebarText: '#ffffff', sidebarUnreadText: '#ffffff',
  sidebarTextHoverBg: '#25262a', sidebarTextActiveBorder: '#afbe5d', sidebarTextActiveColor: '#ffffff',
  sidebarHeaderBg: '#1f1f1f', sidebarTeamBarBg: '#121212', sidebarHeaderTextColor: '#ffffff',
  onlineIndicator: '#a4c940', awayIndicator: '#dcbd4e', dndIndicator: '#d24b4e',
  mentionBg: '#ffffff', mentionColor: '#1f1f1f', centerChannelBg: '#1f1f1f', centerChannelColor: '#dddddd',
  newMessageSeparator: '#cc8f00', linkColor: '#a4ffeb', buttonBg: '#a4ffeb', buttonColor: '#1f1f1f',
  errorTextColor: '#ff6461', mentionHighlightBg: '#784098', mentionHighlightLink: '#a4ffeb', codeTheme: 'solarized-dark',
};

async function api(method, path, body, token) {
  const res = await fetch(`${BASE}/api/v4${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res;
}

async function apiLogin(user) {
  const res = await api('POST', '/users/login', { login_id: user.username, password: user.password });
  const token = res.headers.get('Token');
  const me = await res.json();
  user.token = token; user.id = me.id;
  await api('PUT', `/users/${me.id}/preferences`, [
    { user_id: me.id, category: 'theme', name: '', value: JSON.stringify(ONYX) },
    { user_id: me.id, category: 'tutorial_step', name: me.id, value: '999' },
    { user_id: me.id, category: 'onboarding_task_list', name: 'onboarding_task_list_show', value: 'false' },
    { user_id: me.id, category: 'recommended_next_steps', name: 'hide', value: 'true' },
  ], token).catch(e => console.warn('  preferences:', e.message));
  return token;
}

async function newPage(browser, user, viewport = VIEWPORT) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: 2, colorScheme: 'dark' });
  await ctx.addInitScript(() => {
    try { localStorage.setItem('__landingPageSeen__', 'true'); localStorage.setItem('onboarding_complete', 'true'); } catch {}
  });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
  for (const rx of [/view in browser/i, /continue in browser/i]) {
    try { const l = page.getByText(rx).first(); if (await l.isVisible({ timeout: 1500 })) { await l.click(); break; } } catch {}
  }
  await page.waitForSelector('input[type="password"]', { timeout: 30000 });
  await page.locator('input[type="text"], input[type="email"]').first().fill(user.username);
  await page.locator('input[type="password"]').first().fill(user.password);
  await page.getByRole('button', { name: /log in|sign in/i }).first().click();
  await page.waitForURL(u => !/\/login/.test(new URL(u).pathname), { timeout: 20000 });
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  return { ctx, page };

}

async function dismissModals(page) {
  for (const rx of [/view in browser/i, /no thanks/i, /skip/i, /got it/i, /not now/i]) {
    for (const role of ['link', 'button']) {
      try {
        const el = page.getByRole(role, { name: rx }).first();
        if (await el.isVisible({ timeout: 300 })) { await el.click({ timeout: 1000 }); await page.waitForTimeout(300); }
      } catch {}
    }
  }
}

// The "Preview Mode: Email notifications have not been configured" banner is a stack detail.
// Dismiss it the way a person would, with its close button.
async function closeBanner(page) {
  try {
    const bar = page.locator('.announcement-bar').first();
    if (await bar.isVisible({ timeout: 1500 })) {
      await bar.locator('.announcement-bar__close, .close, [aria-label="Close"]').first().click({ timeout: 2000 });
      await page.waitForTimeout(500);
    }
  } catch {}
}

const maskTokenIds = page => page.evaluate(mask => {
  // Overwrite anything shaped like a 26-character Mattermost ID inside a "Token ID" line.
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const hits = [];
  while (walker.nextNode()) {
    const n = walker.currentNode;
    if (/^[a-z0-9]{26}$/.test(n.nodeValue.trim()) && /Token ID/i.test(n.parentElement?.parentElement?.textContent || '')) hits.push(n);
  }
  for (const n of hits) n.nodeValue = mask;
  return hits.length;
}, MASK);

const shot = async (page, name, clip) => {
  await page.screenshot({ path: join(OUT, name), ...(clip ? { clip } : {}) });
  console.log(`  ok ${name}`);
};

async function waitFor(fn, what) {
  const start = Date.now();
  while (Date.now() - start < TIMEOUT_MS) {
    const v = await fn();
    if (v) return v;
    await new Promise(r => setTimeout(r, 2500));
  }
  throw new Error(`timed out waiting for ${what}`);
}

const browser = await chromium.launch();
let failures = 0;
const attempt = async (name, fn) => { try { await fn(); } catch (e) { failures++; console.error(`  FAIL ${name}: ${e.message}`); } };

await apiLogin(ADMIN);
await apiLogin(ALICE);
const channel = (await (await api('GET', `/teams/name/${TEAM}/channels/name/${CHANNEL}`, null, ALICE.token)).json());

if (steps.has('admin')) await attempt('admin', async () => {
  const { ctx, page } = await newPage(browser, ADMIN);
  await page.goto(`${BASE}/admin_console/integrations/bot_accounts`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);
  await dismissModals(page);
  await closeBanner(page);
  await shot(page, 'mattermost-bot-accounts.png', { x: 220, y: 44, width: 1060, height: 376 });
  await ctx.close();
});

if (steps.has('bots')) await attempt('bots', async () => {
  const { ctx, page } = await newPage(browser, ADMIN);
  await page.goto(`${BASE}/${TEAM}/integrations/bots`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);
  await dismissModals(page);
  await closeBanner(page);
  console.log(`  masked ${await maskTokenIds(page)} token id(s)`);
  await shot(page, 'mattermost-create-bot.png', { x: 16, y: 76, width: 1240, height: 610 });
  await shot(page, 'mattermost-compose-bot-account.png', { x: 290, y: 372, width: 940, height: 150 });
  await ctx.close();
});

const botUserId = async () => (await (await api('GET', '/users/username/netclaw', null, ALICE.token)).json()).id;

async function postAsAlice(message) {
  const res = await api('POST', '/posts', { channel_id: channel.id, message }, ALICE.token);
  return (await res.json());
}

// Start each conversation from an empty channel so only that conversation is on screen.
async function clearChannel() {
  const data = await (await api('GET', `/channels/${channel.id}/posts?per_page=200`, null, ADMIN.token)).json();
  for (const id of data.order) {
    const p = data.posts[id];
    if (p.type === '' && !p.root_id) await api('DELETE', `/posts/${id}`, null, ADMIN.token).catch(() => {});
  }
  await new Promise(r => setTimeout(r, 1000));
}

async function threadPosts(rootId) {
  const data = await (await api('GET', `/posts/${rootId}/thread`, null, ALICE.token)).json();
  return data.order.map(id => data.posts[id]).sort((a, b) => a.create_at - b.create_at);
}

async function openThread(page, rootId) {
  await page.goto(`${BASE}/${TEAM}/pl/${rootId}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2500);
  await dismissModals(page);
  await closeBanner(page);
  // The permalink only highlights the post. Open the thread panel like a person would.
  await page.getByRole('button', { name: /\d+ repl(y|ies)/i }).last().click();
  await page.waitForTimeout(2500);
  await page.mouse.move(640, 790);
}

if (steps.has('thread')) await attempt('thread', async () => {
  const bot = await botUserId();
  await clearChannel();
  const root = await postAsAlice('@netclaw reply with a one-sentence greeting');
  await waitFor(async () => (await threadPosts(root.id)).some(p => p.user_id === bot && p.message), 'the bot reply');
  const { ctx, page } = await newPage(browser, ALICE);
  await openThread(page, root.id);
  await shot(page, 'mattermost-conversation.png');
  await shot(page, 'mattermost-compose-thread.png', { x: 270, y: 45, width: 965, height: 755 });
  await ctx.close();
});

if (steps.has('approval')) await attempt('approval', async () => {
  const bot = await botUserId();
  await clearChannel();
  const root = await postAsAlice(`@netclaw Use the shell to run exactly this, nothing else: git -C ${REPO_DIR} push origin main`);
  const prompt = await waitFor(async () => (await threadPosts(root.id)).find(p => p.user_id === bot && /Tool approval required/i.test(p.message)), 'the approval prompt');
  console.log('--- prompt text ---\n' + prompt.message + '\n-------------------');
  const { ctx, page } = await newPage(browser, ALICE, { width: 1280, height: 900 });
  await openThread(page, root.id);
  // Widen the thread panel so the command doesn't wrap.
  await page.getByRole('button', { name: /expand/i }).first().click();
  await page.waitForTimeout(1500);
  await page.mouse.move(640, 880);
  const rhs = page.locator('#sidebar-right');
  const rb = await rhs.boundingBox();
  const posts = rhs.locator('.post');
  const fb = await posts.first().boundingBox();
  const lb = await posts.last().boundingBox();
  console.log('rhs', JSON.stringify(rb), 'first', JSON.stringify(fb), 'last', JSON.stringify(lb));
  await page.screenshot({ path: join(OUT, '_pending-full.png') });
  // Landing-page crop (public/assets/approval-prompt.png): just the pending prompt post.
  await page.screenshot({ path: join(OUT, 'approval-prompt.png'), clip: { x: rb.x + 2, y: lb.y + 8, width: rb.width - 4, height: 270 } });
  console.log('  ok approval-prompt.png');
  // The guide's image: alice's request, the pending prompt with all six choices, and her
  // one-letter reply typed in the thread box. A prompt resolves the instant the reply is
  // sent (the post is edited in place), so this is the last frame that still shows the choices.
  await page.locator('#reply_textbox').click();
  await page.keyboard.type('A');
  await page.waitForTimeout(400);
  const y0 = fb.y - 24;
  await page.screenshot({ path: join(OUT, 'mattermost-compose-approval.png'), clip: { x: rb.x + 2, y: y0, width: rb.width - 4, height: rb.y + rb.height - 22 - y0 } });
  console.log('  ok mattermost-compose-approval.png');
  await page.keyboard.press('Enter');
  await waitFor(async () => {
    const posts = await threadPosts(root.id);
    const last = posts[posts.length - 1];
    return posts.some(p => /Tool approval resolved/i.test(p.message)) && last.user_id === bot && !/Tool approval/i.test(last.message);
  }, 'the approval to resolve and the bot to finish');
  await page.waitForTimeout(2500);
  await page.mouse.move(640, 880);
  const top = (await posts.first().boundingBox()).y - 24;
  const boxTop = (await page.locator('#reply_textbox').boundingBox()).y;
  await page.screenshot({ path: join(OUT, 'mattermost-compose-approval-resolved.png'), clip: { x: rb.x + 2, y: top, width: rb.width - 4, height: boxTop - 8 - top } });
  console.log('  ok mattermost-compose-approval-resolved.png');
  await ctx.close();
});

await browser.close();
if (failures) { console.error(`${failures} step(s) failed`); process.exit(1); }
console.log('Done.');
