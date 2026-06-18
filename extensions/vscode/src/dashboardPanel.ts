import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import { execSync } from "child_process";
import { HudStatus } from "./hudTypes";

interface StreamEntry { slug: string; status: string; type: string; next_action: string; role: string; }
interface ActivityEvent { ts: string; tool: string; stream: string; file?: string; cmd?: string; }
interface CatalogItem { name: string; description: string; }
interface DashData {
  hud: HudStatus | null; streams: StreamEntry[]; worktrees: string[];
  projectName: string; branch: string; cpRunning: boolean;
  activeStream: string; activeRole: string; recentEvents: ActivityEvent[];
  ctxPct: number | null; sessions: unknown[];
  skills: CatalogItem[]; roles: CatalogItem[]; commands: CatalogItem[];
}

function httpGet(url: string, ms: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let d = ""; res.on("data", (c: Buffer) => { d += c.toString(); }); res.on("end", () => resolve(d));
    });
    req.setTimeout(ms, () => { req.destroy(); reject(new Error("timeout")); });
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
  let files: string[] = [];
  try { files = fs.readdirSync(dir).filter((f) => f.endsWith(".md") && !skip.has(f)); } catch { return []; }
  return files.flatMap((f) => {
    try {
      const c = fs.readFileSync(path.join(dir, f), "utf8");
      const fm = parseFrontmatter(c);
      const st = (fm.status ?? "").toLowerCase();
      if (["done", "archived", "closed"].includes(st)) return [];
      const na = fm.next_action ?? (c.match(/##\s*Next\s+action\s*\n([^\n]+)/i)?.[1]?.trim() ?? "");
      return [{ slug: fm.slug ?? path.basename(f, ".md"), status: fm.status ?? "active", type: fm.type ?? "task", next_action: na, role: fm.role ?? "" }];
    } catch { return []; }
  });
}

function readSkills(root: string): CatalogItem[] {
  const dir = path.join(root, ".claude", "skills");
  try {
    return fs.readdirSync(dir).flatMap(name => {
      const skillFile = path.join(dir, name, "SKILL.md");
      try {
        const fm = parseFrontmatter(fs.readFileSync(skillFile, "utf8"));
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
    const m = brief.match(/\*\*Stream file:\*\*\s*`work\/([^`]+)\.md`/);
    return m?.[1] ?? "";
  } catch { return ""; }
}

function readStreamRole(root: string, slug: string): string {
  if (!slug) return "";
  try { return parseFrontmatter(fs.readFileSync(path.join(root, ".platform", "work", `${slug}.md`), "utf8")).role ?? ""; } catch { return ""; }
}

function readRecentEvents(root: string, n = 15): ActivityEvent[] {
  try {
    return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
      .trim().split("\n").filter(Boolean).slice(-n).reverse()
      .map(line => { try { return JSON.parse(line) as ActivityEvent; } catch { return null; } })
      .filter((e): e is ActivityEvent => e !== null);
  } catch { return []; }
}

function gitWorktrees(root: string): string[] {
  try {
    return execSync("git worktree list --porcelain", { cwd: root, timeout: 2000 }).toString()
      .split("\n\n").filter(Boolean)
      .map(b => b.split("\n").find(l => l.startsWith("branch "))?.replace("branch refs/heads/", "") ?? "main");
  } catch { return []; }
}

function elapsed(s?: string): string {
  if (!s) return "";
  const d = Math.floor((Date.now() - new Date(s).getTime()) / 1000);
  return `${Math.floor(d / 60)}m ${d % 60}s`;
}
function relTime(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

export class DashboardPanel {
  static currentPanel: DashboardPanel | undefined;
  private readonly _panel: vscode.WebviewPanel;
  private _disposables: vscode.Disposable[] = [];
  private _interval: NodeJS.Timeout | undefined;

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
    void this._update();
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(workspaceRoot, "{agentboard.hud-status.json,.platform/events.jsonl}")
    );
    watcher.onDidChange(() => void this._update(), null, this._disposables);
    watcher.onDidCreate(() => void this._update(), null, this._disposables);
    this._disposables.push(watcher);
    this._interval = setInterval(() => void this._update(), 3000);
    this._panel.webview.onDidReceiveMessage(
      (msg: { command: string }) => { if (msg.command === "refresh") void this._update(); },
      null, this._disposables
    );
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
  }

  private async _update(): Promise<void> {
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
        worktrees = raw.map(w => typeof w === "string" ? w : String((w as Record<string,unknown>).branch ?? (w as Record<string,unknown>).path ?? "?").replace("refs/heads/", ""));
      }
    } catch { /* ok */ }
    if (!worktrees.length) worktrees = gitWorktrees(this.workspaceRoot);

    const branch = hud?.context?.branch ?? (() => { try { return execSync("git rev-parse --abbrev-ref HEAD", { cwd: this.workspaceRoot, timeout: 1000 }).toString().trim(); } catch { return ""; } })();
    const activeStream = readActiveStream(this.workspaceRoot);
    const streamRole = readStreamRole(this.workspaceRoot, activeStream);
    const modelNames = new Set(["claude", "sonnet", "opus", "haiku", "fable", "gpt", "gemini", "codex"]);
    const hudRole = hud?.active_agents?.[0]?.role ?? "";
    const activeRole = (!hudRole || modelNames.has(hudRole.toLowerCase().split("-")[0])) ? streamRole : hudRole;
    const ctxPct: number | null = hud?.context?.context_remaining_pct ?? null;

    this._panel.webview.html = this._getHtml({
      hud, streams: readStreams(this.workspaceRoot),
      worktrees, projectName: path.basename(this.workspaceRoot), branch, cpRunning,
      activeStream, activeRole, recentEvents: readRecentEvents(this.workspaceRoot),
      ctxPct, sessions,
      skills: readSkills(this.workspaceRoot),
      roles: readRoles(this.workspaceRoot),
      commands: readSkills(this.workspaceRoot).map(s => ({ name: `/${s.name}`, description: s.description })),
    });
  }

  private _getHtml(d: DashData): string {
    const { hud, streams, worktrees, projectName, branch, cpRunning, activeStream, activeRole, recentEvents, ctxPct, sessions, skills, roles, commands } = d;
    const agents = hud?.active_agents ?? [];
    const hasLive = agents.length > 0;
    const model = hud?.context?.model?.replace("claude-", "").replace(/-\d{8}$/, "") ?? "";
    const modelDisplay = model ? model.split("-").map(w => w[0].toUpperCase() + w.slice(1)).join(" ") : "Claude";
    const cost = hud?.cost?.session_usd ? `$${(hud.cost.session_usd as number).toFixed(3)}` : "";
    const time = agents[0] ? elapsed(agents[0].started_at) : "";
    const ctxBar = ctxPct !== null ? (() => {
      const used = Math.round(100 - ctxPct);
      const fill = Math.floor(used / 10);
      const color = used < 50 ? "#4caf50" : used < 75 ? "#ff9800" : "#f44336";
      return `<span style="font-family:monospace;letter-spacing:-1px;color:${color}">${"█".repeat(fill)}${"░".repeat(10 - fill)}</span><span style="color:${color};font-size:11px"> ${used}%</span>`;
    })() : "";

    const typeColor: Record<string, string> = { bugfix: "#e8823a", feature: "#4caf84", task: "#4a9eff", maintenance: "#888" };
    const badge = (t: string) => { const c = typeColor[t.toLowerCase()] ?? "#888"; return `<span class="badge" style="background:${c}22;color:${c};border:1px solid ${c}55">${t}</span>`; };
    const toolIcon: Record<string, string> = { Edit: "✏", Write: "✏", Bash: "$", Read: "👁", WebSearch: "⌕", WebFetch: "⌕", Agent: "◈" };

    const streamCards = streams.map(s => {
      const isActive = s.slug === activeStream;
      return `<div class="card${isActive ? " active-card" : ""}">
        <div class="st"><span class="si${isActive ? " spin" : ""}">↻</span><span class="ss">${s.slug}</span>${isActive ? `<span class="adot"></span>` : ""}${badge(s.type)}</div>
        ${s.role ? `<div class="sa dim">◈ ${s.role}</div>` : ""}
        ${s.next_action ? `<div class="sa">→ ${s.next_action}</div>` : ""}
      </div>`;
    }).join("") || `<div class="em">No active streams</div>`;

    const actRows = recentEvents.map(e => {
      const icon = toolIcon[e.tool] ?? "·";
      const detail = e.file ? path.basename(e.file) : e.cmd ? e.cmd.slice(0, 50) : e.tool;
      return `<div class="ev"><span class="ev-i">${icon}</span><span class="ev-d">${detail}</span>${e.stream ? `<span class="ev-s">${e.stream}</span>` : ""}<span class="ev-t">${relTime(e.ts)}</span></div>`;
    }).join("") || `<div class="em">No activity yet</div>`;

    const catCol = (title: string, count: number, items: CatalogItem[], accent: string) => `
      <div class="cat-col">
        <div class="cat-hdr"><span class="cat-dot" style="background:${accent}"></span><span class="cat-title">${title}</span><span class="cat-count" style="color:${accent}">${count}</span></div>
        <div class="cat-list">
          ${items.slice(0, 50).map((item, i) => `
            <div class="cat-item${i === 0 ? " cat-first" : ""}">
              <span class="cat-name">${item.name}</span>
              ${item.description ? `<span class="cat-desc">${item.description.slice(0, 60)}${item.description.length > 60 ? "…" : ""}</span>` : ""}
            </div>`).join("")}
          ${items.length > 50 ? `<div class="cat-more">+ ${items.length - 50} more</div>` : ""}
        </div>
      </div>`;

    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;height:100vh;display:flex;flex-direction:column;overflow:hidden}
.hdr{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.logo{color:#4a9eff;font-weight:700;letter-spacing:.08em}.sep{opacity:.3}.proj{opacity:.7}.br{opacity:.45;font-size:12px}
.rbtn{margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:var(--vscode-editor-foreground);border-radius:4px;padding:3px 10px;cursor:pointer;font-size:12px}
.rbtn:hover{background:var(--vscode-list-hoverBackground)}
.live{display:flex;align-items:center;gap:8px;padding:7px 16px;background:rgba(76,175,80,.06);border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.dot{width:7px;height:7px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite;flex-shrink:0}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(1.3)}}
@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}
.ll{font-weight:700;font-size:11px;letter-spacing:.1em;color:#4caf50}.lm{font-size:12px;opacity:.8}
.lpill{padding:1px 8px;border-radius:10px;font-size:10px;font-weight:600}
.lstream{background:#4a9eff18;color:#4a9eff;border:1px solid #4a9eff44}
.lrole{background:#9c6af718;color:#9c6af7;border:1px solid #9c6af744}
.tabs{display:flex;gap:0;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0;padding:0 16px}
.tab{padding:6px 14px;font-size:12px;cursor:pointer;border-bottom:2px solid transparent;opacity:.55;transition:all .15s;background:none;border-top:none;border-left:none;border-right:none;color:var(--vscode-editor-foreground)}
.tab.active{opacity:1;border-bottom-color:#4a9eff;color:#4a9eff}
.tab:hover{opacity:.85}
.view{flex:1;overflow:hidden;display:none;flex-direction:column}
.view.active{display:flex}
/* LIVE VIEW */
.live-body{display:flex;gap:10px;padding:12px 16px;flex:1;min-height:0}
.live-left{flex:6;display:flex;flex-direction:column;gap:8px;overflow-y:auto}
.live-right{flex:4;display:flex;flex-direction:column;gap:10px;overflow-y:auto}
.ttl{font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.45;margin-bottom:6px}
.card{background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);border-radius:6px;padding:8px 12px}
.active-card{border-color:#4a9eff55;background:rgba(74,158,255,.04)}
.adot{width:6px;height:6px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite}
.st{display:flex;align-items:center;gap:7px}.si{color:#4a9eff}.spin{display:inline-block;animation:spin 2s linear infinite}
.ss{font-weight:600;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px}
.badge{font-size:10px;padding:1px 7px;border-radius:10px;margin-left:auto;font-weight:600;white-space:nowrap}
.sa{margin-top:3px;font-size:11px;opacity:.6;padding-left:18px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dim{opacity:.4}
.ev{display:flex;align-items:center;gap:6px;padding:3px 0;border-bottom:1px solid var(--vscode-panel-border);font-size:11px}
.ev:last-child{border-bottom:none}
.ev-i{flex-shrink:0;width:14px;text-align:center;opacity:.6;font-size:10px}
.ev-d{flex:1;font-family:var(--vscode-editor-font-family,'monospace');overflow:hidden;text-overflow:ellipsis;white-space:nowrap;opacity:.85}
.ev-s{font-size:10px;padding:1px 5px;border-radius:8px;background:#4a9eff12;color:#4a9eff;white-space:nowrap;flex-shrink:0}
.ev-t{font-size:10px;opacity:.4;white-space:nowrap;flex-shrink:0}
.wt{padding:3px 0;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;opacity:.8}
.em{opacity:.4;font-size:12px;font-style:italic;line-height:1.8}
code{font-family:var(--vscode-editor-font-family,'monospace');font-size:11px}
/* CATALOG VIEW */
.cat-body{display:flex;gap:0;flex:1;overflow:hidden}
.cat-col{flex:1;display:flex;flex-direction:column;border-right:1px solid var(--vscode-panel-border);overflow:hidden}
.cat-col:last-child{border-right:none}
.cat-hdr{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.cat-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}
.cat-title{font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;opacity:.6;flex:1}
.cat-count{font-size:22px;font-weight:700;line-height:1}
.cat-list{flex:1;overflow-y:auto;padding:4px 0}
.cat-item{padding:6px 14px;border-bottom:1px solid rgba(255,255,255,.04);cursor:default}
.cat-item:hover{background:var(--vscode-list-hoverBackground)}
.cat-first{border-top:1px solid rgba(255,255,255,.06)}
.cat-name{display:block;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;font-weight:500}
.cat-desc{display:block;font-size:10px;opacity:.45;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cat-more{padding:8px 14px;font-size:11px;opacity:.4;font-style:italic}
/* FOOTER */
.footer{display:flex;flex-wrap:wrap;gap:6px;padding:7px 16px;border-top:1px solid var(--vscode-panel-border);flex-shrink:0;font-size:11px}
.fi{padding:2px 7px;border-radius:4px;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border)}
.fi-role{color:#9c6af7;border-color:#9c6af744}.risk{color:#e8823a;border-color:#e8823a55}
</style></head><body>

<div class="hdr">
  <span class="logo">◆ AGENTBOARD</span><span class="sep">·</span><span class="proj">${projectName}</span>${branch ? `<span class="sep">·</span><span class="br">${branch}</span>` : ""}
  <button class="rbtn" onclick="vscode.postMessage({command:'refresh'})">↻ Refresh</button>
</div>

${hasLive ? `<div class="live">
  <span class="dot"></span><span class="ll">LIVE</span>
  <span class="lm">${[modelDisplay, cost, time].filter(Boolean).join(" · ")}</span>
  ${activeStream ? `<span class="lpill lstream">${activeStream}</span>` : ""}
  ${activeRole ? `<span class="lpill lrole">◈ ${activeRole}</span>` : ""}
  <span style="margin-left:auto;font-size:11px;display:flex;align-items:center;gap:6px">${ctxBar}</span>
</div>` : ""}

<div class="tabs">
  <button class="tab active" onclick="switchTab('live',this)">Live</button>
  <button class="tab" onclick="switchTab('catalog',this)">Catalog · ${skills.length + roles.length}</button>
</div>

<!-- LIVE TAB -->
<div id="live" class="view active">
  <div class="live-body">
    <div class="live-left">
      <div><div class="ttl">Active Streams (${streams.length})</div>${streamCards}</div>
      <div><div class="ttl">Recent Activity</div><div class="card" style="padding:5px 10px">${actRows}</div></div>
    </div>
    <div class="live-right">
      <div>
        <div class="ttl">Agent</div>
        <div class="card">
          <div style="font-size:12px;line-height:2;display:grid;grid-template-columns:auto 1fr;gap:0 12px">
            <span style="opacity:.45">Model</span><span style="font-weight:600">${modelDisplay || "—"}</span>
            <span style="opacity:.45">Role</span><span style="font-weight:600;color:#9c6af7">${activeRole || "—"}</span>
            <span style="opacity:.45">Stream</span><span style="font-weight:600;color:#4a9eff">${activeStream || "—"}</span>
            <span style="opacity:.45">Cost</span><span style="font-weight:600">${cost || "—"}</span>
            <span style="opacity:.45">Session</span><span style="font-weight:600">${time || "—"}</span>
          </div>
        </div>
      </div>
      <div>
        <div class="ttl">Worktrees (${worktrees.length})</div>
        ${worktrees.map(w => `<div class="wt">⎇ ${w}</div>`).join("") || `<div class="em">None</div>`}
      </div>
      <div>
        <div class="ttl">Sessions</div>
        ${!cpRunning
          ? `<div class="em">Control plane not running<br><code>$ ab start</code></div>`
          : sessions.length
            ? `<div style="color:#4caf50;font-size:12px">● ${sessions.length} active</div>`
            : `<div class="em" style="color:#4caf84">● CP running — no sessions</div>`}
      </div>
    </div>
  </div>
</div>

<!-- CATALOG TAB -->
<div id="catalog" class="view">
  <div class="cat-body">
    ${catCol("Skills", skills.length, skills, "#4a9eff")}
    ${catCol("Roles", roles.length, roles, "#9c6af7")}
    ${catCol("Commands", commands.length, commands, "#4caf84")}
  </div>
</div>

<div class="footer">
  ${modelDisplay ? `<span class="fi">⬡ ${modelDisplay}</span>` : ""}
  ${activeRole ? `<span class="fi fi-role">◈ ${activeRole}</span>` : ""}
  ${branch ? `<span class="fi">⎇ ${branch}</span>` : ""}
  ${cost ? `<span class="fi">${cost}</span>` : ""}
  ${hud?.risk?.dirty_worktree ? `<span class="fi risk">⚠ dirty</span>` : ""}
  <span style="margin-left:auto;opacity:.35;font-size:11px">${skills.length} skills · ${roles.length} roles · ${streams.length} streams</span>
</div>

<script>
const vscode = acquireVsCodeApi();
function switchTab(id, btn) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  btn.classList.add('active');
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

function catCol(title: string, count: number, items: CatalogItem[], accent: string): string {
  return `<div class="cat-col">
    <div class="cat-hdr"><span class="cat-dot" style="background:${accent}"></span><span class="cat-title">${title}</span><span class="cat-count" style="color:${accent}">${count}</span></div>
    <div class="cat-list">
      ${items.slice(0, 100).map((item, i) => `
        <div class="cat-item${i === 0 ? " cat-first" : ""}">
          <span class="cat-name">${item.name}</span>
          ${item.description ? `<span class="cat-desc">${item.description.slice(0, 70)}${item.description.length > 70 ? "…" : ""}</span>` : ""}
        </div>`).join("")}
      ${items.length > 100 ? `<div class="cat-more">+ ${items.length - 100} more</div>` : ""}
    </div>
  </div>`;
}
