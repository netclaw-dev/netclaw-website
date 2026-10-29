#!/usr/bin/env node
// Posts an @netclaw message as the test user, then waits until the bot replies.
// Exits non-zero if no reply arrives in time (the daemon or inference is broken).
// Runs in the Playwright container (run.sh).
//
// Usage: node post-message.mjs ["message text"]
// Env:   BOOTSTRAP_FILE (default ./.bootstrap.json), REPLY_TIMEOUT_SECONDS (default 300)

import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const boot = JSON.parse(readFileSync(process.env.BOOTSTRAP_FILE || join(__dirname, '.bootstrap.json'), 'utf8'));
const MESSAGE = process.argv[2] || '@netclaw hey! In one sentence, what are you and what can you help with?';
const TIMEOUT_MS = Number(process.env.REPLY_TIMEOUT_SECONDS || 300) * 1000;

async function api(method, path, body, token) {
  const res = await fetch(`${boot.serverUrl}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res;
}

const login = await api('POST', '/api/v4/users/login', { login_id: boot.testuser.username, password: boot.testuser.password });
const userToken = login.headers.get('Token');
await api('POST', '/api/v4/posts', { channel_id: boot.channel.id, message: MESSAGE }, userToken);
console.log(`posted: ${MESSAGE}`);

const start = Date.now();
while (Date.now() - start < TIMEOUT_MS) {
  const data = await (await api('GET', `/api/v4/channels/${boot.channel.id}/posts`, null, boot.bot.token)).json();
  const reply = data.order.map(id => data.posts[id]).find(p => p.user_id === boot.bot.userId && p.root_id && p.message);
  if (reply) {
    console.log(`bot replied after ${Math.round((Date.now() - start) / 1000)}s: ${reply.message.slice(0, 200).replace(/\s+/g, ' ')}`);
    process.exit(0);
  }
  await new Promise(r => setTimeout(r, 3000));
}
console.error(`no bot reply within ${TIMEOUT_MS / 1000}s`);
process.exit(1);
