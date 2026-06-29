// Agentboard dashboard — catalog column renderers (skills, roles, commands)
(function(root) {
  'use strict';
  var AB_CORE;
  function _core() { return AB_CORE || (AB_CORE = root.AgentboardDashboard.core); }
  function _save() { root.AgentboardDashboard.uiState.saveUiState(); }

  var MAX_ITEMS = 200;

  // Shared: render one expandable catalog item row (skill, command, or role base card).
  function _itemRow(eid, item, accentColor, extraHeaderHtml, extraBodyHtml) {
    var esc = _core().esc;
    var isOpen = (root._catExpanded || new Set()).has(eid);
    var hasMore = item.fullDescription
      && item.fullDescription !== item.description
      && item.fullDescription.length > 10;
    var usedBy = item.usedBy && item.usedBy.length ? item.usedBy : null;

    var row = '<div class="ci" style="cursor:' + (hasMore ? 'pointer' : 'default') + '" data-cat-toggle="' + eid + '">';
    row += '<div style="display:flex;align-items:baseline;gap:6px;flex-wrap:wrap">';
    row += '<span class="ci-name">' + esc(item.name) + '</span>';
    if (hasMore) row += '<span style="font-size:9px;opacity:.25">' + (isOpen ? '▾' : '▸') + '</span>';
    if (usedBy) {
      row += usedBy.map(function(nick) {
        return '<span style="font-size:9px;padding:1px 5px;border-radius:8px;background:' + (accentColor || '#4a9eff') + '22;color:' + (accentColor || '#4a9eff') + ';white-space:nowrap">' + esc(nick) + '</span>';
      }).join('');
    }
    if (extraHeaderHtml) row += extraHeaderHtml;
    row += '</div>';
    if (item.description) row += '<span class="ci-desc">' + esc(item.description.slice(0, 120)) + '</span>';
    if (hasMore) row += '<div id="' + eid + '-body" style="display:' + (isOpen ? 'block' : 'none') + ';font-size:11px;opacity:.55;line-height:1.6;margin-top:4px;white-space:pre-wrap;border-left:2px solid ' + (accentColor || '#4a9eff') + '44;padding-left:8px">' + esc(item.fullDescription || '') + '</div>';
    if (extraBodyHtml) row += extraBodyHtml;
    row += '</div>';
    return row;
  }

  function renderCatalogCol(listId, items, accentColor) {
    var html = _core().html;
    root._catExpanded = root._catExpanded || new Set();
    var h = items.slice(0, MAX_ITEMS).map(function(item, idx) {
      return _itemRow(listId + '-' + idx, item, accentColor, '', '');
    }).join('');
    if (items.length > MAX_ITEMS) h += '<div class="more">+' + (items.length - MAX_ITEMS) + ' more</div>';
    html(listId, h);
  }

  function renderRolesCol(listId, roles, accentColor) {
    var esc = _core().esc;
    var html = _core().html;
    root._catExpanded = root._catExpanded || new Set();
    var selected = root._selectedRole;
    var h = roles.slice(0, MAX_ITEMS).map(function(role, idx) {
      var eid = listId + '-' + idx;
      var isSelected = selected === (role.slug || role.name);
      var linked = role.linkedSkills && role.linkedSkills.length ? role.linkedSkills : [];
      var cardStyle = 'cursor:pointer;border-radius:5px;padding:2px 4px;margin:-2px -4px;transition:background .1s;';
      if (isSelected) cardStyle += 'background:rgba(156,106,247,.1);outline:1px solid rgba(156,106,247,.35);';

      var extraHeader = '<span style="font-size:9px;opacity:.25">' +
        ((root._catExpanded || new Set()).has(eid) ? '▾' : '▸') + '</span>';

      var extraBody = '';
      if (isSelected) {
        extraBody += '<div style="margin-top:8px;padding:8px;background:rgba(156,106,247,.06);border-radius:4px;border:1px solid rgba(156,106,247,.18)">';
        if (linked.length) {
          extraBody += '<div style="display:flex;flex-wrap:wrap;gap:4px;margin-bottom:7px">';
          extraBody += linked.map(function(sk){
            return '<span style="font-size:10px;padding:2px 7px;border-radius:10px;background:#4a9eff18;color:#4a9eff;border:1px solid #4a9eff33">' + esc(sk) + '</span>';
          }).join('');
          extraBody += '</div>';
        }
        extraBody += '<button data-launch-role="' + esc(role.slug || role.name) + '" data-launch-role-name="' + esc(role.name) + '" style="width:100%;background:#9c6af7;color:#fff;border:none;border-radius:4px;padding:6px 10px;font-size:12px;cursor:pointer;font-family:inherit">▶  Launch Claude as ' + esc(role.name) + '</button>';
        extraBody += '</div>';
      }

      // Role cards use a slightly different outer div with selection style + data-role-select
      var row = '<div class="ci" style="' + cardStyle + '" data-role-select="' + esc(role.slug || role.name) + '" data-role-name="' + esc(role.name) + '" data-cat-toggle="' + eid + '">';
      row += '<div style="display:flex;align-items:baseline;gap:6px;flex-wrap:wrap">';
      row += '<span class="ci-name">' + esc(role.name) + '</span>';
      var hasMore = role.fullDescription && role.fullDescription.length > 10;
      if (hasMore) row += '<span style="font-size:9px;opacity:.25">' + ((root._catExpanded || new Set()).has(eid) ? '▾' : '▸') + '</span>';
      if (role.usedBy && role.usedBy.length) {
        row += role.usedBy.map(function(n) {
          return '<span style="font-size:9px;padding:1px 5px;border-radius:8px;background:' + accentColor + '22;color:' + accentColor + ';white-space:nowrap">' + esc(n) + '</span>';
        }).join('');
      }
      row += '</div>';
      if (role.description) row += '<span class="ci-desc">' + esc(role.description.slice(0, 120)) + '</span>';
      if (hasMore) row += '<div id="' + eid + '-body" style="display:' + ((root._catExpanded || new Set()).has(eid) ? 'block' : 'none') + ';font-size:11px;opacity:.55;line-height:1.6;margin-top:4px;white-space:pre-wrap;border-left:2px solid ' + accentColor + '44;padding-left:8px">' + esc(role.fullDescription || '') + '</div>';
      row += extraBody;
      row += '</div>';
      return row;
    }).join('');
    html(listId, h);
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.catalog = {
    renderCatalogCol: renderCatalogCol,
    renderRolesCol:   renderRolesCol
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
