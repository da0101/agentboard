// Agentboard dashboard — trend chart (activity sparkline + hover tooltip)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }
  function _save() { root.AgentboardDashboard.uiState.saveUiState(); }

  var TS = [
    {k:'edits',  l:'Edits',  c:'#4caf50'},
    {k:'agents', l:'Agents', c:'#9c6af7'},
    {k:'cmds',   l:'Cmds',   c:'#f0b429'},
    {k:'skills', l:'Skills', c:'#4a9eff'},
    {k:'workflows',l:'Wflows',c:'#ff6b35'}
  ];
  var TW = ['10m','30m','1h','3h','6h','12h','all'];

  function _fmtT(ms) {
    var d = new Date(ms), h = d.getHours(), m = d.getMinutes();
    return (h<10?'0':'')+h+':'+(m<10?'0':'')+m;
  }

  function trendHover(e) {
    var el = root.document.getElementById('trend-area');
    if (!el || !root._lastD) return;
    var td = (root._lastD.trendData || {})[root._trendWin] || [];
    if (!td.length) return;
    var rect = el.getBoundingClientRect();
    var bi = Math.round(Math.max(0, Math.min((e.clientX - rect.left) / rect.width, 1)) * (td.length - 1));
    var b = td[bi] || td[td.length - 1];
    var bMs = td.length > 1 ? td[1].ts - td[0].ts : 60000;
    var hidden = root._trendHidden || new Set();
    var rows = '<div style="font-size:9px;color:#666;margin-bottom:5px;white-space:nowrap">' + _fmtT(b.ts) + ' – ' + _fmtT(b.ts + bMs) + '</div>';
    TS.forEach(function(s) {
      if (hidden.has(s.k)) return;
      var v = b[s.k] || 0;
      rows += '<div style="display:flex;align-items:center;gap:5px;padding:1px 0"><span style="width:7px;height:7px;border-radius:50%;background:' + s.c + ';flex-shrink:0"></span><span style="color:#888;min-width:40px">' + s.l + '</span><span style="color:#fff;font-weight:700;min-width:24px;text-align:right">' + v + '</span></div>';
    });
    var tip = root.document.getElementById('trend-tip');
    if (!tip) {
      tip = root.document.createElement('div');
      tip.id = 'trend-tip';
      tip.style.cssText = 'position:fixed;background:#12121f;border:1px solid #4a9eff55;border-radius:6px;padding:7px 10px;font-size:10px;pointer-events:none;z-index:9999;box-shadow:0 4px 16px #00000099;line-height:1.6';
      root.document.body.appendChild(tip);
    }
    tip.innerHTML = rows;
    tip.style.display = 'block';
    var tx = e.clientX + 14, ty = e.clientY - 30;
    if (tx + 130 > root.innerWidth) tx = e.clientX - 130;
    tip.style.left = tx + 'px';
    tip.style.top = Math.max(4, ty) + 'px';
  }

  function trendOut() {
    var t = root.document.getElementById('trend-tip');
    if (t) t.style.display = 'none';
  }

  function renderActivityChart(d) {
    var win = root._trendWin;
    var td = (d.trendData || {})[win];
    var hidden = root._trendHidden || new Set();

    var sel = '<div style="display:flex;gap:3px;padding:2px 0 7px;flex-wrap:wrap">';
    TW.forEach(function(w) {
      var on = w === win;
      sel += '<button data-trend-win="' + w + '" style="padding:1px 8px;border-radius:10px;font-size:10px;cursor:pointer;border:1px solid ' + (on?'#4a9eff':'#ffffff1a') + ';background:' + (on?'#4a9eff22':'transparent') + ';color:' + (on?'#4a9eff':'#777') + '">' + w + '</button>';
    });
    sel += '</div>';

    var sess = d.activeSessions || [];
    var cost = sess.reduce(function(a, s){ return a + (s.costUsd || 0); }, 0);
    var ctxVals = sess.map(function(s){ return s.ctxPct !== null && s.ctxPct !== undefined ? Math.round(100 - s.ctxPct) : null; }).filter(function(v){ return v !== null; });
    var avgCtx = ctxVals.length ? Math.round(ctxVals.reduce(function(a,b){return a+b;},0) / ctxVals.length) : null;
    var runAgents = sess.reduce(function(a,s){ return a + (s.agents||[]).filter(function(ag){return !ag.done;}).length; }, 0);
    var sp = ['<span style="color:#4caf50;font-weight:600">' + sess.length + '</span> active'];
    if (cost > 0) sp.push('<span style="color:#4caf50">$' + (cost||0).toFixed(2) + '</span>');
    if (avgCtx !== null) sp.push('<span style="color:' + (avgCtx>=80?'#f44336':avgCtx>=50?'#ff9800':'#4caf50') + '">' + avgCtx + '% ctx</span>');
    if (runAgents > 0) sp.push('<span style="color:#4a9eff">' + runAgents + ' agent' + (runAgents>1?'s':'') + '</span>');
    // Live workflow badge — reads transcriptAgents (the live list) not workflowAgentCount (the initial estimate, often 0)
    var wfAC = 0, wfRC = 0;
    sess.forEach(function(s) {
      if (!s.hasWorkflow) return;
      var tx = s.workflowTranscriptAgents;
      if (tx && tx.length) { wfAC += tx.length; wfRC += tx.filter(function(a){return a.status!=='done';}).length; }
      else { wfAC += (s.workflowAgentCount||0); wfRC += (s.agents||[]).filter(function(a){return !a.done;}).length; }
    });
    if (wfAC > 0) sp.push('<span style="color:#ff6b35;font-weight:600">⟳ workflow</span><span style="color:#ff6b35;opacity:.7"> ' + wfAC + ' agents' + (wfRC ? ' · ' + wfRC + ' live' : '') + '</span>');
    var stats = '<div style="padding:0 0 7px;font-size:10px;opacity:.75">' + sp.join('<span style="opacity:.3;margin:0 3px">·</span>') + '</div>';

    if (!td || !td.length) return stats + sel + '<div style="opacity:.25;text-align:center;padding:14px;font-size:11px">No event data</div>';
    var active = TS.filter(function(s){ return !hidden.has(s.k) && td.some(function(b){ return (b[s.k]||0) > 0; }); });
    var allSeries = TS.filter(function(s){ return td.some(function(b){ return (b[s.k]||0) > 0; }); });

    var n = td.length;
    var leg = '<div style="display:flex;flex-wrap:wrap;gap:6px;font-size:10px;padding-top:4px">';
    allSeries.forEach(function(s) {
      var isHid = hidden.has(s.k);
      var total = 0, arr = '', ac = '#555';
      if (!isHid) {
        total = td.reduce(function(a,b){ return a+(b[s.k]||0); }, 0);
        var q = Math.ceil(n/3);
        var early = td.slice(0,q).reduce(function(a,b){ return a+(b[s.k]||0); }, 0);
        var late  = td.slice(-q).reduce(function(a,b){ return a+(b[s.k]||0); }, 0);
        arr = late > early*1.15 ? '↑' : late < early*0.85 ? '↓' : '';
        ac = arr==='↑' ? '#4caf50' : arr==='↓' ? '#f44336' : '#555';
      }
      leg += '<span data-trend-toggle="' + s.k + '" title="' + (isHid?'Show':'Hide') + ' ' + s.l + '" style="display:inline-flex;align-items:center;gap:3px;cursor:pointer;opacity:' + (isHid?.3:1) + ';transition:opacity .15s"><span style="width:10px;height:2px;background:' + s.c + ';border-radius:1px;display:inline-block"></span><span style="color:#888;text-decoration:' + (isHid?'line-through':'none') + '">' + s.l + '</span>' + (isHid ? '' : ('<span style="color:#ccc;font-weight:600">' + total + '</span><span style="color:' + ac + ';font-weight:700">' + arr + '</span>')) + '</span>';
    });
    leg += '</div>';

    if (!active.length) return stats + sel + '<div style="opacity:.25;text-align:center;padding:10px;font-size:11px">All series hidden</div>' + leg;

    var rawMax = 0;
    active.forEach(function(s){ rawMax = Math.max(rawMax, Math.max.apply(null, td.map(function(b){ return b[s.k]||0; }))); });
    var yMax = rawMax<=5?5:rawMax<=10?10:rawMax<=20?20:rawMax<=50?50:rawMax<=100?100:Math.ceil(rawMax/50)*50;
    var yMid = Math.round(yMax/2);

    var W=280,H=90,P=6,pW=W-P*2,pH=H-P*2;
    function px(i){ return P + (n>1 ? i/(n-1)*pW : pW/2); }
    function py(v){ return yMax>0 ? P+pH*(1-v/yMax) : P+pH; }

    var svg = '<svg viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="none" style="width:100%;height:90px;display:block">';
    [.25,.5,.75].forEach(function(f){ var gy=P+pH*f; svg+='<line x1="'+P+'" y1="'+gy+'" x2="'+(W-P)+'" y2="'+gy+'" stroke="#ffffff07" stroke-width="0.5"/>'; });
    [.25,.5,.75].forEach(function(f){ var gx=P+pW*f; svg+='<line x1="'+gx+'" y1="'+P+'" x2="'+gx+'" y2="'+(P+pH)+'" stroke="#ffffff04" stroke-width="0.5"/>'; });
    active.forEach(function(s) {
      var pts = td.map(function(b,i){ return px(i)+','+py(b[s.k]||0); });
      svg += '<polygon points="'+px(0)+','+(P+pH)+' '+pts.join(' ')+' '+px(n-1)+','+(P+pH)+'" fill="'+s.c+'" fill-opacity="0.08"/>';
      svg += '<polyline points="'+pts.join(' ')+'" fill="none" stroke="'+s.c+'" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>';
      var lv = td[n-1][s.k]||0; if(lv>0) svg+='<circle cx="'+px(n-1)+'" cy="'+py(lv)+'" r="2.5" fill="'+s.c+'"/>';
    });
    svg += '</svg>';

    var ruler = '<div style="display:flex;justify-content:space-between;padding:2px 6px 6px;font-size:9px;color:#3a3a5c">';
    [0,.25,.5,.75,1].forEach(function(f){ var li=Math.round(f*(n-1)); ruler+='<span>'+_fmtT(td[li].ts)+'</span>'; });
    ruler += '</div>';

    var yAxis = '<div style="display:flex;flex-direction:column;justify-content:space-between;width:22px;font-size:8px;color:#3a3a5c;padding:6px 4px 6px 0;text-align:right;flex-shrink:0;line-height:1"><span>'+yMax+'</span><span>'+yMid+'</span><span>0</span></div>';
    var chartWrap = '<div style="display:flex;align-items:stretch">'+yAxis+'<div id="trend-area" style="flex:1;position:relative;cursor:crosshair">'+svg+'</div></div>';
    return stats + sel + chartWrap + ruler + leg;
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.trendChart = {
    TS:                  TS,
    TW:                  TW,
    trendHover:          trendHover,
    trendOut:            trendOut,
    renderActivityChart: renderActivityChart
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
