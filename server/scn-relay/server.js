const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.SCN_RELAY_PORT || 53319);
const HOST_TTL_MS = Number(process.env.SCN_HOST_TTL_MS || 45_000);
const SESSION_TTL_MS = Number(process.env.SCN_SESSION_TTL_MS || 10 * 60_000);
const RELAY_ID = process.env.SCN_RELAY_ID || 'de';
const RELAY_REGION = process.env.SCN_RELAY_REGION || 'eu';
const PUBLIC_BASE_URL = process.env.SCN_PUBLIC_BASE_URL || `http://5.187.4.132:${PORT}`;
const TURN_USERNAME = process.env.SCN_TURN_USERNAME || 'scn';
const TURN_CREDENTIAL = process.env.SCN_TURN_CREDENTIAL || '';
const TURN_HOST = process.env.SCN_TURN_HOST || '5.187.4.132';
const UPDATES_DIR = process.env.SCN_UPDATES_DIR || path.join(__dirname, 'updates');

const hosts = new Map();
const hostCodes = new Map();
const sessions = new Map();

function id(bytes = 16) {
  return crypto.randomBytes(bytes).toString('hex');
}

function nowIso() {
  return new Date().toISOString();
}

function iceServers() {
  const servers = [
    { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] },
    { urls: [`stun:${TURN_HOST}:3478`] },
  ];
  if (TURN_CREDENTIAL) {
    servers.push({
      urls: [`turn:${TURN_HOST}:3478?transport=udp`, `turn:${TURN_HOST}:3478?transport=tcp`],
      username: TURN_USERNAME,
      credential: TURN_CREDENTIAL,
    });
  }
  return servers;
}

function send(ws, type, payload = {}) {
  if (!ws || ws.readyState !== ws.OPEN) return false;
  ws.send(JSON.stringify({ type, payload }));
  return true;
}

function prune() {
  const cutoff = Date.now();
  for (const [deviceId, host] of hosts) {
    if (host.expiresAt <= cutoff || host.ws.readyState !== host.ws.OPEN) {
      hosts.delete(deviceId);
      if (host.code) hostCodes.delete(host.code);
    }
  }
  for (const [sessionId, session] of sessions) {
    if (session.expiresAt <= cutoff) {
      send(session.hostWs, 'rdBye', { relaySessionId: sessionId, reason: 'expired' });
      send(session.viewerWs, 'rdBye', { relaySessionId: sessionId, reason: 'expired' });
      sessions.delete(sessionId);
    }
  }
}

function publicHosts() {
  prune();
  return [...hosts.values()].map((host) => ({
    deviceId: host.deviceId,
    code: host.code,
    alias: host.alias,
    online: true,
    updatedAt: new Date(host.updatedAt).toISOString(),
    expiresAt: new Date(host.expiresAt).toISOString(),
  }));
}

function contentTypeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.json') return 'application/json; charset=utf-8';
  if (ext === '.zip') return 'application/zip';
  if (ext === '.txt' || ext === '.md') return 'text/plain; charset=utf-8';
  return 'application/octet-stream';
}

function serveUpdateFile(req, res, urlPath) {
  // Only allow /scn/<safe-filename>
  const rel = decodeURIComponent(urlPath.replace(/^\/scn\//, ''));
  if (!rel || rel.includes('..') || path.isAbsolute(rel) || rel.includes('/') || rel.includes('\\')) {
    res.writeHead(400, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'bad_path' }));
    return;
  }
  const filePath = path.join(UPDATES_DIR, rel);
  if (!filePath.startsWith(UPDATES_DIR)) {
    res.writeHead(400, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'bad_path' }));
    return;
  }
  fs.stat(filePath, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not_found' }));
      return;
    }
    res.writeHead(200, {
      'content-type': contentTypeFor(filePath),
      'content-length': st.size,
      'cache-control': 'no-cache',
      'access-control-allow-origin': '*',
    });
    fs.createReadStream(filePath).pipe(res);
  });
}

const server = http.createServer((req, res) => {
  const urlPath = (req.url || '').split('?')[0];

  if (req.method === 'GET' && urlPath === '/api/v1/health') {
    const body = JSON.stringify({
      ok: true,
      service: 'scn-relay',
      id: RELAY_ID,
      region: RELAY_REGION,
      timestamp: nowIso(),
      hosts: publicHosts().length,
      sessions: sessions.size,
      updatesDir: UPDATES_DIR,
    });
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(body);
    return;
  }

  if (req.method === 'GET' && urlPath === '/api/v1/config') {
    const body = JSON.stringify({
      ok: true,
      timestamp: nowIso(),
      relay: {
        id: RELAY_ID,
        region: RELAY_REGION,
        httpUrl: PUBLIC_BASE_URL,
        wsUrl: PUBLIC_BASE_URL.replace(/^http/, 'ws') + '/ws',
      },
      update: {
        manifestUrl: `${PUBLIC_BASE_URL}/scn/update.json`,
      },
      iceServers: iceServers(),
    });
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(body);
    return;
  }

  if (req.method === 'GET' && urlPath === '/api/v1/rd/hosts') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ hosts: publicHosts() }));
    return;
  }

  if (req.method === 'GET' && urlPath === '/api/v1/rd/lookup') {
    const u = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
    const codeRaw = String(u.searchParams.get('code') || '').replace(/\D/g, '');
    prune();
    let found = null;
    if (codeRaw) {
      for (const host of hosts.values()) {
        const c = String(host.code || '').replace(/\D/g, '');
        if (c === codeRaw || c === codeRaw.padStart(9, '0')) {
          found = host;
          break;
        }
      }
      if (!found && hostCodes.has(codeRaw)) {
        found = hosts.get(hostCodes.get(codeRaw));
      }
      if (!found && hostCodes.has(codeRaw.padStart(9, '0'))) {
        found = hosts.get(hostCodes.get(codeRaw.padStart(9, '0')));
      }
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      found: !!found,
      id: RELAY_ID,
      region: RELAY_REGION,
      host: found
        ? {
            deviceId: found.deviceId,
            code: found.code,
            alias: found.alias,
          }
        : null,
    }));
    return;
  }

  if (req.method === 'GET' && urlPath.startsWith('/scn/')) {
    serveUpdateFile(req, res, urlPath);
    return;
  }

  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
});

