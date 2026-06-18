import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import { execSync } from "child_process";
import { HudStatus } from "./hudTypes";

interface StreamEntry { slug: string; status: string; type: string; next_action: string; role: string; }
interface ActivityEvent { ts: string; tool: string; stream: string; file?: string; cmd?: string; hook_event_name?: string; }
interface CatalogItem { name: string; description: string; }

function httpGet(url: string, ms: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let d = ""; res.on("data", (c: Buffer) => { d += c.toString(); }); res.on("end", () => resolve(d));
    });
    req.setTimeout(ms, () => { req.destroy(); reject(new Error("t")); });
    req.on("error", reject);
  });
}

function parseFrontmatter(content: string): Record<string, string> {
  const m = content.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return {};
  const r: Record<string, string> = {};
  for (const line of m[1].split("\n")) {
    const i = line.indexOf(":"); if (i === -1) continue;
    r[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, "");
  }
  return r;
}

function readStreams(root: string): StreamEntry[] {
  const dir = path.join(root, ".platform", "work");
  const skip = new Set(["BRIEF.md", "TEMPLATE.md", "Status.md", "ACTIVE.md"]);
  try {
    return fs.readdirSync(dir).filter(f => f.endsWith(".md") && !skip.has(f)).flatMap(f => {
      try {
        const c = fs.readFileSync(path.join(dir, f), "utf8");
        const fm = parseFrontmatter(c);
        const st = (fm.status ?? "").toLowerCase();
        if (["done", "archived", "closed"].includes(st)) return [];
        const na = fm.next_action ?? (c.match(/##\s*Next\s+action\s*\n([^\n]+)/i)?.[1]?.trim() ?? "");
        return [{ slug: fm.slug ?? path.basename(f, ".md"), status: fm.status ?? "active", type: fm.type ?? "task", next_action: na, role: fm.role ?? "" }];
      } catch { return []; }
    });
  } catch { return []; }
}

function readSkills(root: string): CatalogItem[] {
  const dir = path.join(root, ".claude", "skills");
  try {
    return fs.readdirSync(dir).flatMap(name => {
      try {
        const fm = parseFrontmatter(fs.readFileSync(path.join(dir, name, "SKILL.md"), "utf8"));
        return [{ name: fm.name ?? name, description: fm.description ?? "" }];
      } catch { return [{ name, description: "" }]; }
    });
  } catch { return []; }
}

function readRoles(root: string): CatalogItem[] {
  const dir = path.join(root, ".platform", "roles");
  try {
    return fs.readdirSync(dir).filter(f => f.endsWith(".md") && f !== "INDEX.md").flatMap(f => {
      try {
        const fm = parseFrontmatter(fs.readFileSync(path.join(dir, f), "utf8"));
        return [{ name: fm.name ?? fm.slug ?? path.basename(f, ".md"), description: fm.description ?? fm.objective ?? "" }];
      } catch { return []; }
    });
  } catch { return []; }
}

function readActiveStream(root: string): string {
  try {
    const brief = fs.readFileSync(path.join(root, ".platform", "work", "BRIEF.md"), "utf8");
    return brief.match(/\*\*Stream file:\*\*\s*`work\/([^`]+)\.md`/)?.[1] ?? "";
  } catch { return ""; }
}

function readStreamRole(root: string, slug: string): string {
  if (!slug) return "";
  try { return parseFrontmatter(fs.readFileSync(path.join(root, ".platform", "work", `${slug}.md`), "utf8")).role ?? ""; } catch { return ""; }
}

function readRecentEvents(root: string, n = 20): ActivityEvent[] {
  try {
    return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
      .trim().split("\n").filter(Boolean).slice(-n).reverse()
      .map(line => { try { return JSON.parse(line) as ActivityEvent; } catch { return null; } })
      .filter((e): e is ActivityEvent => e !== null);
  } catch { return []; }
}

function readLastSkill(root: string): string {
  try {
    const lines = fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
      .trim().split("\n").filter(Boolean).reverse();
    for (const line of lines) {
      try {
        const e = JSON.parse(line) as { tool?: string; skill?: string; cmd?: string };
        if (e.tool === "Skill" && e.skill) return e.skill;
      } catch { /* ok */ }
    }
  } catch { /* ok */ }
  return "";
}

function gitWorktrees(root: string): string[] {
  try {
    return execSync("git worktree list --porcelain", { cwd: root, timeout: 2000 }).toString()
      .split("\n\n").filter(Boolean)
      .map(b => b.split("\n").find(l => l.startsWith("branch "))?.replace("branch refs/heads/", "") ?? "main");
  } catch { return []; }
}

function relTime(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

function elapsedStr(s?: string): string {
  if (!s) return "";
  const d = Math.floor((Date.now() - new Date(s).getTime()) / 1000);
  return `${Math.floor(d / 60)}m ${d % 60}s`;
}

function fmtModel(raw: string): string {
  return raw.replace(/^claude-/i, "").replace(/-\d{8}$/, "")
    .split("-").map(w => w[0].toUpperCase() + w.slice(1)).join(" ");
}

const MODEL_NAMES = new Set(["claude", "sonnet", "opus", "haiku", "fable", "gpt", "gemini", "codex"]);

export class DashboardPanel {
  static currentPanel: DashboardPanel | undefined;
  private readonly _panel: vscode.WebviewPanel;
  private _disposables: vscode.Disposable[] = [];
  private _interval: NodeJS.Timeout | undefined;
  private _initialized = false;

  static createOrShow(workspaceRoot: string): void {
    const col = vscode.window.activeTextEditor?.viewColumn ?? vscode.ViewColumn.One;
    if (DashboardPanel.currentPanel) { DashboardPanel.currentPanel._panel.reveal(col); return; }
    DashboardPanel.currentPanel = new DashboardPanel(
      vscode.window.createWebviewPanel("agentboardDashboard", "Agentboard", col, { enableScripts: true, retainContextWhenHidden: true }),
      workspaceRoot
    );
  }

  private constructor(panel: vscode.WebviewPanel, private readonly workspaceRoot: string) {
    this._panel = panel;
    this._panel.webview.html = this._getShell();
    this._initialized = true;
    void this._update();
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(workspaceRoot, "{agentboard.hud-status.json,.platform/events.jsonl,.platform/work/*.md}")
    );
    watcher.onDidChange(() => void this._update(), null, this._disposables);
    watcher.onDidCreate(() => void this._update(), null, this._disposables);
    this._disposables.push(watcher);
    this._interval = setInterval(() => void this._update(), 4000);
    this._panel.webview.onDidReceiveMessage(
      (msg: { command: string }) => { if (msg.command === "refresh") void this._update(); },
      null, this._disposables
    );
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
  }

  private async _update(): Promise<void> {
    if (!this._initialized) return;
    let hud: HudStatus | null = null;
    try { hud = JSON.parse(fs.readFileSync(path.join(this.workspaceRoot, "agentboard.hud-status.json"), "utf8")) as HudStatus; } catch { /* ok */ }

    const [sRaw, wRaw] = await Promise.all([
      httpGet("http://127.0.0.1:7842/sessions", 300).catch(() => null),
      httpGet("http://127.0.0.1:7842/worktrees", 300).catch(() => null),
    ]);
    let sessions: unknown[] = []; let cpRunning = false;
    try { if (sRaw) { const p = JSON.parse(sRaw); cpRunning = true; sessions = Array.isArray(p) ? p : (p.sessions ?? []); } } catch { /* ok */ }
    let worktrees: string[] = [];
    try {
      if (wRaw) {
        const p = JSON.parse(wRaw);
        const raw: unknown[] = Array.isArray(p) ? p : (p.worktrees ?? []);
        worktrees = raw.map(w => typeof w === "string" ? w : String((w as Record<string, unknown>).branch ?? (w as Record<string, unknown>).path ?? "?").replace("refs/heads/", ""));
      }
    } catch { /* ok */ }
    if (!worktrees.length) worktrees = gitWorktrees(this.workspaceRoot);

    const branch = hud?.context?.branch ?? (() => { try { return execSync("git rev-parse --abbrev-ref HEAD", { cwd: this.workspaceRoot, timeout: 1000 }).toString().trim(); } catch { return ""; } })();
    const activeStream = readActiveStream(this.workspaceRoot);
    const streamRole = readStreamRole(this.workspaceRoot, activeStream);
    const hudRole = hud?.active_agents?.[0]?.role ?? "";
    const activeRole = (!hudRole || MODEL_NAMES.has(hudRole.toLowerCase().split("-")[0])) ? streamRole : hudRole;
    const ctxPct: number | null = hud?.context?.context_remaining_pct ?? null;
    const rawModel = hud?.context?.model ?? hud?.active_agents?.[0]?.model ?? "";
    const model = rawModel ? fmtModel(rawModel) : "";
    const cost = hud?.cost?.session_usd ? `$${(hud.cost.session_usd as number).toFixed(3)}` : "";
    const sessionTime = hud?.active_agents?.[0]?.started_at ? elapsedStr(hud.active_agents[0].started_at) : "";
    const hasLive = (hud?.active_agents?.length ?? 0) > 0;
    const lastSkill = readLastSkill(this.workspaceRoot);
    const skills = readSkills(this.workspaceRoot);
    const roles = readRoles(this.workspaceRoot);

    const agentCount = hasLive ? 1 : 0;
    void this._panel.webview.postMessage({
      type: "update",
      hasLive, model, cost, sessionTime, activeStream, activeRole, lastSkill,
      ctxPct, branch, cpRunning, sessions: sessions.length, agentCount,
      streams: readStreams(this.workspaceRoot),
      events: readRecentEvents(this.workspaceRoot),
      worktrees,
      skillCount: skills.length, roleCount: roles.length,
      skills, roles,
      commands: skills.map(s => ({ name: `/${s.name}`, description: s.description })),
      projectName: path.basename(this.workspaceRoot),
    });
  }

  private _getShell(): string {
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;height:100vh;display:flex;flex-direction:column;overflow:hidden}
/* header */
#hdr{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.logo{color:#4a9eff;font-weight:700;letter-spacing:.08em}.sep{opacity:.3}.proj{opacity:.7}.br{opacity:.45;font-size:12px}
.rbtn{margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:inherit;border-radius:4px;padding:3px 10px;cursor:pointer;font-size:12px}
.rbtn:hover{background:var(--vscode-list-hoverBackground)}
/* live bar */
#live-bar{display:none;align-items:center;gap:8px;padding:7px 16px;background:rgba(76,175,80,.06);border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0;flex-wrap:wrap}
#live-bar.on{display:flex}
.dot{width:7px;height:7px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite;flex-shrink:0}
.ll{font-weight:700;font-size:11px;letter-spacing:.1em;color:#4caf50}.lm{font-size:12px;opacity:.8}
.lpill{padding:2px 9px;border-radius:10px;font-size:10px;font-weight:600;white-space:nowrap}
.lstream{background:#4a9eff18;color:#4a9eff;border:1px solid #4a9eff44}
.lrole{background:#9c6af718;color:#9c6af7;border:1px solid #9c6af744}
.lskill{background:#4caf5018;color:#4caf84;border:1px solid #4caf5044}
/* tabs */
.tabs{display:flex;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0;padding:0 16px}
.tab{padding:6px 14px;font-size:12px;cursor:pointer;border:none;border-bottom:2px solid transparent;opacity:.5;transition:all .15s;background:none;color:inherit}
.tab.on{opacity:1;border-bottom-color:#4a9eff;color:#4a9eff}
.tab:hover{opacity:.85}
/* views */
.view{flex:1;overflow:hidden;display:none;flex-direction:column}
.view.on{display:flex}
/* live view */
#live-body{display:flex;gap:10px;padding:12px 16px;flex:1;min-height:0}
.lleft{flex:6;display:flex;flex-direction:column;gap:8px;overflow-y:auto}
.lright{flex:4;display:flex;flex-direction:column;gap:10px;overflow-y:auto}
/* catalog view */
#cat-body{display:flex;flex:1;overflow:hidden}
.cat-col{flex:1;display:flex;flex-direction:column;border-right:1px solid var(--vscode-panel-border);overflow:hidden}
.cat-col:last-child{border-right:none}
.cat-hdr{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.cdot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.ctitle{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.5;flex:1}
.ccount{font-size:24px;font-weight:700;line-height:1}
.cat-list{flex:1;overflow-y:auto;padding:4px 0}
.ci{padding:5px 14px;border-bottom:1px solid rgba(128,128,128,.08);cursor:default;transition:background .1s}
.ci:hover{background:var(--vscode-list-hoverBackground)}
.ci-name{display:block;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;font-weight:500}
.ci-desc{display:block;font-size:10px;opacity:.4;margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.more{padding:7px 14px;font-size:11px;opacity:.35;font-style:italic}
/* shared */
.ttl{font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.4;margin-bottom:6px}
.card{background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);border-radius:6px;padding:8px 12px}
.active-card{border-color:#4a9eff55;background:rgba(74,158,255,.04)}
.adot{display:inline-block;width:6px;height:6px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite}
.st{display:flex;align-items:center;gap:7px}
.si{color:#4a9eff}
@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}
.spin{display:inline-block;animation:spin 2s linear infinite}
.ss{font-weight:600;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px}
.badge{font-size:10px;padding:1px 7px;border-radius:10px;margin-left:auto;font-weight:600;white-space:nowrap}
.sa{margin-top:3px;font-size:11px;opacity:.55;padding-left:18px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sa.dim{opacity:.35}
/* activity */
.ev{display:flex;align-items:center;gap:6px;padding:3px 0;border-bottom:1px solid var(--vscode-panel-border);font-size:11px}
.ev:last-child{border-bottom:none}
.ev-i{flex-shrink:0;width:14px;text-align:center;opacity:.55;font-size:10px}
.ev-d{flex:1;font-family:var(--vscode-editor-font-family,'monospace');overflow:hidden;text-overflow:ellipsis;white-space:nowrap;opacity:.85}
.ev-s{font-size:10px;padding:1px 5px;border-radius:8px;background:#4a9eff12;color:#4a9eff;white-space:nowrap;flex-shrink:0}
.ev-t{font-size:10px;opacity:.35;white-space:nowrap;flex-shrink:0}
/* agent panel */
.agent-grid{display:grid;grid-template-columns:56px 1fr;gap:2px 10px;font-size:12px;line-height:1.9}
.ag-k{opacity:.4;font-size:11px}.ag-v{font-weight:600}
.ag-role{color:#9c6af7}.ag-stream{color:#4a9eff}.ag-skill{color:#4caf84}
/* worktrees/sessions */
.wt{padding:3px 0;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;opacity:.8}
.em{opacity:.4;font-size:12px;font-style:italic;line-height:1.9}code{font-family:var(--vscode-editor-font-family,'monospace');font-size:11px}
/* footer */
#footer{display:flex;flex-wrap:wrap;gap:6px;padding:7px 16px;border-top:1px solid var(--vscode-panel-border);flex-shrink:0;font-size:11px;align-items:center}
.fi{padding:2px 7px;border-radius:4px;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border)}
.fi-role{color:#9c6af7;border-color:#9c6af744}.fi-risk{color:#e8823a;border-color:#e8823a55}
.ctx{font-family:monospace;letter-spacing:-1px;font-size:11px}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(1.3)}}
</style></head><body>

<div id="hdr">
  <span class="logo">◆ AGENTBOARD</span><span class="sep">·</span>
  <span class="proj" id="h-proj">—</span><span class="sep" id="h-sep2" style="display:none">·</span><span class="br" id="h-br"></span>
  <button class="rbtn" onclick="vscode.postMessage({command:'refresh'})">↻ Refresh</button>
</div>

<div id="live-bar">
  <span class="dot"></span><span class="ll">LIVE</span>
  <span class="lm" id="lb-meta"></span>
  <span class="lpill lstream" id="lb-stream" style="display:none"></span>
  <span class="lpill lrole" id="lb-role" style="display:none"></span>
  <span class="lpill lskill" id="lb-skill" style="display:none"></span>
  <span style="margin-left:auto" id="lb-ctx"></span>
</div>

<div class="tabs">
  <button class="tab on" onclick="switchTab('live',this)">Live</button>
  <button class="tab" id="tab-catalog" onclick="switchTab('catalog',this)">Catalog</button>
</div>

<div id="live" class="view on">
  <div id="live-body">
    <div class="lleft">
      <div><div class="ttl" id="streams-ttl">Active Streams</div><div id="streams-list"></div></div>
      <div style="margin-top:4px"><div class="ttl">Recent Activity</div><div class="card" style="padding:5px 10px" id="events-list"></div></div>
    </div>
    <div class="lright">
      <div>
        <div class="ttl" id="agent-ttl">Agent</div>
        <div class="card"><div class="agent-grid" id="agent-grid">
          <span class="ag-k">Model</span><span class="ag-v" id="ag-model">—</span>
          <span class="ag-k">Role</span><span class="ag-v ag-role" id="ag-role">—</span>
          <span class="ag-k">Skill</span><span class="ag-v ag-skill" id="ag-skill">—</span>
          <span class="ag-k">Stream</span><span class="ag-v ag-stream" id="ag-stream">—</span>
          <span class="ag-k">Cost</span><span class="ag-v" id="ag-cost">—</span>
          <span class="ag-k">Session</span><span class="ag-v" id="ag-session">—</span>
        </div></div>
      </div>
      <div><div class="ttl" id="wt-ttl">Worktrees</div><div id="wt-list"></div></div>
      <div><div class="ttl">Sessions</div><div id="sess-block"></div></div>
    </div>
  </div>
</div>

<div id="catalog" class="view">
  <div id="cat-body">
    <div class="cat-col" id="col-skills">
      <div class="cat-hdr"><span class="cdot" style="background:#4a9eff"></span><span class="ctitle">Skills</span><span class="ccount" style="color:#4a9eff" id="cnt-skills">0</span></div>
      <div class="cat-list" id="list-skills"></div>
    </div>
    <div class="cat-col" id="col-roles">
      <div class="cat-hdr"><span class="cdot" style="background:#9c6af7"></span><span class="ctitle">Roles</span><span class="ccount" style="color:#9c6af7" id="cnt-roles">0</span></div>
      <div class="cat-list" id="list-roles"></div>
    </div>
    <div class="cat-col" id="col-cmds">
      <div class="cat-hdr"><span class="cdot" style="background:#4caf84"></span><span class="ctitle">Commands</span><span class="ccount" style="color:#4caf84" id="cnt-cmds">0</span></div>
      <div class="cat-list" id="list-cmds"></div>
    </div>
  </div>
</div>

<div id="footer"></div>

<script>
const vscode = acquireVsCodeApi();
const TYPE_COLOR = {bugfix:'#e8823a',feature:'#4caf84',task:'#4a9eff',maintenance:'#888'};
const TOOL_ICON = {Edit:'✏',Write:'✏',Bash:'$',Read:'👁',WebSearch:'⌕',WebFetch:'⌕',Agent:'◈',Skill:'⚡'};

function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function show(id,v){ const el=document.getElementById(id); if(el){ el.style.display=v?'':'none'; if(v) el.textContent=v; } }
function html(id,h){ const el=document.getElementById(id); if(el) el.innerHTML=h; }
function txt(id,t){ const el=document.getElementById(id); if(el) el.textContent=t; }
function cls(id,c,on){ const el=document.getElementById(id); if(el) el.classList.toggle(c,on); }

function switchTab(id,btn){
  document.querySelectorAll('.view').forEach(v=>v.classList.remove('on'));
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));
  document.getElementById(id).classList.add('on');
  btn.classList.add('on');
}

function ctxBar(pct){
  if(pct===null||pct===undefined) return '';
  const used=Math.round(100-pct);
  const fill=Math.floor(used/10);
  const c=used<50?'#4caf50':used<75?'#ff9800':'#f44336';
  return '<span class="ctx" style="color:'+c+'">'+'█'.repeat(fill)+'░'.repeat(10-fill)+'</span><span style="color:'+c+';font-size:11px"> '+used+'%</span>';
}

function badge(t){
  const c=TYPE_COLOR[t.toLowerCase()]||'#888';
  return '<span class="badge" style="background:'+c+'22;color:'+c+';border:1px solid '+c+'55">'+esc(t)+'</span>';
}

function renderCatalogCol(listId, items){
  const MAX=100;
  let h=items.slice(0,MAX).map(function(item){
    return '<div class="ci"><span class="ci-name">'+esc(item.name)+'</span>'+(item.description?'<span class="ci-desc">'+esc(item.description.slice(0,80))+'</span>':'')+'</div>';
  }).join('');
  if(items.length>MAX) h+='<div class="more">+ '+(items.length-MAX)+' more</div>';
  html(listId,h);
}

window.addEventListener('message', function(e){
  const d=e.data;
  if(d.type!=='update') return;

  // header
  txt('h-proj', d.projectName||'—');
  const br=document.getElementById('h-br');
  const sep=document.getElementById('h-sep2');
  if(br&&sep){ br.textContent=d.branch||''; sep.style.display=d.branch?'':'none'; }

  // live bar
  const lb=document.getElementById('live-bar');
  if(lb) lb.className=d.hasLive?'on':'';
  txt('lb-meta',[d.model,d.cost,d.sessionTime].filter(Boolean).join(' · '));
  const lbStream=document.getElementById('lb-stream');
  if(lbStream){ lbStream.textContent=d.activeStream||''; lbStream.style.display=d.activeStream?'':'none'; }
  const lbRole=document.getElementById('lb-role');
  if(lbRole){ lbRole.textContent='◈ '+(d.activeRole||''); lbRole.style.display=d.activeRole?'':'none'; }
  const lbSkill=document.getElementById('lb-skill');
  if(lbSkill){ lbSkill.textContent='/'+d.lastSkill; lbSkill.style.display=d.lastSkill?'':'none'; }
  const lbCtx=document.getElementById('lb-ctx');
  if(lbCtx) lbCtx.innerHTML=ctxBar(d.ctxPct);

  // tab catalog label
  const tc=document.getElementById('tab-catalog');
  if(tc) tc.textContent='Catalog · '+(d.skillCount+d.roleCount);

  // streams
  txt('streams-ttl','Active Streams ('+d.streams.length+')');
  html('streams-list', d.streams.length ? d.streams.map(function(s){
    const isActive=s.slug===d.activeStream;
    return '<div class="card'+(isActive?' active-card':'')+'" style="margin-bottom:6px">'
      +'<div class="st"><span class="si'+(isActive?' spin':'')+'">↻</span>'
      +'<span class="ss">'+esc(s.slug)+'</span>'
      +(isActive?'<span class="adot" style="margin-left:2px"></span>':'')
      +badge(s.type)+'</div>'
      +(s.role?'<div class="sa dim">◈ '+esc(s.role)+'</div>':'')
      +(s.next_action?'<div class="sa">→ '+esc(s.next_action)+'</div>':'')
      +'</div>';
  }).join('') : '<div class="em">No active streams</div>');

  // activity
  html('events-list', d.events.length ? d.events.map(function(ev){
    const icon=TOOL_ICON[ev.tool]||'·';
    const isSkill=ev.tool==='Skill';
    const detail=isSkill?('/'+ev.skill):(ev.file?ev.file.split('/').pop():(ev.cmd?ev.cmd.slice(0,55):ev.tool));
    const color=isSkill?'color:#4caf84;font-weight:600':'';
    return '<div class="ev">'
      +'<span class="ev-i" style="'+(isSkill?'color:#4caf84':'')+'">'+icon+'</span>'
      +'<span class="ev-d" style="'+color+'">'+esc(detail)+'</span>'
      +(ev.stream&&!isSkill?'<span class="ev-s">'+esc(ev.stream)+'</span>':'')
      +'<span class="ev-t">'+relTime(ev.ts)+'</span>'
      +'</div>';
  }).join('') : '<div class="em">No activity yet — hooks write here on each tool call</div>');

  // agent panel
  txt('agent-ttl', d.agentCount ? 'Agent ('+d.agentCount+' active)' : 'Agent');
  txt('ag-model', d.model||'—');
  txt('ag-role', d.activeRole||'—');
  txt('ag-skill', d.lastSkill?'/'+d.lastSkill:'—');
  txt('ag-stream', d.activeStream||'—');
  txt('ag-cost', d.cost||'—');
  txt('ag-session', d.sessionTime||'—');

  // worktrees
  txt('wt-ttl','Worktrees ('+d.worktrees.length+')');
  html('wt-list', d.worktrees.map(function(w){ return '<div class="wt">⎇ '+esc(w)+'</div>'; }).join('')||'<div class="em">None</div>');

  // sessions
  html('sess-block', !d.cpRunning
    ? '<div class="em">Control plane not running<br><code>$ ab start</code></div>'
    : d.sessions>0
      ? '<div style="color:#4caf50;font-size:12px">● '+d.sessions+' active session'+(d.sessions>1?'s':'')+'</div>'
      : '<div class="em" style="color:#4caf84">● CP running — no sessions</div>');

  // catalog
  document.getElementById('cnt-skills').textContent=String(d.skillCount);
  document.getElementById('cnt-roles').textContent=String(d.roleCount);
  document.getElementById('cnt-cmds').textContent=String(d.commands.length);
  renderCatalogCol('list-skills', d.skills);
  renderCatalogCol('list-roles', d.roles);
  renderCatalogCol('list-cmds', d.commands);

  // footer
  const fp=[];
  if(d.model) fp.push('<span class="fi">⬡ '+esc(d.model)+'</span>');
  if(d.activeRole) fp.push('<span class="fi fi-role">◈ '+esc(d.activeRole)+'</span>');
  if(d.lastSkill) fp.push('<span class="fi" style="color:#4caf84">/'+esc(d.lastSkill)+'</span>');
  if(d.branch) fp.push('<span class="fi">⎇ '+esc(d.branch)+'</span>');
  if(d.cost) fp.push('<span class="fi">'+esc(d.cost)+'</span>');
  fp.push('<span style="margin-left:auto;opacity:.3;font-size:11px">'+d.skillCount+' skills · '+d.roleCount+' roles · '+d.streams.length+' streams</span>');
  html('footer', fp.join(''));
});

function relTime(iso){
  const s=Math.floor((Date.now()-new Date(iso).getTime())/1000);
  if(s<60) return s+'s ago';
  if(s<3600) return Math.floor(s/60)+'m ago';
  return Math.floor(s/3600)+'h ago';
}
</script>
</body></html>`;
  }

  dispose(): void {
    if (this._interval) clearInterval(this._interval);
    DashboardPanel.currentPanel = undefined;
    this._panel.dispose();
    for (const d of this._disposables) d.dispose();
    this._disposables = [];
  }
}
