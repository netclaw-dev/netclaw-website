#!/usr/bin/env node
// Forwards 0.0.0.0:LISTEN to 127.0.0.1:TARGET inside the netclawd network namespace.
// The daemon's default `local` exposure mode binds loopback only, so Mattermost (another
// container) can't reach /api/mattermost/actions directly. This sidecar is the "forwarder"
// the Mattermost channel docs describe; the daemon still sees loopback traffic.
// Env: LISTEN (5299), TARGET (5199)
import net from 'net';
const LISTEN = Number(process.env.LISTEN || 5299), TARGET = Number(process.env.TARGET || 5199);
net.createServer(c => {
  const u = net.connect(TARGET, '127.0.0.1');
  c.pipe(u).pipe(c);
  const end = () => { c.destroy(); u.destroy(); };
  c.on('error', end); u.on('error', end);
}).listen(LISTEN, '0.0.0.0', () => console.log(`forwarding :${LISTEN} -> 127.0.0.1:${TARGET}`));
