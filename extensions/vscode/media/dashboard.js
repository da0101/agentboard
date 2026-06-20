// agentboard dashboard webview script — loaded as external file to satisfy VS Code CSP
/* global acquireVsCodeApi */

const vscode = acquireVsCodeApi();
window._vscode = vscode; // make accessible to inline onclick attributes
const TYPE_COLOR={bugfix:'#e8823a',feature:'#4caf84',task:'#4a9eff',maintenance:'#888',research:'#9c6af7'};
const TOOL_ICON={Edit:'✏',Write:'✏',Bash:'$',Read:'👁',WebSearch:'⌕',WebFetch:'⌕',Agent:'◈',Skill:'⚡'};
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}
function html(id,h){const el=document.getElementById(id);if(el)el.innerHTML=h;}

function renderStreams(streams, activeStream) {
  if (!streams || !streams.length) return '<div class="em">No active streams</div>';
  return streams.map(function(s, i) {
    const isA = s.slug === activeStream;
    const c = TYPE_COLOR[s.type] || '#888';
    const statColor = {active:'#4caf50','in-progress':'#4caf50','awaiting-verification':'#ff9800',blocked:'#f44336',paused:'#888'}[s.status] || '#888';
    const doneCount = s.doneCriteria ? s.doneCriteria.filter(function(x){return x.done;}).length : 0;
    const totalCount = s.doneCriteria ? s.doneCriteria.length : 0;
    const pct = totalCount > 0 ? Math.round(doneCount / totalCount * 100) : null;
    var header = '<div class="sr-hdr" data-toggle-id="sr-detail-'+i+'" style="cursor:pointer;display:flex;align-items:center;gap:6px;padding:6px 4px;border-radius:4px;transition:background .15s">'
      + '<span style="width:7px;height:7px;border-radius:50%;background:'+(isA?'#4caf50':c)+';flex-shrink:0"></span>'
      + '<span style="font-size:12px;font-weight:'+(isA?'600':'400')+';color:'+(isA?'#4caf84':'#ccc')+';flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(s.slug)+'</span>'
      + (pct!==null?'<span style="font-size:10px;opacity:.45">'+doneCount+'/'+totalCount+'</span>':'')
      + '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+c+'22;color:'+c+'">'+esc(s.type)+'</span>'
      + '<span style="font-size:10px;opacity:.4">▾</span>'
      + '</div>';
    var detail = '<div id="sr-detail-'+i+'" style="display:'+(isA?'block':'none')+';padding:0 4px 8px 18px;border-left:2px solid '+c+'44;margin-left:3px">';
    detail += '<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:6px">'
      + '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+statColor+'22;color:'+statColor+'">'+esc(s.status)+'</span>'
      + (s.role?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">'+esc(s.role)+'</span>':'')
      + (s.branch?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4a9eff22;color:#4a9eff;font-family:monospace">'+esc(s.branch)+'</span>':'')
      + '</div>';
    if (s.objective) detail += '<div style="font-size:11px;opacity:.65;margin-bottom:6px;line-height:1.5">'+esc(s.objective.slice(0,200))+'</div>';
    if (s.doneCriteria && s.doneCriteria.length) {
      detail += '<div style="font-size:10px;opacity:.35;text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px">Done criteria</div>';
      detail += s.doneCriteria.map(function(cr){
        return '<div style="display:flex;gap:5px;font-size:11px;margin-bottom:3px;'+(cr.done?'opacity:.4':'opacity:.8')+'">'
          + '<span style="flex-shrink:0;color:'+(cr.done?'#4caf50':'#666')+'">'+(cr.done?'✓':'○')+'</span>'
          + '<span style="'+(cr.done?'text-decoration:line-through':'')+'">'+esc(cr.text)+'</span>'
          + '</div>';
      }).join('');
    }
    if (s.nextAction) detail += '<div style="margin-top:6px;font-size:10px;opacity:.35;text-transform:uppercase;letter-spacing:.06em">Next action</div>'
      + '<div style="font-size:11px;color:#ff9800;margin-top:2px">→ '+esc(s.nextAction)+'</div>';
    detail += '<div style="margin-top:8px"><button data-open-stream="'+esc(s.filePath)+'" style="font-size:10px;padding:3px 10px;border-radius:4px;background:#4a9eff22;color:#4a9eff;border:1px solid #4a9eff44;cursor:pointer">Open stream file ↗</button></div>';
    detail += '</div>';
    return '<div class="sr-item">'+header+detail+'</div>';
  }).join('');
}

// Deterministic pet name from session ID (like Docker: "swift-falcon")
const _SN_ADJ=['bold','calm','swift','bright','deep','sharp','keen','dark','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','teal','grey','sage'];
const _SN_NON=['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch'];
function sessionNickname(id) {
  var h = 0;
  for (var i = 0; i < id.length; i++) h = (Math.imul(h, 31) + id.charCodeAt(i)) >>> 0;
  return _SN_ADJ[h % _SN_ADJ.length] + '-' + _SN_NON[(h >>> 8) % _SN_NON.length];
}
function txt(id,t){const el=document.getElementById(id);if(el)el.textContent=t;}
function switchTab(id,btn){
  document.querySelectorAll('.view').forEach(v=>v.classList.remove('on'));
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));
  document.getElementById(id).classList.add('on');btn.classList.add('on');
}
function relTime(iso){
  if(!iso)return'';
  const ms=new Date(iso).getTime();
  if(isNaN(ms))return'?';
  const s=Math.floor((Date.now()-ms)/1000);
  if(s<0)return'just now';
  if(s<60)return s+'s ago';
  if(s<3600)return Math.floor(s/60)+'m ago';
  return Math.floor(s/3600)+'h ago';
}
function toggleStream(id){
  const el=document.getElementById(id);
  if(!el)return;
  if(id==='sr-list2-body'){
    const open=el.style.display!=='none';
    el.style.display=open?'none':'block';
    const arrow=document.getElementById('sr-toggle-arrow');
    if(arrow)arrow.textContent=open?'▸':'▾';
    return;
  }
  const open=el.style.display==='block';
  document.querySelectorAll('[id^="sr-detail-"]').forEach(function(e){e.style.display='none';});
  if(!open)el.style.display='block';
}
function openStream(fp){vscode.postMessage({command:'openStream',filePath:fp});}
function ctxBar(pct){
  if(pct===null||pct===undefined)return'—';
  const used=Math.round(100-pct);const fill=Math.floor(used/10);
  const c=used<50?'#4caf50':used<75?'#ff9800':'#f44336';
  return '<span class="ctx" style="color:'+c+'">'+'█'.repeat(fill)+'░'.repeat(10-fill)+'</span><span style="color:'+c+';font-size:11px"> '+used+'%</span>';
}
function renderCatalogCol(listId, items, accentColor) {
  const MAX = 200;
  window._catExpanded = window._catExpanded || new Set();
  let h = items.slice(0, MAX).map(function(item, idx) {
    var eid = listId + '-' + idx;
    var isOpen = window._catExpanded.has(eid);
    var hasMore = item.fullDescription && item.fullDescription !== item.description && item.fullDescription.length > 10;
    var usedBy = item.usedBy && item.usedBy.length ? item.usedBy : null;

    var row = '<div class="ci" style="cursor:' + (hasMore ? 'pointer' : 'default') + '" data-cat-toggle="' + eid + '">';
    row += '<div style="display:flex;align-items:baseline;gap:6px;flex-wrap:wrap">';
    row += '<span class="ci-name">' + esc(item.name) + '</span>';
    if (hasMore) row += '<span style="font-size:9px;opacity:.25">' + (isOpen ? '▾' : '▸') + '</span>';
    if (usedBy) {
      row += usedBy.map(function(nick) {
        return '<span style="font-size:9px;padding:1px 5px;border-radius:8px;background:' + (accentColor||'#4a9eff') + '22;color:' + (accentColor||'#4a9eff') + ';white-space:nowrap">' + esc(nick) + '</span>';
      }).join('');
    }
    row += '</div>';
    if (item.description) row += '<span class="ci-desc">' + esc(item.description.slice(0, 120)) + '</span>';
    if (hasMore) row += '<div id="' + eid + '-body" style="display:' + (isOpen ? 'block' : 'none') + ';font-size:11px;opacity:.55;line-height:1.6;margin-top:4px;white-space:pre-wrap;border-left:2px solid ' + (accentColor||'#4a9eff') + '44;padding-left:8px">' + esc(item.fullDescription || '') + '</div>';
    row += '</div>';
    return row;
  }).join('');
  if (items.length > MAX) h += '<div class="more">+' + (items.length - MAX) + ' more</div>';
  html(listId, h);
}

