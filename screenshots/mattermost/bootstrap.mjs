#!/usr/bin/env node
// Bootstraps a fresh mattermost-preview the same way the netclaw repo's Aspire
// demo does: first user (auto system-admin), team, bot + access token, channel,
// and a non-admin test user. Writes the resulting IDs/token/credentials to
// .bootstrap.json for run.sh (netclaw config) and capture.mjs (Playwright).
//
// Usage: node bootstrap.mjs [serverUrl]   (default http://localhost:8065)

import { writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const SERVER = (process.argv[2] || 'http://localhost:8065').replace(/\/$/, '');
const __dirname = dirname(fileURLToPath(import.meta.url));

const ADMIN = { email: 'admin@test.local', username: 'admin', password: 'Admin1234!' };
const USER = { email: 'testuser@test.local', username: 'testuser', password: 'TestUser1234!' };
const TEAM = { name: 'test-team', display_name: 'Test Team', type: 'O' };
const CHANNEL = { name: 'test-channel', display_name: 'Test Channel', type: 'O' };
const BOT = { username: 'netclaw', display_name: 'Netclaw' };

let adminToken = null;

async function api(method, path, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(`${SERVER}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 300)}`);
  }
  return { json: text ? JSON.parse(text) : {}, headerToken: res.headers.get('Token') };
}

async function waitForPing() {
  for (let i = 0; i < 90; i++) {
    try {
      const res = await fetch(`${SERVER}/api/v4/system/ping`);
      if (res.ok) return;
    } catch {}
    await new Promise(r => setTimeout(r, 2000));
  }
  throw new Error('Mattermost did not become ready in time');
}

async function main() {
  console.log(`==> Waiting for Mattermost at ${SERVER} ...`);
  await waitForPing();

  console.log('==> Creating admin (first user is auto-promoted to system admin)');
  const admin = (await api('POST', '/api/v4/users', ADMIN)).json;

  console.log('==> Logging in as admin');
  adminToken = (await api('POST', '/api/v4/users/login', { login_id: ADMIN.username, password: ADMIN.password })).headerToken;
  if (!adminToken) throw new Error('No admin token returned from login');

  console.log('==> Enabling bot accounts + access tokens via the System Console config');
  // Done via the config API (not env vars) so the System Console shows these as
  // editable toggles in the screenshot rather than "set through an environment variable".
  const cfg = (await api('GET', '/api/v4/config', null, adminToken)).json;
  cfg.ServiceSettings.EnableBotAccountCreation = true;
  cfg.ServiceSettings.EnableUserAccessTokens = true;
  await api('PUT', '/api/v4/config', cfg, adminToken);

  console.log('==> Creating team');
  const team = (await api('POST', '/api/v4/teams', TEAM, adminToken)).json;

  console.log('==> Creating bot account');
  const bot = (await api('POST', '/api/v4/bots', BOT, adminToken)).json;

  console.log('==> Issuing bot access token');
  const tok = (await api('POST', `/api/v4/users/${bot.user_id}/tokens`, { description: 'netclaw-bootstrap-token' }, adminToken)).json;

  console.log('==> Adding bot to team');
  await api('POST', `/api/v4/teams/${team.id}/members`, { team_id: team.id, user_id: bot.user_id }, adminToken);

  console.log('==> Creating channel');
  const channel = (await api('POST', '/api/v4/channels', { team_id: team.id, ...CHANNEL }, adminToken)).json;

  console.log('==> Adding bot to channel');
  await api('POST', `/api/v4/channels/${channel.id}/members`, { user_id: bot.user_id }, adminToken);

  console.log('==> Creating test user');
  const user = (await api('POST', '/api/v4/users', USER)).json;
  await api('POST', `/api/v4/teams/${team.id}/members`, { team_id: team.id, user_id: user.id }, adminToken);
  await api('POST', `/api/v4/channels/${channel.id}/members`, { user_id: user.id }, adminToken);

  const out = {
    serverUrl: SERVER,
    admin: { ...ADMIN, id: admin.id },
    testuser: { ...USER, id: user.id },
    team: { id: team.id, name: team.name },
    channel: { id: channel.id, name: channel.name },
    bot: { userId: bot.user_id, username: bot.username, token: tok.token },
  };
  writeFileSync(join(__dirname, '.bootstrap.json'), JSON.stringify(out, null, 2));
  console.log(`\n✅ Bootstrap complete. channel=${channel.id} bot=${bot.user_id}`);
  console.log(`   Wrote ${join(__dirname, '.bootstrap.json')}`);
}

main().catch(err => { console.error('❌ Bootstrap failed:', err.message); process.exit(1); });
