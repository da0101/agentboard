// Agentboard dashboard — event delegation (click, change, keyboard, mouse)
(function(root) {
  'use strict';

  function _save() { root.AgentboardDashboard.uiState.saveUiState(); }
  function _esc(s) { return root.AgentboardDashboard.core.esc(s); }

  function _buildFileMenuItemHtml(fm, icon, label, color, hint) {
    var c = color || '#d4d4d4';
    var base = 'padding:7px 14px;cursor:pointer;font-size:12px;color:' + c + ';display:flex;align-items:center;gap:8px;transition:background .12s,border-color .12s;border-left:2px solid transparent;box-sizing:border-box';
    var over = 'this.style.background=\'rgba(255,255,255,.1)\';this.style.borderLeftColor=\'' + c + '\'';
    var out  = 'this.style.background=\'\';this.style.borderLeftColor=\'transparent\'';
    return '<div data-fm="' + fm + '" style="' + base + '" onmouseenter="' + over + '" onmouseleave="' + out + '">'
      + '<span style="font-size:13px;width:18px;text-align:center;flex-shrink:0;display:inline-block;transition:transform .12s" onmouseenter="this.style.transform=\'scale(1.25)\'" onmouseleave="this.style.transform=\'\'">'+icon+'</span>'
      + '<span style="flex:1">' + label + '</span>'
      + (hint ? '<span style="font-size:9px;white-space:nowrap">' + hint + '</span>' : '')
      + '</div>';
  }

  function _openFileMenu(e, diffEl, vscode) {
    e.stopPropagation();
    var menu = root.document.getElementById('_file-menu');
    if (!menu) {
      menu = root.document.createElement('div');
      menu.id = '_file-menu';
      menu.style.cssText = 'position:fixed;z-index:9999;background:#252526;border:1px solid rgba(255,255,255,.12);border-radius:5px;box-shadow:0 4px 16px rgba(0,0,0,.6);display:none;flex-direction:column;min-width:200px;overflow:hidden;padding:3px 0';
      root.document.body.appendChild(menu);
    }
    menu._filePath       = diffEl.dataset.openDiff || '';
    menu._sessionRoot    = diffEl.dataset.sessionRoot || '';
    menu._isNew          = diffEl.dataset.isNew === '1';
    menu._isDeleted      = diffEl.dataset.isDeleted === '1';
    menu._lineCount      = parseInt(diffEl.dataset.lineCount || '0', 10);
    menu._added          = parseInt(diffEl.dataset.added || '0', 10);
    menu._deleted        = parseInt(diffEl.dataset.deleted || '0', 10);
    menu._totalChanged   = parseInt(diffEl.dataset.totalChanged || '0', 10);
    menu._sessionId      = diffEl.dataset.sessionId || '';
    menu._shellPid       = parseInt(diffEl.dataset.shellPid || '0', 10);
    menu._sessionNick    = diffEl.dataset.sessionNick || '';
    menu._sessionProvider= diffEl.dataset.sessionProvider || '';
    menu._sourceEl       = diffEl;
    var _sep = '<div style="border-top:1px solid rgba(255,255,255,.07);margin:3px 0"></div>';
    var _diffHint = '';
    if (menu._added || menu._deleted) {
      _diffHint = (menu._added ? '<span style="color:#4caf50">+' + menu._added + '</span>' : '')
        + (menu._added && menu._deleted ? '<span style="opacity:.3"> / </span>' : '')
        + (menu._deleted ? '<span style="color:#f44336">-' + menu._deleted + '</span>' : '');
    }
    var _mHtml = '<div style="display:flex;align-items:center;gap:8px;padding:5px 8px 4px 14px;border-bottom:1px solid rgba(255,255,255,.07)">'
      + '<span style="flex:1;font-size:10px;opacity:.45;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + _esc(menu._filePath||'') + '">' + _esc(menu._filePath || 'File actions') + '</span>'
      + '<button data-menu-close="1" title="Close" style="width:20px;height:20px;line-height:18px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.04);color:#aaa;border-radius:4px;cursor:pointer;padding:0;font-size:13px">×</button>'
      + '</div>';
    _mHtml += _buildFileMenuItemHtml('diff', menu._isNew || menu._isDeleted ? '↗️' : '↔️', menu._isNew || menu._isDeleted ? 'Open file' : 'Open diff', '#d4d4d4', _diffHint);
    _mHtml += _buildFileMenuItemHtml('copy', '📋', 'Copy path');
    if (menu._totalChanged >= 50) {
      var _wHint = (menu._added ? '<span style="color:#4caf50">+' + menu._added + '</span>' : '')
        + (menu._added && menu._deleted ? '<span style="opacity:.3"> / </span>' : '')
        + (menu._deleted ? '<span style="color:#f44336">-' + menu._deleted + '</span>' : '');
      _mHtml += _sep;
      _mHtml += _buildFileMenuItemHtml('explain-change', '🔍', 'Explain this change', '#89ddff', _wHint);
    }
    if (menu._lineCount >= 500) {
      var _lcTier = menu._lineCount >= 1000 ? '🔴' : menu._lineCount >= 800 ? '🟠' : '🟡';
      var _lcHint = '<span style="opacity:.45">' + _lcTier + ' ' + menu._lineCount + 'L</span>';
      if (menu._totalChanged < 50) _mHtml += _sep;
      _mHtml += _buildFileMenuItemHtml('refactor-here',       '⚡', 'Refactor in this session',       '#c792ea', _lcHint);
      _mHtml += _buildFileMenuItemHtml('refactor-new-codex',  '✨', 'Refactor in new Codex session',  '#82aaff');
      _mHtml += _buildFileMenuItemHtml('refactor-new-claude', '☄',  'Refactor in new Claude session', '#c792ea');
      _mHtml += _buildFileMenuItemHtml('refactor-new-gemini', '◇',  'Refactor in new Gemini session', '#8bd5ca');
      var _alreadyIgnored = root._ignoredSizeFiles && root._ignoredSizeFiles.has(menu._filePath || '');
      _mHtml += _buildFileMenuItemHtml('ignore-size', _alreadyIgnored ? '🔔' : '🔕', _alreadyIgnored ? 'Show size badge' : 'Ignore size badge', '#888');
    }
    menu.innerHTML = _mHtml;
    var rect = diffEl.getBoundingClientRect();
    menu.style.visibility = 'hidden';
    menu.style.display = 'flex';
    var menuH = menu.offsetHeight || 180;
    var spaceBelow = root.innerHeight - rect.bottom - 8;
    var menuTop = spaceBelow >= menuH ? rect.bottom + 2 : Math.max(4, rect.top - menuH - 2);
    menu.style.left = Math.min(e.clientX, root.innerWidth - 220) + 'px';
    menu.style.top  = menuTop + 'px';
    menu.style.visibility = '';
  }

  function _handleFileMenuAction(t, e, vscode) {
    if (t.closest('[data-menu-close]')) {
      var m = root.document.getElementById('_file-menu');
      if (m) m.style.display = 'none';
      e.stopPropagation(); return true;
    }
    var fm = t.closest('[data-fm]');
    if (!fm) return false;
    var menu = root.document.getElementById('_file-menu');
    var fp = menu._filePath || '';
    var sr = menu._sessionRoot || '';
    if (fm.dataset.fm === 'diff') {
      vscode.postMessage({command:'openDiff', filePath:fp, sessionRoot:sr, isNew:menu._isNew||false});
    } else if (fm.dataset.fm === 'copy') {
      vscode.postMessage({command:'copyPath', filePath:fp, sessionRoot:sr});
    } else if (fm.dataset.fm === 'explain-change') {
      vscode.postMessage({command:'explainChange', filePath:fp, sessionRoot:sr, added:menu._added||0, deleted:menu._deleted||0, totalChanged:menu._totalChanged||0, shellPid:menu._shellPid||0, sessionNick:menu._sessionNick||'', sessionId:menu._sessionId||''});
    } else if (fm.dataset.fm === 'refactor-here') {
      vscode.postMessage({command:'refactorInSession', filePath:fp, sessionRoot:sr, lineCount:menu._lineCount||0, shellPid:menu._shellPid||0, sessionNick:menu._sessionNick||'', sessionId:menu._sessionId||''});
    } else if (fm.dataset.fm === 'refactor-new-codex' || fm.dataset.fm === 'refactor-new-claude' || fm.dataset.fm === 'refactor-new-gemini' || fm.dataset.fm === 'refactor-new') {
      var agentProvider = fm.dataset.provider || fm.dataset.fm.replace('refactor-new-','');
      if (agentProvider === 'refactor-new') agentProvider = '';
      vscode.postMessage({command:'refactorNewSession', filePath:fp, sessionRoot:sr, lineCount:menu._lineCount||0, sessionProvider:menu._sessionProvider||'', agentProvider:agentProvider});
    } else if (fm.dataset.fm === 'ignore-size') {
      root._ignoredSizeFiles = root._ignoredSizeFiles || new Set();
      if (root._ignoredSizeFiles.has(fp)) {
        root._ignoredSizeFiles.delete(fp);
      } else {
        root._ignoredSizeFiles.add(fp);
        if (menu._sourceEl) { var badge = menu._sourceEl.querySelector('.fa-size-badge'); if (badge) badge.remove(); }
      }
      vscode.postMessage({command:'toggleIgnoreSize', filePath:fp, sessionRoot:sr});
    }
    menu.style.display = 'none';
    e.stopPropagation(); return true;
  }

  function initEvents(vscode) {
    var AB = root.AgentboardDashboard;

    root.document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') { var m = root.document.getElementById('_file-menu'); if (m) m.style.display = 'none'; }
    });

    root.document.addEventListener('mousemove', function(e) {
      var area = root.document.getElementById('trend-area');
      if (area && area.contains(e.target)) AB.trendChart.trendHover(e);
    });
    root.document.addEventListener('mouseout', function(e) {
      var area = root.document.getElementById('trend-area');
      if (area && !area.contains(e.relatedTarget)) AB.trendChart.trendOut();
    });

    root.document.addEventListener('change', function(e) {
      var sel = e.target.closest('[data-sess-stream-select]');
      if (sel) { vscode.postMessage({command:'setSessionStream', sessionId:sel.dataset.sessionId||'', streamSlug:sel.value, sessionRoot:sel.dataset.sessionRoot||''}); return; }
      var brSel = e.target.closest('[data-sess-branch-select]');
      if (brSel) { vscode.postMessage({command:'setSessionBranch', sessionId:brSel.dataset.sessionId||'', branch:brSel.value, sessionRoot:brSel.dataset.sessionRoot||''}); return; }
      if (e.target.id === 'h-br-sel') { vscode.postMessage({command:'setSessionBranch', sessionId:e.target.dataset.sessionId||'', branch:e.target.value, sessionRoot:e.target.dataset.sessionRoot||''}); return; }
    });

    root.document.addEventListener('click', function(e) {
      var t = e.target;

      // Trend time-window selector
      var tw = t.closest('[data-trend-win]');
      if (tw) {
        root._trendWin = tw.dataset.trendWin; _save();
        var ke = root.document.getElementById('kpi-grid');
        if (ke && root._lastD) ke.innerHTML = AB.trendChart.renderActivityChart(root._lastD);
        return;
      }
      // Trend series toggle
      var tt = t.closest('[data-trend-toggle]');
      if (tt) {
        if (!root._trendHidden) root._trendHidden = new Set();
        var tk = tt.dataset.trendToggle;
        if (root._trendHidden.has(tk)) root._trendHidden.delete(tk); else root._trendHidden.add(tk);
        _save();
        var ke2 = root.document.getElementById('kpi-grid');
        if (ke2 && root._lastD) ke2.innerHTML = AB.trendChart.renderActivityChart(root._lastD);
        return;
      }
      // Foldable section toggle
      var foldHdr = t.closest('.sec-ttl.foldable');
      if (foldHdr && !t.closest('[data-toggle-id]') && !t.closest('[data-view]')) {
        var foldSec = foldHdr.closest('.sec');
        if (foldSec) {
          var foldKey = foldSec.id || foldHdr.textContent || '';
          root._sectionFolded = root._sectionFolded || new Set();
          foldSec.classList.toggle('folded');
          if (foldSec.classList.contains('folded')) root._sectionFolded.add(foldKey);
          else root._sectionFolded.delete(foldKey);
          _save();
        }
        return;
      }
      // Session tab: Open Chat button
      var chatBtn = t.closest('[data-chat-btn]');
      if (chatBtn) {
        vscode.postMessage({command:'focusTerminal', shellPid:parseInt(chatBtn.dataset.shellPid||'0',10), sessionNick:chatBtn.dataset.sessionNick||'', sessionRoot:chatBtn.dataset.sessionRoot||'', sessionId:chatBtn.dataset.sessionId||''});
        return;
      }
      // Session tab: sibling session pill
      var sibBtn = t.closest('[data-focus-sibling]');
      if (sibBtn) { vscode.postMessage({command:'focusSessionTab', targetSessionId:sibBtn.dataset.focusSibling||''}); return; }
      // Main hub: "↗ tab" button on session card
      var openTabBtn = t.closest('[data-open-session-tab]');
      if (openTabBtn) { vscode.postMessage({command:'focusSessionTab', targetSessionId:openTabBtn.dataset.openSessionTab||''}); return; }
      // Session tab: refresh button (inside session-hdr)
      var rhdrBtn = t.closest('[data-refresh-btn]');
      if (rhdrBtn) { vscode.postMessage({command:'refresh'}); return; }
      // Refresh button (main)
      if (t.id === 'refresh-btn' || t.closest('#refresh-btn')) {
        var rbtn = root.document.getElementById('refresh-btn');
        if (rbtn) { rbtn.textContent = '↻ Refreshing…'; rbtn.disabled = true; setTimeout(function(){ rbtn.textContent = '↻ Refresh'; rbtn.disabled = false; }, 1200); }
        vscode.postMessage({command:'refresh'}); return;
      }
      // File options menu (diff / copy path / refactor / ignore)
      if (t.closest('#_file-menu')) { _handleFileMenuAction(t, e, vscode); return; }
      // Close file menu on outside click
      var existMenu = root.document.getElementById('_file-menu');
      if (existMenu && existMenu.style.display !== 'none' && !existMenu.contains(t)) {
        existMenu.style.display = 'none';
      }
      // Open file options menu
      var diffEl = t.closest('[data-open-diff]');
      if (diffEl) { _openFileMenu(e, diffEl, vscode); return; }
      // Workflow agent label expand/collapse
      var wfAgentEl = t.closest('[data-wf-agent-expand]');
      if (wfAgentEl) {
        var agKey2 = wfAgentEl.dataset.wfAgentExpand;
        root._wfAgentExpanded = root._wfAgentExpanded || new Set();
        var labelEl = wfAgentEl.querySelector('span[style*="cursor:pointer"]');
        if (root._wfAgentExpanded.has(agKey2)) {
          root._wfAgentExpanded.delete(agKey2);
          if (labelEl) { labelEl.style.whiteSpace='nowrap'; labelEl.style.overflow='hidden'; labelEl.style.textOverflow='ellipsis'; labelEl.style.wordBreak=''; }
        } else {
          root._wfAgentExpanded.add(agKey2);
          if (labelEl) { labelEl.style.whiteSpace='normal'; labelEl.style.overflow='visible'; labelEl.style.textOverflow='clip'; labelEl.style.wordBreak='break-word'; }
        }
        return;
      }
      // Close stream button
      var closeStreamBtn = t.closest('[data-close-stream-btn]');
      if (closeStreamBtn) {
        e.stopPropagation();
        var slug = closeStreamBtn.dataset.streamSlug || '';
        var sRoot2 = closeStreamBtn.dataset.sessionRoot || '';
        if (slug && root.confirm('Run "agentboard close ' + slug + '" in a new terminal?')) {
          vscode.postMessage({command:'closeStream', streamSlug:slug, sessionRoot:sRoot2});
        }
        return;
      }
      // Close session button
      var closeSessBtn = t.closest('[data-close-session]');
      if (closeSessBtn) { e.stopPropagation(); vscode.postMessage({command:'closeSession', sessionId:closeSessBtn.dataset.closeSession||''}); return; }
      // Focus terminal button
      var ftBtn = t.closest('[data-focus-terminal]');
      if (ftBtn) { e.stopPropagation(); vscode.postMessage({command:'focusTerminal', sessionRoot:ftBtn.dataset.sessionRoot||'', sessionNick:ftBtn.dataset.sessionNick||'', shellPid:parseInt(ftBtn.dataset.shellPid||'0',10), sessionStartedAt:ftBtn.dataset.sessionStartedAt||''}); return; }
      // Workflow toggle
      var wfToggle = t.closest('[data-workflow-toggle]');
      if (wfToggle) {
        var wfSid = wfToggle.dataset.workflowToggle;
        var wfBody = root.document.getElementById('wf-body-' + wfSid);
        var wfChevronEl = wfToggle.querySelector('span:last-child');
        if (wfBody) {
          var wfOpen = wfBody.style.display !== 'none';
          if (wfOpen) { wfBody.style.display='none'; wfBody.style.padding='0'; root._workflowExpanded.delete(wfSid); if(wfChevronEl) wfChevronEl.textContent='▸'; }
          else { wfBody.style.display='block'; wfBody.style.padding='0 14px 10px'; root._workflowExpanded.add(wfSid); if(wfChevronEl) wfChevronEl.textContent='▾'; }
          _save();
        }
        return;
      }
      // Activity toggle
      var actToggle = t.closest('[data-act-toggle]');
      if (actToggle) {
        root._actCollapsed = root._actCollapsed || new Set();
        var actSid = actToggle.dataset.actToggle;
        var actBody = root.document.getElementById('act-body-' + actSid);
        var actChevEl = actToggle.querySelector('span:last-child');
        if (actBody) {
          var actOpen = actBody.style.display !== 'none';
          if (actOpen) { actBody.style.display='none'; root._actCollapsed.add(actSid); if(actChevEl) actChevEl.textContent='▸'; }
          else { actBody.style.display='block'; root._actCollapsed.delete(actSid); if(actChevEl) actChevEl.textContent='▾'; }
          _save();
        }
        return;
      }
      // Sub-agents toggle
      var agToggle = t.closest('[data-agents-toggle]');
      if (agToggle) {
        var sid = agToggle.dataset.agentsToggle;
        var body = root.document.getElementById('agents-body-' + sid);
        var chevronEl = agToggle.querySelector('span:last-child');
        if (body) {
          var open = body.style.display !== 'none';
          if (open) { body.style.display='none'; body.style.padding='0'; root._agentExpanded.delete(sid); if(chevronEl) chevronEl.textContent='▸'; }
          else { body.style.display='block'; body.style.padding='0 14px 8px'; root._agentExpanded.add(sid); if(chevronEl) chevronEl.textContent='▾'; }
          _save();
        }
        return;
      }
      // Role launch button
      var launchBtn = t.closest('[data-launch-role]');
      if (launchBtn) { e.stopPropagation(); vscode.postMessage({command:'launchRole', slug:launchBtn.dataset.launchRole||'', name:launchBtn.dataset.launchRoleName||''}); return; }
      // Role card selection (toggle)
      var roleCard = t.closest('[data-role-select]');
      if (roleCard && !t.closest('[data-launch-role]')) {
        var slug2 = roleCard.dataset.roleSelect;
        root._selectedRole = root._selectedRole === slug2 ? null : slug2;
        AB.catalog.renderRolesCol('list-roles', root._rolesData || [], '#9c6af7');
      }
      // Catalog item expand/collapse
      var catToggle = t.closest('[data-cat-toggle]');
      if (catToggle) {
        root._catExpanded = root._catExpanded || new Set();
        var cid = catToggle.dataset.catToggle;
        var cbody = root.document.getElementById(cid + '-body');
        var changed = catToggle.querySelector('span[style*="opacity:.25"]');
        if (cbody) {
          var copen = cbody.style.display !== 'none';
          cbody.style.display = copen ? 'none' : 'block';
          if (changed) changed.textContent = copen ? '▸' : '▾';
          if (copen) root._catExpanded.delete(cid); else root._catExpanded.add(cid);
          _save();
        }
        return;
      }
      // Tab buttons
      var tab = t.closest('[data-view]');
      if (tab) { root.switchTab(tab.dataset.view, tab); return; }
      // Stream header toggle
      var hdr = t.closest('[data-toggle-id]');
      if (hdr) { AB.streams.toggleStream(hdr.dataset.toggleId, hdr.dataset.streamSlug||''); return; }
      // Open stream file button
      var openBtn = t.closest('[data-open-stream]');
      if (openBtn) { vscode.postMessage({command:'openStream', filePath:openBtn.dataset.openStream}); return; }
    });
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.events = { initEvents: initEvents };
})(typeof globalThis !== 'undefined' ? globalThis : this);
