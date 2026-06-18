#!/usr/bin/env node
// workflow-parser.js — extract planned agents from a Workflow script (PreToolUse payload)
// Writes agentboard.workflow-agents.json so the dashboard can render the team before/during execution.
'use strict';

const fs = require('fs');
const path = require('path');

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', c => { raw += c; });
process.stdin.on('end', () => {
  let payload;
  try { payload = JSON.parse(raw); } catch { process.exit(0); }

  const script = payload.script || '';
  const agents = [];

  // Match: agent("prompt", { label: "...", model: "...", phase: "..." })
  // Handles single/double/template quotes for the prompt, and extracts the opts object
  const re = /\bagent\s*\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|`((?:[^`\\]|\\.)*)`)\s*(?:,\s*(\{[^}]*\}))?\s*\)/g;
  let m;
  while ((m = re.exec(script)) !== null) {
    const prompt = (m[1] || m[2] || m[3] || '').trim();
    const optsStr = m[4] || '';

    const get = (key) => {
      const r = new RegExp(key + '\\s*:\\s*[\'"`]([^\'"` ,}]+)[\'"`]');
      const hit = optsStr.match(r);
      return hit ? hit[1].trim() : '';
    };

    const label = get('label') || prompt.slice(0, 80);
    const model = get('model');
    const phase = get('phase');
    const agentType = get('agentType');

    // Parse role and skill out of the label convention: "role:X · skill:Y · task"
    const roleM = label.match(/role:\s*([^·|]+)/);
    const skillM = label.match(/skill:\s*([^·|]+)/);

    agents.push({
      label: label,
      role: roleM ? roleM[1].trim() : '',
      skill: skillM ? skillM[1].trim() : '',
      model: model || '',
      phase: phase || '',
      agentType: agentType || '',
      status: 'planned',
    });
  }

  // Extract meta.name and meta.phases
  const nameM = script.match(/name\s*:\s*['"`]([^'"`]+)['"`]/);
  const wfName = payload.name || (nameM ? nameM[1] : '') || 'workflow';

  const phases = [];
  const phasesM = script.match(/phases\s*:\s*\[([\s\S]*?)\]/);
  if (phasesM) {
    const titleRe = /title\s*:\s*['"`]([^'"`]+)['"`]/g;
    let pm;
    while ((pm = titleRe.exec(phasesM[1])) !== null) phases.push(pm[1]);
  }

  const result = {
    name: wfName,
    phases,
    agents,
    total: agents.length,
    started_at: new Date().toISOString(),
    status: 'running',
  };

  process.stdout.write(JSON.stringify(result, null, 2));
});
