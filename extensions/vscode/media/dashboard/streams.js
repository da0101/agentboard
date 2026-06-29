// Agentboard dashboard — stream list renderer + accordion toggle
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }
  function _save() { root.AgentboardDashboard.uiState.saveUiState(); }

  function renderStreams(streams, activeStream) {
    var esc = _core().esc;
    var TYPE_COLOR = _core().TYPE_COLOR;
    var streamDetailId = _core().streamDetailId;
    if (!streams || !streams.length) return '<div class="em">No active streams</div>';
    return streams.map(function(s, i) {
      var isA = s.slug === activeStream;
      var key = s.slug || String(i);
      var explicit = Object.prototype.hasOwnProperty.call(root._streamOpenState || {}, key);
      var isOpen = explicit ? !!root._streamOpenState[key] : isA;
      var detailId = streamDetailId(key, i);
      var c = TYPE_COLOR[s.type] || '#888';
      var statColor = {active:'#4caf50','in-progress':'#4caf50','awaiting-verification':'#ff9800',blocked:'#f44336',paused:'#888'}[s.status] || '#888';
      var doneCount = s.doneCriteria ? s.doneCriteria.filter(function(x){return x.done;}).length : 0;
      var totalCount = s.doneCriteria ? s.doneCriteria.length : 0;
      var pct = totalCount > 0 ? Math.round(doneCount / totalCount * 100) : null;
      var header = '<div class="sr-hdr" data-toggle-id="'+esc(detailId)+'" data-stream-slug="'+esc(key)+'" style="cursor:pointer;display:flex;align-items:center;gap:6px;padding:6px 4px;border-radius:4px;transition:background .15s">'
        + '<span style="width:7px;height:7px;border-radius:50%;background:'+(isA?'#4caf50':c)+';flex-shrink:0"></span>'
        + '<span style="font-size:12px;font-weight:'+(isA?'600':'400')+';color:'+(isA?'#4caf84':'#ccc')+';flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(s.slug)+'</span>'
        + (pct!==null?'<span style="font-size:10px;opacity:.45">'+doneCount+'/'+totalCount+'</span>':'')
        + '<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+c+'22;color:'+c+'">'+esc(s.type)+'</span>'
        + '<span style="font-size:10px;opacity:.4">'+(isOpen?'▾':'▸')+'</span>'
        + '</div>';
      var detail = '<div id="'+esc(detailId)+'" data-stream-detail-slug="'+esc(key)+'" style="display:'+(isOpen?'block':'none')+';padding:0 4px 8px 18px;border-left:2px solid '+c+'44;margin-left:3px">';
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

  function toggleStream(id, slug) {
    var el = root.document.getElementById(id);
    if (!el) return;
    var open = el.style.display === 'block';
    root._streamOpenState = root._streamOpenState || {};
    root.document.querySelectorAll('[data-stream-detail-slug]').forEach(function(e) {
      e.style.display = 'none';
      root._streamOpenState[e.dataset.streamDetailSlug || ''] = false;
    });
    if (!open) {
      el.style.display = 'block';
      root._streamOpenState[slug || el.dataset.streamDetailSlug || id] = true;
    } else {
      root._streamOpenState[slug || el.dataset.streamDetailSlug || id] = false;
    }
    _save();
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.streams = {
    renderStreams:  renderStreams,
    toggleStream:   toggleStream
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
