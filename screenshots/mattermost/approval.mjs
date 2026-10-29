#!/usr/bin/env node
// Captures the landing page's approval prompt (public/assets/approval-prompt.png): the thread
// post that netclaw sends when shell_execute needs approval, with its buttons, framed by
// frame-approval.mjs. Runs in the Playwright container (run.sh with SCRIPTED_APPROVAL=1).
//
// Env: BOOTSTRAP_FILE, OUT_DIR, REPLY_TIMEOUT_SECONDS (default 120)
import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { frame } from './frame-approval.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const boot = JSON.parse(readFileSync(process.env.BOOTSTRAP_FILE || join(__dirname, '.bootstrap.json'), 'utf8'));
const OUT = process.env.OUT_DIR || join(__dirname, '..', 'output');
const TIMEOUT_MS = Number(process.env.REPLY_TIMEOUT_SECONDS || 120) * 1000;
const BASE = boot.serverUrl;
mkdirSync(OUT, { recursive: true });

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

const login = await api('POST', '/users/login', { login_id: boot.testuser.username, password: boot.testuser.password });
const token = login.headers.get('Token');
const me = await login.json();
await api('PUT', `/users/${me.id}/preferences`, [
  { user_id: me.id, category: 'theme', name: '', value: JSON.stringify(ONYX) },
  { user_id: me.id, category: 'tutorial_step', name: me.id, value: '999' },
  { user_id: me.id, category: 'onboarding_task_list', name: 'onboarding_task_list_show', value: 'false' },
  { user_id: me.id, category: 'recommended_next_steps', name: 'hide', value: 'true' },
], token);

const root = await (await api('POST', '/posts', { channel_id: boot.channel.id, message: '@netclaw push the website changes' }, token)).json();
const thread = async () => {
  const d = await (await api('GET', `/posts/${root.id}/thread`, null, token)).json();
  return d.order.map(id => d.posts[id]).sort((a, b) => a.create_at - b.create_at);
};
let prompt;
for (const t0 = Date.now(); Date.now() - t0 < TIMEOUT_MS && !prompt; await new Promise(r => setTimeout(r, 2000)))
  prompt = (await thread()).find(p => p.user_id === boot.bot.userId && /Tool approval required/i.test(p.message));
if (!prompt) { console.error('no approval prompt within the timeout'); process.exit(1); }
const actions = (prompt.props?.attachments?.[0]?.actions || []).map(a => a.name);
console.log('prompt text:\n' + prompt.message + '\nbuttons: ' + JSON.stringify(actions));
if (!actions.length) { console.error('the prompt has no buttons; CallbackUrl is not taking effect'); process.exit(1); }

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, colorScheme: 'dark' });
await ctx.addInitScript(() => { try { localStorage.setItem('__landingPageSeen__', 'true'); localStorage.setItem('onboarding_complete', 'true'); } catch {} });
const page = await ctx.newPage();
await page.goto(`${BASE}/login`, { waitUntil: 'networkidle' });
for (const rx of [/view in browser/i, /continue in browser/i]) {
  try { const l = page.getByText(rx).first(); if (await l.isVisible({ timeout: 1500 })) { await l.click(); break; } } catch {}
}
await page.waitForSelector('input[type="password"]', { timeout: 30000 });
await page.locator('input[type="text"], input[type="email"]').first().fill(boot.testuser.username);
await page.locator('input[type="password"]').first().fill(boot.testuser.password);
await page.getByRole('button', { name: /log in|sign in/i }).first().click();
await page.waitForURL(u => !/\/login/.test(new URL(u).pathname), { timeout: 20000 });
await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

await page.goto(`${BASE}/${boot.team.name}/pl/${root.id}`, { waitUntil: 'networkidle' });
await page.waitForTimeout(2500);
await page.getByRole('button', { name: /\d+ repl(y|ies)/i }).last().click();
await page.waitForTimeout(2500);
await page.getByRole('button', { name: /expand/i }).first().click();   // widen the panel so the buttons fit one row
await page.waitForTimeout(1500);
await page.mouse.move(640, 880);
await page.addStyleTag({ content: '.NotificationSeparator{display:none !important}' });   // the "New Messages" line
await page.waitForTimeout(500);
const post = page.locator(`#sidebar-right #post_${prompt.id}, #sidebar-right [id$="${prompt.id}"]`).first();
await post.waitFor({ timeout: 15000 });
await page.screenshot({ path: join(OUT, '_approval-full.png') });
const raw = join(OUT, '_approval-raw.png');
await post.screenshot({ path: raw });
await frame(browser, raw, join(OUT, 'approval-prompt.png'));
await browser.close();
console.log('  ok approval-prompt.png');