const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  let role = null;
  let deviceId = null;

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch (_) {
      send(ws, 'error', { reason: 'invalid_json' });
      return;
    }
    const type = msg.type;
    const payload = msg.payload || {};

    if (type === 'hello') {
      role = payload.role;
      deviceId = String(payload.deviceId || '').trim();
      if (!role || !deviceId) {
        send(ws, 'error', { reason: 'missing_hello_fields' });
        ws.close();
        return;
      }

      if (role === 'rdHost') {
        const alias = String(payload.alias || 'SCN Host');
        const code = String(payload.code || '').replace(/\D/g, '');
        hosts.set(deviceId, {
          deviceId,
          code,
          alias,
          ws,
          updatedAt: Date.now(),
          expiresAt: Date.now() + HOST_TTL_MS,
        });
        if (code) hostCodes.set(code, deviceId);
      }

      send(ws, 'welcome', {
        role,
        deviceId,
        iceServers: iceServers(),
        serverTime: nowIso(),
      });
      return;
    }

    if (!role || !deviceId) {
      send(ws, 'error', { reason: 'hello_required_first' });
      ws.close();
      return;
    }

    if (type === 'ping') {
      if (role === 'rdHost') {
        const host = hosts.get(deviceId);
        if (host && host.ws === ws) {
          host.updatedAt = Date.now();
          host.expiresAt = Date.now() + HOST_TTL_MS;
        }
      }
      send(ws, 'pong', { serverTime: nowIso() });
      return;
    }

    if (type === 'rdRequest' && role === 'rdViewer') {
      const targetDeviceId = String(payload.targetDeviceId || '').trim();
      const normalizedCode = targetDeviceId.replace(/\D/g, '');
      const resolvedDeviceId = hosts.has(targetDeviceId)
        ? targetDeviceId
        : hostCodes.get(normalizedCode);
      const host = resolvedDeviceId ? hosts.get(resolvedDeviceId) : null;
      if (!host || host.ws.readyState !== host.ws.OPEN) {
        send(ws, 'rdResponse', {
          requestId: payload.requestId,
          response: { status: 'rejected', errorMessage: 'Host is offline on relay' },
        });
        return;
      }

      const relaySessionId = id(12);
      sessions.set(relaySessionId, {
        relaySessionId,
        hostDeviceId: resolvedDeviceId,
        viewerDeviceId: deviceId,
        hostWs: host.ws,
        viewerWs: ws,
        expiresAt: Date.now() + SESSION_TTL_MS,
      });

      send(host.ws, 'rdRequest', {
        requestId: payload.requestId,
        relaySessionId,
        viewerDeviceId: deviceId,
        viewerAlias: payload.viewerAlias || 'SCN Viewer',
        request: payload.request || {},
        iceServers: iceServers(),
      });
      return;
    }

    if (type === 'rdResponse' && role === 'rdHost') {
      const session = sessions.get(payload.relaySessionId);
      if (!session || session.hostWs !== ws) return;
      send(session.viewerWs, 'rdResponse', payload);
      return;
    }

    if (type === 'rdSignal') {
      const session = sessions.get(payload.relaySessionId);
      if (!session) return;
      const target = ws === session.hostWs ? session.viewerWs : session.hostWs;
      send(target, 'rdSignal', payload);
      return;
    }

    if (type === 'rdBye') {
      const session = sessions.get(payload.relaySessionId);
      if (!session) return;
      const target = ws === session.hostWs ? session.viewerWs : session.hostWs;
      send(target, 'rdBye', payload);
      sessions.delete(payload.relaySessionId);
    }
  });

  ws.on('close', () => {
    if (role === 'rdHost' && deviceId) {
      const host = hosts.get(deviceId);
      if (host && host.ws === ws) {
        hosts.delete(deviceId);
        if (host.code) hostCodes.delete(host.code);
      }
    }
    for (const [sessionId, session] of sessions) {
      if (session.hostWs === ws || session.viewerWs === ws) {
        const target = session.hostWs === ws ? session.viewerWs : session.hostWs;
        send(target, 'rdBye', { relaySessionId: sessionId, reason: 'peer_closed' });
        sessions.delete(sessionId);
      }
    }
  });
});

setInterval(prune, 10_000).unref();

server.listen(PORT, '0.0.0.0', () => {
  console.log(`SCN relay listening on ${PORT}`);
});
