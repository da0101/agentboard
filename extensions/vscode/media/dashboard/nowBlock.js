// Agentboard dashboard — NOW block updater (live/idle/workflow status + file/tool display)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }

  function updateNowBlock(d, isMultiNow, isWorkflow) {
    var txt = _core().txt;
    var esc = _core().esc;
    var relTime = _core().relTime;
    var nowEl    = root.document.getElementById('now');
    var dot      = root.document.getElementById('now-dot');
    var stateEl  = root.document.getElementById('now-state');
    if (!nowEl || !dot || !stateEl) return;

    if (isMultiNow) {
      nowEl.classList.remove('idle'); dot.classList.remove('idle');
      var liveSessions = d.activeSessions.filter(function(s){
        return s.lastUpdated && (Date.now() - new Date(s.lastUpdated).getTime() < 180000);
      });
      var totalCost = d.activeSessions.reduce(function(sum, s){ return sum + (s.costUsd || 0); }, 0);
      stateEl.textContent = liveSessions.length + ' ACTIVE';
      stateEl.style.color = '#4caf50';
      dot.style.background = '#4caf50'; dot.style.animation = 'pulse 1.5s ease-in-out infinite';
      var summaryParts = [d.activeSessions.length + ' sessions'];
      if (totalCost > 0) summaryParts.push('$' + totalCost.toFixed(2) + ' total');
      if (d.branch) summaryParts.push(d.branch);
      txt('now-stats', summaryParts.join(' · '));
    } else if (d.hasLive) {
      nowEl.classList.remove('idle'); dot.classList.remove('idle');
      if (isWorkflow) {
        stateEl.textContent = 'WORKFLOW'; stateEl.style.color = '#4a9eff';
        dot.style.background = '#4a9eff'; dot.style.animation = 'pulse 0.6s ease-in-out infinite';
      } else {
        stateEl.textContent = 'LIVE'; stateEl.style.color = '#4caf50';
        dot.style.background = '#4caf50'; dot.style.animation = 'pulse 1.5s ease-in-out infinite';
      }
    } else {
      nowEl.classList.add('idle'); dot.classList.add('idle');
      stateEl.textContent = 'IDLE'; stateEl.style.color = '#666'; dot.style.background = '#666';
    }
    if (!isMultiNow) txt('now-stats', [d.model, d.cost, d.sessionTime].filter(Boolean).join(' · '));

    var nowFileRow = root.document.getElementById('now-file-row');
    var lopEl = root.document.getElementById('now-longop');
    if (isMultiNow) {
      if (nowFileRow) nowFileRow.style.display = 'none';
      if (lopEl) { lopEl.className = 'now-longop'; lopEl.textContent = ''; }
      txt('now-desc', '');
    } else {
      if (nowFileRow) nowFileRow.style.display = '';
      if (d.lastEventLabel) {
        var fa0 = d.fileActivity && d.fileActivity[0];
        var isSkill   = fa0 && fa0.tool === 'Skill';
        var isWaiting = d.lastEventLabel === 'AskUserQuestion' || d.lastEventLabel === 'AskUser';
        var nowFile = root.document.getElementById('now-file');
        var nowTool = root.document.getElementById('now-tool');
        if (nowFile) {
          nowFile.textContent = isWaiting ? 'Waiting for your reply' : d.lastEventLabel;
          nowFile.style.color = isWaiting ? '#888' : isSkill ? '#4caf84' : '#e8e8e8';
        }
        txt('now-ago', relTime(d.lastEventTs));
        if (nowTool) {
          if (isWaiting) {
            nowTool.textContent = ''; nowTool.style.background = 'none';
          } else {
            nowTool.textContent = isSkill ? '⚡ skill' : (fa0 ? fa0.tool : '');
            nowTool.style.background = isSkill ? 'rgba(76,175,132,.15)' : 'rgba(255,255,255,.08)';
            nowTool.style.color = isSkill ? '#4caf84' : 'inherit';
          }
        }
      }
      txt('now-desc', d.streamDesc || '');
      if (lopEl) {
        lopEl.className = 'now-longop' + (d.isInLongOp ? ' on' : '');
        lopEl.textContent = '⟳ Running long operation — last tool call completed >90s ago';
        lopEl.style.color = '#ff9800';
      }
    }
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.nowBlock = { updateNowBlock: updateNowBlock };
})(typeof globalThis !== 'undefined' ? globalThis : this);
