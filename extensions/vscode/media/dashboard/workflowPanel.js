// Agentboard dashboard — workflow panel renderer (compact badge + full detail)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }

  // tabMode=false → compact badge for session card; tabMode=true → full expanded panel for session tab
  function buildWfPanel(s, tabMode) {
    if (!s || !s.hasWorkflow) return '';
    var esc = _core().esc;
    var relTime = _core().relTime;
    var wp2 = s.workflowPlan || null;
    var wfSid = 'wf-' + s.sessionId;
    var bgLaunch2 = wp2 && wp2.status === 'done' && wp2.ended_at && wp2.started_at
      && (new Date(wp2.ended_at).getTime() - new Date(wp2.started_at).getTime() < 30000);
    var wfRun = !wp2 || wp2.status !== 'done' || !!bgLaunch2;
    var wfColor = wfRun ? '#4a9eff' : '#4caf50';
    var wfIcon = wfRun ? '⟳' : '✓';
    var wfLabel = (wp2 && wp2.name && wp2.name.toLowerCase() !== 'workflow') ? wp2.name
      : (s.workflowLabel && s.workflowLabel.toLowerCase() !== 'workflow' ? s.workflowLabel : '');
    var txAgents = (s.workflowTranscriptAgents && s.workflowTranscriptAgents.length) ? s.workflowTranscriptAgents : null;
    var wfAgents = txAgents || ((wp2 && wp2.agents && wp2.agents.length) ? wp2.agents : null);
    var txRun  = txAgents ? txAgents.filter(function(a){ return a.status !== 'done'; }).length : 0;
    var txDone = txAgents ? txAgents.filter(function(a){ return a.status === 'done';  }).length : 0;
    var evNotDone = s.agents ? s.agents.filter(function(a){ return !a.done; }).length : 0;
    var standby = txAgents ? Math.max(0, evNotDone - txRun) : 0;
    var wfRC, wfDC, wfAC;
    if (txAgents) {
      wfRC = txRun; wfDC = txDone; wfAC = txRun + txDone + standby;
    } else if (wfAgents) {
      wfRC = wfAgents.filter(function(a){ return a.status !== 'done'; }).length;
      wfDC = wfAgents.filter(function(a){ return a.status === 'done';  }).length;
      wfAC = wfAgents.length; standby = 0;
    } else {
      wfRC = evNotDone;
      wfDC = s.agents ? s.agents.filter(function(a){ return a.done; }).length : 0;
      wfAC = s.agents ? s.agents.length : (s.workflowAgentCount || 0);
      standby = 0;
    }
    var runB  = wfRC ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:' + wfColor + '22;color:' + wfColor + ';font-weight:700">' + wfRC + ' running</span>' : '';
    var stbB  = standby ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:#ff980022;color:#ff9800;font-weight:700">' + standby + ' standby</span>' : '';
    var doneB = wfDC ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:rgba(255,255,255,.06);color:#888">' + wfDC + ' done</span>' : '';

    if (!tabMode) {
      return '<div style="padding:6px 14px;border-bottom:1px solid rgba(128,128,128,.1);display:flex;align-items:center;gap:6px;flex-wrap:wrap">'
        + '<span style="font-size:10px;font-weight:700;letter-spacing:.06em;color:' + wfColor + '">' + wfIcon + ' WORKFLOW</span>'
        + (wfAC ? '<span style="font-size:10px;color:' + wfColor + ';opacity:.5">· ' + wfAC + ' agents</span>' : '')
        + runB + stbB + doneB
        + (wfLabel ? '<span style="font-size:10px;opacity:.2;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(wfLabel) + '</span>' : '')
        + '</div>';
    }

    var h = '<div style="border-bottom:1px solid rgba(128,128,128,.1)">'
      + '<div style="display:flex;align-items:center;gap:6px;padding:8px 14px">'
      + '<span style="font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' + wfColor + '">' + wfIcon + ' WORKFLOW</span>'
      + (wfAC ? '<span style="font-size:10px;color:' + wfColor + ';opacity:.6">· ' + wfAC + '</span>' : '')
      + runB + stbB + doneB
      + (wfLabel ? '<span style="font-size:10px;opacity:.25;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(wfLabel) + '</span>' : '<span style="flex:1"></span>')
      + '</div>'
      + '<div style="padding:0 14px 10px;max-height:400px;overflow-y:auto;scrollbar-width:thin">';

    if (wp2 && wp2.phases && wp2.phases.length) {
      h += '<div style="display:flex;flex-wrap:wrap;gap:3px;margin-bottom:8px">';
      wp2.phases.forEach(function(p) {
        var pa = wfAgents ? wfAgents.filter(function(a){ return a.phase === p; }) : [];
        var pd = pa.length > 0 && pa.every(function(a){ return a.status === 'done'; });
        var pr = pa.some(function(a){ return a.status !== 'done'; });
        var pc = pd ? '#4caf50' : pr ? '#4a9eff' : '#888';
        h += '<span style="font-size:9px;padding:2px 7px;border-radius:8px;background:' + pc + '18;color:' + pc + ';border:1px solid ' + pc + '33">' + (pd?'✓ ':pr?'⟳ ':'') + esc(p) + '</span>';
      });
      h += '</div>';
    }

    root._wfAgentExpanded = root._wfAgentExpanded || new Set();
    if (wfAgents && wfAgents.length) {
      h += wfAgents.filter(function(a){ return a.status !== 'done'; }).map(function(a, ai) {
        var mc = (a.model || '').toLowerCase();
        var mC = mc.includes('opus') ? '#9c6af7' : mc.includes('haiku') ? '#4a9eff' : '#ff9800';
        var mL = txAgents ? a.model || '' : (a.model || '').replace(/^claude-/,'').replace(/-\d{8}$/,'').replace(/-latest$/,'');
        var tL = (a.label || 'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim() || (a.label || 'agent');
        var sd = txAgents ? (a.currentTool ? 'using ' + a.currentTool : '') : (a.phase || '');
        var ak = wfSid + '-' + ai;
        var ae = root._wfAgentExpanded.has(ak);
        return '<div data-wf-agent-expand="' + ak + '" style="display:flex;flex-direction:column;gap:1px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,.04);cursor:pointer">'
          + '<div style="display:flex;align-items:flex-start;gap:5px">'
          + '<span style="width:6px;height:6px;border-radius:50%;background:' + wfColor + ';flex-shrink:0;display:inline-block;margin-top:3px;animation:pulse 1.2s ease-in-out infinite"></span>'
          + '<span style="flex:1;' + (ae?'word-break:break-word':'overflow:hidden;text-overflow:ellipsis;white-space:nowrap') + ';cursor:pointer;font-size:10px">' + esc(tL) + '<span style="opacity:.3">' + (ae?' ▾':' ▸') + '</span></span>'
          + '<span style="font-size:9px;color:' + wfColor + ';opacity:.8;flex-shrink:0;font-weight:600">running</span>'
          + (mL ? '<span style="font-size:9px;padding:1px 5px;border-radius:6px;background:' + mC + '22;color:' + mC + ';font-weight:600;flex-shrink:0">' + esc(mL) + '</span>' : '')
          + '</div>' + (sd ? '<div style="font-size:9px;opacity:.3;padding-left:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(sd) + '</div>' : '') + '</div>';
      }).join('');
      if (standby > 0) h += '<div style="display:flex;align-items:center;gap:5px;padding:4px 0;border-top:1px solid rgba(255,255,255,.04)"><span style="width:6px;height:6px;border-radius:50%;background:#ff9800;flex-shrink:0;display:inline-block;opacity:.6"></span><span style="flex:1;font-size:10px;color:#ff9800;opacity:.7">' + standby + ' agent' + (standby!==1?'s':'') + ' on standby</span><span style="font-size:9px;color:#ff9800;opacity:.5;font-weight:600">standby</span></div>';
      var dW = wfAgents.filter(function(a){ return a.status === 'done'; });
      if (dW.length) {
        var dm = []; dW.forEach(function(a){ var m=(a.model||'').trim(); if(m&&dm.indexOf(m)<0)dm.push(m); });
        h += '<div style="font-size:9px;opacity:.28;padding:6px 0 2px;border-top:1px solid rgba(255,255,255,.05)">✓ ' + dW.length + ' done' + (dm.length ? ' · ' + dm.join(', ') : '') + '</div>';
      }
    } else if (s.agents && s.agents.length) {
      var rEv = s.agents.filter(function(a){ return !a.done; });
      var dEv = s.agents.filter(function(a){ return a.done;  });
      h += rEv.map(function(a) {
        var l2 = (a.label||'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim() || (a.label||'agent');
        var rc = (a.role||'').toLowerCase().includes('debug') ? '#f44336' : (a.role||'').toLowerCase().includes('research') ? '#9c6af7' : '#4a9eff';
        return '<div style="display:flex;align-items:center;gap:5px;padding:3px 0;font-size:10px"><span style="width:5px;height:5px;border-radius:50%;background:' + wfColor + ';flex-shrink:0;display:inline-block;animation:pulse 1.2s ease-in-out infinite"></span><span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(l2) + '</span>' + (a.role ? '<span style="font-size:9px;padding:1px 5px;border-radius:6px;background:' + rc + '22;color:' + rc + '">' + esc(a.role) + '</span>' : '') + '<span style="font-size:9px;color:' + wfColor + ';opacity:.7;font-weight:600">running</span></div>';
      }).join('');
      if (dEv.length) h += '<div style="font-size:9px;opacity:.28;padding:6px 0 2px;border-top:1px solid rgba(255,255,255,.05)">✓ ' + dEv.length + ' done</div>';
    } else {
      var isBg = wp2 && wp2.status === 'done' && !!bgLaunch2;
      var sk = (wp2 && wp2.total) || s.workflowAgentCount || 0;
      if (isBg) {
        h += '<div style="font-size:10px;opacity:.5;padding:2px 0">Background workflow</div><div style="font-size:9px;opacity:.3;margin-top:4px;line-height:1.5">Agents run inside the workflow harness — individual tracking unavailable for background launches.</div>';
      } else if (sk > 0) {
        h += '<div style="font-size:10px;opacity:.35;margin-bottom:6px">' + sk + ' agent' + (sk!==1?'s':'') + ' — waiting for details</div>';
        for (var wi = 0; wi < Math.min(sk, 8); wi++) {
          h += '<div style="display:flex;align-items:center;gap:6px;padding:3px 0"><span style="width:5px;height:5px;border-radius:50%;background:' + wfColor + ';flex-shrink:0;display:inline-block;animation:pulse 1.2s ease-in-out infinite;animation-delay:' + (wi*0.15) + 's"></span><span style="flex:1;height:8px;border-radius:3px;background:rgba(255,255,255,.06)"></span></div>';
        }
      } else {
        h += '<div style="font-size:10px;opacity:.35;padding:4px 0">Workflow running — agent count unknown</div>';
      }
    }
    return h + '</div></div>';
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.workflowPanel = { buildWfPanel: buildWfPanel };
})(typeof globalThis !== 'undefined' ? globalThis : this);
