#!/usr/bin/env node
// agentboard-daemon.js — local HTTP event serializer for multi-provider workflows
// Usage: node agentboard-daemon.js <events-jsonl-path> <port-file-path>
// Zero npm dependencies — only Node built-ins.

'use strict';

const http = require('http');
const fs   = require('fs');

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

const [,, eventsPath, portFilePath] = process.argv;
if (!eventsPath || !portFilePath) {
  process.stderr.write('Usage: agentboard-daemon.js <events-jsonl-path> <port-file-path>\n');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function nowISO() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function eventCount() {
  try {
    const data = fs.readFileSync(eventsPath, 'utf8');
    return data.split('\n').filter(l => l.trim()).length;
  } catch (_) {
    return 0;
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', chunk => {
      size += chunk.length;
      if (size > 65536) {
        reject(new Error('body_too_large'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function send(res, status, body) {
  const payload = typeof body === 'string' ? body : JSON.stringify(body);
  const ct = typeof body === 'string' ? 'text/plain' : 'application/json';
  res.writeHead(status, { 'Content-Type': ct, 'Content-Length': Buffer.byteLength(payload) });
  res.end(payload);
}

function cleanup() {
  try { fs.unlinkSync(portFilePath); } catch (_) {}
}

// ---------------------------------------------------------------------------
// Lock state
// ---------------------------------------------------------------------------

// locks: Map<normalizedPath, {holder, session_id, acquired_at, queue: [{provider, session_id}]}>
const locks = new Map();
const LOCK_TTL_MS = 5 * 60 * 1000; // 5 minutes — auto-expire to prevent deadlock

function normalizePath(p) {
  // Strip leading ./ and normalize slashes
  return p.replace(/^\.\//, '').replace(/\\/g, '/');
}

function expireLocks() {
  const now = Date.now();
  for (const [file, lock] of locks.entries()) {
    if (now - lock.acquired_at > LOCK_TTL_MS) {
      // Grant to next in queue or delete
      if (lock.queue.length > 0) {
        const next = lock.queue.shift();
        locks.set(file, { holder: next.provider, session_id: next.session_id, acquired_at: Date.now(), queue: lock.queue });
      } else {
        locks.delete(file);
      }
    }
  }
}

function saveLocks() {
  try {
    const lockFile = eventsPath.replace('events.jsonl', '.file-locks.json');
    const obj = {};
    for (const [k, v] of locks.entries()) obj[k] = v;
    fs.writeFileSync(lockFile, JSON.stringify(obj, null, 2), 'utf8');
  } catch (_) {}
}

function loadLocks() {
  try {
    const lockFile = eventsPath.replace('events.jsonl', '.file-locks.json');
    const raw = fs.readFileSync(lockFile, 'utf8');
    const obj = JSON.parse(raw);
    for (const [k, v] of Object.entries(obj)) locks.set(k, v);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

function handlePostEvent(req, res) {
  readBody(req).then(raw => {
    const ts = nowISO();
    let line;
    if (!raw.trim()) {
      send(res, 400, 'empty body');
      return;
    }
    try {
      const obj = JSON.parse(raw);
      // Enrich with ts if not already present
      if (!obj.ts) obj.ts = ts;
      line = JSON.stringify(obj);
    } catch (_) {
      // Malformed JSON — wrap raw string
      const escaped = raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
      line = `{"ts":"${ts}","raw":"${escaped}"}`;
    }
    // appendFileSync serializes concurrent writes (the whole point of this daemon)
    fs.appendFileSync(eventsPath, line + '\n', 'utf8');
    send(res, 204, '');
  }).catch(err => {
    if (err.message === 'body_too_large') {
      send(res, 400, 'body exceeds 65536 bytes');
    } else {
      send(res, 500, 'read error');
    }
  });
}

function handleGetEvents(req, res) {
  const url  = new URL(req.url, 'http://localhost');
  const since  = url.searchParams.get('since')  || null;
  const stream = url.searchParams.get('stream') || null;
  const tool   = url.searchParams.get('tool')   || null;
  const rawLimit = parseInt(url.searchParams.get('limit') || '100', 10);
  const limit  = isNaN(rawLimit) ? 100 : Math.min(Math.max(rawLimit, 1), 1000);

  let data;
  try {
    data = fs.readFileSync(eventsPath, 'utf8');
  } catch (_) {
    send(res, 200, []);
    return;
  }

  const results = [];
  for (const line of data.split('\n')) {
    if (!line.trim()) continue;
    let obj;
    try { obj = JSON.parse(line); } catch (_) { continue; }
    if (since  && obj.ts   && obj.ts   < since)  continue;
    if (stream && obj.stream !== stream)           continue;
    if (tool   && obj.tool   !== tool)             continue;
    results.push(obj);
  }

  // Return last `limit` matching events
  send(res, 200, results.slice(-limit));
}

function handleGetHealth(_req, res) {
  send(res, 200, {
    pid:    process.pid,
    uptime: Math.floor(process.uptime()),
    events: eventCount(),
  });
}

function handleShutdown(_req, res) {
  send(res, 200, 'shutting down');
  cleanup();
  // Give the response a tick to flush before exiting
  setImmediate(() => process.exit(0));
}

// POST /lock  body: {file, provider, session_id?}
// 200 = acquired, 202 = queued (body has position)
function handlePostLock(req, res) {
  expireLocks();
  readBody(req).then(raw => {
    let body;
    try { body = JSON.parse(raw); } catch (_) { send(res, 400, 'invalid JSON'); return; }
    const file = normalizePath(body.file || '');
    const provider = body.provider || 'unknown';
    const session_id = body.session_id || provider;
    if (!file) { send(res, 400, 'file required'); return; }

    const existing = locks.get(file);
    if (!existing) {
      locks.set(file, { holder: provider, session_id, acquired_at: Date.now(), queue: [] });
      saveLocks();
      send(res, 200, { status: 'acquired', file, holder: provider });
    } else if (existing.holder === provider || existing.session_id === session_id) {
      // Same provider re-acquiring (idempotent)
      send(res, 200, { status: 'acquired', file, holder: provider });
    } else {
      // Queued — add if not already in queue
      const alreadyQueued = existing.queue.some(q => q.provider === provider);
      if (!alreadyQueued) existing.queue.push({ provider, session_id });
      saveLocks();
      send(res, 202, { status: 'queued', file, holder: existing.holder, position: existing.queue.length });
    }
  }).catch(() => send(res, 500, 'read error'));
}

// DELETE /lock  body: {file, provider}
function handleDeleteLock(req, res) {
  expireLocks();
  readBody(req).then(raw => {
    let body;
    try { body = JSON.parse(raw); } catch (_) { send(res, 400, 'invalid JSON'); return; }
    const file = normalizePath(body.file || '');
    const provider = body.provider || 'unknown';
    if (!file) { send(res, 400, 'file required'); return; }

    const existing = locks.get(file);
    if (!existing || existing.holder !== provider) {
      send(res, 200, { status: 'released', file }); // idempotent
      return;
    }
    if (existing.queue.length > 0) {
      const next = existing.queue.shift();
      locks.set(file, { holder: next.provider, session_id: next.session_id, acquired_at: Date.now(), queue: existing.queue });
    } else {
      locks.delete(file);
    }
    saveLocks();
    send(res, 200, { status: 'released', file });
  }).catch(() => send(res, 500, 'read error'));
}

// GET /locks
function handleGetLocks(_req, res) {
  expireLocks();
  const result = [];
  for (const [file, lock] of locks.entries()) {
    result.push({
      file,
      holder: lock.holder,
      acquired_at: new Date(lock.acquired_at).toISOString(),
      held_seconds: Math.floor((Date.now() - lock.acquired_at) / 1000),
      queue: lock.queue.map(q => q.provider),
    });
  }
  send(res, 200, result);
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

const server = http.createServer((req, res) => {
  try {
    const urlPath = req.url.split('?')[0];
    if (req.method === 'POST' && urlPath === '/event') {
      handlePostEvent(req, res);
    } else if (req.method === 'GET' && urlPath === '/events') {
      handleGetEvents(req, res);
    } else if (req.method === 'GET' && urlPath === '/health') {
      handleGetHealth(req, res);
    } else if (req.method === 'GET' && urlPath === '/shutdown') {
      handleShutdown(req, res);
    } else if (req.method === 'POST' && urlPath === '/lock') {
      handlePostLock(req, res);
    } else if (req.method === 'DELETE' && urlPath === '/lock') {
      handleDeleteLock(req, res);
    } else if (req.method === 'GET' && urlPath === '/locks') {
      handleGetLocks(req, res);
    } else {
      send(res, 404, 'not found');
    }
  } catch (err) {
    try { send(res, 500, 'internal error'); } catch (_) {}
  }
});

server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  // Write port file AFTER bind — this is the signal to the shell watcher
  fs.writeFileSync(portFilePath, String(port), 'utf8');
  process.stderr.write(`agentboard-daemon listening on port ${port} (pid ${process.pid})\n`);
  loadLocks();
});

process.on('SIGTERM', () => { cleanup(); server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { cleanup(); server.close(() => process.exit(0)); });
