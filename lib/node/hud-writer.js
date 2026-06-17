'use strict';

// hud-writer.js — writes agentboard.hud-status.json atomically.

const fs   = require('fs');
const path = require('path');

function writeHud(workspaceRoot, hudData) {
  const hudPath = path.join(workspaceRoot, 'agentboard.hud-status.json');
  const tmpPath = hudPath + '.tmp';
  try {
    let existing = {};
    try {
      existing = JSON.parse(fs.readFileSync(hudPath, 'utf8'));
    } catch (_) {
      // File missing or unreadable — start fresh.
    }
    const merged = Object.assign({}, existing, hudData);
    fs.writeFileSync(tmpPath, JSON.stringify(merged, null, 2) + '\n', 'utf8');
    fs.renameSync(tmpPath, hudPath);
  } catch (err) {
    process.stderr.write(`[hud-writer] write failed: ${err.message}\n`);
    try { fs.unlinkSync(tmpPath); } catch (_) {}
  }
}

module.exports = { writeHud };
