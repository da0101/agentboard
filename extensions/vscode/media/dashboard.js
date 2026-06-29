// agentboard dashboard webview script — loaded as external file to satisfy VS Code CSP
/* global acquireVsCodeApi */

const vscode = acquireVsCodeApi();
window._vscode = vscode; // expose for inline onclick attributes and submodules

// Namespace aliases (modules loaded before this file via shell.ts script order)
const AB       = window.AgentboardDashboard;
const AB_CORE  = AB.core;
const esc      = AB_CORE.esc;
const html     = AB_CORE.html;
const txt      = AB_CORE.txt;
const relTime  = AB_CORE.relTime;
const ctxBar   = AB_CORE.ctxBar;
const streamDetailId = AB_CORE.streamDetailId;

// Persistent UI state — initialised from saved webview state
const { savedUi, savedSet, saveUiState } = AB.uiState;
window._streamOpenState  = window._streamOpenState  || Object.assign({}, savedUi().streamOpen || {});
window._sectionFolded    = window._sectionFolded    || savedSet('sectionFolded');
window._agentExpanded    = window._agentExpanded    || savedSet('agentExpanded');
window._workflowExpanded = window._workflowExpanded || savedSet('workflowExpanded');
window._actCollapsed     = window._actCollapsed     || savedSet('actCollapsed');
window._catExpanded      = window._catExpanded      || savedSet('catExpanded');
window._trendWin         = window._trendWin         || savedUi().trendWin || '1h';
window._trendHidden      = window._trendHidden      || savedSet('trendHidden');
window._selectedRole     = window._selectedRole     || null;
window._rolesData        = window._rolesData        || [];

// Deterministic pet name from session ID (like Docker: "swift-falcon")
// Arrays must stay in sync with dashboardPanel.ts and codex-hook-bridge.js (verified by nickname-hash.test.js)
const _SN_ADJ=['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
const _SN_NON=['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
function sessionNickname(id) {
  var h = 0;
  for (var i = 0; i < id.length; i++) h = (Math.imul(h, 31) + id.charCodeAt(i)) >>> 0;
  return _SN_ADJ[h % _SN_ADJ.length] + '-' + _SN_NON[(h >>> 8) % _SN_NON.length];
}

function switchTab(id, btn) {
  document.querySelectorAll('.view').forEach(v=>v.classList.remove('on'));
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));
  document.getElementById(id).classList.add('on'); btn.classList.add('on');
}

function applySectionFoldState() {
  window._sectionFolded = window._sectionFolded || new Set();
  document.querySelectorAll('.sec').forEach(function(sec) {
    var key = sec.id || ((sec.querySelector('.sec-ttl')||{}).textContent || '');
    if (!key) return;
    sec.classList.toggle('folded', window._sectionFolded.has(key));
  });
}

