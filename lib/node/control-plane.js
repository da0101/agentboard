#!/usr/bin/env node
'use strict';

// control-plane.js — agentboard Node.js control plane HTTP server.
// Zero npm dependencies — built-ins only.

const http = require('http');
const fs   = require('fs');
const path = require('path');

const store    = require('./session-store');
const hud      = require('./hud-writer');
const worktree = require('./worktree-manager');
const delegate = require('./delegation-router');

const PORT        = parseInt(process.env.AGENTBOARD_PORT || '7842', 10);
const HOME        = process.env.HOME || require('os').homedir();
const DB_DIR      = path.join(HOME, '.agentboard');
const DB_PATH     = path.join(DB_DIR, 'sessions.db');
const PID_FILE    = path.join(DB_DIR, 'control-plane.pid');
const REPO_ROOT   = process.env.AGENTBOARD_REPO_ROOT || process.cwd();
const VERSION     = '1.0.0';

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

fs.mkdirSync(DB_DIR, { recursive: true });
store.initDb(DB_PATH);
fs.writeFileSync(PID_FILE, String(process.pid), 'utf8');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function send(res, status, body) {
  const payload = typeof body === 'string' ? body : JSON.stringify(body);
  const ct = typeof body === 'string' ? 'text/plain' : 'application/json';
  res.writeHead(status, { 'Content-Type': ct, 'Content-Length': Buffer.byteLength(payload) });
  res.end(payload);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => { try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}

function refreshHud() {
  try {
    const running = store.listSessions(DB_PATH, { status: 'running', limit: 50 });
    hud.writeHud(REPO_ROOT, {
      active_agents: running.map(s => ({
        label:      s.role || s.stream_slug || s.id,
        objective:  s.stream_slug || '',
        phase:      'running',
        started_at: s.started_at || new Date().toISOString(),
      })),
    });
  } catch (_) {}
}

function cleanup() {
  try { fs.unlinkSync(PID_FILE); } catch (_) {}
}

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

function handleStatus(res) {
  const sessions  = store.listSessions(DB_PATH, { limit: 9999 });
  const worktrees = worktree.listWorktrees(REPO_ROOT);
  send(res, 200, { running: true, version: VERSION, sessions_count: sessions.length, worktrees_count: worktrees.length });
}

function handleGetSessions(res) {
  send(res, 200, { sessions: store.listSessions(DB_PATH) });
}

async function handleCreateSession(req, res) {
  const body = await readBody(req);
  const id = store.createSession(DB_PATH, { stream_slug: body.stream_slug, role: body.role, model: body.model });
  refreshHud();
  send(res, 201, { id });
}

async function handleUpdateSession(req, res, id) {
  const body = await readBody(req);
  store.updateSession(DB_PATH, id, body);
  refreshHud();
  send(res, 200, { ok: true });
}

function handleDeleteSession(res, id) {
  store.endSession(DB_PATH, id);
  refreshHud();
  send(res, 200, { ok: true });
}

function handleGetWorktrees(res) {
  send(res, 200, { worktrees: worktree.listWorktrees(REPO_ROOT) });
}

async function handleCreateWorktree(req, res) {
  const body = await readBody(req);
  const result = worktree.createWorktree(REPO_ROOT, { streamSlug: body.stream_slug, baseBranch: body.base_branch });
  if (!result) { send(res, 500, { error: 'worktree creation failed' }); return; }
  send(res, 201, result);
}

async function handleDelegate(req, res) {
  const body = await readBody(req);
  if (!body.task) { send(res, 400, { error: 'task required' }); return; }
  const role   = delegate.matchRole(body.task);
  const prompt = delegate.buildDelegationPrompt(body.task, role, { streamSlug: body.stream_slug, worktreePath: body.worktree_path });
  send(res, 200, { role, prompt, suggest_worktree: delegate.suggestWorktree(role.slug) });
}

async function handleHud(req, res) {
  const body = await readBody(req);
  hud.writeHud(REPO_ROOT, body);
  send(res, 200, { ok: true });
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

const server = http.createServer(async (req, res) => {
  try {
    const urlPath = req.url.split('?')[0];
    const method  = req.method;
    const sessionMatch = urlPath.match(/^\/sessions\/(.+)$/);

    if (method === 'GET'    && urlPath === '/status')    return handleStatus(res);
    if (method === 'GET'    && urlPath === '/sessions')  return handleGetSessions(res);
    if (method === 'POST'   && urlPath === '/sessions')  return handleCreateSession(req, res);
    if (method === 'PATCH'  && sessionMatch)             return handleUpdateSession(req, res, sessionMatch[1]);
    if (method === 'DELETE' && sessionMatch)             return handleDeleteSession(res, sessionMatch[1]);
    if (method === 'GET'    && urlPath === '/worktrees') return handleGetWorktrees(res);
    if (method === 'POST'   && urlPath === '/worktrees') return handleCreateWorktree(req, res);
    if (method === 'POST'   && urlPath === '/delegate')  return handleDelegate(req, res);
    if (method === 'POST'   && urlPath === '/hud')       return handleHud(req, res);
    send(res, 404, 'not found');
  } catch (err) {
    try { send(res, 500, { error: err.message }); } catch (_) {}
  }
});

server.listen(PORT, '127.0.0.1', () => {
  process.stderr.write(`agentboard-control-plane listening on port ${PORT} (pid ${process.pid})\n`);
});

process.on('SIGTERM', () => { cleanup(); server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { cleanup(); server.close(() => process.exit(0)); });
