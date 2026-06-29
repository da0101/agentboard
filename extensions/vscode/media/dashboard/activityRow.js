// Agentboard dashboard — shared file-activity row renderer (used in global + per-session card paths)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }

  // f        — file activity object {file, tool, lastTs, added, deleted, count, lineCount, isNew, isDeleted, committed}
  // sessRoot — session root path (string)
  // sess     — session object or null (provides sessionId, shellPid, nick, provider/model for context menus)
  function renderActivityRow(f, sessRoot, sess) {
    var c = _core();
    var esc = c.esc;
    var relTime = c.relTime;
    var icon = c.TOOL_ICON[f.tool] || '·';
    var isCmd = f.file.startsWith('$ ');
    var isEdited = (f.tool === 'Edit' || f.tool === 'Write' || f.tool === 'MultiEdit') && !isCmd;
    var ago = relTime(f.lastTs);
    var totalChanged = (f.added || 0) + (f.deleted || 0);

    var editWarn = '';
    if (isEdited && totalChanged >= 50) {
      var warnColor = c.editWarnColor(totalChanged);
      editWarn = '<span title="' + totalChanged + ' lines changed" style="color:' + warnColor + ';font-size:11px;flex-shrink:0;margin-right:2px">⚠</span>';
    }

    var sizeBadge = '';
    if (f.lineCount && !(root._ignoredSizeFiles && root._ignoredSizeFiles.has(f.file))) {
      var lc = f.lineCount;
      var sizeColor = c.sizeColor(lc);
      if (sizeColor) {
        sizeBadge = '<span class="fa-size-badge" title="' + lc + ' lines — ' + c.sizeDescription(lc) + '" style="font-size:9px;padding:1px 5px;border-radius:8px;background:' + sizeColor + '22;color:' + sizeColor + ';border:1px solid ' + sizeColor + '44;flex-shrink:0;cursor:default">' + c.sizeLabel(lc) + 'L</span>';
      }
    }

    var rowBg = f.isNew
      ? 'background:rgba(40,200,80,.07);border-left:2px solid rgba(40,200,80,.35);padding-left:4px;'
      : f.isDeleted
        ? 'background:rgba(220,60,60,.07);border-left:2px solid rgba(220,60,60,.35);padding-left:4px;'
        : '';

    var hasMenu = isEdited || (f.lineCount || 0) >= 500;
    var diffAttrs = hasMenu
      ? ' data-open-diff="' + esc(f.file) + '" data-session-root="' + esc(sessRoot) + '"'
        + (f.isNew ? ' data-is-new="1"' : '') + (f.isDeleted ? ' data-is-deleted="1"' : '')
        + ' data-line-count="' + (f.lineCount || 0) + '"'
        + ' data-added="' + (f.added || 0) + '" data-deleted="' + (f.deleted || 0) + '" data-total-changed="' + totalChanged + '"'
        + ' data-session-id="' + esc((sess && sess.sessionId) || '') + '"'
        + ' data-shell-pid="' + ((sess && sess.shellPid) || 0) + '"'
        + ' data-session-nick="' + esc((sess && sess.nick) || '') + '"'
        + ' data-session-provider="' + esc((sess && (sess.provider || sess.model)) || '') + '"'
        + ' title="Click for options" style="cursor:pointer;' + rowBg + '"'
      : (rowBg ? ' style="' + rowBg + '"' : '');

    return '<div class="fa"' + diffAttrs + '>'
      + '<span class="fa-icon">' + icon + '</span>'
      + '<div class="fa-body">'
      + '<span class="fa-file" title="' + esc(f.file) + '"'
        + (isEdited ? ' onmouseover="this.style.color=\'#7cbfff\'" onmouseout="this.style.color=\'\'"' : '')
        + ' style="color:' + (isCmd ? '#f0b429' : 'inherit') + '">' + esc(f.file) + '</span>'
      + (isEdited && (f.added != null || f.deleted != null)
        ? '<span style="font-size:10px;white-space:nowrap;flex-shrink:0">'
          + (f.added  ? '<span style="color:#4caf50">+' + f.added  + '</span>' : '')
          + (f.added && f.deleted ? '<span style="opacity:.3"> / </span>' : '')
          + (f.deleted ? '<span style="color:#f44336">-' + f.deleted + '</span>' : '')
          + '</span>'
        : '')
      + (f.count > 1 ? '<span class="fa-cnt">×' + f.count + '</span>' : '')
      + '<span class="fa-t">' + ago + '</span>'
      + sizeBadge + editWarn
      + (f.committed && f.added == null && f.deleted == null ? '<span title="Committed to branch" style="color:#4caf50;font-size:11px;flex-shrink:0;margin-left:2px">✓</span>' : '')
      + '</div>'
      + '</div>';
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.activityRow = { renderActivityRow: renderActivityRow };
})(typeof globalThis !== 'undefined' ? globalThis : this);
