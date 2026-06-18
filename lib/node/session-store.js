'use strict';

// session-store.js — SQLite-backed session store via sqlite3 CLI (no npm deps).

const { execSync } = require('child_process');

function sql(dbPath, stmt) {
  return execSync(`sqlite3 "${dbPath}" ${JSON.stringify(stmt)}`, { encoding: 'utf8' }).trim();
}

function sqlRows(dbPath, query) {
  const raw = execSync(
    `sqlite3 -separator '|' "${dbPath}" ${JSON.stringify(query)}`,
    { encoding: 'utf8' }
  ).trim();
  if (!raw) return [];
  return raw.split('\n').map(line => line.split('|'));
}

const COLS = ['id', 'stream_slug', 'role', 'model', 'status',
  'started_at', 'ended_at', 'input_tokens', 'output_tokens', 'cost_usd',
  'worktree_path', 'notes'];

function rowToObj(row) {
  if (!row || row.length === 0) return null;
  const obj = {};
  COLS.forEach((col, i) => { obj[col] = row[i] !== undefined ? row[i] : null; });
  return obj;
}

function initDb(dbPath) {
  sql(dbPath, `CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    stream_slug TEXT,
    role TEXT,
    model TEXT,
    status TEXT DEFAULT 'running',
    started_at TEXT,
    ended_at TEXT,
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    cost_usd REAL DEFAULT 0,
    worktree_path TEXT,
    notes TEXT
  );`);
}

function genId() {
  return `${Date.now()}${Math.floor(Math.random() * 0xffff).toString(16).padStart(4, '0')}`;
}

function nowISO() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function escape(v) {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return String(v);
  return `'${String(v).replace(/'/g, "''")}'`;
}

function createSession(dbPath, { stream_slug, role, model } = {}) {
  const id = genId();
  const started = nowISO();
  sql(dbPath, `INSERT INTO sessions (id, stream_slug, role, model, status, started_at)
    VALUES (${escape(id)}, ${escape(stream_slug)}, ${escape(role)}, ${escape(model)}, 'running', ${escape(started)});`);
  return id;
}

function updateSession(dbPath, id, fields = {}) {
  const allowed = ['stream_slug', 'role', 'model', 'status', 'ended_at',
    'input_tokens', 'output_tokens', 'cost_usd', 'worktree_path', 'notes'];
  const sets = Object.entries(fields)
    .filter(([k]) => allowed.includes(k))
    .map(([k, v]) => `${k} = ${escape(v)}`)
    .join(', ');
  if (!sets) return;
  sql(dbPath, `UPDATE sessions SET ${sets} WHERE id = ${escape(id)};`);
}

function getSession(dbPath, id) {
  const rows = sqlRows(dbPath, `SELECT ${COLS.join(',')} FROM sessions WHERE id = ${escape(id)} LIMIT 1;`);
  return rows.length ? rowToObj(rows[0]) : null;
}

function listSessions(dbPath, { status, limit = 20 } = {}) {
  const where = status ? `WHERE status = ${escape(status)}` : '';
  const rows = sqlRows(dbPath,
    `SELECT ${COLS.join(',')} FROM sessions ${where} ORDER BY started_at DESC LIMIT ${parseInt(limit, 10) || 20};`);
  return rows.map(rowToObj);
}

function endSession(dbPath, id, { status = 'done', input_tokens, output_tokens } = {}) {
  updateSession(dbPath, id, {
    status,
    ended_at: nowISO(),
    ...(input_tokens !== undefined && { input_tokens }),
    ...(output_tokens !== undefined && { output_tokens }),
  });
}

module.exports = { initDb, createSession, updateSession, getSession, listSessions, endSession };
