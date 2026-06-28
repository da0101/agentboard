// Shared pure helpers for the Agentboard dashboard webview.
(function(root) {
  'use strict';

  var TYPE_COLOR = {
    bugfix: '#e8823a',
    feature: '#4caf84',
    task: '#4a9eff',
    maintenance: '#888',
    research: '#9c6af7'
  };

  var TOOL_ICON = {
    Edit: '✏',
    Write: '✏',
    Bash: '$',
    Read: '👁',
    WebSearch: '⌕',
    WebFetch: '⌕',
    Agent: '◈',
    Skill: '⚡'
  };

  var SIZE_THRESHOLDS = {
    amber: 500,
    orange: 800,
    red: 1000
  };

  var EDIT_WARN_THRESHOLDS = {
    amber: 50,
    orange: 150
  };

  var COLOR = {
    green: '#4caf50',
    blue: '#4a9eff',
    red: '#f44336',
    amber: '#f0b429',
    orange: '#ff7043',
    monolith: '#ef5350'
  };

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function html(id, h) {
    var el = root.document && root.document.getElementById(id);
    if (el) el.innerHTML = h;
  }

  function txt(id, t) {
    var el = root.document && root.document.getElementById(id);
    if (el) el.textContent = t;
  }

  function streamDetailId(slug, i) {
    return 'sr-detail-' + String(slug || i).replace(/[^a-zA-Z0-9_-]/g, '-');
  }

  function relTime(iso, nowMs) {
    if (!iso) return '';
    var ms = new Date(iso).getTime();
    if (isNaN(ms)) return '?';
    var s = Math.floor(((nowMs == null ? Date.now() : nowMs) - ms) / 1000);
    if (s < 0) return 'just now';
    if (s < 60) return s + 's ago';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    return Math.floor(s / 3600) + 'h ago';
  }

  function ctxBar(pct) {
    if (pct === null || pct === undefined) return '—';
    var used = Math.round(100 - pct);
    var fill = Math.floor(used / 10);
    var c = used < 50 ? COLOR.green : used < 75 ? '#ff9800' : COLOR.red;
    return '<span class="ctx" style="color:' + c + '">' + '█'.repeat(fill) + '░'.repeat(10 - fill) + '</span><span style="color:' + c + ';font-size:11px"> ' + used + '%</span>';
  }

  function sizeTier(lineCount) {
    if (lineCount >= SIZE_THRESHOLDS.red) return 'red';
    if (lineCount >= SIZE_THRESHOLDS.orange) return 'orange';
    if (lineCount >= SIZE_THRESHOLDS.amber) return 'amber';
    return '';
  }

  function sizeColor(lineCount) {
    var tier = sizeTier(lineCount);
    if (tier === 'red') return COLOR.monolith;
    if (tier === 'orange') return COLOR.orange;
    if (tier === 'amber') return COLOR.amber;
    return '';
  }

  function sizeLabel(lineCount) {
    return lineCount >= SIZE_THRESHOLDS.red ? (Math.round(lineCount / 100) / 10) + 'k' : lineCount + '';
  }

  function sizeDescription(lineCount) {
    if (lineCount >= SIZE_THRESHOLDS.red) return 'monolith, very hard to refactor';
    if (lineCount >= SIZE_THRESHOLDS.orange) return 'large, hard to refactor';
    return 'growing, consider splitting';
  }

  function editWarnColor(totalChanged) {
    if (totalChanged < EDIT_WARN_THRESHOLDS.amber) return '';
    return totalChanged >= EDIT_WARN_THRESHOLDS.orange ? COLOR.orange : COLOR.amber;
  }

  var api = {
    TYPE_COLOR: TYPE_COLOR,
    TOOL_ICON: TOOL_ICON,
    SIZE_THRESHOLDS: SIZE_THRESHOLDS,
    EDIT_WARN_THRESHOLDS: EDIT_WARN_THRESHOLDS,
    COLOR: COLOR,
    esc: esc,
    html: html,
    txt: txt,
    streamDetailId: streamDetailId,
    relTime: relTime,
    ctxBar: ctxBar,
    sizeTier: sizeTier,
    sizeColor: sizeColor,
    sizeLabel: sizeLabel,
    sizeDescription: sizeDescription,
    editWarnColor: editWarnColor
  };

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.core = api;

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this);
