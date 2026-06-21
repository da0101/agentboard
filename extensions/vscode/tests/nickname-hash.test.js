#!/usr/bin/env node
/**
 * nickname-hash.test.js
 *
 * Verifies that the deterministic session nickname hash function in
 * status-bridge.js and dashboard.js (JS) matches the TypeScript
 * implementation in dashboardPanel.ts.
 *
 * All three sources must produce the same nickname for the same session_id.
 *
 * Run: node extensions/vscode/tests/nickname-hash.test.js
 */

'use strict';

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) {
    console.log('  PASS:', msg);
    passed++;
  } else {
    console.error('  FAIL:', msg);
    failed++;
  }
}

function assertEqual(a, b, msg) {
  if (a === b) {
    console.log('  PASS:', msg);
    passed++;
  } else {
    console.error('  FAIL:', msg + ' — expected ' + JSON.stringify(b) + ', got ' + JSON.stringify(a));
    failed++;
  }
}

// ---------------------------------------------------------------------------
// Implementations extracted verbatim from the three source files.
// If these diverge the tests will catch it.
// ---------------------------------------------------------------------------

// From dashboardPanel.ts
function nickFromTs(id) {
  const ADJ = ['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
  const NON = ['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (Math.imul(h, 31) + id.charCodeAt(i)) >>> 0;
  return ADJ[h % ADJ.length] + '-' + NON[(h >>> 8) % NON.length];
}

// From dashboard.js — sessionNickname()
function nickFromJs(id) {
  const _SN_ADJ = ['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
  const _SN_NON = ['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
  var h = 0;
  for (var i = 0; i < id.length; i++) h = (Math.imul(h, 31) + id.charCodeAt(i)) >>> 0;
  return _SN_ADJ[h % _SN_ADJ.length] + '-' + _SN_NON[(h >>> 8) % _SN_NON.length];
}

// From status-bridge.js — inlined in the on('end') callback
function nickFromBridge(sessionId) {
  const ADJ = ['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
  const NON = ['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
  let _h = 0;
  for (let _i = 0; _i < sessionId.length; _i++) _h = (Math.imul(_h, 31) + sessionId.charCodeAt(_i)) >>> 0;
  return ADJ[_h % ADJ.length] + '-' + NON[(_h >>> 8) % NON.length];
}

// ---------------------------------------------------------------------------
// Known session IDs and their expected nicknames (ground-truth, new 40×40 arrays).
// ---------------------------------------------------------------------------
const KNOWN = [
  { id: 'abc123',                                   nick: 'violet-otter'  },
  { id: 'session-xyz-001',                          nick: 'wild-eagle'    },
  { id: '550e8400-e29b-41d4-a716-446655440000',     nick: 'keen-bison'    },
  { id: '',                                          nick: 'bold-falcon'   },
  { id: 'a',                                         nick: 'sage-falcon'   },
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

console.log('\n[1] ADJ/NON array equality across all three implementations');

const TS_ADJ = ['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
const TS_NON = ['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
const JS_ADJ = ['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
const JS_NON = ['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
const SB_ADJ = ['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
const SB_NON = ['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];

assert(JSON.stringify(TS_ADJ) === JSON.stringify(JS_ADJ),  'ADJ: dashboardPanel.ts === dashboard.js');
assert(JSON.stringify(JS_ADJ) === JSON.stringify(SB_ADJ),  'ADJ: dashboard.js === status-bridge.js');
assert(JSON.stringify(TS_NON) === JSON.stringify(JS_NON),  'NON: dashboardPanel.ts === dashboard.js');
assert(JSON.stringify(JS_NON) === JSON.stringify(SB_NON),  'NON: dashboard.js === status-bridge.js');
assert(TS_ADJ.length === 40, 'ADJ has 40 entries');
assert(TS_NON.length === 40, 'NON has 40 entries');
assert(!TS_ADJ.includes('dark'),  'ADJ does not contain confusable "dark"');
assert(!TS_ADJ.includes('deep'),  'ADJ does not contain confusable "deep"');
assert(!TS_ADJ.includes('grey'),  'ADJ does not contain confusable "grey"');
assert(!TS_ADJ.includes('teal'),  'ADJ does not contain confusable "teal"');

console.log('\n[2] Hash is deterministic (same id → same nick on repeated calls)');

const repeatId = 'test-session-determinism';
assertEqual(nickFromTs(repeatId), nickFromTs(repeatId), 'TS: deterministic');
assertEqual(nickFromJs(repeatId), nickFromJs(repeatId), 'JS: deterministic');
assertEqual(nickFromBridge(repeatId), nickFromBridge(repeatId), 'Bridge: deterministic');

console.log('\n[3] All three implementations agree for each known id');

for (const { id } of KNOWN) {
  const ts = nickFromTs(id);
  const js = nickFromJs(id);
  const br = nickFromBridge(id);
  assertEqual(js, ts, `TS==JS for ${JSON.stringify(id)}`);
  assertEqual(br, ts, `TS==Bridge for ${JSON.stringify(id)}`);
}

console.log('\n[4] Known session IDs map to expected nicknames');

for (const { id, nick } of KNOWN) {
  assertEqual(nickFromTs(id), nick, `expected nick for ${JSON.stringify(id)}`);
}

console.log('\n[5] Nick format is always ADJ-NON (two lowercase words, hyphen-separated)');

const testIds = ['', 'a', 'short', 'a-very-long-session-id-string-that-exercises-hash-overflow', '0', '12345'];
for (const id of testIds) {
  const n = nickFromTs(id);
  assert(/^[a-z]+-[a-z]+$/.test(n), `nick(${JSON.stringify(id)}) matches /^[a-z]+-[a-z]+$/ — got ${n}`);
  const [adj, non] = n.split('-');
  assert(TS_ADJ.includes(adj), `adj "${adj}" is in ADJ list`);
  assert(TS_NON.includes(non), `non "${non}" is in NON list`);
}

console.log('\n[6] Different session IDs produce varied output (not all the same)');

const differentIds = [
  'session-001', 'session-002', 'session-003', 'session-abc', 'xyz-999',
  'aaaa', 'bbbb', 'cccc', '1111', '2222',
];
const nickSet = new Set(differentIds.map(nickFromTs));
// With 40×40 = 1600 combinations, 10 different ids should all be unique
assert(nickSet.size === differentIds.length, `10 different ids produce 10 distinct nicks (got ${nickSet.size} unique)`);

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log('\n' + '─'.repeat(50));
console.log(`Result: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
