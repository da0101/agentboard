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
const _SN_ADJ=['bold','calm','swift','bright','sharp','keen','wild','quiet','brave','cool','warm','soft','fast','wise','pure','deft','lean','sage','red','blue','gold','jade','iron','amber','violet','azure','coral','frost','storm','sand','ember','cedar','steel','nova','oak','ivy','clay','moss','dawn','rust'];
const _SN_NON=['falcon','tiger','wolf','eagle','raven','fox','bear','hawk','lynx','crane','otter','pike','heron','wren','viper','bison','moose','ibis','kite','wasp','colt','finch','puma','cobra','gecko','quail','trout','mink','stork','stoat','dingo','snipe','marten','condor','osprey','ferret','oriole','magpie','jaguar','marlin'];
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
// Role launcher — selectable role cards with linked skills + launch button
window._selectedRole = window._selectedRole || null;
window._rolesData   = window._rolesData   || [];

function renderRolesCol(listId, roles, accentColor) {
  window._catExpanded = window._catExpanded || new Set();
  var selected = window._selectedRole;
  var h = roles.slice(0, 200).map(function(role, idx) {
    var eid = listId + '-' + idx;
    var isOpen = window._catExpanded.has(eid);
    var hasMore = role.fullDescription && role.fullDescription.length > 10;
    var isSelected = selected === (role.slug || role.name);
    var usedBy = role.usedBy && role.usedBy.length ? role.usedBy : null;
    var linked = role.linkedSkills && role.linkedSkills.length ? role.linkedSkills : [];

    var cardStyle = 'cursor:pointer;border-radius:5px;padding:2px 4px;margin:-2px -4px;transition:background .1s;';
    if (isSelected) cardStyle += 'background:rgba(156,106,247,.1);outline:1px solid rgba(156,106,247,.35);';

    var row = '<div class="ci" style="'+cardStyle+'" data-role-select="'+esc(role.slug||role.name)+'" data-role-name="'+esc(role.name)+'" data-cat-toggle="'+eid+'">';
    row += '<div style="display:flex;align-items:baseline;gap:6px;flex-wrap:wrap">';
    row += '<span class="ci-name">'+esc(role.name)+'</span>';
    if (hasMore) row += '<span style="font-size:9px;opacity:.25">'+(isOpen?'▾':'▸')+'</span>';
    if (usedBy) row += usedBy.map(function(n){return '<span style="font-size:9px;padding:1px 5px;border-radius:8px;background:'+accentColor+'22;color:'+accentColor+';white-space:nowrap">'+esc(n)+'</span>';}).join('');
    row += '</div>';
    if (role.description) row += '<span class="ci-desc">'+esc(role.description.slice(0,120))+'</span>';
    if (hasMore) row += '<div id="'+eid+'-body" style="display:'+(isOpen?'block':'none')+';font-size:11px;opacity:.55;line-height:1.6;margin-top:4px;white-space:pre-wrap;border-left:2px solid '+accentColor+'44;padding-left:8px">'+esc(role.fullDescription||'')+'</div>';
    // Launch panel — only when selected
    if (isSelected) {
      row += '<div style="margin-top:8px;padding:8px;background:rgba(156,106,247,.06);border-radius:4px;border:1px solid rgba(156,106,247,.18)">';
      if (linked.length) {
        row += '<div style="display:flex;flex-wrap:wrap;gap:4px;margin-bottom:7px">';
        row += linked.map(function(sk){return '<span style="font-size:10px;padding:2px 7px;border-radius:10px;background:#4a9eff18;color:#4a9eff;border:1px solid #4a9eff33">'+esc(sk)+'</span>';}).join('');
        row += '</div>';
      }
      row += '<button data-launch-role="'+esc(role.slug||role.name)+'" data-launch-role-name="'+esc(role.name)+'" style="width:100%;background:#9c6af7;color:#fff;border:none;border-radius:4px;padding:6px 10px;font-size:12px;cursor:pointer;font-family:inherit">▶  Launch Claude as '+esc(role.name)+'</button>';
      row += '</div>';
    }
    row += '</div>';
    return row;
  }).join('');
  html(listId, h);
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
    // Preserve scroll positions of all inner-scrollable sections before re-render
    var _scrollState = {};
    sessionColsEl.querySelectorAll('[id^="act-body-"],[id^="wf-body-"],[id^="agents-body-"]').forEach(function(el){
      if(el.scrollTop > 0) _scrollState[el.id] = el.scrollTop;
    });
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
        + '<button data-focus-terminal="1" data-session-root="' + esc(s.root||'') + '" data-session-nick="' + esc(nick) + '" data-shell-pid="' + (s.shellPid||0) + '" data-session-started-at="' + esc(s.startedAt||'') + '" title="Open terminal for ' + esc(nick) + '" style="background:#ffffff0d;border:1px solid #ffffff18;cursor:pointer;padding:2px 8px;border-radius:4px;color:#aaa;font-size:10px;line-height:1.6;display:flex;align-items:center;gap:4px;transition:all .15s;white-space:nowrap" onmouseover="this.style.background=\'#ffffff1a\';this.style.color=\'#fff\'" onmouseout="this.style.background=\'#ffffff0d\';this.style.color=\'#aaa\'">⌨ terminal</button>'
        + '</div>'
        + '<div class="sess-col-grid">'
        + (s.stream ? '<span style="opacity:.4">Stream</span><span style="color:#4a9eff">' + esc(s.stream) + '</span>' : '')
        + (s.cost ? '<span style="opacity:.4">Cost</span><span>' + esc(s.cost) + '</span>' : '')
        + (s.sessionTime ? '<span style="opacity:.4">Time</span><span>' + esc(s.sessionTime) + '</span>' : '')
        + (ctxBar ? '<span style="opacity:.4">Context</span><span>' + ctxBar + '</span>' : '')
        + (s.branch ? '<span style="opacity:.4">Branch</span><span style="font-family:monospace;font-size:10px">' + esc(s.branch) + '</span>' : '')
        + '<span style="opacity:.4">Last</span><span style="opacity:.5">' + age + '</span>'
        + (s.sessionLastRole ? '<span style="opacity:.4">Role</span><span style="color:#9c6af7;font-size:10px">◈ ' + esc(s.sessionLastRole) + '</span>' : '')
        + (s.sessionLastSkill ? '<span style="opacity:.4">Skill</span><span style="color:#4caf84;font-size:10px">/ ' + esc(s.sessionLastSkill) + '</span>' : '')
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
        var RECENT_MS = 5 * 60 * 1000; // 5 min — done agents older than this collapse to summary
        var now = Date.now();
        var recentDone = s.agents.filter(function(a){ return a.done && a.ts && (now - new Date(a.ts).getTime()) < RECENT_MS; });
        var oldDone = s.agents.filter(function(a){ return a.done && (!a.ts || (now - new Date(a.ts).getTime()) >= RECENT_MS); });
        var visibleAgents = runningAgents.concat(recentDone);
        var agentRows = visibleAgents.map(function(a) {
          var label = (a.label || 'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i, '').trim() || (a.label || 'agent');
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

        // Agent rows — show running agents in detail; collapse done into summary
        window._wfAgentExpanded = window._wfAgentExpanded || new Set();
        if(wfAgents && wfAgents.length) {
          var runningWfAgents = wfAgents.filter(function(a){ return a.status !== 'done'; });
          var doneWfAgents = wfAgents.filter(function(a){ return a.status === 'done'; });
          workflowHtml += runningWfAgents.map(function(a, ai) {
            var mc = (a.model||'').toLowerCase();
            var mColor = mc.includes('opus')?'#9c6af7':mc.includes('haiku')?'#4a9eff':'#ff9800';
            var mLabel = a.model || '';
            if(!txAgents) mLabel = mLabel.replace(/^claude-/,'').replace(/-\d{8}$/,'').replace(/-latest$/,'');
            var taskLabel = (a.label||'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim()||(a.label||'agent');
            var subDetail = txAgents ? (a.currentTool ? 'using '+a.currentTool : '') : (a.phase || '');
            var agKey = wfSid+'-'+ai;
            var agExpanded = window._wfAgentExpanded.has(agKey);
            var labelStyle = agExpanded
              ? 'flex:1;word-break:break-word;cursor:pointer;font-size:10px'
              : 'flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer;font-size:10px';
            var chevronStr = agExpanded ? ' ▾' : ' ▸';
            return '<div data-wf-agent-expand="'+agKey+'" style="display:flex;flex-direction:column;gap:1px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,.04);cursor:pointer" title="Click to expand/collapse">'
              +'<div style="display:flex;align-items:flex-start;gap:5px">'
              +'<span title="Running" style="width:6px;height:6px;border-radius:50%;background:'+wfColor+';flex-shrink:0;display:inline-block;margin-top:3px;animation:pulse 1.2s ease-in-out infinite"></span>'
              +'<span style="'+labelStyle+'">'+esc(taskLabel)+'<span style="opacity:.3">'+chevronStr+'</span></span>'
              +'<span style="font-size:9px;color:'+wfColor+';opacity:.8;flex-shrink:0;font-weight:600">running</span>'
              +(mLabel?'<span style="font-size:9px;padding:1px 5px;border-radius:6px;background:'+mColor+'22;color:'+mColor+';font-weight:600;flex-shrink:0">'+esc(mLabel)+'</span>':'')
              +'</div>'
              +(subDetail?'<div style="font-size:9px;opacity:.3;padding-left:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(subDetail)+'</div>':'')
              +'</div>';
          }).join('');
          if(doneWfAgents.length) {
            var doneModels=[];
            doneWfAgents.forEach(function(a){var m=(a.model||'').trim();if(m&&doneModels.indexOf(m)<0)doneModels.push(m);});
            workflowHtml += '<div style="font-size:9px;opacity:.28;padding:6px 0 2px;border-top:1px solid rgba(255,255,255,.05)">'
              +'✓ '+doneWfAgents.length+' done'
              +(doneModels.length?' · '+doneModels.join(', '):'')
              +'</div>';
          }
        } else if(s.agents && s.agents.length) {
          // Fall back to AgentStart events — show running only, summarize done
          var runningEvAgents = s.agents.filter(function(a){ return !a.done; });
          var doneEvAgents = s.agents.filter(function(a){ return a.done; });
          workflowHtml += runningEvAgents.map(function(a) {
            var label = (a.label||'agent').replace(/^role:[^·]+·\s*skill:[^·]+·\s*/i,'').trim()||(a.label||'agent');
            var roleColor = (a.role||'').toLowerCase().includes('debug')?'#f44336':(a.role||'').toLowerCase().includes('research')?'#9c6af7':'#4a9eff';
            return '<div style="display:flex;align-items:center;gap:5px;padding:3px 0;font-size:10px">'
              +'<span style="width:5px;height:5px;border-radius:50%;background:'+wfColor+';flex-shrink:0;display:inline-block;animation:pulse 1.2s ease-in-out infinite"></span>'
              +'<span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(label)+'</span>'
              +(a.role?'<span style="font-size:9px;padding:1px 5px;border-radius:6px;background:'+roleColor+'22;color:'+roleColor+'">'+esc(a.role)+'</span>':'')
              +'</div>';
          }).join('');
          if(doneEvAgents.length) {
            workflowHtml += '<div style="font-size:9px;opacity:.28;padding:6px 0 2px;border-top:1px solid rgba(255,255,255,.05)">✓ '+doneEvAgents.length+' done</div>';
          }
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
      var sessRoot = s.root || '';
      const acts = (s.activity || []).map(function(f) {
        const icon = TOOL_ICON_LOCAL[f.tool] || '·';
        const isCmd = f.file.startsWith('$ ');
        const isEdited = (f.tool === 'Edit' || f.tool === 'Write' || f.tool === 'MultiEdit') && !isCmd;
        const ago = relTime(f.lastTs);

        // Large-edit warning: total lines changed >= 50
        var totalChanged = (f.added || 0) + (f.deleted || 0);
        var editWarn = '';
        if (isEdited && totalChanged >= 50) {
          var warnColor = totalChanged >= 150 ? '#ff7043' : '#f0b429';
          editWarn = '<span title="'+totalChanged+' lines changed" style="color:'+warnColor+';font-size:11px;flex-shrink:0;margin-right:2px">⚠</span>';
        }

        // File-size badge: line count tiers
        var sizeBadge = '';
        if (f.lineCount) {
          var lc = f.lineCount;
          var sizeColor = lc >= 1000 ? '#ef5350' : lc >= 800 ? '#ff7043' : lc >= 500 ? '#f0b429' : '';
          if (sizeColor) {
            var sizeLabel = lc >= 1000 ? (Math.round(lc/100)/10)+'k' : lc+'';
            sizeBadge = '<span title="'+lc+' lines — '+(lc>=1000?'monolith, very hard to refactor':lc>=800?'large, hard to refactor':'growing, consider splitting')+'" style="font-size:9px;padding:1px 5px;border-radius:8px;background:'+sizeColor+'22;color:'+sizeColor+';border:1px solid '+sizeColor+'44;flex-shrink:0;cursor:default">'+sizeLabel+'L</span>';
          }
        }

        const diffAttrs = isEdited
          ? ' data-open-diff="'+esc(f.file)+'" data-session-root="'+esc(sessRoot)+'" title="Click for options" style="cursor:pointer"'
          : '';
        return '<div class="fa"'+diffAttrs+'>'
          + '<span class="fa-icon">' + icon + '</span>'
          + '<div class="fa-body">'
          + '<span class="fa-file"'+(isEdited?' onmouseover="this.style.color=\'#7cbfff\'" onmouseout="this.style.color=\'\'"':'')+' style="color:' + (isCmd ? '#f0b429' : 'inherit') + '">' + esc(f.file) + '</span>'
          + (isEdited && (f.added != null || f.deleted != null)
            ? '<span style="font-size:10px;white-space:nowrap;flex-shrink:0">'
              + (f.added  ? '<span style="color:#4caf50">+' + f.added  + '</span>' : '')
              + (f.added && f.deleted ? '<span style="opacity:.3"> / </span>' : '')
              + (f.deleted ? '<span style="color:#f44336">-' + f.deleted + '</span>' : '')
              + '</span>'
            : '')
          + (f.count > 1 ? '<span class="fa-cnt">×' + f.count + '</span>' : '')
          + '<span class="fa-t">' + ago + '</span>'
          + sizeBadge
          + editWarn
          + (f.committed && f.added == null && f.deleted == null ? '<span title="Committed to branch" style="color:#4caf50;font-size:11px;flex-shrink:0;margin-left:2px">✓</span>' : '')
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
    // Restore scroll positions after re-render
    Object.keys(_scrollState).forEach(function(id){
      var el=document.getElementById(id);
      if(el) el.scrollTop=_scrollState[id];
    });

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
  window._rolesData = d.roles;
  renderRolesCol('list-roles',d.roles,'#9c6af7');
  renderCatalogCol('list-cmds',d.commands,'#888');

  // footer — global counts only (session-specific data is shown on each session card)
  html('footer','<span style="opacity:.25;font-size:10px">'+d.skillCount+' skills · '+d.roleCount+' roles · '+d.streams.length+' streams</span>');
}

window.addEventListener('message',function(e){
  const d=e.data;if(d.type!=='update')return;
  applyUpdate(d);
});

// Persistent toggle state (survives re-renders)
window._agentExpanded = window._agentExpanded || new Set();
window._workflowExpanded = window._workflowExpanded || new Set();

document.addEventListener('keydown',function(e){
  if(e.key==='Escape'){var m=document.getElementById('_file-menu');if(m)m.style.display='none';}
});

// Event delegation — handles tabs, stream toggles, open-stream, refresh, agents toggle
document.addEventListener('click',function(e){
  const t=e.target;
  // Refresh button
  if(t.id==='refresh-btn'||t.closest('#refresh-btn')){
    var rbtn=document.getElementById('refresh-btn');
    if(rbtn){rbtn.textContent='↻ Refreshing…';rbtn.disabled=true;setTimeout(function(){rbtn.textContent='↻ Refresh';rbtn.disabled=false;},1200);}
    vscode.postMessage({command:'refresh'});return;
  }
  // File options menu (diff / copy path)
  if(t.closest('#_file-menu')){
    const fm=t.closest('[data-fm]');
    if(fm){
      const menu=document.getElementById('_file-menu');
      const fp=menu._filePath||''; const sr=menu._sessionRoot||'';
      if(fm.dataset.fm==='diff'){
        vscode.postMessage({command:'openDiff',filePath:fp,sessionRoot:sr});
      } else if(fm.dataset.fm==='copy'){
        vscode.postMessage({command:'copyPath',filePath:fp,sessionRoot:sr});
      }
      menu.style.display='none';
    }
    e.stopPropagation(); return;
  }
  // Close file menu on outside click
  const existMenu=document.getElementById('_file-menu');
  if(existMenu&&existMenu.style.display!=='none'&&!existMenu.contains(t)){
    existMenu.style.display='none';
  }
  // Open file options menu on click
  const diffEl = t.closest('[data-open-diff]');
  if(diffEl){
    e.stopPropagation();
    var menu=document.getElementById('_file-menu');
    if(!menu){
      menu=document.createElement('div');
      menu.id='_file-menu';
      menu.style.cssText='position:fixed;z-index:9999;background:#252526;border:1px solid rgba(255,255,255,.12);border-radius:5px;box-shadow:0 4px 16px rgba(0,0,0,.6);display:none;flex-direction:column;min-width:170px;overflow:hidden;padding:3px 0';
      menu.innerHTML='<div data-fm="diff" style="padding:7px 14px;cursor:pointer;font-size:12px;color:#d4d4d4;display:flex;align-items:center;gap:8px" onmouseover="this.style.background=\'rgba(255,255,255,.07)\'" onmouseout="this.style.background=\'\'"><span style="opacity:.5;font-size:11px">⇄</span>Open diff</div>'
        +'<div data-fm="copy" style="padding:7px 14px;cursor:pointer;font-size:12px;color:#d4d4d4;display:flex;align-items:center;gap:8px" onmouseover="this.style.background=\'rgba(255,255,255,.07)\'" onmouseout="this.style.background=\'\'"><span style="opacity:.5;font-size:11px">⧉</span>Copy path</div>';
      document.body.appendChild(menu);
    }
    menu._filePath=diffEl.dataset.openDiff||'';
    menu._sessionRoot=diffEl.dataset.sessionRoot||'';
    var rect=diffEl.getBoundingClientRect();
    menu.style.display='flex';
    menu.style.left=Math.min(e.clientX, window.innerWidth-180)+'px';
    menu.style.top=(rect.bottom+2)+'px';
    return;
  }
  // Workflow agent label expand/collapse
  const wfAgentEl = t.closest('[data-wf-agent-expand]');
  if(wfAgentEl){
    var agKey2 = wfAgentEl.dataset.wfAgentExpand;
    window._wfAgentExpanded = window._wfAgentExpanded || new Set();
    var labelEl = wfAgentEl.querySelector('span[style*="cursor:pointer"]');
    if(window._wfAgentExpanded.has(agKey2)){
      window._wfAgentExpanded.delete(agKey2);
      if(labelEl){ labelEl.style.whiteSpace='nowrap'; labelEl.style.overflow='hidden'; labelEl.style.textOverflow='ellipsis'; labelEl.style.wordBreak=''; }
    } else {
      window._wfAgentExpanded.add(agKey2);
      if(labelEl){ labelEl.style.whiteSpace='normal'; labelEl.style.overflow='visible'; labelEl.style.textOverflow='clip'; labelEl.style.wordBreak='break-word'; }
    }
    return;
  }
  // Focus terminal button
  const ftBtn = t.closest('[data-focus-terminal]');
  if(ftBtn){
    e.stopPropagation();
    vscode.postMessage({command:'focusTerminal',sessionRoot:ftBtn.dataset.sessionRoot||'',sessionNick:ftBtn.dataset.sessionNick||'',shellPid:parseInt(ftBtn.dataset.shellPid||'0',10),sessionStartedAt:ftBtn.dataset.sessionStartedAt||''});
    return;
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
  // Role launch button
  const launchBtn = t.closest('[data-launch-role]');
  if (launchBtn) {
    e.stopPropagation();
    vscode.postMessage({command:'launchRole',slug:launchBtn.dataset.launchRole||'',name:launchBtn.dataset.launchRoleName||''});
    return;
  }
  // Role card selection (toggle)
  const roleCard = t.closest('[data-role-select]');
  if (roleCard && !t.closest('[data-launch-role]')) {
    var slug2 = roleCard.dataset.roleSelect;
    window._selectedRole = window._selectedRole === slug2 ? null : slug2;
    renderRolesCol('list-roles', window._rolesData || [], '#9c6af7');
    // Don't return — still allow data-cat-toggle to fire for expand
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
