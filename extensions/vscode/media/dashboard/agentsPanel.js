// Agentboard dashboard — agents / workflow panel (global single-session panel)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }

  function renderAgentCard(a, i) {
    var esc = _core().esc;
    var done = a.status === 'done';
    var pulse = done
      ? '<span style="width:6px;height:6px;border-radius:50%;background:#4caf50;display:inline-block;flex-shrink:0;margin-top:3px"></span>'
      : '<span class="ag-pulse" style="margin-top:3px"></span>';
    var roleTag  = a.role  ? '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">' + esc(a.role)  + '</span>' : '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#88888820;color:#888">no role</span>';
    var skillTag = a.skill ? '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4caf8422;color:#4caf84">' + esc(a.skill) + '</span>' : '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#88888820;color:#888">no skill</span>';
    var modelRaw   = a.model || '';
    var modelLabel = modelRaw.replace('claude-','').replace(/-\d{8}$/,'').replace('-latest','');
    var modelColor = modelRaw.includes('opus') ? '#9c6af7' : modelRaw.includes('haiku') ? '#4a9eff' : '#ff9800';
    var modelTag   = modelLabel ? '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:' + modelColor + '22;color:' + modelColor + '">' + esc(modelLabel) + '</span>' : '';
    var phaseTag   = a.phase ? '<span style="font-size:10px;opacity:.35;padding:1px 4px">' + esc(a.phase) + '</span>' : '';
    var num = '<span style="font-size:10px;opacity:.25;flex-shrink:0;min-width:18px;margin-top:1px">' + (i+1) + '</span>';
    return '<div class="ag-row" style="align-items:flex-start;gap:5px;padding:6px 0;border-bottom:1px solid rgba(128,128,128,.07)">'
      + num + pulse
      + '<div style="flex:1;min-width:0">'
      + '<div style="font-size:11px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-bottom:4px;' + (done ? 'text-decoration:line-through;opacity:.4' : '') + '">' + esc(a.label) + '</div>'
      + '<div style="display:flex;flex-wrap:wrap;gap:3px">' + roleTag + skillTag + modelTag + phaseTag + '</div>'
      + '</div>'
      + '</div>';
  }

  // d           — full data object
  // agentsEl    — #agents-list DOM element
  // agentsTtl   — #agents-ttl DOM element
  // wp          — workflowPlan (from active session, or null)
  // hasWf       — boolean: workflow is active
  function updateAgentsPanel(d, agentsEl, agentsTtl, wp, hasWf) {
    if (!agentsEl) return;
    var esc = _core().esc;
    var relTime = _core().relTime;
    var renderActivityRow = root.AgentboardDashboard.activityRow.renderActivityRow;

    if (hasWf) {
      var liveRunning = !!(d.activeWorkflow && d.activeWorkflow.label);
      var bgLaunch = wp && wp.status === 'done' && wp.ended_at && wp.started_at
        && (new Date(wp.ended_at).getTime() - new Date(wp.started_at).getTime() < 30000);
      var isDone = wp && wp.status === 'done' && !liveRunning && !bgLaunch;
      var wfName = wp ? wp.name : (d.activeWorkflow ? d.activeWorkflow.label : 'workflow');
      var agentCount = wp ? wp.total : (d.activeWorkflow ? d.activeWorkflow.agentCount : 0);
      var dotColor = isDone ? '#4caf50' : '#4a9eff';
      var stateLabel = isDone ? '✓ WORKFLOW DONE' : '⟳ WORKFLOW';
      var wfNameLabel = (wfName && wfName.toLowerCase() !== 'workflow')
        ? ' <span style="font-weight:400;opacity:.35;font-size:10px;text-transform:none;letter-spacing:0;margin-left:4px">' + esc(wfName) + '</span>' : '';
      if (agentsTtl) agentsTtl.innerHTML = '<span style="color:' + dotColor + ';font-weight:700">' + stateLabel + '</span>'
        + (agentCount ? ' <span style="color:' + dotColor + ';font-weight:700"> · ' + agentCount + ' agents</span>' : '')
        + wfNameLabel;

      var phasePills = '';
      if (wp && wp.phases && wp.phases.length) {
        phasePills = '<div style="display:flex;flex-wrap:wrap;gap:4px;margin-bottom:8px">'
          + wp.phases.map(function(p) {
            var phDone = wp.agents && wp.agents.filter(function(a){ return a.phase===p; }).every(function(a){ return a.status==='done'; }) && wp.agents.some(function(a){ return a.phase===p; });
            return '<span style="font-size:10px;padding:1px 7px;border-radius:10px;background:#4a9eff' + (phDone?'44':'22') + ';color:#4a9eff;border:1px solid #4a9eff44">' + (phDone?'✓ ':'') + esc(p) + '</span>';
          }).join('') + '</div>';
      }

      var cards = '';
      if (wp && wp.agents && wp.agents.length) {
        cards = wp.agents.map(renderAgentCard).join('');
      } else if (liveRunning && agentCount) {
        var elapsed = d.activeWorkflow ? relTime(d.activeWorkflow.ts) : '';
        cards = '<div style="font-size:11px;color:#4a9eff;opacity:.7;padding:4px 0 8px">' + agentCount + ' agents running since ' + elapsed + '</div>'
          + Array.from({length: Math.min(agentCount, 8)}, function(_, i) {
            return '<div class="ag-row" style="align-items:center;gap:6px;padding:5px 0;border-bottom:1px solid rgba(128,128,128,.07)">'
              + '<span class="ag-pulse"></span>'
              + '<span style="flex:1;height:10px;border-radius:4px;background:rgba(255,255,255,.07);animation:pulse 1.8s ease-in-out infinite;animation-delay:' + (i*0.15) + 's"></span>'
              + '</div>';
          }).join('')
          + '<div style="font-size:10px;opacity:.3;margin-top:8px">Add <code>label: "role:X · skill:Y · task"</code> to agent() calls for details</div>';
      } else {
        cards = '<div style="font-size:11px;opacity:.4;padding:6px 0">No agents this workflow</div>';
      }
      agentsEl.innerHTML = phasePills + cards;

    } else if (d.isSessionTab && d.sessionWorkflow) {
      if (agentsTtl) agentsTtl.style.display = 'none';
      agentsEl.innerHTML = root.AgentboardDashboard.workflowPanel.buildWfPanel(d.sessionWorkflow, true);

    } else if (d.recentAgents && d.recentAgents.length) {
      var attributed = (d.agentActivity || []).reduce(function(map, a) { map[a.agentId || a.label] = a; return map; }, {});
      var _agNow = Date.now(), _agRecentMs = 5 * 60 * 1000;
      var running   = d.recentAgents.filter(function(a){ return !a.done; });
      var recentDone = d.recentAgents.filter(function(a){ return a.done && a.ts && (_agNow - new Date(a.ts).getTime()) < _agRecentMs; });
      var oldDone    = d.recentAgents.filter(function(a){ return a.done && (!a.ts || (_agNow - new Date(a.ts).getTime()) >= _agRecentMs); });
      var visibleAgents = running.concat(recentDone);
      if (agentsTtl) agentsTtl.innerHTML = 'Agents'
        + (running.length ? ' <span style="color:#4caf50;font-weight:700">' + running.length + ' running</span>' : '')
        + (d.recentAgents.filter(function(a){ return a.done; }).length ? ' <span style="opacity:.4;font-size:11px"> ' + d.recentAgents.filter(function(a){ return a.done; }).length + ' done</span>' : '')
        + '<span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none"> · this session</span>';
      agentsEl.innerHTML = visibleAgents.map(function(a) {
        var pulse = a.done
          ? '<span style="width:6px;height:6px;border-radius:50%;background:#555;display:inline-block;flex-shrink:0"></span>'
          : '<span class="ag-pulse"></span>';
        var roleTag  = a.role  ? '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">' + esc(a.role)  + '</span>' : '';
        var skillTag = a.skill ? '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4caf8422;color:#4caf84">' + esc(a.skill) + '</span>' : '';
        var activity = (attributed[a.agentId || a.label] && attributed[a.agentId || a.label].activity) || [];
        var activityHtml = activity.length
          ? '<div style="margin-left:14px;margin-top:4px;border-left:1px solid rgba(255,255,255,.08);padding-left:8px">'
            + activity.slice(0,5).map(function(item) {
              var ic = item.file && item.file.startsWith('$ ') ? '$' : (_core().TOOL_ICON[item.tool] || '·');
              return '<div style="display:flex;gap:6px;align-items:center;min-width:0;font-size:10px;opacity:.68;padding:1px 0">'
                + '<span style="color:#f0b429;flex-shrink:0">' + esc(ic) + '</span>'
                + '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1">' + esc(item.file) + '</span>'
                + (item.count>1 ? '<span style="opacity:.45;flex-shrink:0">×' + item.count + '</span>' : '')
                + '<span style="opacity:.45;flex-shrink:0">' + relTime(item.lastTs) + '</span>'
                + '</div>';
            }).join('')
            + '</div>'
          : '';
        return '<div style="border-bottom:1px solid rgba(128,128,128,.07);padding:4px 0">'
          + '<div class="ag-row">' + pulse + '<span class="ag-label" style="' + (a.done?'opacity:.4':'') + '">' + esc(a.label) + '</span>' + roleTag + skillTag + '<span class="ag-t">' + relTime(a.ts) + '</span></div>'
          + activityHtml
          + '</div>';
      }).join('')
        + (oldDone.length ? '<div style="font-size:9px;opacity:.25;padding:4px 0;border-top:1px solid rgba(255,255,255,.05)">✓ ' + oldDone.length + ' done earlier</div>' : '');
    } else {
      if (agentsTtl) agentsTtl.innerHTML = 'Agents <span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none">· this session</span>';
      agentsEl.innerHTML = '<div class="em">No sub-agents</div>';
    }
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.agentsPanel = {
    renderAgentCard:   renderAgentCard,
    updateAgentsPanel: updateAgentsPanel
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
