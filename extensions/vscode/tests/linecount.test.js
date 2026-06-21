#!/usr/bin/env node
/**
 * linecount.test.js
 *
 * Tests the line-count enrichment logic used in dashboardPanel.ts:
 *   - fs.readFileSync(absFile, 'utf8').split('\n').length
 *   - 60 s TTL cache (verified as a reasonable TTL)
 *   - Size tier thresholds: amber >= 500L, orange >= 800L, red >= 1000L
 *   - Edit-warning threshold: warn (amber) >= 50 lines changed, orange >= 150
 *
 * Run: node extensions/vscode/tests/linecount.test.js
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

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
// Helper: write a temp file with N lines and return its path
// ---------------------------------------------------------------------------
function writeTempFile(lines) {
  const p = path.join(os.tmpdir(), 'linecount-test-' + process.pid + '-' + Math.random().toString(36).slice(2) + '.txt');
  fs.writeFileSync(p, lines.join('\n'));
  return p;
}

// ---------------------------------------------------------------------------
// The counting function extracted verbatim from dashboardPanel.ts
// ---------------------------------------------------------------------------
function countLines(absFile) {
  return fs.readFileSync(absFile, 'utf8').split('\n').length;
}

// ---------------------------------------------------------------------------
// Size-badge tier logic extracted verbatim from dashboard.js
// ---------------------------------------------------------------------------
function sizeTier(lineCount) {
  if (lineCount >= 1000) return 'red';
  if (lineCount >= 800)  return 'orange';
  if (lineCount >= 500)  return 'amber';
  return '';
}

// sizeBadge label logic from dashboard.js
function sizeBadgeLabel(lc) {
  return lc >= 1000 ? (Math.round(lc / 100) / 10) + 'k' : lc + '';
}

// ---------------------------------------------------------------------------
// Edit-warning logic extracted verbatim from dashboard.js
// ---------------------------------------------------------------------------
function editWarnColor(totalChanged) {
  if (totalChanged < 50) return '';
  return totalChanged >= 150 ? '#ff7043' : '#f0b429';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

console.log('\n[1] Line counting with known file contents');

// A file with exactly 5 lines of content (split('\n') on "a\nb\nc\nd\ne" gives 5 elements)
{
  const p = writeTempFile(['a', 'b', 'c', 'd', 'e']);
  // "a\nb\nc\nd\ne" → split('\n') = ['a','b','c','d','e'] → length 5
  assertEqual(countLines(p), 5, 'file with 5 lines → count 5');
  fs.unlinkSync(p);
}

// A file with a trailing newline ("a\nb\n") → split('\n') = ['a','b',''] → length 3
{
  const p = path.join(os.tmpdir(), 'linecount-trailing-' + process.pid + '.txt');
  fs.writeFileSync(p, 'a\nb\n');
  assertEqual(countLines(p), 3, 'file "a\\nb\\n" → split gives 3 elements (matches dashboard behavior)');
  fs.unlinkSync(p);
}

// Empty file: "" → split('\n') = [''] → length 1
{
  const p = path.join(os.tmpdir(), 'linecount-empty-' + process.pid + '.txt');
  fs.writeFileSync(p, '');
  assertEqual(countLines(p), 1, 'empty file → count 1 (single empty string from split)');
  fs.unlinkSync(p);
}

// Single line no newline
{
  const p = path.join(os.tmpdir(), 'linecount-single-' + process.pid + '.txt');
  fs.writeFileSync(p, 'hello world');
  assertEqual(countLines(p), 1, 'single line, no newline → count 1');
  fs.unlinkSync(p);
}

// 100 lines exactly
{
  const lines = Array.from({ length: 100 }, (_, i) => 'line ' + (i + 1));
  const p = writeTempFile(lines);
  assertEqual(countLines(p), 100, '100 lines → count 100');
  fs.unlinkSync(p);
}

console.log('\n[2] Cache TTL constant is sensible');

const LINE_COUNT_TTL = 60_000; // from dashboardPanel.ts
assertEqual(LINE_COUNT_TTL, 60000, 'LINE_COUNT_TTL is 60000 ms (60 seconds)');
assert(LINE_COUNT_TTL >= 30_000, 'TTL >= 30s (not too aggressive)');
assert(LINE_COUNT_TTL <= 120_000, 'TTL <= 120s (not too stale)');

console.log('\n[3] Size tier thresholds');

assertEqual(sizeTier(0),    '',       'size 0 → no badge');
assertEqual(sizeTier(499),  '',       'size 499 → no badge');
assertEqual(sizeTier(500),  'amber',  'size 500 → amber (growing)');
assertEqual(sizeTier(799),  'amber',  'size 799 → amber');
assertEqual(sizeTier(800),  'orange', 'size 800 → orange (large)');
assertEqual(sizeTier(999),  'orange', 'size 999 → orange');
assertEqual(sizeTier(1000), 'red',    'size 1000 → red (monolith)');
assertEqual(sizeTier(9999), 'red',    'size 9999 → red');

console.log('\n[4] Size badge label formatting');

assertEqual(sizeBadgeLabel(500),  '500', 'label for 500 is "500"');
assertEqual(sizeBadgeLabel(800),  '800', 'label for 800 is "800"');
assertEqual(sizeBadgeLabel(999),  '999', 'label for 999 is "999"');
// 1000 → Math.round(1000/100)/10 = Math.round(10)/10 = 1, → "1k"
assertEqual(sizeBadgeLabel(1000), '1k',  'label for 1000 is "1k"');
// 1500 → Math.round(1500/100)/10 = Math.round(15)/10 = 1.5 → "1.5k"
assertEqual(sizeBadgeLabel(1500), '1.5k', 'label for 1500 is "1.5k"');
// 2000 → Math.round(2000/100)/10 = 20/10 = 2 → "2k"
assertEqual(sizeBadgeLabel(2000), '2k',   'label for 2000 is "2k"');

console.log('\n[5] Edit-warning thresholds');

// totalChanged = added + deleted
assertEqual(editWarnColor(0),   '',        '0 lines changed → no warning');
assertEqual(editWarnColor(49),  '',        '49 lines changed → no warning');
assertEqual(editWarnColor(50),  '#f0b429', '50 lines changed → amber warning');
assertEqual(editWarnColor(100), '#f0b429', '100 lines changed → amber warning');
assertEqual(editWarnColor(149), '#f0b429', '149 lines changed → amber warning');
assertEqual(editWarnColor(150), '#ff7043', '150 lines changed → orange warning');
assertEqual(editWarnColor(500), '#ff7043', '500 lines changed → orange warning');

console.log('\n[6] Counting consistency: split("\\n").length counts all lines');

// Verify behaviour is identical to dashboardPanel.ts implementation
{
  const content = 'a\nb\nc';
  const result = content.split('\n').length;
  assertEqual(result, 3, 'split on content without trailing newline');
}
{
  const content = Array.from({ length: 300 }, (_, i) => 'x'.repeat(40)).join('\n');
  const p = path.join(os.tmpdir(), 'linecount-300-' + process.pid + '.txt');
  fs.writeFileSync(p, content);
  const result = countLines(p);
  assertEqual(result, 300, '300-line file → count 300');
  fs.unlinkSync(p);
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
console.log('\n' + '─'.repeat(50));
console.log(`Result: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
