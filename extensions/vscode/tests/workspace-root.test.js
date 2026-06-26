#!/usr/bin/env node
/**
 * workspace-root.test.js
 *
 * Tests project root detection for the dashboard.
 *
 * Run:
 *   cd extensions/vscode
 *   npm run compile
 *   node tests/workspace-root.test.js
 */

'use strict';

const path = require('path');
const {
  detectWorkspaceRootFromFolders,
  detectWorkspaceRootFromGlobalLive,
  detectWorkspaceRootFromSources,
} = require('../out/workspaceRoot.js');

let passed = 0;
let failed = 0;

function assertEqual(a, b, msg) {
  if (a === b) {
    console.log('  PASS:', msg);
    passed++;
  } else {
    console.error('  FAIL:', msg + ' — expected ' + b + ', got ' + a);
    failed++;
  }
}

const home = '/tmp/home';
const agentboardRoot = '/repo/agentboard';
const staleOtherRoot = '/repo/vibe-music-ai';
const nowMs = Date.parse('2026-06-26T16:30:00Z');

const existing = new Set([
  path.join(agentboardRoot, '.platform'),
  path.join(agentboardRoot, '.platform', 'work'),
  path.join(staleOtherRoot, '.platform'),
]);

const exists = (filePath) => existing.has(filePath);
const readFile = (filePath) => {
  if (filePath === path.join(home, '.agentboard', 'live.json')) {
    return JSON.stringify({
      _root: staleOtherRoot,
      last_updated: '2026-06-26T16:29:00Z',
    });
  }
  throw new Error('unexpected read: ' + filePath);
};

console.log('\n[1] Workspace folders win over global live pointer');
assertEqual(
  detectWorkspaceRootFromSources([agentboardRoot], { homeDir: home, nowMs, exists, readFile }),
  agentboardRoot,
  'open Agentboard workspace is not hijacked by recent live.json from another project'
);

console.log('\n[2] Global live remains fallback when no workspace has Agentboard evidence');
assertEqual(
  detectWorkspaceRootFromSources(['/repo/plain'], { homeDir: home, nowMs, exists, readFile }),
  staleOtherRoot,
  'recent live.json is used when workspace folders do not look like Agentboard projects'
);

console.log('\n[3] Workspace scoring ignores folders with no Agentboard evidence');
assertEqual(
  detectWorkspaceRootFromFolders(['/repo/plain'], exists),
  '',
  'plain workspace does not become dashboard root'
);

console.log('\n[4] Stale global live is ignored');
const staleLive = () => JSON.stringify({
  _root: staleOtherRoot,
  last_updated: '2026-06-26T11:00:00Z',
});
assertEqual(
  detectWorkspaceRootFromGlobalLive({ homeDir: home, nowMs, exists, readFile: staleLive }),
  '',
  'global live older than four hours is ignored'
);

console.log('\n' + '-'.repeat(50));
console.log(`Result: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
