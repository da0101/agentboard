#!/usr/bin/env node
/**
 * parseEtime.test.js
 *
 * Tests the parseEtime() function from dashboardPanel.ts (focusTerminal handler).
 *
 * macOS ps etime format: [[DD-]HH:]MM:SS
 *   - MM:SS          (minutes + seconds, no hours, no days)
 *   - HH:MM:SS       (hours + minutes + seconds)
 *   - DD-HH:MM:SS    (days + hours + minutes + seconds)
 *
 * Run: node extensions/vscode/tests/parseEtime.test.js
 */

'use strict';

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

// ---------------------------------------------------------------------------
// parseEtime extracted verbatim from dashboardPanel.ts (lines 459-464)
// ---------------------------------------------------------------------------
function parseEtime(s) {
  s = s.trim();
  let days = 0;
  if (s.includes('-')) { const [d, rest] = s.split('-'); days = parseInt(d, 10); s = rest; }
  const parts = s.split(':').map(Number);
  const secs = parts.length === 3 ? parts[0]*3600 + parts[1]*60 + parts[2] : parts[0]*60 + (parts[1] ?? 0);
  return days * 86400 + secs;
}

// ---------------------------------------------------------------------------
// Tests using the required cases from the task brief
// ---------------------------------------------------------------------------

console.log('\n[1] Required test vectors (from task spec)');

// "01-21:28:30" → 1 day + 21h + 28m + 30s = 86400 + 75600 + 1680 + 30 = 163710
assertEqual(
  parseEtime('01-21:28:30'),
  163710,
  '"01-21:28:30" → 1×86400 + 21×3600 + 28×60 + 30 = 163710'
);

// "06:23:59" → 6h + 23m + 59s = 21600 + 1380 + 59 = 23039
assertEqual(
  parseEtime('06:23:59'),
  23039,
  '"06:23:59" → 6×3600 + 23×60 + 59 = 23039'
);

// "04:52" → 4m + 52s = 240 + 52 = 292
assertEqual(
  parseEtime('04:52'),
  292,
  '"04:52" → 4×60 + 52 = 292'
);

console.log('\n[2] Additional format variations');

// Pure seconds representation: "00:05" → 5s
assertEqual(parseEtime('00:05'),  5,   '"00:05" → 5 seconds');

// Exactly 1 minute: "01:00" → 60s
assertEqual(parseEtime('01:00'), 60,  '"01:00" → 60 seconds');

// Exactly 1 hour: "01:00:00" → 3600s
assertEqual(parseEtime('01:00:00'), 3600, '"01:00:00" → 3600 seconds');

// Exactly 1 day: "01-00:00:00" → 86400s
assertEqual(parseEtime('01-00:00:00'), 86400, '"01-00:00:00" → 86400 seconds');

// Larger day count: "07-00:00:00" → 7×86400 = 604800
assertEqual(parseEtime('07-00:00:00'), 604800, '"07-00:00:00" → 604800 seconds');

// Hours+minutes, no days: "02:30:00" → 9000
assertEqual(parseEtime('02:30:00'), 9000, '"02:30:00" → 9000 seconds');

// Leading/trailing whitespace (ps output often has spaces): "  04:52  "
assertEqual(parseEtime('  04:52  '), 292, 'leading/trailing whitespace trimmed');

// Minutes:seconds = "59:59" → 3599s
assertEqual(parseEtime('59:59'), 3599, '"59:59" → 3599 seconds');

// 2 days, some hours: "02-12:00:00" → 2×86400 + 12×3600 = 172800 + 43200 = 216000
assertEqual(parseEtime('02-12:00:00'), 216000, '"02-12:00:00" → 216000 seconds');

console.log('\n[3] Edge cases');

// "00:00" → 0s
assertEqual(parseEtime('00:00'), 0, '"00:00" → 0 seconds');

// "00:00:00" → 0s
assertEqual(parseEtime('00:00:00'), 0, '"00:00:00" → 0 seconds');

// "00-00:00:00" → 0s
assertEqual(parseEtime('00-00:00:00'), 0, '"00-00:00:00" → 0 seconds');

// Single seconds field: "00:01" → 1s
assertEqual(parseEtime('00:01'), 1, '"00:01" → 1 second');

console.log('\n[4] Arithmetic sanity checks');

// 1 day 21h 28m 30s broken down
const d1 = 1, h1 = 21, m1 = 28, s1 = 30;
const expected1 = d1*86400 + h1*3600 + m1*60 + s1;
assertEqual(expected1, 163710, 'manual arithmetic confirms 01-21:28:30 = 163710');

// 6h 23m 59s
const h2 = 6, m2 = 23, s2 = 59;
const expected2 = h2*3600 + m2*60 + s2;
assertEqual(expected2, 23039, 'manual arithmetic confirms 06:23:59 = 23039');

// 4m 52s
const m3 = 4, s3 = 52;
const expected3 = m3*60 + s3;
assertEqual(expected3, 292, 'manual arithmetic confirms 04:52 = 292');

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log('\n' + '─'.repeat(50));
console.log(`Result: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