function applyUpdate(d){

  // header
  txt('h-proj',d.projectName||'—');
  const br=document.getElementById('h-br'),sep=document.getElementById('h-sep2');
  if(br&&sep){br.textContent=d.branch||'';sep.style.display=d.branch?'':'none';}

  // tabs
  const tc=document.getElementById('tab-catalog');
  if(tc)tc.textContent='Catalog · '+(d.skillCount+d.roleCount);

  // NOW block — multi-session: show summary. single-session: show live status.
  const nowEl=document.getElementById('now');
  const dot=document.getElementById('now-dot');
  const stateEl=document.getElementById('now-state');
  const ctxNow=d.ctxPct!==null&&d.ctxPct!==undefined?Math.round(100-d.ctxPct):0;
  const isWorkflow=!!(d.activeWorkflow);
  const isMultiNow = d.activeSessions && d.activeSessions.length > 1;
  if(isMultiNow){
    // Multi-session summary banner
    nowEl.classList.remove('idle');dot.classList.remove('idle');
    var liveSessions = d.activeSessions.filter(function(s){ return s.lastUpdated && (Date.now()-new Date(s.lastUpdated).getTime()<180000); });
    var totalCost = d.activeSessions.reduce(function(sum,s){ return sum+(s.costUsd||0); },0);
    stateEl.textContent = liveSessions.length + ' ACTIVE';
    stateEl.style.color='#4caf50';
    dot.style.background='#4caf50';dot.style.animation='pulse 1.5s ease-in-out infinite';
    var summaryParts=[d.activeSessions.length+' sessions'];
    if(totalCost>0) summaryParts.push('$'+totalCost.toFixed(2)+' total');
    if(d.branch) summaryParts.push(d.branch);
    txt('now-stats',summaryParts.join(' · '));
  } else if(d.hasLive){
    nowEl.classList.remove('idle');dot.classList.remove('idle');
    const isCompact=d.isInLongOp&&ctxNow>=75;
    if(isWorkflow){
      stateEl.textContent='WORKFLOW';stateEl.style.color='#4a9eff';
      dot.style.background='#4a9eff';dot.style.animation='pulse 0.6s ease-in-out infinite';
    } else if(isCompact){
      stateEl.textContent='COMPACTING';stateEl.style.color='#9c6af7';
      dot.style.background='#9c6af7';dot.style.animation='pulse 0.6s ease-in-out infinite';
    } else {
      stateEl.textContent='LIVE';stateEl.style.color='#4caf50';
      dot.style.background='#4caf50';dot.style.animation='pulse 1.5s ease-in-out infinite';
    }
  } else {
    nowEl.classList.add('idle');dot.classList.add('idle');
    stateEl.textContent='IDLE';stateEl.style.color='#666';dot.style.background='#666';
  }
  if(!isMultiNow) txt('now-stats',[d.model,d.cost,d.sessionTime].filter(Boolean).join(' · '));
  // Tool/file line and long-op warning: only show in single-session mode
  const nowFileRow = document.getElementById('now-file-row');
  const lopEl = document.getElementById('now-longop');
  if(isMultiNow){
    if(nowFileRow) nowFileRow.style.display='none';
    if(lopEl){ lopEl.className='now-longop'; lopEl.textContent=''; }
    txt('now-desc','');
  } else {
    if(nowFileRow) nowFileRow.style.display='';
    if(d.lastEventLabel){
      const fa0=d.fileActivity&&d.fileActivity[0];
      const isSkill=fa0&&fa0.tool==='Skill';
      const isWaiting=d.lastEventLabel==='AskUserQuestion'||d.lastEventLabel==='AskUser';
      const nowFile=document.getElementById('now-file');
      const nowTool=document.getElementById('now-tool');
      if(nowFile){
        nowFile.textContent=isWaiting?'Waiting for your reply':d.lastEventLabel;
        nowFile.style.color=isWaiting?'#888':isSkill?'#4caf84':'#e8e8e8';
      }
      txt('now-ago',relTime(d.lastEventTs));
      if(nowTool){
        if(isWaiting){
          nowTool.textContent='';nowTool.style.background='none';
        } else {
          nowTool.textContent=isSkill?'⚡ skill':fa0?fa0.tool:'';
          nowTool.style.background=isSkill?'rgba(76,175,132,.15)':'rgba(255,255,255,.08)';
          nowTool.style.color=isSkill?'#4caf84':'inherit';
        }
      }
    }
    txt('now-desc',d.streamDesc||'');
    const ctxUsed=d.ctxPct!==null&&d.ctxPct!==undefined?Math.round(100-d.ctxPct):0;
    const isCompacting=d.isInLongOp&&ctxUsed>=75;
    if(lopEl){
      lopEl.className='now-longop'+(d.isInLongOp?' on':'');
      lopEl.textContent=isCompacting
        ?'⟳ Context at '+ctxUsed+'% — compaction in progress (will update when complete)'
        :'⟳ Running long operation — last tool call completed >90s ago';
      lopEl.style.color=isCompacting?'#9c6af7':'#ff9800';
    }
  }

  // file activity
  var _totalFiles = d.totalUniqueFiles || (d.fileActivity && d.fileActivity.length) || 0;
  var _shownFiles = d.fileActivity && d.fileActivity.length || 0;
  var _actLabel = 'Activity this session';
  if (_totalFiles > 0) {
    _actLabel += ' · ' + _totalFiles + ' file' + (_totalFiles !== 1 ? 's' : '');
    if (_shownFiles < _totalFiles) _actLabel += ' (showing ' + _shownFiles + ')';
  }
  txt('fa-ttl', _actLabel);
  html('fa-list', d.fileActivity&&d.fileActivity.length ? d.fileActivity.map(function(f){
    const isSkillEntry=f.tool==='Skill';
    const isBash=f.tool==='Bash';
    const icon=TOOL_ICON[f.tool]||'·';
    let fname;
    if(isSkillEntry) fname='/'+f.file;
    else fname=f.file; // full path/command — let .fa-file word-break handle layout
    const color=isSkillEntry?'color:#4caf84;font-weight:600':isBash?'color:#ff9800':'';
    return '<div class="fa">'
      +'<span class="fa-icon" style="'+(isSkillEntry?'color:#4caf84':'')+'">'+icon+'</span>'
      +'<div class="fa-body">'
      +'<span class="fa-file" style="'+color+'">'+esc(fname)+'</span>'
      +(f.count>1?'<span class="fa-cnt">×'+f.count+'</span>':'')
      +'<span class="fa-t">'+relTime(f.lastTs)+'</span>'
      +'</div>'
      +'</div>';
  }).join('') : '<div class="em">No edits or commands yet this session</div>');

  // agents / workflow panel
  const agentsEl=document.getElementById('agents-list');
  const agentsTtl=document.getElementById('agents-ttl');
  const wp=(d.activeSessions&&d.activeSessions.length===1)?d.activeSessions[0].workflowPlan:null;
  const hasWf=wp||(d.activeWorkflow&&d.activeWorkflow.label);

  function renderAgentCard(a,i){
    const done=a.status==='done';
    const pulse=done
      ?'<span style="width:6px;height:6px;border-radius:50%;background:#4caf50;display:inline-block;flex-shrink:0;margin-top:3px"></span>'
      :'<span class="ag-pulse" style="margin-top:3px"></span>';
    const roleTag=a.role?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">'+esc(a.role)+'</span>':'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#88888820;color:#888">no role</span>';
    const skillTag=a.skill?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4caf8422;color:#4caf84">'+esc(a.skill)+'</span>':'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#88888820;color:#888">no skill</span>';
    const modelRaw=a.model||'';
    const modelLabel=modelRaw.replace('claude-','').replace(/-\d{8}$/,'').replace('-latest','');
    const modelColor=modelRaw.includes('opus')?'#9c6af7':modelRaw.includes('haiku')?'#4a9eff':'#ff9800';
    const modelTag=modelLabel?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+modelColor+'22;color:'+modelColor+'">'+esc(modelLabel)+'</span>':'';
    const phaseTag=a.phase?'<span style="font-size:10px;opacity:.35;padding:1px 4px">'+esc(a.phase)+'</span>':'';
    const num='<span style="font-size:10px;opacity:.25;flex-shrink:0;min-width:18px;margin-top:1px">'+(i+1)+'</span>';
    return '<div class="ag-row" style="align-items:flex-start;gap:5px;padding:6px 0;border-bottom:1px solid rgba(128,128,128,.07)">'
      +num+pulse
      +'<div style="flex:1;min-width:0">'
      +'<div style="font-size:11px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-bottom:4px;'+(done?'text-decoration:line-through;opacity:.4':'')+'">'+esc(a.label)+'</div>'
      +'<div style="display:flex;flex-wrap:wrap;gap:3px">'+roleTag+skillTag+modelTag+phaseTag+'</div>'
      +'</div>'
      +'</div>';
  }

  if(agentsEl&&hasWf){
    // activeWorkflow from events is the authoritative "still running" signal.
    // Also treat workflowPlan as "still running" if ended_at - started_at < 30s
    // (background launch — PostToolUse fires instantly, actual workflow runs for hours)
    const liveRunning = !!(d.activeWorkflow && d.activeWorkflow.label);
    const bgLaunch = wp && wp.status === 'done' && wp.ended_at && wp.started_at
      && (new Date(wp.ended_at).getTime() - new Date(wp.started_at).getTime() < 30000);
    const isDone = wp && wp.status === 'done' && !liveRunning && !bgLaunch;
    const wfName = wp ? wp.name : (d.activeWorkflow ? d.activeWorkflow.label : 'workflow');
    const agentCount = wp ? wp.total : (d.activeWorkflow ? d.activeWorkflow.agentCount : 0);
    const dotColor = isDone ? '#4caf50' : '#4a9eff';
    const stateLabel = isDone ? '✓ WORKFLOW DONE' : '⟳ WORKFLOW';
    var wfNameLabel = (wfName && wfName.toLowerCase() !== 'workflow') ? ' <span style="font-weight:400;opacity:.35;font-size:10px;text-transform:none;letter-spacing:0;margin-left:4px">'+esc(wfName)+'</span>' : '';
    if(agentsTtl)agentsTtl.innerHTML='<span style="color:'+dotColor+';font-weight:700">'+stateLabel+'</span>'
      +(agentCount?' <span style="color:'+dotColor+';font-weight:700"> · '+agentCount+' agents</span>':'')
      +wfNameLabel;
    let phasePills='';
    if(wp&&wp.phases&&wp.phases.length){
      phasePills='<div style="display:flex;flex-wrap:wrap;gap:4px;margin-bottom:8px">'
        +wp.phases.map(function(p){
          const phDone=wp.agents&&wp.agents.filter(function(a){return a.phase===p;}).every(function(a){return a.status==='done';})&&wp.agents.some(function(a){return a.phase===p;});
          return '<span style="font-size:10px;padding:1px 7px;border-radius:10px;background:#4a9eff'+(phDone?'44':'22')+';color:#4a9eff;border:1px solid #4a9eff44">'+(phDone?'✓ ':'')+esc(p)+'</span>';
        }).join('')+'</div>';
    }
    let cards='';
    if(wp&&wp.agents&&wp.agents.length){
      cards=wp.agents.map(renderAgentCard).join('');
    } else if(liveRunning && agentCount) {
      // Workflow running but no labels extracted — show live count with skeleton rows
      const elapsed = d.activeWorkflow ? relTime(d.activeWorkflow.ts) : '';
      cards = '<div style="font-size:11px;color:#4a9eff;opacity:.7;padding:4px 0 8px">'+agentCount+' agents running since '+elapsed+'</div>'
        + Array.from({length: Math.min(agentCount, 8)}, function(_,i) {
          return '<div class="ag-row" style="align-items:center;gap:6px;padding:5px 0;border-bottom:1px solid rgba(128,128,128,.07)">'
            +'<span class="ag-pulse"></span>'
            +'<span style="flex:1;height:10px;border-radius:4px;background:rgba(255,255,255,.07);animation:pulse 1.8s ease-in-out infinite;animation-delay:'+(i*0.15)+'s"></span>'
            +'</div>';
        }).join('')
        +'<div style="font-size:10px;opacity:.3;margin-top:8px">Add <code>label: "role:X · skill:Y · task"</code> to agent() calls for details</div>';
    } else {
      cards='<div style="font-size:11px;opacity:.4;padding:6px 0">No agents this workflow</div>';
    }
    agentsEl.innerHTML=phasePills+cards;
  } else if(agentsEl&&d.recentAgents&&d.recentAgents.length){
    const running=d.recentAgents.filter(function(a){return !a.done;});
    const done2=d.recentAgents.filter(function(a){return a.done;});
    if(agentsTtl)agentsTtl.innerHTML='Agents'
      +(running.length?' <span style="color:#4caf50;font-weight:700">'+running.length+' running</span>':'')
      +(done2.length?' <span style="opacity:.4;font-size:11px"> '+done2.length+' done</span>':'')
      +'<span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none"> · this session</span>';
    agentsEl.innerHTML=d.recentAgents.map(function(a){
      const pulse=a.done?'<span style="width:6px;height:6px;border-radius:50%;background:#555;display:inline-block;flex-shrink:0"></span>':'<span class="ag-pulse"></span>';
      const roleTag=a.role?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">'+esc(a.role)+'</span>':'';
      const skillTag=a.skill?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4caf8422;color:#4caf84">'+esc(a.skill)+'</span>':'';
      return '<div class="ag-row">'+pulse+'<span class="ag-label" style="'+(a.done?'opacity:.4':'')+'">'+esc(a.label)+'</span>'+roleTag+skillTag+'<span class="ag-t">'+relTime(a.ts)+'</span></div>';
    }).join('');
  } else if(agentsEl){
    if(agentsTtl)agentsTtl.innerHTML='Agents <span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none">· last 10 min</span>';
    agentsEl.innerHTML='<div class="em">No sub-agents — Claude is working solo</div>';
  }

  // Layout mode: multi-session columns vs single-session split
  const multiSession = d.activeSessions && d.activeSessions.length > 1;
  const liveBody = document.getElementById('live-body');
  const sessionColsEl = document.getElementById('session-cols');
  const streamsRowEl = document.getElementById('streams-row');
  const colL = document.querySelector('.col-l');
  const colR = document.querySelector('.col-r');

  if (multiSession && liveBody && sessionColsEl) {
    liveBody.classList.add('multi');
    sessionColsEl.style.display = 'flex';
    if (streamsRowEl) streamsRowEl.style.display = '';
    if (colL) colL.style.display = 'none';
    if (colR) colR.style.display = 'none';

    // 1 session = 100%, 2 = 50%, 3+ = 33.33%. flex-grow fills row if fewer than 3 on it.
    var totalSess = d.activeSessions.length;
    var colBasis = totalSess <= 1 ? '100%' : totalSess === 2 ? '50%' : '33.333%';
    sessionColsEl.innerHTML = d.activeSessions.map(function(s) { try {
      // Green dot = this session received a status update within the last 90s (status-bridge fires every turn)
      var lastUpdatedMs = s.lastUpdated ? new Date(s.lastUpdated).getTime() : 0;
      var isLive = lastUpdatedMs > 0 && (Date.now() - lastUpdatedMs < 180000);
      const nick = sessionNickname(s.sessionId);
      const displayName = (s.projectName || s.sessionId.slice(0, 8)) + ' · ' + nick;
      const age = s.ageSeconds < 60 ? s.ageSeconds + 's ago'
        : s.ageSeconds < 3600 ? Math.floor(s.ageSeconds / 60) + 'm ago'
        : Math.floor(s.ageSeconds / 3600) + 'h ago';
      const mc = s.model.toLowerCase();
      const modelColor = mc.includes('opus') ? '#9c6af7' : mc.includes('haiku') ? '#4a9eff' : '#ff9800';
      const dotColor = isLive ? '#4caf50' : '#555';
      const ctxUsed = s.ctxPct !== null && s.ctxPct !== undefined ? Math.round(100 - s.ctxPct) : null;
      const ctxFill = ctxUsed !== null ? Math.max(0,Math.min(10,Math.floor(ctxUsed / 10))) : 0;
      const ctxColor = ctxUsed === null ? '#555' : ctxUsed < 50 ? '#4caf50' : ctxUsed < 75 ? '#ff9800' : '#f44336';
      const ctxBar = ctxUsed !== null
        ? '<span style="color:' + ctxColor + ';font-size:10px">'
          + '█'.repeat(ctxFill) + '░'.repeat(10 - ctxFill) + ' ' + ctxUsed + '%</span>'
        : '';
      // Header
      const hdr = '<div class="sess-col-hdr">'
        + '<div class="sess-col-name">'
        + '<span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;background:' + dotColor + (isLive ? ';box-shadow:0 0 5px ' + dotColor + ';animation:pulse 1.5s ease-in-out infinite' : '') + '"></span>'
        + '<span style="font-size:12px;font-weight:' + (isLive ? '600' : '400') + ';color:' + (isLive ? '#e8e8e8' : '#aaa') + ';flex:1">' + esc(displayName) + '</span>'
        + '<span style="font-size:10px;padding:1px 6px;border-radius:8px;background:' + modelColor + '22;color:' + modelColor + '">' + esc(s.model) + '</span>'
        + '</div>'
        + '<div class="sess-col-grid">'
        + (s.stream ? '<span style="opacity:.4">Stream</span><span style="color:#4a9eff">' + esc(s.stream) + '</span>' : '')
        + (s.cost ? '<span style="opacity:.4">Cost</span><span>' + esc(s.cost) + '</span>' : '')
        + (s.sessionTime ? '<span style="opacity:.4">Time</span><span>' + esc(s.sessionTime) + '</span>' : '')
        + (ctxBar ? '<span style="opacity:.4">Context</span><span>' + ctxBar + '</span>' : '')
        + (s.branch ? '<span style="opacity:.4">Branch</span><span style="font-family:monospace;font-size:10px">' + esc(s.branch) + '</span>' : '')
        + '<span style="opacity:.4">Last</span><span style="opacity:.5">' + age + '</span>'
        + '</div>'
        + '</div>';
      // Agents panel (shown when agents active in last 30 min)
      var agentsHtml = '';
      if (s.agents && s.agents.length) {
        var runningAgents = s.agents.filter(function(a) { return !a.done; });
        var totalAgents = s.agents.length;
        var sid = s.sessionId;
        var expanded = window._agentExpanded && window._agentExpanded.has(sid);
        var chevron = expanded ? '▾' : '▸';
        var runBadge = runningAgents.length
          ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:#4caf5022;color:#4caf50;font-weight:700">' + runningAgents.length + ' running</span>'
          : '';
        var doneBadge = (totalAgents - runningAgents.length) > 0
          ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:rgba(255,255,255,.06);color:#888">' + (totalAgents - runningAgents.length) + ' done</span>'
          : '';
        var agentRows = s.agents.map(function(a) {
          var label = (a.label || 'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i, '').trim() || (a.label || 'agent');
          var roleColor = (a.role||'').toLowerCase().includes('debug') ? '#f44336' : (a.role||'').toLowerCase().includes('research') ? '#9c6af7' : '#4a9eff';
          var pulse = a.done
            ? '<span style="width:6px;height:6px;border-radius:50%;background:#444;flex-shrink:0;display:inline-block"></span>'
            : '<span style="width:6px;height:6px;border-radius:50%;background:#4caf50;flex-shrink:0;display:inline-block;animation:pulse 1.5s ease-in-out infinite"></span>';
          return '<div style="display:flex;align-items:center;gap:6px;padding:3px 0;font-size:11px;' + (a.done ? 'opacity:.35' : '') + '">'
            + pulse
            + '<span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(label) + '</span>'
            + (a.role ? '<span style="font-size:9px;padding:1px 5px;border-radius:8px;background:' + roleColor + '22;color:' + roleColor + '">' + esc(a.role) + '</span>' : '')
            + '<span style="font-size:9px;opacity:.3;white-space:nowrap">' + relTime(a.ts) + '</span>'
            + '</div>';
        }).join('');
        agentsHtml = '<div style="border-bottom:1px solid rgba(128,128,128,.1)">'
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

      // Workflow panel — collapsible, shown when THIS session launched a workflow
      var workflowHtml = '';
      if (s.hasWorkflow) {
        var wp2 = s.workflowPlan || null;
        var wfSid = 'wf-' + s.sessionId;
        var wfExpanded = window._workflowExpanded && window._workflowExpanded.has(wfSid);
        var bgLaunch2 = wp2 && wp2.status === 'done' && wp2.ended_at && wp2.started_at
          && (new Date(wp2.ended_at).getTime() - new Date(wp2.started_at).getTime() < 30000);
        // Running if: no plan yet (workflow launched but parser didn't capture it), OR plan is not done, OR bg launch
        var wfRunning = !wp2 || wp2.status !== 'done' || !!bgLaunch2;
        var wfColor = wfRunning ? '#4a9eff' : '#4caf50';
        var wfIcon = wfRunning ? '⟳' : '✓';
        var wfLabel = (wp2 && wp2.name && wp2.name.toLowerCase() !== 'workflow') ? wp2.name : (s.workflowLabel && s.workflowLabel.toLowerCase() !== 'workflow' ? s.workflowLabel : '');

        // Agents: transcript (journal-derived) > workflowPlan > AgentStart events
        var txAgents = (s.workflowTranscriptAgents && s.workflowTranscriptAgents.length) ? s.workflowTranscriptAgents : null;
        var wfAgents = txAgents || ((wp2 && wp2.agents && wp2.agents.length) ? wp2.agents : null);
        var wfAgentCount = wfAgents ? wfAgents.length : (s.workflowAgentCount || 0);
        var wfRunningCount = txAgents ? txAgents.filter(function(a){return a.status!=='done';}).length
          : wfAgents ? wfAgents.filter(function(a){return a.status!=='done';}).length
          : (s.agents ? s.agents.filter(function(a){return !a.done;}).length : 0);
        var wfDoneCount = wfAgentCount - wfRunningCount;

        // Header badges
        var wfRunBadge = wfRunningCount ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:'+wfColor+'22;color:'+wfColor+';font-weight:700">'+wfRunningCount+' running</span>' : '';
        var wfDoneBadge = wfDoneCount ? '<span style="font-size:9px;padding:1px 6px;border-radius:8px;background:rgba(255,255,255,.06);color:#888">'+wfDoneCount+' done</span>' : '';
        var wfChevron = wfExpanded ? '▾' : '▸';

        workflowHtml = '<div style="border-bottom:1px solid rgba(128,128,128,.1)">'
          + '<div data-workflow-toggle="'+esc(wfSid)+'" style="display:flex;align-items:center;gap:6px;padding:8px 14px;cursor:pointer;user-select:none">'
          + '<span style="font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:'+wfColor+'">'+wfIcon+' WORKFLOW</span>'
          + (wfAgentCount ? '<span style="font-size:10px;color:'+wfColor+';opacity:.6">· '+wfAgentCount+'</span>' : '')
          + wfRunBadge + wfDoneBadge
          + (wfLabel ? '<span style="font-size:10px;opacity:.25;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(wfLabel)+'</span>' : '<span style="flex:1"></span>')
          + '<span style="font-size:11px;opacity:.4">'+wfChevron+'</span>'
          + '</div>';

        // Expanded body
        workflowHtml += '<div id="wf-body-'+esc(wfSid)+'" style="display:'+(wfExpanded?'block':'none')+';padding:'+(wfExpanded?'0 14px 10px':'0')+';max-height:260px;overflow-y:auto;scrollbar-width:thin">';

        // Phase pills
        if(wp2 && wp2.phases && wp2.phases.length) {
          workflowHtml += '<div style="display:flex;flex-wrap:wrap;gap:3px;margin-bottom:8px">';
          wp2.phases.forEach(function(p) {
            var pAgents = wfAgents ? wfAgents.filter(function(a){return a.phase===p;}) : [];
            var pDone = pAgents.length > 0 && pAgents.every(function(a){return a.status==='done';});
            var pRunning = pAgents.some(function(a){return a.status!=='done';});
            var pColor = pDone ? '#4caf50' : pRunning ? '#4a9eff' : '#888';
            workflowHtml += '<span style="font-size:9px;padding:2px 7px;border-radius:8px;background:'+pColor+'18;color:'+pColor+';border:1px solid '+pColor+'33">'
              +(pDone?'✓ ':pRunning?'⟳ ':'')+esc(p)+'</span>';
          });
          workflowHtml += '</div>';
        }

        // Agent rows — transcript agents are richest; fall back to workflowPlan
        if(wfAgents && wfAgents.length) {
          workflowHtml += wfAgents.map(function(a) {
            var done = a.status === 'done';
            var mc = (a.model||'').toLowerCase();
            var mColor = mc.includes('opus')?'#9c6af7':mc.includes('haiku')?'#4a9eff':'#ff9800';
            // Transcript agents already have formatted model; plan agents need stripping
            var mLabel = a.model || '';
            if(!txAgents) mLabel = mLabel.replace(/^claude-/,'').replace(/-\d{8}$/,'').replace(/-latest$/,'');
            var taskLabel = (a.label||'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim()||(a.label||'agent');
            var subDetail = txAgents
              ? (done ? (a.result ? a.result.split('.')[0].trim().slice(0,80) : '') : (a.currentTool ? 'using '+a.currentTool : ''))
              : (a.phase || '');
            var statusDot = done
              ? '<span title="Done" style="width:6px;height:6px;border-radius:50%;background:#4caf50;flex-shrink:0;display:inline-block"></span>'
              : '<span title="Running" style="width:6px;height:6px;border-radius:50%;background:'+wfColor+';flex-shrink:0;display:inline-block;animation:pulse 1.2s ease-in-out infinite"></span>';
            var statusTag = done
              ? '<span style="font-size:9px;color:#4caf50;opacity:.7;flex-shrink:0">✓</span>'
              : '<span style="font-size:9px;color:'+wfColor+';opacity:.8;flex-shrink:0;font-weight:600">running</span>';
            return '<div style="display:flex;flex-direction:column;gap:1px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,.04)">'
              +'<div style="display:flex;align-items:center;gap:5px;font-size:10px">'
              +statusDot
              +'<span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;'+(done?'opacity:.4':'')+'">'+esc(taskLabel)+'</span>'
              +statusTag
              +(mLabel?'<span style="font-size:9px;padding:1px 5px;border-radius:6px;background:'+mColor+'22;color:'+mColor+';font-weight:600;flex-shrink:0">'+esc(mLabel)+'</span>':'')
              +'</div>'
              +(subDetail?'<div style="font-size:9px;opacity:.3;padding-left:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(subDetail)+'</div>':'')
              +'</div>';
          }).join('');
        } else if(s.agents && s.agents.length) {
          // Fall back to AgentStart events for this session
          workflowHtml += s.agents.map(function(a) {
            var label = (a.label||'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim()||(a.label||'agent');
            var roleColor = (a.role||'').toLowerCase().includes('debug')?'#f44336':(a.role||'').toLowerCase().includes('research')?'#9c6af7':'#4a9eff';
            var pulse = a.done
              ? '<span style="width:5px;height:5px;border-radius:50%;background:#444;flex-shrink:0;display:inline-block"></span>'
              : '<span style="width:5px;height:5px;border-radius:50%;background:'+wfColor+';flex-shrink:0;display:inline-block;animation:pulse 1.2s ease-in-out infinite"></span>';
            return '<div style="display:flex;align-items:center;gap:5px;padding:3px 0;font-size:10px;'+(a.done?'opacity:.35':'')+'">'
              +pulse
              +'<span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(label)+'</span>'
              +(a.role?'<span style="font-size:9px;padding:1px 5px;border-radius:6px;background:'+roleColor+'22;color:'+roleColor+'">'+esc(a.role)+'</span>':'')
              +'<span style="font-size:9px;opacity:.25">'+relTime(a.ts)+'</span>'
              +'</div>';
          }).join('');
        } else {
          // Background workflow: harness returns immediately, agents run in background process
          // — no hook events fire per-agent, only the total count (if parser found it) is known
          var isBgWf = wp2 && wp2.status === 'done' && !!bgLaunch2;
          var skelCount = (wp2 && wp2.total) || s.workflowAgentCount || 0;
          if(isBgWf) {
            workflowHtml += '<div style="font-size:10px;opacity:.5;padding:2px 0">Background workflow</div>'
              + '<div style="font-size:9px;opacity:.3;margin-top:4px;line-height:1.5">'
              + 'Agents run inside the workflow harness — individual tracking unavailable for background launches.'
              + '</div>';
          } else if(skelCount > 0) {
            workflowHtml += '<div style="font-size:10px;opacity:.35;margin-bottom:6px">'+skelCount+' agent'+(skelCount!==1?'s':'')+' — waiting for details</div>';
            for(var wi=0;wi<Math.min(skelCount,8);wi++) {
              workflowHtml += '<div style="display:flex;align-items:center;gap:6px;padding:3px 0">'
                +'<span style="width:5px;height:5px;border-radius:50%;background:'+wfColor+';flex-shrink:0;display:inline-block;animation:pulse 1.2s ease-in-out infinite;animation-delay:'+(wi*0.15)+'s"></span>'
                +'<span style="flex:1;height:8px;border-radius:3px;background:rgba(255,255,255,.06)"></span>'
                +'</div>';
            }
          } else {
            workflowHtml += '<div style="font-size:10px;opacity:.35;padding:4px 0">Workflow running — agent count unknown</div>';
          }
        }
        workflowHtml += '</div></div>';
      }

      // Activity feed
      const TOOL_ICON_LOCAL={Edit:'✏',Write:'✏',Bash:'$',Read:'👁',WebSearch:'⌕',WebFetch:'⌕',Agent:'◈',Skill:'⚡'};
      const acts = (s.activity || []).map(function(f) {
        const icon = TOOL_ICON_LOCAL[f.tool] || '·';
        const isCmd = f.file.startsWith('$ ');
        const ago = relTime(f.lastTs);
        return '<div class="fa">'
          + '<span class="fa-icon">' + icon + '</span>'
          + '<div class="fa-body">'
          + '<span class="fa-file" style="color:' + (isCmd ? '#f0b429' : 'inherit') + '">' + esc(f.file) + '</span>'
          + ((f.tool === 'Edit' || f.tool === 'Write' || f.tool === 'MultiEdit') && (f.added != null || f.deleted != null)
            ? '<span style="font-size:10px;white-space:nowrap;flex-shrink:0">'
              + (f.added  ? '<span style="color:#4caf50">+' + f.added  + '</span>' : '')
              + (f.added && f.deleted ? '<span style="opacity:.3"> / </span>' : '')
              + (f.deleted ? '<span style="color:#f44336">-' + f.deleted + '</span>' : '')
              + '</span>'
            : '')
          + (f.count > 1 ? '<span class="fa-cnt">×' + f.count + '</span>' : '')
          + '<span class="fa-t">' + ago + '</span>'
          + '</div>'
          + '</div>';
      }).join('') || '<div class="em" style="padding:8px 14px">No activity yet</div>';
      var actSid = 'act-' + s.sessionId;
      var actExpanded = !window._actCollapsed || !window._actCollapsed.has(actSid); // default open
      var actChevron = actExpanded ? '▾' : '▸';
      var actCount = s.activity ? s.activity.length : 0;
      var actHdr = '<div data-act-toggle="'+esc(actSid)+'" style="display:flex;align-items:center;gap:6px;padding:6px 14px;cursor:pointer;border-top:1px solid rgba(128,128,128,.1);user-select:none">'
        + '<span style="font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;opacity:.35">Activity</span>'
        + (actCount ? '<span style="font-size:10px;opacity:.25">'+actCount+'</span>' : '')
        + '<span style="margin-left:auto;font-size:11px;opacity:.3">'+actChevron+'</span>'
        + '</div>';
      var actBody = '<div id="act-body-'+esc(actSid)+'" style="display:'+(actExpanded?'block':'none')+';padding:4px 14px;max-height:260px;overflow-y:auto;scrollbar-width:thin">' + acts + '</div>';
      return '<div class="sess-col" style="flex:1 1 ' + colBasis + '">' + hdr + agentsHtml + workflowHtml + actHdr + actBody + '</div>';
    } catch(e) { return '<div class="sess-col" style="padding:12px;opacity:.4;font-size:11px">Error rendering session: '+(e&&e.message||e)+'</div>'; }
    }).join('');

    // Streams in bottom row — collapsible
    const srTtl2 = document.getElementById('sr-ttl2');
    const srList2 = document.getElementById('sr-list2');
    if (srTtl2) {
      srTtl2.style.cursor = 'pointer';
      srTtl2.innerHTML = 'Active streams (' + d.streams.length + ') <span id="sr-toggle-arrow" style="opacity:.5">▸</span>';
      srTtl2.setAttribute('data-toggle-id', 'sr-list2-body');
    }
    var srBody = document.getElementById('sr-list2-body');
    if (!srBody && srList2) {
      srBody = document.createElement('div');
      srBody.id = 'sr-list2-body';
      srBody.style.display = 'none'; // collapsed by default
      srList2.parentNode.insertBefore(srBody, srList2.nextSibling);
    }
    if (srBody) srBody.innerHTML = renderStreams(d.streams, d.activeStream);
  } else {
    // Single-session: restore original layout
    if (liveBody) liveBody.classList.remove('multi');
    if (sessionColsEl) sessionColsEl.style.display = 'none';
    if (streamsRowEl) streamsRowEl.style.display = 'none';
    if (colL) colL.style.display = '';
    if (colR) colR.style.display = '';

    // Show/hide single-session blocks
    const sessionsSecEl = document.getElementById('sec-sessions');
    const singleSecEl = document.getElementById('sec-session-single');
    if (sessionsSecEl) sessionsSecEl.style.display = 'none';
    if (singleSecEl) singleSecEl.style.display = '';
  }

  // streams (single-session path)
  if (!multiSession) {
  txt('sr-ttl','Active streams ('+d.streams.length+')');
  if(!d.streams.length){html('sr-list','<div class="em">No active streams</div>');}
  else {
    const srList=document.getElementById('sr-list');
    if(srList){srList.innerHTML=renderStreams(d.streams,d.activeStream);}
  }
  } // end if(!multiSession) streams block

  // session stats (single-session only)
  txt('sv-model',d.model||'—');
  txt('sv-stream',d.activeStream||'—');
  txt('sv-cost',d.cost||'—');
  txt('sv-time',d.sessionTime||'—');
  const svCtx=document.getElementById('sv-ctx');if(svCtx)svCtx.innerHTML=ctxBar(d.ctxPct);
  txt('sv-branch',d.branch||'—');

  const secRole=document.getElementById('sec-role');
  const rg=document.getElementById('role-grid');
  const rows=[];
  if(d.activeRole)rows.push('<span class="sk">Role</span><span class="sv sv-role">'+esc(d.activeRole)+'</span>');
  if(d.lastSkill)rows.push('<span class="sk">Skill</span><span class="sv sv-skill">/'+esc(d.lastSkill)+'</span>');
  if(secRole&&rg){secRole.style.display=rows.length?'':'none';rg.innerHTML=rows.join('');}

  // catalog
  txt('cnt-skills',String(d.skillCount));
  txt('cnt-roles',String(d.roleCount));
  txt('cnt-cmds',String(d.commands.length));
  renderCatalogCol('list-skills',d.skills,'#4a9eff');
  renderCatalogCol('list-roles',d.roles,'#9c6af7');
  renderCatalogCol('list-cmds',d.commands,'#888');

  // footer
  const fp=[];
  if(d.model)fp.push('<span class="fi">⬡ '+esc(d.model)+'</span>');
  if(d.cost)fp.push('<span class="fi">'+esc(d.cost)+'</span>');
  if(d.branch)fp.push('<span class="fi" style="font-family:monospace;font-size:10px">⎇ '+esc(d.branch)+'</span>');
  if(d.activeRole)fp.push('<span class="fi" style="color:#9c6af7;border-color:#9c6af744">◈ '+esc(d.activeRole)+'</span>');
  if(d.lastSkill)fp.push('<span class="fi" style="color:#4caf84">/'+esc(d.lastSkill)+'</span>');
  fp.push('<span style="margin-left:auto;opacity:.25;font-size:10px">'+d.skillCount+' skills · '+d.roleCount+' roles · '+d.streams.length+' streams</span>');
  html('footer',fp.join(''));
}

window.addEventListener('message',function(e){
  const d=e.data;if(d.type!=='update')return;
  applyUpdate(d);
});

// Persistent toggle state (survives re-renders)
window._agentExpanded = window._agentExpanded || new Set();
window._workflowExpanded = window._workflowExpanded || new Set();

// Event delegation — handles tabs, stream toggles, open-stream, refresh, agents toggle
document.addEventListener('click',function(e){
  const t=e.target;
  // Refresh button
  if(t.id==='refresh-btn'||t.closest('#refresh-btn')){
    vscode.postMessage({command:'refresh'});return;
  }
  // Workflow toggle
  const wfToggle=t.closest('[data-workflow-toggle]');
  if(wfToggle){
    var wfSid=wfToggle.dataset.workflowToggle;
    var wfBody=document.getElementById('wf-body-'+wfSid);
    var wfChevronEl=wfToggle.querySelector('span:last-child');
    if(wfBody){
      var wfOpen=wfBody.style.display!=='none';
      if(wfOpen){
        wfBody.style.display='none';wfBody.style.padding='0';
        window._workflowExpanded.delete(wfSid);
        if(wfChevronEl)wfChevronEl.textContent='▸';
      } else {
        wfBody.style.display='block';wfBody.style.padding='0 14px 10px';
        window._workflowExpanded.add(wfSid);
        if(wfChevronEl)wfChevronEl.textContent='▾';
      }
    }
    return;
  }
  // Activity toggle
  const actToggle=t.closest('[data-act-toggle]');
  if(actToggle){
    window._actCollapsed=window._actCollapsed||new Set();
    var actSid=actToggle.dataset.actToggle;
    var actBody=document.getElementById('act-body-'+actSid);
    var actChevEl=actToggle.querySelector('span:last-child');
    if(actBody){
      var actOpen=actBody.style.display!=='none';
      if(actOpen){actBody.style.display='none';window._actCollapsed.add(actSid);if(actChevEl)actChevEl.textContent='▸';}
      else{actBody.style.display='block';window._actCollapsed.delete(actSid);if(actChevEl)actChevEl.textContent='▾';}
    }
    return;
  }
  // Sub-agents toggle
  const agToggle=t.closest('[data-agents-toggle]');
  if(agToggle){
    var sid=agToggle.dataset.agentsToggle;
    var body=document.getElementById('agents-body-'+sid);
    var chevronEl=agToggle.querySelector('span:last-child');
    if(body){
      var open=body.style.display!=='none';
      if(open){
        body.style.display='none';body.style.padding='0';
        window._agentExpanded.delete(sid);
        if(chevronEl)chevronEl.textContent='▸';
      } else {
        body.style.display='block';body.style.padding='0 14px 8px';
        window._agentExpanded.add(sid);
        if(chevronEl)chevronEl.textContent='▾';
      }
    }
    return;
  }
  // Catalog item expand/collapse
  const catToggle = t.closest('[data-cat-toggle]');
  if (catToggle) {
    window._catExpanded = window._catExpanded || new Set();
    var cid = catToggle.dataset.catToggle;
    var cbody = document.getElementById(cid + '-body');
    var changed = catToggle.querySelector('span[style*="opacity:.25"]');
    if (cbody) {
      var copen = cbody.style.display !== 'none';
      cbody.style.display = copen ? 'none' : 'block';
      if (changed) changed.textContent = copen ? '▸' : '▾';
      if (copen) window._catExpanded.delete(cid); else window._catExpanded.add(cid);
    }
    return;
  }
  // Tab buttons
  const tab=t.closest('[data-view]');
  if(tab){switchTab(tab.dataset.view,tab);return;}
  // Stream header toggle
  const hdr=t.closest('[data-toggle-id]');
  if(hdr){toggleStream(hdr.dataset.toggleId);return;}
  // Open stream file button
  const openBtn=t.closest('[data-open-stream]');
  if(openBtn){vscode.postMessage({command:'openStream',filePath:openBtn.dataset.openStream});return;}
});

// Read initial data from embedded JSON element (avoids inline script CSP issues)
(function(){
  const el=document.getElementById('ab-data');
  if(!el)return;
  try{
    const d=JSON.parse(el.textContent||'');
    if(d&&d.type==='update')applyUpdate(d);
  }catch(e){}
})();
