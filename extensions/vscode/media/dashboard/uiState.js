// Agentboard dashboard — UI state persistence helpers
(function(root) {
  'use strict';

  function loadUiState() {
    try {
      var vs = root._vscode;
      return (vs && vs.getState && vs.getState()) || {};
    } catch(e) { return {}; }
  }

  function savedUi() { return loadUiState().ui || {}; }

  function savedSet(name) {
    var v = savedUi()[name];
    return new Set(Array.isArray(v) ? v : []);
  }

  function saveUiState() {
    try {
      var vs = root._vscode;
      if (!vs) return;
      var prev = loadUiState();
      vs.setState(Object.assign({}, prev, {ui:{
        streamOpen:    root._streamOpenState  || {},
        sectionFolded: Array.from(root._sectionFolded  || []),
        trendWin:      root._trendWin || '1h',
        trendHidden:   Array.from(root._trendHidden   || []),
        agentExpanded: Array.from(root._agentExpanded  || []),
        workflowExpanded: Array.from(root._workflowExpanded || []),
        actCollapsed:  Array.from(root._actCollapsed   || []),
        catExpanded:   Array.from(root._catExpanded    || [])
      }}));
    } catch(e) {}
  }

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.uiState = {
    loadUiState:  loadUiState,
    savedUi:      savedUi,
    savedSet:     savedSet,
    saveUiState:  saveUiState
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
