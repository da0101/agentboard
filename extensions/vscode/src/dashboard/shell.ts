import * as vscode from "vscode";

export function getDashboardShell(data: object | undefined, webview: vscode.Webview | undefined, extensionUri: vscode.Uri | undefined): string { // eslint-disable-line
    const src = webview?.cspSource ?? "";
    const csp = `default-src 'none'; img-src 'none'; style-src 'unsafe-inline' ${src}; script-src ${src}; connect-src 'none';`;
    // Data injected as non-executable JSON element — works regardless of script CSP
    const dataEl = data
      ? `<script id="ab-data" type="application/json">${JSON.stringify(data).replace(/<\/script>/gi, "<\\/script>")}</script>`
      : "";
    // External scripts loaded via webview URIs (allowed by cspSource)
    let scriptTag = "";
    if (webview && extensionUri) {
      const scripts = [
        vscode.Uri.joinPath(extensionUri, "media", "dashboard", "core.js"),
        vscode.Uri.joinPath(extensionUri, "media", "dashboard.js"),
      ];
      scriptTag = scripts
        .map((uri) => `<script src="${webview.asWebviewUri(uri).toString()}"></script>`)
        .join("");
    }
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="${csp}">${dataEl}<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;height:100vh;display:flex;flex-direction:column;overflow:hidden}
#hdr{display:flex;align-items:center;gap:8px;padding:8px 14px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.logo{color:#4a9eff;font-weight:700;letter-spacing:.08em;font-size:11px}.sep{opacity:.25}.proj{opacity:.65;font-size:12px}.br{opacity:.4;font-size:11px}
.rbtn{margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:inherit;border-radius:4px;padding:2px 8px;cursor:pointer;font-size:11px;transition:opacity .1s}
.rbtn:hover{background:var(--vscode-list-hoverBackground)}
.rbtn:active{opacity:.5}
.tabs{display:flex;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0;padding:0 14px}
.tab{padding:5px 12px;font-size:12px;cursor:pointer;border:none;border-bottom:2px solid transparent;opacity:.45;transition:all .15s;background:none;color:inherit}
.tab.on{opacity:1;border-bottom-color:#4a9eff;color:#4a9eff}
.tab:hover{opacity:.75}
.view{flex:1;overflow:hidden;display:none;flex-direction:column}
.view.on{display:flex}
/* NOW block */
#now{flex-shrink:0;padding:12px 14px;border-bottom:1px solid var(--vscode-panel-border);background:rgba(74,158,255,.04)}
#now.idle{background:transparent}
.now-status{display:flex;align-items:center;gap:8px;margin-bottom:6px}
.dot{width:7px;height:7px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite;flex-shrink:0}
.dot.idle{background:#666;animation:none}
.now-state{font-size:11px;font-weight:700;letter-spacing:.1em;color:#4caf50}
.now-state.idle{color:#666}
.now-stats{font-size:12px;opacity:.65;margin-left:4px}
.now-last{display:flex;align-items:baseline;gap:6px;margin-bottom:4px}
.now-file{font-family:var(--vscode-editor-font-family,'monospace');font-size:14px;font-weight:600;color:#e8e8e8}
.now-tool{font-size:10px;padding:1px 6px;border-radius:4px;background:rgba(255,255,255,.08);font-weight:500}
.now-ago{font-size:11px;opacity:.4;margin-left:auto;white-space:nowrap}
.now-desc{font-size:11px;opacity:.45;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
.now-longop{font-size:11px;color:#ff9800;margin-top:4px;display:none}
.now-longop.on{display:block}
/* body split */
#live-body{display:flex;flex:1;min-height:0;overflow:hidden}
.col-l{flex:3;border-right:1px solid var(--vscode-panel-border);overflow-y:auto;display:flex;flex-direction:column}
.col-r{flex:2;overflow-y:auto;display:flex;flex-direction:column}
/* multi-session layout */
#live-body.multi{flex-direction:column;overflow-y:auto;overflow-x:hidden}
#sec-multi-sessions{padding:0}
#sec-multi-sessions>.sec-ttl{padding:6px 14px;margin:0}
#streams-row{flex-shrink:0}
#streams-row>#sr-list2{max-height:220px;overflow-y:auto}
#session-cols{display:flex;flex-wrap:wrap;align-content:flex-start;overflow-y:visible;overflow-x:hidden}
.sess-col{border-right:1px solid var(--vscode-panel-border);border-bottom:1px solid var(--vscode-panel-border);display:flex;flex-direction:column;min-width:220px;overflow-y:auto;overflow-x:hidden;min-height:200px}
.sess-col:last-child{border-right:none}
.sess-col-hdr{flex-shrink:0;padding:10px 14px;border-bottom:1px solid var(--vscode-panel-border);background:rgba(255,255,255,.02)}
.sess-col-name{display:flex;align-items:center;gap:6px;margin-bottom:6px}
.sess-col-grid{display:grid;grid-template-columns:52px 1fr;gap:2px 8px;font-size:11px}
.sess-col-activity{flex:1;overflow-y:auto;padding:4px 0}
.streams-row{flex-shrink:0;border-top:1px solid var(--vscode-panel-border);overflow-y:auto;max-height:220px}
.sec{padding:10px 14px;border-bottom:1px solid var(--vscode-panel-border)}
.sec:last-child{border-bottom:none}
.sec-ttl{font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.35;margin-bottom:8px}
/* file activity */
.fa{display:grid;grid-template-columns:auto 1fr;gap:0 10px;padding:4px 0;border-bottom:1px solid rgba(128,128,128,.07);font-size:12px}
.fa:last-child{border-bottom:none}
.fa-icon{opacity:.45;font-size:11px;text-align:center;width:14px;padding-top:2px}
.fa-body{display:flex;flex-wrap:nowrap;align-items:baseline;gap:0 6px;min-width:0;overflow:hidden}
.fa-file{font-family:var(--vscode-editor-font-family,'monospace');overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;min-width:0}
.fa-cnt{font-size:10px;opacity:.3;white-space:nowrap;flex-shrink:0}
.fa-t{font-size:10px;opacity:.35;white-space:nowrap;flex-shrink:0}
/* streams */
.sr{display:flex;align-items:center;gap:8px;padding:4px 0;border-bottom:1px solid rgba(128,128,128,.07);font-size:12px}
.sr:last-child{border-bottom:none}
.sr-dot{width:5px;height:5px;border-radius:50%;flex-shrink:0}
.sr-name{font-family:var(--vscode-editor-font-family,'monospace');flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sr-name.active{color:#4a9eff;font-weight:600}
.sr-type{font-size:10px;padding:1px 5px;border-radius:4px;white-space:nowrap;font-weight:500}
/* stats */
.stat-grid{display:grid;grid-template-columns:auto 1fr;gap:3px 12px;font-size:12px;line-height:1.8}
.sk{opacity:.35;font-size:11px;white-space:nowrap}.sv{font-weight:500}
.sv-stream{color:#4a9eff}.sv-role{color:#9c6af7}.sv-skill{color:#4caf84}
/* agent rows */
.ag-row{display:flex;align-items:center;gap:6px;padding:4px 0;border-bottom:1px solid rgba(128,128,128,.07);font-size:12px}
.ag-row:last-child{border-bottom:none}
.ag-pulse{width:6px;height:6px;border-radius:50%;background:#4caf50;animation:pulse .8s ease-in-out infinite;flex-shrink:0}
.ag-label{flex:1;font-family:var(--vscode-editor-font-family,'monospace');overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ag-t{font-size:10px;opacity:.35;white-space:nowrap}
.ctx{font-family:monospace;letter-spacing:-1px;font-size:11px}
/* footer */
#footer{display:flex;gap:6px;padding:6px 14px;border-top:1px solid var(--vscode-panel-border);flex-shrink:0;font-size:11px;align-items:center;flex-wrap:wrap}
.fi{padding:2px 6px;border-radius:4px;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);white-space:nowrap}
/* catalog */
#cat-body{display:flex;flex:1;overflow:hidden}
.cat-col{flex:1;display:flex;flex-direction:column;border-right:1px solid var(--vscode-panel-border);overflow:hidden}
.cat-col:last-child{border-right:none}
.cat-hdr{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.cdot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.ctitle{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.45;flex:1}
.ccount{font-size:24px;font-weight:700;line-height:1}
.cat-list{flex:1;overflow-y:auto;padding:4px 0}
.ci{padding:5px 14px;border-bottom:1px solid rgba(128,128,128,.07);cursor:default;transition:background .1s}
.ci:hover{background:var(--vscode-list-hoverBackground)}
.ci-name{display:block;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;font-weight:500}
.ci-desc{display:block;font-size:10px;opacity:.38;margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.more{padding:7px 14px;font-size:11px;opacity:.3;font-style:italic}
.em{opacity:.35;font-size:11px;font-style:italic}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(1.3)}}
/* KPI grid */
#kpi-grid{padding:10px 14px 6px;border-bottom:1px solid var(--vscode-panel-border);display:none;flex-direction:column;gap:8px}
.kpi-group{display:flex;flex-direction:column;gap:4px}
.kpi-group-lbl{font-size:9px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;opacity:.25;cursor:pointer;user-select:none;display:flex;align-items:center;justify-content:space-between}
.kpi-group-lbl::after{content:'▾';font-size:9px;opacity:.4;flex-shrink:0;margin-left:4px}
.kpi-group.folded .kpi-group-lbl::after{content:'▸'}
.kpi-row{display:flex;flex-wrap:wrap;gap:5px}
.kpi-tile{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.07);border-radius:5px;padding:5px 10px;min-width:48px;cursor:default;transition:background .1s}
.kpi-tile:hover{background:rgba(255,255,255,.07)}
.kpi-val{font-size:14px;font-weight:700;line-height:1.15;letter-spacing:-.01em}
.kpi-lbl{font-size:9px;opacity:.38;margin-top:1px;white-space:nowrap}
/* Session tab mode — stacked single-column layout, no nav bar */
#session-hdr{display:none;flex-direction:column;flex-shrink:0;border-bottom:1px solid var(--vscode-panel-border);background:rgba(255,255,255,.015)}
body.session-tab #hdr{display:none}
body.session-tab .tabs{display:none}
body.session-tab #session-hdr{display:flex}
body.session-tab #live{overflow-y:auto;overflow-x:hidden}
body.session-tab #live-body{flex-direction:column;overflow:visible}
body.session-tab .col-l{flex:none;width:100%;overflow-y:visible;border-right:none;border-bottom:1px solid var(--vscode-panel-border)}
body.session-tab .col-r{flex:none;width:100%;overflow-y:visible}
body.session-tab #footer{display:none}
/* Session tab section ordering: 1-Session 2-Agents 3-Activity */
body.session-tab .col-r{order:1!important}
body.session-tab .col-l{order:2!important}
body.session-tab #sec-session-single,body.session-tab #sec-role{order:-1}
/* Hide streams completely in session tabs — they belong in the main hub */
body.session-tab #sec-streams{display:none!important}
/* Foldable sections */
.sec-ttl.foldable{cursor:pointer;user-select:none;display:flex;align-items:center;justify-content:space-between}
.sec-ttl.foldable::after{content:'▾';font-size:10px;opacity:.28;flex-shrink:0;margin-left:6px}
.sec.folded>.sec-ttl.foldable::after{content:'▸'}
.sec.folded>:not(.sec-ttl){display:none!important}
.sib-pill{cursor:pointer;padding:2px 8px;border-radius:10px;border:1px solid rgba(255,255,255,.18);font-size:10px;font-family:monospace;opacity:.65;display:inline-block;transition:opacity .15s}
.sib-pill:hover{opacity:1}
</style></head><body>

<div id="session-hdr"></div>
<div id="hdr">
  <span class="logo">◆ AGENTBOARD</span><span class="sep">·</span>
  <span class="proj" id="h-proj">—</span><span class="sep" id="h-sep2" style="display:none">·</span><span class="br" id="h-br"></span>
  <button class="rbtn" id="refresh-btn">↻ Refresh</button>
</div>

<div class="tabs">
  <button class="tab on" data-view="live">Live</button>
  <button class="tab" id="tab-catalog" data-view="catalog">Catalog</button>
</div>

<div id="live" class="view on">
  <!-- NOW block -->
  <div id="now">
    <div class="now-status">
      <span class="dot" id="now-dot"></span>
      <span class="now-state" id="now-state">IDLE</span>
      <span class="now-stats" id="now-stats"></span>
    </div>
    <div id="now-file-row">
      <div class="now-last">
        <span class="now-tool" id="now-tool"></span>
        <span class="now-file" id="now-file">No activity yet</span>
        <span class="now-ago" id="now-ago"></span>
      </div>
      <div class="now-desc" id="now-desc"></div>
      <div class="now-longop" id="now-longop">⟳ Running long operation — last tool call completed &gt;90s ago</div>
    </div>
  </div>

  <div id="kpi-grid" style="display:none"></div>

  <div id="live-body">
    <!-- Multi-session: sessions + streams sections (foldable) -->
    <div class="sec" id="sec-multi-sessions" style="display:none">
      <div class="sec-ttl foldable" id="multi-sessions-ttl">Sessions</div>
      <div id="session-cols"></div>
    </div>
    <div class="sec" id="streams-row" style="display:none">
      <div class="sec-ttl foldable" id="sr-ttl2">Active streams</div>
      <div id="sr-list2"></div>
    </div>
    <!-- Single-session: Left: files touched + streams -->
    <div class="col-l">
      <div class="sec" id="sec-activity">
        <div class="sec-ttl foldable" id="fa-ttl">Activity this session</div>
        <div id="fa-list"><div class="em">No activity yet</div></div>
      </div>
      <div class="sec" id="sec-streams">
        <div class="sec-ttl foldable" id="sr-ttl">Active streams</div>
        <div id="sr-list"></div>
      </div>
    </div>
    <!-- Right: agents + session stats -->
    <div class="col-r">
      <div class="sec" id="sec-agents">
        <div class="sec-ttl foldable" id="agents-ttl">Agents <span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none">· last 5 min</span></div>
        <div id="agents-list"><div class="em">No sub-agents</div></div>
      </div>
      <div class="sec" id="sec-sessions" style="display:none">
        <div class="sec-ttl foldable">Sessions</div>
        <div id="sessions-list"></div>
      </div>
      <div class="sec" id="sec-session-single">
        <div class="sec-ttl foldable">Session</div>
        <div class="stat-grid">
          <span class="sk">Model</span><span class="sv" id="sv-model">—</span>
          <span class="sk">Stream</span><span class="sv sv-stream" id="sv-stream">—</span>
          <span class="sk">Cost</span><span class="sv" id="sv-cost">—</span>
          <span class="sk">Time</span><span class="sv" id="sv-time">—</span>
          <span class="sk">Context</span><span class="sv" id="sv-ctx">—</span>
          <span class="sk">Branch</span><span class="sv" id="sv-branch" style="font-family:var(--vscode-editor-font-family,'monospace');font-size:11px">—</span>
        </div>
      </div>
      <div class="sec" id="sec-role" style="display:none">
        <div class="sec-ttl foldable">Role / Skill</div>
        <div class="stat-grid" id="role-grid"></div>
      </div>
    </div>
  </div>
</div>

<div id="catalog" class="view">
  <div id="cat-body">
    <div class="cat-col">
      <div class="cat-hdr"><span class="cdot" style="background:#4a9eff"></span><span class="ctitle">Skills</span><span class="ccount" style="color:#4a9eff" id="cnt-skills">0</span></div>
      <div class="cat-list" id="list-skills"></div>
    </div>
    <div class="cat-col">
      <div class="cat-hdr"><span class="cdot" style="background:#9c6af7"></span><span class="ctitle">Roles</span><span class="ccount" style="color:#9c6af7" id="cnt-roles">0</span></div>
      <div class="cat-list" id="list-roles"></div>
    </div>
    <div class="cat-col">
      <div class="cat-hdr"><span class="cdot" style="background:#4caf84"></span><span class="ctitle">Commands</span><span class="ccount" style="color:#4caf84" id="cnt-cmds">0</span></div>
      <div class="cat-list" id="list-cmds"></div>
    </div>
  </div>
</div>

<div id="footer"></div>

${scriptTag}
</body></html>`;
}
