// Agentboard dashboard — session tab identity header + session-tab mode setup
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }

  function renderSessionHdr(s, d) {
    var el = root.document.getElementById('session-hdr');
    if (!el) return;
    var esc = _core().esc;
    var ctxBar = _core().ctxBar;
    var relTime = _core().relTime;
    var nick = s.nick || root.sessionNickname(s.sessionId || '');
    var isLive = typeof s.ageSeconds === 'number' && s.ageSeconds < 120;
    var dotColor = isLive ? '#4caf50' : '#888';
    var dotAnim = isLive ? 'animation:pulse 1.5s ease-in-out infinite;' : '';
    var siblings = (root._stSiblings || []);
    var statsLine = [
      s.model ? '<span style="opacity:.55;font-size:11px">' + esc(s.model) + '</span>' : '',
      s.cost  ? '<span style="color:#4caf50;font-size:11px">' + esc(s.cost) + '</span>' : '',
      s.sessionTime ? '<span style="opacity:.4;font-size:11px">' + esc(s.sessionTime) + '</span>' : '',
      (s.ctxPct !== null && s.ctxPct !== undefined) ? '<span>' + ctxBar(s.ctxPct) + '</span>' : '',
    ].filter(Boolean).join('<span style="opacity:.2;margin:0 4px">·</span>');
    var contextLine = [
      s.branch      ? '<span style="font-family:monospace;opacity:.4;font-size:11px">' + esc(s.branch)      + '</span>' : '',
      s.stream      ? '<span style="color:#4a9eff;font-size:11px">' + esc(s.stream)      + '</span>' : '',
      s.projectName ? '<span style="opacity:.3;font-size:11px">'    + esc(s.projectName) + '</span>' : '',
    ].filter(Boolean).join('<span style="opacity:.18;margin:0 5px">·</span>');
    var sibHtml = siblings.map(function(sib) {
      var sibNick = sib.nick || root.sessionNickname(sib.sessionId || '');
      return '<span class="sib-pill" data-focus-sibling="' + esc(sib.sessionId) + '">' + esc(sibNick) + ' ↗</span>';
    }).join(' ');
    el.innerHTML =
      '<div style="display:flex;align-items:center;gap:8px;padding:9px 14px 5px;flex-wrap:wrap">'
      + '<span style="width:7px;height:7px;border-radius:50%;background:' + dotColor + ';flex-shrink:0;' + dotAnim + '"></span>'
      + '<span style="font-weight:700;font-size:13px;letter-spacing:.02em;color:#e8e8e8">' + esc(nick) + '</span>'
      + (statsLine ? '<span style="opacity:.2;margin:0 2px">·</span>' + statsLine : '')
      + '</div>'
      + (contextLine ? '<div style="padding:0 14px 5px">' + contextLine + '</div>' : '')
      + '<div style="display:flex;align-items:center;gap:8px;padding:5px 14px 8px;border-top:1px solid rgba(255,255,255,.06);flex-wrap:wrap">'
      + '<button data-chat-btn="1" data-shell-pid="' + (s.shellPid || 0) + '" data-session-nick="' + esc(nick) + '" data-session-root="' + esc(s.root || '') + '" data-session-id="' + esc(s.sessionId || '') + '" style="padding:3px 10px;border-radius:4px;border:1px solid #4a9eff55;background:rgba(74,158,255,.1);color:#4a9eff;cursor:pointer;font-size:11px;font-weight:600">↗ Open Chat</button>'
      + (siblings.length ? '<span style="opacity:.28;font-size:10px;margin-left:4px">also open:</span> ' + sibHtml : '')
      + '<button data-refresh-btn="1" style="margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:inherit;border-radius:4px;padding:2px 8px;cursor:pointer;font-size:11px">↻</button>'
      + '</div>';
  }

  // Apply session-tab mode (or revert to main-hub layout) based on d.isSessionTab.
  // Returns the possibly-mutated data object (session tab overrides top-level fields).
  function applySessionTabMode(d) {
    if (d.isSessionTab) {
      var s0 = d.activeSessions && d.activeSessions[0];
      root.document.body.classList.add('session-tab');
      if (s0) {
        root._stSession  = s0;
        root._stSiblings = (d.sessionTabSiblings || []).filter(function(x){ return x.sessionId !== s0.sessionId; });
        var _s0act  = s0.activity || [];
        var _s0act0 = _s0act[0] || null;
        d = Object.assign({}, d, {
          model:       s0.model       || d.model,
          cost:        s0.cost        || d.cost,
          sessionTime: s0.sessionTime || d.sessionTime,
          ctxPct:      s0.ctxPct !== undefined ? s0.ctxPct : d.ctxPct,
          branch:      s0.branch      || d.branch,
          activeStream: s0.streamPinned ? (s0.stream || '') : (s0.stream || d.activeStream || ''),
          projectName: s0.projectName || d.projectName,
          hasLive:     typeof s0.ageSeconds === 'number' ? s0.ageSeconds < 120 : d.hasLive,
          fileActivity:    _s0act.length ? _s0act : d.fileActivity,
          recentAgents:    s0.agents || [],
          agentActivity:   s0.agentActivity || [],
          lastEventLabel:  _s0act0 ? _s0act0.file : '',
          lastEventTs:     _s0act0 ? _s0act0.lastTs : null,
          streamDesc:      s0.streamDesc  || d.streamDesc,
          isInLongOp:      false,
          activeWorkflow:  (s0.hasWorkflow && s0.workflowLabel)
            ? { label: s0.workflowLabel, agentCount: s0.workflowAgentCount || 0, ts: s0.lastUpdated || '' }
            : d.activeWorkflow,
          sessionWorkflow: s0.hasWorkflow ? s0 : null,
        });
        renderSessionHdr(s0, d);
      }
      var liveEl = root.document.getElementById('live');
      if (liveEl && !liveEl.classList.contains('on')) liveEl.classList.add('on');
      var catEl = root.document.getElementById('catalog');
      if (catEl) { catEl.classList.remove('on'); catEl.style.display = 'none'; }
      var kpiElST = root.document.getElementById('kpi-grid');
      if (kpiElST) kpiElST.style.display = 'none';
      var nsEl = root.document.getElementById('now-stats');
      if (nsEl) nsEl.style.display = 'none';
    } else {
      root.document.body.classList.remove('session-tab');
      var shdrEl = root.document.getElementById('session-hdr');
      if (shdrEl) shdrEl.style.display = 'none';
      var nsEl2 = root.document.getElementById('now-stats');
      if (nsEl2) nsEl2.style.display = '';
      var catEl2 = root.document.getElementById('catalog');
      if (catEl2) catEl2.style.display = '';
      var kpiEl = root.document.getElementById('kpi-grid');
      if (kpiEl) {
        kpiEl.style.display = 'block';
        kpiEl.innerHTML = root.AgentboardDashboard.trendChart.renderActivityChart(d);
      }
    }
    return d;
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.sessionHeader = {
    renderSessionHdr:    renderSessionHdr,
    applySessionTabMode: applySessionTabMode
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
