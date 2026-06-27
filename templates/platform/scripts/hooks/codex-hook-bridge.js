#!/usr/bin/env node
/**
 * codex-hook-bridge.js — normalize Codex native hook payloads for Agentboard.
 *
 * Codex project hooks run in the session cwd and send event payloads on stdin.
 * This adapter writes the same session JSON and events.jsonl shapes that the
 * VS Code dashboard already consumes for Claude Code.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { writeSnapshot, deriveSessionId, findProjectRoot } = require('./session-snapshot.js');

const MAX_STDIN = 512 * 1024;

function readPayload() {
  try {
    if (process.stdin.isTTY) return {};
    const raw = fs.readFileSync(0, { encoding: 'utf8' }).slice(0, MAX_STDIN).trim();
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function get(obj, pathExpr) {
  let cur = obj;
  for (const part of pathExpr.split('.')) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = cur[part];
  }
  return cur;
}

function firstString(...values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  }
  return '';
}

function toolName(payload) {
  return firstString(
    payload.tool_name,
    payload.toolName,
    payload.tool,
    payload.name,
    payload.matcher,
    get(payload, 'tool.name'),
    get(payload, 'tool_call.name'),
    get(payload, 'toolCall.name'),
  );
}

function eventName(payload) {
  return firstString(
    process.env.AGENTBOARD_CODEX_HOOK_EVENT,
    payload.hook_event_name,
    payload.hookEventName,
    payload.event,
    payload.event_name,
    payload.type,
  );
}

function filePath(payload) {
  return firstString(
    payload.file_path,
    payload.filePath,
    payload.path,
    get(payload, 'tool_input.file_path'),
    get(payload, 'tool_input.path'),
    get(payload, 'toolInput.file_path'),
    get(payload, 'toolInput.path'),
    get(payload, 'input.file_path'),
    get(payload, 'input.path'),
    get(payload, 'params.file_path'),
    get(payload, 'params.path'),
    get(payload, 'arguments.file_path'),
    get(payload, 'arguments.path'),
  );
}

function command(payload) {
  return firstString(
    payload.command,
    get(payload, 'tool_input.command'),
    get(payload, 'toolInput.command'),
    get(payload, 'input.command'),
    get(payload, 'params.command'),
    get(payload, 'arguments.command'),
  );
}

function label(payload) {
  return firstString(
    payload.label,
    payload.subagent_type,
    payload.subagentType,
    payload.agent_type,
    payload.agentType,
    payload.name,
    get(payload, 'subagent.type'),
    get(payload, 'agent.type'),
  );
}

function runEventLogger(root, payload, env = {}) {
  const hook = path.join(root, '.platform', 'scripts', 'hooks', 'event-logger.sh');
  if (!fs.existsSync(hook)) return;
  spawnSync('bash', [hook], {
    cwd: root,
    input: JSON.stringify(payload),
    stdio: ['pipe', 'ignore', 'ignore'],
    env: {
      ...process.env,
      AGENTBOARD_PROVIDER: 'codex',
      ...env,
    },
    timeout: 3000,
  });
}

function normalizePayload(payload, hookEvent, sessionId) {
  const t = toolName(payload);
  const fp = filePath(payload);
  const cmd = command(payload);
  const out = {
    ...payload,
    hook_event_name: hookEvent,
    session_id: sessionId,
  };

  if (!out.tool_name && t) out.tool_name = t === 'apply_patch' ? 'Edit' : t;
  if (fp && !out.file_path) out.file_path = fp;
  if (cmd && !out.command) out.command = cmd;
  return out;
}

function main() {
  const payload = readPayload();
  const root = findProjectRoot(firstString(payload.cwd, get(payload, 'workspace.current_dir')) || process.cwd());
  const provider = 'codex';
  const sessionId = deriveSessionId(payload, provider);
  const hookEvent = eventName(payload) || 'PostToolUse';

  writeSnapshot(payload, { provider, sessionId, cwd: root });

  if (hookEvent === 'SubagentStart') {
    runEventLogger(root, {
      hook_event_name: hookEvent,
      session_id: sessionId,
      tool_name: 'Agent',
      label: label(payload) || 'sub-agent',
      subagent_type: label(payload) || 'sub-agent',
    }, { AGENTBOARD_HOOK_TYPE: 'agent_start' });
    return;
  }

  if (hookEvent === 'SubagentStop') {
    runEventLogger(root, {
      hook_event_name: hookEvent,
      session_id: sessionId,
      tool_name: 'Agent',
      label: label(payload) || 'sub-agent',
      subagent_type: label(payload) || 'sub-agent',
    }, { AGENTBOARD_HOOK_TYPE: 'agent_done' });
    return;
  }

  if (hookEvent === 'SessionStart' || hookEvent === 'Stop') {
    runEventLogger(root, {
      hook_event_name: hookEvent === 'Stop' ? 'SessionEnd' : 'SessionStart',
      session_id: sessionId,
      provider,
    });
    return;
  }

  runEventLogger(root, normalizePayload(payload, hookEvent, sessionId));
}

try {
  main();
} catch {
  process.exit(0);
}
