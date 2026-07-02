// Provider-specific presentation model for dashboard session surfaces.
(function(root) {
  'use strict';

  var PROVIDERS = {
    claude: {
      key: 'claude',
      label: 'Claude',
      accent: '#ff8a3d',
      accentSoft: 'rgba(255,138,61,.07)',
      accentBorder: 'rgba(255,138,61,.24)',
      subagentsLabel: 'Sub-agents',
      emptyAgents: 'No Claude sub-agents',
      liveHint: 'Claude session snapshot is updating',
      staleHint: 'Claude session snapshot is stale',
      clearLiveLabel: 'Dismiss',
      clearStaleLabel: 'Clear stale',
      clearLiveTitle: 'Dismiss this Claude session snapshot from the dashboard',
      clearStaleTitle: 'Clear this stale Claude session snapshot from the dashboard'
    },
    codex: {
      key: 'codex',
      label: 'Codex',
      accent: '#4a9eff',
      accentSoft: 'rgba(74,158,255,.07)',
      accentBorder: 'rgba(74,158,255,.24)',
      subagentsLabel: 'Workers',
      emptyAgents: 'No Codex workers attributed yet',
      liveHint: 'Codex session snapshot is updating',
      staleHint: 'Codex session snapshot is stale',
      clearLiveLabel: 'Dismiss',
      clearStaleLabel: 'Clear stale Codex',
      clearLiveTitle: 'Dismiss this Codex session snapshot from the dashboard',
      clearStaleTitle: 'Clear this stale Codex snapshot. This does not terminate Codex or delete work.'
    },
    gemini: {
      key: 'gemini',
      label: 'Gemini',
      accent: '#00bfa5',
      accentSoft: 'rgba(0,191,165,.18)',
      accentBorder: 'rgba(0,191,165,.48)',
      subagentsLabel: 'Workers',
      emptyAgents: 'No Gemini workers attributed yet',
      liveHint: 'Gemini session snapshot is updating',
      staleHint: 'Gemini session snapshot is stale',
      clearLiveLabel: 'Dismiss',
      clearStaleLabel: 'Clear stale',
      clearLiveTitle: 'Dismiss this Gemini session snapshot from the dashboard',
      clearStaleTitle: 'Clear this stale Gemini session snapshot from the dashboard'
    },
    unknown: {
      key: 'unknown',
      label: 'Agent',
      accent: '#8a8a8a',
      accentSoft: 'rgba(255,255,255,.08)',
      accentBorder: 'rgba(255,255,255,.18)',
      subagentsLabel: 'Agents',
      emptyAgents: 'No sub-agents',
      liveHint: 'Session snapshot is updating',
      staleHint: 'Session snapshot is stale',
      clearLiveLabel: 'Dismiss',
      clearStaleLabel: 'Clear stale',
      clearLiveTitle: 'Dismiss this session snapshot from the dashboard',
      clearStaleTitle: 'Clear this stale session snapshot from the dashboard'
    }
  };

  function normalizeProvider(provider) {
    var raw = String(provider || '').toLowerCase();
    if (raw.indexOf('claude') !== -1 || raw.indexOf('anthropic') !== -1) return 'claude';
    if (raw.indexOf('codex') !== -1 || raw.indexOf('openai') !== -1 || raw.indexOf('gpt') !== -1) return 'codex';
    if (raw.indexOf('gemini') !== -1 || raw.indexOf('google') !== -1) return 'gemini';
    return 'unknown';
  }

  function isSessionLive(session, nowMs) {
    if (!session) return false;
    var now = nowMs == null ? Date.now() : nowMs;
    if (typeof session.ageSeconds === 'number') return session.ageSeconds < 180;
    var lastUpdatedMs = session.lastUpdated ? new Date(session.lastUpdated).getTime() : 0;
    return lastUpdatedMs > 0 && (now - lastUpdatedMs < 180000);
  }

  function getProviderUi(session, nowMs) {
    var key = normalizeProvider(session && (session.provider || session.model));
    var base = PROVIDERS[key] || PROVIDERS.unknown;
    var live = isSessionLive(session, nowMs);
    return {
      key: base.key,
      label: base.label,
      accent: base.accent,
      accentSoft: base.accentSoft,
      accentBorder: base.accentBorder,
      subagentsLabel: base.subagentsLabel,
      emptyAgents: base.emptyAgents,
      live: live,
      stale: !live,
      statusHint: live ? base.liveHint : base.staleHint,
      clearLabel: live ? base.clearLiveLabel : base.clearStaleLabel,
      clearTitle: live ? base.clearLiveTitle : base.clearStaleTitle
    };
  }

  var api = {
    PROVIDERS: PROVIDERS,
    normalizeProvider: normalizeProvider,
    isSessionLive: isSessionLive,
    getProviderUi: getProviderUi
  };

  root.AgentboardDashboard = root.AgentboardDashboard || {};
  root.AgentboardDashboard.providerUi = api;

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this);
