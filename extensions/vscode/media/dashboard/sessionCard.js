// Agentboard dashboard — per-session card renderer (multi-session grid)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }
  function _save() { root.AgentboardDashboard.uiState.saveUiState(); }

  var RECENT_AGENT_MS = 5 * 60 * 1000;

  function _agentRowsHtml(s, d) {
    var esc = _core().esc;
    var relTime = _core().relTime;
    if (!s.agents || !s.agents.length) return '';

    var runningAgents = s.agents.filter(function(a){ return !a.done; });
    var totalAgents = s.agents.length;
    var sid = s.sessionId;
    var expanded = root._agentExpanded && root._agentExpanded.has(sid);
    var chevron = expanded ? '▾' : '▸';
    var runBadge = runningAgents.length
      ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:#4caf5022;color:#4caf50;font-weight:700">' + runningAgents.length + ' running</span>'
      : '';
    var doneBadge = (totalAgents - runningAgents.length) > 0
      ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:rgba(255,255,255,.06);color:#888">' + (totalAgents - runningAgents.length) + ' done</span>'
      : '';

    var now = Date.now();
    var recentDone = s.agents.filter(function(a){ return a.done && a.ts && (now - new Date(a.ts).getTime()) < RECENT_AGENT_MS; });
    var oldDone    = s.agents.filter(function(a){ return a.done && (!a.ts || (now - new Date(a.ts).getTime()) >= RECENT_AGENT_MS); });
    var visibleAgents = runningAgents.concat(recentDone);

    var agentRows = visibleAgents.map(function(a) {
      var label = (a.label || 'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim() || (a.label || 'agent');
      var roleColor = (a.role||'').toLowerCase().includes('debug') ? '#f44336' : (a.role||'').toLowerCase().includes('research') ? '#9c6af7' : '#4a9eff';
      var pulse = a.done
        ? '<span style="width:6px;height:6px;border-radius:50%;background:#4caf50;flex-shrink:0;display:inline-block;opacity:.5"></span>'
        : '<span style="width:6px;height:6px;border-radius:50%;background:#4caf50;flex-shrink:0;display:inline-block;animation:pulse 1.5s ease-in-out infinite"></span>';
      return '<div style="display:flex;align-items:center;gap:6px;padding:3px 0;font-size:11px;' + (a.done ? 'opacity:.4' : '') + '">'
        + pulse
        + '<span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(label) + '</span>'
        + (a.role ? '<span style="font-size:9px;padding:1px 5px;border-radius:8px;background:' + roleColor + '22;color:' + roleColor + '">' + esc(a.role) + '</span>' : '')
        + '<span style="font-size:9px;opacity:.3;white-space:nowrap">' + relTime(a.ts) + '</span>'
        + '</div>';
    }).join('');
    if (oldDone.length) {
      agentRows += '<div style="font-size:9px;opacity:.25;padding:4px 0;border-top:1px solid rgba(255,255,255,.05)">✓ ' + oldDone.length + ' done earlier</div>';
    }

    return '<div style="border-bottom:1px solid rgba(128,128,128,.1)">'
      + '<div data-agents-toggle="' + esc(sid) + '" style="display:flex;align-items:center;gap:6px;padding:8px 14px;cursor:pointer;user-select:none" title="Toggle sub-agents">'
      + '<span style="font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#888">◈ Sub-agents</span>'
      + '<span style="font-size:10px;font-weight:700;color:#888">· ' + totalAgents + '</span>'
      + runBadge + doneBadge
      + '<span style="margin-left:auto;font-size:11px;opacity:.4">' + chevron + '</span>'
      + '</div>'
      + '<div id="agents-body-' + esc(sid) + '" style="padding:' + (expanded ? '0 14px 8px' : '0') + ';display:' + (expanded ? 'block' : 'none') + '">'
      + agentRows
      + '</div>'
      + '</div>';
  }

  function _activityHtml(s, d, sessRoot) {
    var esc = _core().esc;
    var relTime = _core().relTime;
    var renderActivityRow = root.AgentboardDashboard.activityRow.renderActivityRow;
    var acts = (s.activity || []).map(function(f) {
      return renderActivityRow(f, sessRoot, s);
    }).join('') || '<div class="em" style="padding:8px 14px">No activity yet</div>';
    var actSid = 'act-' + s.sessionId;
    var actExpanded = !root._actCollapsed || !root._actCollapsed.has(actSid);
    var actChevron = actExpanded ? '▾' : '▸';
    var actCount = s.activity ? s.activity.length : 0;
    var actHdr = '<div data-act-toggle="' + esc(actSid) + '" style="display:flex;align-items:center;gap:6px;padding:6px 14px;cursor:pointer;border-top:1px solid rgba(128,128,128,.1);user-select:none">'
      + '<span style="font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;opacity:.35">Activity</span>'
      + (actCount ? '<span style="font-size:10px;opacity:.25">' + actCount + '</span>' : '')
      + '<span style="margin-left:auto;font-size:11px;opacity:.3">' + actChevron + '</span>'
      + '</div>';
    var actBody = '<div id="act-body-' + esc(actSid) + '" style="display:' + (actExpanded ? 'block' : 'none') + ';padding:4px 14px;max-height:260px;overflow-y:auto;scrollbar-width:thin">' + acts + '</div>';
    return actHdr + actBody;
  }

  function _streamSelectHtml(s, d, esc) {
    var effStream = s.streamPinned ? (s.stream || '') : (s.stream || d.activeStream || '');
    var avail = s.availableStreams || [];
    var opts = '<option value="">— none —</option>';
    avail.forEach(function(slug) {
      opts += '<option value="' + esc(slug) + '"' + (slug === effStream ? ' selected' : '') + '>' + esc(slug) + '</option>';
    });
    if (effStream && !avail.includes(effStream)) {
      opts += '<option value="' + esc(effStream) + '" selected>' + esc(effStream) + ' ⚠</option>';
    }
    var autoLabel = (!s.streamPinned && effStream) ? '<span title="Auto from workspace BRIEF.md" style="font-size:9px;opacity:.35;flex-shrink:0">auto</span>' : '';
    var closeBtn = effStream
      ? '<button data-close-stream-btn="1" data-stream-slug="' + esc(effStream) + '" data-session-root="' + esc(s.root||'') + '" style="flex-shrink:0;background:#ff453a18;border:1px solid #ff453a44;color:#ff453a;border-radius:4px;font-size:9px;padding:1px 7px;cursor:pointer;white-space:nowrap" onmouseover="this.style.background=\'#ff453a33\'" onmouseout="this.style.background=\'#ff453a18\'">Close</button>'
      : '';
    return '<span style="opacity:.4;align-self:center">Stream</span>'
      + '<span style="display:flex;align-items:center;gap:5px;min-width:0">'
      + '<select data-sess-stream-select="1" data-session-id="' + esc(s.sessionId||'') + '" data-session-root="' + esc(s.root||'') + '" style="flex:1;min-width:0;max-width:150px;background:#1e1e2e;color:' + (effStream ? '#4a9eff' : '#666') + ';border:1px solid #4a9eff33;border-radius:4px;font-size:10px;padding:1px 5px;cursor:pointer;outline:none">' + opts + '</select>'
      + autoLabel + closeBtn + '</span>';
  }

  function _branchSelectHtml(s, esc) {
    var availBr = s.availableBranches || [];
    var effBr = s.branch || '';
    var pinned = s.branchPinned;
    var opts = '<option value="">— auto —</option>';
    availBr.forEach(function(br) {
      opts += '<option value="' + esc(br) + '"' + (pinned && br === effBr ? ' selected' : '') + '>' + esc(br) + '</option>';
    });
    if (pinned && effBr && !availBr.includes(effBr)) {
      opts += '<option value="' + esc(effBr) + '" selected>' + esc(effBr) + ' ⚠</option>';
    }
    var pinLabel = pinned ? '<span title="Branch manually pinned" style="font-size:9px;opacity:.35;flex-shrink:0">pinned</span>' : '';
    return '<span style="opacity:.4;align-self:center">Branch</span>'
      + '<span style="display:flex;align-items:center;gap:5px;min-width:0">'
      + (availBr.length
        ? '<select data-sess-branch-select="1" data-session-id="' + esc(s.sessionId||'') + '" data-session-root="' + esc(s.root||'') + '" style="flex:1;min-width:0;max-width:150px;background:#1e1e2e;color:' + (effBr ? '#e8e8e8' : '#666') + ';border:1px solid #ffffff22;border-radius:4px;font-size:10px;padding:1px 5px;cursor:pointer;outline:none;font-family:monospace">' + opts + '</select>'
        : '<span style="font-family:monospace;font-size:10px;opacity:.7">' + esc(effBr || '—') + '</span>')
      + pinLabel + '</span>';
  }

  // Render a single session column card in the multi-session grid.
  // Returns an HTML string.
  function renderSessionCard(s, d, colBasis) {
    var esc = _core().esc;
    var relTime = _core().relTime;
    try {
      var lastUpdatedMs = s.lastUpdated ? new Date(s.lastUpdated).getTime() : 0;
      var isLive = lastUpdatedMs > 0 && (Date.now() - lastUpdatedMs < 180000);
      var nick = root.sessionNickname(s.sessionId);
      var displayName = (s.projectName || s.sessionId.slice(0,8)) + ' · ' + nick;
      var age = s.ageSeconds < 60 ? s.ageSeconds + 's ago'
        : s.ageSeconds < 3600 ? Math.floor(s.ageSeconds / 60) + 'm ago'
        : Math.floor(s.ageSeconds / 3600) + 'h ago';
      var mc = s.model.toLowerCase();
      var modelColor = mc.includes('opus') ? '#9c6af7' : mc.includes('haiku') ? '#4a9eff' : '#ff9800';
      var dotColor = isLive ? '#4caf50' : '#555';
      var ctxUsed = s.ctxPct !== null && s.ctxPct !== undefined ? Math.round(100 - s.ctxPct) : null;
      var ctxFill = ctxUsed !== null ? Math.max(0, Math.min(10, Math.floor(ctxUsed / 10))) : 0;
      var ctxColor = ctxUsed === null ? '#555' : ctxUsed < 50 ? '#4caf50' : ctxUsed < 75 ? '#ff9800' : '#f44336';
      var ctxBar = ctxUsed !== null
        ? '<span style="color:' + ctxColor + ';font-size:10px">' + '█'.repeat(ctxFill) + '░'.repeat(10 - ctxFill) + ' ' + ctxUsed + '%</span>'
        : '';
      var sessRoot = s.root || '';

      var hdr = '<div class="sess-col-hdr">'
        + '<div class="sess-col-name">'
        + '<span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;background:' + dotColor + (isLive ? ';box-shadow:0 0 5px ' + dotColor + ';animation:pulse 1.5s ease-in-out infinite' : '') + '"></span>'
        + '<span style="font-size:12px;font-weight:' + (isLive ? '600' : '400') + ';color:' + (isLive ? '#e8e8e8' : '#aaa') + ';flex:1">' + esc(displayName) + '</span>'
        + '<span style="font-size:10px;padding:1px 6px;border-radius:8px;background:' + modelColor + '22;color:' + modelColor + '">' + esc(s.model) + '</span>'
        + '<button data-focus-terminal="1" data-session-root="' + esc(s.root||'') + '" data-session-nick="' + esc(nick) + '" data-shell-pid="' + (s.shellPid||0) + '" data-session-started-at="' + esc(s.startedAt||'') + '" title="Open chat for ' + esc(nick) + '" style="background:#ffffff0d;border:1px solid #ffffff18;cursor:pointer;padding:2px 8px;border-radius:4px;color:#aaa;font-size:10px;line-height:1.6;display:flex;align-items:center;gap:4px;transition:all .15s;white-space:nowrap" onmouseover="this.style.background=\'#ffffff1a\';this.style.color=\'#fff\'" onmouseout="this.style.background=\'#ffffff0d\';this.style.color=\'#aaa\'">⌨ chat</button>'
        + '<button data-open-session-tab="' + esc(s.sessionId||'') + '" title="Open session tab for ' + esc(nick) + '" style="background:#4a9eff0d;border:1px solid #4a9eff33;cursor:pointer;padding:2px 8px;border-radius:4px;color:#4a9eff;font-size:10px;line-height:1.6;display:flex;align-items:center;gap:4px;transition:all .15s;white-space:nowrap" onmouseover="this.style.background=\'#4a9eff22\'" onmouseout="this.style.background=\'#4a9eff0d\'">↗ tab</button>'
        + '<button data-close-session="' + esc(s.sessionId||'') + '" title="Dismiss session from dashboard" style="background:transparent;border:none;cursor:pointer;color:#ff453a;font-size:13px;line-height:1;padding:2px 4px;opacity:.5;flex-shrink:0" onmouseover="this.style.opacity=\'1\'" onmouseout="this.style.opacity=\'.5\'">×</button>'
        + '</div>'
        + '<div class="sess-col-grid">'
        + _streamSelectHtml(s, d, esc)
        + (s.cost         ? '<span style="opacity:.4">Cost</span><span>' + esc(s.cost) + '</span>' : '')
        + (s.sessionTime  ? '<span style="opacity:.4">Time</span><span>' + esc(s.sessionTime) + '</span>' : '')
        + (ctxBar         ? '<span style="opacity:.4">Context</span><span>' + ctxBar + '</span>' : '')
        + _branchSelectHtml(s, esc)
        + '<span style="opacity:.4">Last</span><span style="opacity:.5">' + age + '</span>'
        + (s.sessionLastRole  ? '<span style="opacity:.4">Role</span><span style="color:#9c6af7;font-size:10px">◈ ' + esc(s.sessionLastRole)  + '</span>' : '')
        + (s.sessionLastSkill ? '<span style="opacity:.4">Skill</span><span style="color:#4caf84;font-size:10px">/ '  + esc(s.sessionLastSkill) + '</span>' : '')
        + '</div>'
        + '</div>';

      var agentsHtml  = _agentRowsHtml(s, d);
      var workflowHtml = root.AgentboardDashboard.workflowPanel.buildWfPanel(s, false);
      var actHtml = _activityHtml(s, d, sessRoot);

      return '<div class="sess-col" style="flex:1 1 ' + colBasis + '">' + hdr + agentsHtml + workflowHtml + actHtml + '</div>';
    } catch(e) {
      return '<div class="sess-col" style="padding:12px;opacity:.4;font-size:11px">Error rendering session: ' + (e && e.message || e) + '</div>';
    }
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.sessionCard = { renderSessionCard: renderSessionCard };
})(typeof globalThis !== 'undefined' ? globalThis : this);