function applyUpdate(d) {
  window._lastD = d;
  window._ignoredSizeFiles = new Set(d.ignoredSizeFiles || []);

  // Session tab setup (mutates d with per-session overrides, applies DOM mode)
  d = AB.sessionHeader.applySessionTabMode(d);

  // Header: project name + branch selector
  txt('h-proj', d.projectName || '—');
  var _hbrWrap = document.getElementById('h-br-wrap'), _hSep = document.getElementById('h-sep2');
  if (_hbrWrap && _hSep) {
    _hSep.style.display = d.branch ? '' : 'none';
    var _avail = d.availableBranches || [];
    if (_avail.length > 1) {
      var _opts = '';
      _avail.forEach(function(b){ _opts += '<option value="'+esc(b)+'"'+(b===d.branch?' selected':'')+'>'+esc(b)+'</option>'; });
      var _sid   = (d.activeSessions&&d.activeSessions[0]&&d.activeSessions[0].sessionId) || '';
      var _sroot = (d.activeSessions&&d.activeSessions[0]&&d.activeSessions[0].root)      || '';
      _hbrWrap.innerHTML = '<select id="h-br-sel" data-session-id="'+esc(_sid)+'" data-session-root="'+esc(_sroot)+'" style="background:#1e1e2e;color:#e8e8e8;border:1px solid #ffffff22;border-radius:4px;font-size:11px;font-family:monospace;padding:1px 4px;cursor:pointer;outline:none;max-width:140px">'+_opts+'</select>';
    } else {
      _hbrWrap.innerHTML = '<span class="br" style="font-family:monospace">'+esc(d.branch||'')+'</span>';
    }
  }

  // Catalog tab count
  const tc = document.getElementById('tab-catalog');
  if (tc) tc.textContent = 'Catalog · ' + (d.skillCount + d.roleCount);

  // NOW block
  const isMultiNow  = !d.isSessionTab && d.activeSessions && d.activeSessions.length > 0;
  const isWorkflow  = !!(d.activeWorkflow);
  AB.nowBlock.updateNowBlock(d, isMultiNow, isWorkflow);

  // File activity list (single-session path)
  var _singleSess   = (d.activeSessions && d.activeSessions.length === 1) ? d.activeSessions[0] : null;
  var _richActivity = _singleSess ? (_singleSess.activity || null) : null;
  var _singleRoot   = _singleSess ? (_singleSess.root || '') : '';
  var _actFiles     = _richActivity || d.fileActivity || [];
  var _totalFiles   = d.totalUniqueFiles || _actFiles.length || 0;
  var _actLabel     = 'Activity this session';
  if (_totalFiles > 0) {
    _actLabel += ' · ' + _totalFiles + ' file' + (_totalFiles !== 1 ? 's' : '');
    if (_actFiles.length < _totalFiles) _actLabel += ' (showing ' + _actFiles.length + ')';
  }
  txt('fa-ttl', _actLabel);
  html('fa-list', _actFiles.length
    ? _actFiles.map(function(f){ return AB.activityRow.renderActivityRow(f, _singleRoot, _singleSess); }).join('')
    : '<div class="em">No edits or commands yet this session</div>');

  // Agents / workflow panel
  const agentsEl  = document.getElementById('agents-list');
  const agentsTtl = document.getElementById('agents-ttl');
  const wp    = (d.activeSessions && d.activeSessions.length === 1) ? d.activeSessions[0].workflowPlan : null;
  const hasWf = wp || (d.activeWorkflow && d.activeWorkflow.label);
  AB.agentsPanel.updateAgentsPanel(d, agentsEl, agentsTtl, wp, hasWf);

  // Layout: multi-session grid vs single-session columns
  const multiSession   = !d.isSessionTab;
  const liveBody       = document.getElementById('live-body');
  const sessionColsEl  = document.getElementById('session-cols');
  const streamsRowEl   = document.getElementById('streams-row');
  const colL = document.querySelector('.col-l');
  const colR = document.querySelector('.col-r');

  if (multiSession && liveBody && sessionColsEl) {
    liveBody.classList.add('multi');
    var secMultiSessEl = document.getElementById('sec-multi-sessions');
    if (secMultiSessEl) secMultiSessEl.style.display = '';
    sessionColsEl.style.display = 'flex';
    if (streamsRowEl) streamsRowEl.style.display = '';
    if (colL) colL.style.display = 'none';
    if (colR) colR.style.display = 'none';

    var totalSess = d.activeSessions.length;
    var colBasis  = totalSess <= 1 ? '100%' : totalSess === 2 ? '50%' : '33.333%';

    // Preserve scroll positions before re-render
    var _scrollState = {};
    sessionColsEl.querySelectorAll('[id^="act-body-"],[id^="wf-body-"],[id^="agents-body-"]').forEach(function(el) {
      if (el.scrollTop > 0) _scrollState[el.id] = el.scrollTop;
    });

    var _activeSessions = d.activeSessions || [];
    var multiSessTtl = document.getElementById('multi-sessions-ttl');
    if (multiSessTtl) multiSessTtl.textContent = 'Sessions (' + _activeSessions.length + ')';

    if (!_activeSessions.length) {
      sessionColsEl.innerHTML = '<div style="padding:32px 20px;opacity:.3;font-size:12px;text-align:center;width:100%">No active sessions</div>';
    } else {
      sessionColsEl.innerHTML = _activeSessions.map(function(s) {
        return AB.sessionCard.renderSessionCard(s, d, colBasis);
      }).join('');
    }

    // Restore scroll positions
    Object.keys(_scrollState).forEach(function(id) {
      var el = document.getElementById(id); if (el) el.scrollTop = _scrollState[id];
    });

    // Streams in bottom row
    const srTtl2  = document.getElementById('sr-ttl2');
    const srList2 = document.getElementById('sr-list2');
    if (srTtl2) { srTtl2.textContent = 'Active streams (' + d.streams.length + ')'; srTtl2.removeAttribute('data-toggle-id'); }
    if (srList2) srList2.innerHTML = AB.streams.renderStreams(d.streams, d.activeStream);
  } else {
    if (liveBody) liveBody.classList.remove('multi');
    var secMultiSessEl2 = document.getElementById('sec-multi-sessions');
    if (secMultiSessEl2) secMultiSessEl2.style.display = 'none';
    if (sessionColsEl) sessionColsEl.style.display = 'none';
    if (streamsRowEl)  streamsRowEl.style.display = 'none';
    if (colL) colL.style.display = '';
    if (colR) colR.style.display = '';
    var sessionsSecEl = document.getElementById('sec-sessions');
    var singleSecEl   = document.getElementById('sec-session-single');
    if (sessionsSecEl) sessionsSecEl.style.display = 'none';
    if (singleSecEl)   singleSecEl.style.display = d.isSessionTab ? 'none' : '';
  }

  // Streams (single-session path)
  if (!multiSession) {
    txt('sr-ttl', 'Active streams (' + d.streams.length + ')');
    if (!d.streams.length) { html('sr-list', '<div class="em">No active streams</div>'); }
    else { const srList = document.getElementById('sr-list'); if (srList) srList.innerHTML = AB.streams.renderStreams(d.streams, d.activeStream); }
  }

  // Session stats (single-session only)
  txt('sv-model',  d.model       || '—');
  txt('sv-stream', d.activeStream|| '—');
  txt('sv-cost',   d.cost        || '—');
  txt('sv-time',   d.sessionTime || '—');
  const svCtx = document.getElementById('sv-ctx'); if (svCtx) svCtx.innerHTML = ctxBar(d.ctxPct);
  txt('sv-branch', d.branch      || '—');

  // Role / skill display
  const secRole = document.getElementById('sec-role');
  const rg      = document.getElementById('role-grid');
  const rows    = [];
  if (d.activeRole) rows.push('<span class="sk">Role</span><span class="sv sv-role">' + esc(d.activeRole) + '</span>');
  if (d.lastSkill)  rows.push('<span class="sk">Skill</span><span class="sv sv-skill">/' + esc(d.lastSkill) + '</span>');
  if (secRole && rg) { secRole.style.display = rows.length ? '' : 'none'; rg.innerHTML = rows.join(''); }

  // Catalog
  txt('cnt-skills', String(d.skillCount));
  txt('cnt-roles',  String(d.roleCount));
  txt('cnt-cmds',   String(d.commands.length));
  AB.catalog.renderCatalogCol('list-skills', d.skills,   '#4a9eff');
  window._rolesData = d.roles;
  AB.catalog.renderRolesCol('list-roles',   d.roles,    '#9c6af7');
  AB.catalog.renderCatalogCol('list-cmds',  d.commands, '#888');

  // Footer
  html('footer', '<span style="opacity:.25;font-size:10px">' + d.skillCount + ' skills · ' + d.roleCount + ' roles · ' + d.streams.length + ' streams</span>');
  applySectionFoldState();
}

window.addEventListener('message', function(e) {
  const d = e.data; if (d.type !== 'update') return;
  applyUpdate(d);
});

// Tell the extension this webview is live — triggers a fresh data push.
vscode.postMessage({command:'webviewReady'});

// Wire up all event handlers
AB.events.initEvents(vscode);

// Read initial data from embedded JSON element (avoids inline script CSP issues)
(function() {
  const el = document.getElementById('ab-data');
  if (!el) return;
  try {
    const d = JSON.parse(el.textContent || '');
    if (d && d.type === 'update') applyUpdate(d);
  } catch(e) {}
})();
