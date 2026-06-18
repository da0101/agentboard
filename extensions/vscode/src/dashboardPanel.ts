import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import { execSync } from "child_process";
import { HudStatus } from "./hudTypes";

interface StreamEntry { slug: string; status: string; type: string; next_action: string; role: string; }
interface ActivityEvent { ts: string; tool: string; stream: string; file?: string; cmd?: string; }
interface DashData {
  hud: HudStatus | null; streams: StreamEntry[]; skillCount: number;
  roleCount: number; sessions: unknown[]; worktrees: string[];
  projectName: string; branch: string; cpRunning: boolean;
  activeStream: string; activeRole: string; recentEvents: ActivityEvent[];
  ctxPct: number | null;
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
    r[line.slice(0, i).trim()] = line.slice(i + 1).trim();
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

function readActiveStream(root: string): string {
  try {
    const brief = fs.readFileSync(path.join(root, ".platform", "work", "BRIEF.md"), "utf8");
    const m = brief.match(/\*\*Stream file:\*\*\s*`work\/([^`]+)\.md`/);
    return m?.[1] ?? "";
  } catch { return ""; }
}

function readStreamRole(root: string, slug: string): string {
  if (!slug) return "";
  try {
    const c = fs.readFileSync(path.join(root, ".platform", "work", `${slug}.md`), "utf8");
    return parseFrontmatter(c).role ?? "";
  } catch { return ""; }
}

function readRecentEvents(root: string, n = 12): ActivityEvent[] {
  try {
    const content = fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8");
    return content.trim().split("\n").filter(Boolean).slice(-n).reverse()
      .map(line => { try { return JSON.parse(line) as ActivityEvent; } catch { return null; } })
      .filter((e): e is ActivityEvent => e !== null);
  } catch { return []; }
}

function countDirs(p: string): number {
  try { return fs.readdirSync(p).filter((f) => { try { return fs.statSync(path.join(p, f)).isDirectory(); } catch { return false; } }).length; } catch { return 0; }
}
function countMd(p: string, excl: string[]): number {
  try { return fs.readdirSync(p).filter((f) => f.endsWith(".md") && !excl.includes(f)).length; } catch { return 0; }
}
function gitWorktrees(root: string): string[] {
  try {
    return execSync("git worktree list --porcelain", { cwd: root, timeout: 2000 }).toString()
      .split("\n\n").filter(Boolean)
      .map((b) => b.split("\n").find((l) => l.startsWith("branch "))?.replace("branch refs/heads/", "") ?? "main");
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
    const hudFile = path.join(workspaceRoot, "agentboard.hud-status.json");
    const eventsFile = path.join(workspaceRoot, ".platform", "events.jsonl");
    const watcher = vscode.workspace.createFileSystemWatcher(`{${hudFile},${eventsFile}}`);
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
    try { if (wRaw) { const p = JSON.parse(wRaw); worktrees = Array.isArray(p) ? p : (p.worktrees ?? []); } } catch { /* ok */ }
    if (!worktrees.length) worktrees = gitWorktrees(this.workspaceRoot);
    const branch = hud?.context?.branch ?? (() => { try { return execSync("git rev-parse --abbrev-ref HEAD", { cwd: this.workspaceRoot, timeout: 1000 }).toString().trim(); } catch { return ""; } })();
    const activeStream = readActiveStream(this.workspaceRoot);
    const recentEvents = readRecentEvents(this.workspaceRoot);
    const streamRole = readStreamRole(this.workspaceRoot, activeStream);
    const activeRole = hud?.active_agents?.[0]?.role ?? streamRole ?? "";
    const ctxPct: number | null = hud?.context?.context_remaining_pct ?? null;
    this._panel.webview.html = this._getHtml({
      hud, streams: readStreams(this.workspaceRoot),
      skillCount: countDirs(path.join(this.workspaceRoot, ".claude", "skills")),
      roleCount: countMd(path.join(this.workspaceRoot, ".platform", "roles"), ["INDEX.md"]),
      sessions, worktrees, projectName: path.basename(this.workspaceRoot), branch, cpRunning,
      activeStream, activeRole, recentEvents, ctxPct,
    });
  }

  private _getHtml(d: DashData): string {
    const { hud, streams, skillCount, roleCount, sessions, worktrees, projectName, branch, cpRunning, activeStream, activeRole, recentEvents, ctxPct } = d;
    const agents = hud?.active_agents ?? [];
    const hasLive = agents.length > 0 || sessions.length > 0;
    const model = hud?.context?.model ?? "claude";
    const tokens = hud?.cost?.session_tokens ? `${(hud.cost.session_tokens / 1000).toFixed(1)}k ctx` : "";
    const cost = hud?.cost?.session_usd ? `$${(hud.cost.session_usd as number).toFixed(3)}` : "";
    const time = agents[0] ? elapsed(agents[0].started_at) : "";

    // context bar
    const ctxBar = ctxPct !== null ? (() => {
      const used = Math.round(100 - ctxPct);
      const fill = Math.floor(used / 10);
      const color = used < 50 ? "#4caf50" : used < 75 ? "#ff9800" : "#f44336";
      return `<span class="ctx-bar" style="color:${color}">${"█".repeat(fill)}${"░".repeat(10 - fill)}</span><span style="color:${color};font-size:11px"> ${used}%</span>`;
    })() : "";

    const liveMeta = [model, cost, time, tokens].filter(Boolean).join(" · ");
    const typeColor: Record<string, string> = { bugfix: "#e8823a", feature: "#4caf84", task: "#4a9eff", maintenance: "#888" };
    const badge = (t: string) => { const c = typeColor[t.toLowerCase()] ?? "#888"; return `<span class="badge" style="background:${c}22;color:${c};border:1px solid ${c}55">${t}</span>`; };

    const streamCards = streams.length ? streams.map((s) => {
      const isActive = s.slug === activeStream;
      return `<div class="card${isActive ? " active-card" : ""}"><div class="st"><span class="si${isActive ? " spin" : ""}">↻</span><span class="ss">${s.slug}</span>${isActive ? `<span class="active-dot"></span>` : ""}${badge(s.type)}</div>${s.role ? `<div class="sa" style="opacity:.5">◈ ${s.role}</div>` : ""}${s.next_action ? `<div class="sa">→ ${s.next_action}</div>` : ""}</div>`;
    }).join("") : `<div class="em">No active streams</div>`;

    const toolIcon: Record<string, string> = { Edit: "✏", Write: "✏", Bash: "$", Read: "📖", WebSearch: "🔍", WebFetch: "🌐", Agent: "🤖" };
    const activityLines = recentEvents.length
      ? recentEvents.map(e => {
          const icon = toolIcon[e.tool] ?? "·";
          const detail = e.file ? path.basename(e.file) : e.cmd ? e.cmd.slice(0, 40) : e.tool;
          const stream = e.stream ? `<span class="ev-stream">${e.stream}</span>` : "";
          return `<div class="ev"><span class="ev-icon">${icon}</span><span class="ev-detail">${detail}</span>${stream}<span class="ev-time">${relTime(e.ts)}</span></div>`;
        }).join("")
      : `<div class="em">No activity yet — hooks fire on next tool call</div>`;

    const wtLines = worktrees.length ? worktrees.map((w) => `<div class="wr">⎇ ${w}</div>`).join("") : `<div class="em">No worktrees</div>`;
    const sessionBlock = !cpRunning
      ? `<div class="em">Control plane not running<br><code>$ ab start</code></div>`
      : sessions.length
        ? `<div style="color:#4caf50">● ${sessions.length} active session${sessions.length > 1 ? "s" : ""}</div>`
        : `<div class="em" style="color:#4caf84">● Control plane running</div><div class="em">No sessions yet</div>`;
    const hudFooter = `<div class="footer">${[
      model && `<span class="fi">⬡ ${model}</span>`,
      activeRole && `<span class="fi role-fi">◈ ${activeRole}</span>`,
      branch && `<span class="fi">⎇ ${branch}</span>`,
      cost && `<span class="fi">${cost}</span>`,
      ctxBar && `<span class="fi ctx-fi">${ctxBar}</span>`,
      hud?.risk?.dirty_worktree && `<span class="fi risk">⚠ dirty</span>`,
    ].filter(Boolean).join("")}</div>`;

    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;height:100vh;display:flex;flex-direction:column;overflow:hidden}
.hdr{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.logo{color:#4a9eff;font-weight:700;letter-spacing:.08em}.sep{opacity:.4}.proj{opacity:.7}.br{opacity:.5;font-size:12px}
.rbtn{margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:var(--vscode-editor-foreground);border-radius:4px;padding:3px 10px;cursor:pointer;font-size:12px}
.rbtn:hover{background:var(--vscode-list-hoverBackground)}
.live{display:flex;align-items:center;gap:8px;padding:8px 16px;background:rgba(76,175,80,.07);border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0;flex-wrap:wrap}
.dot{width:8px;height:8px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite;flex-shrink:0}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.5;transform:scale(1.3)}}
@keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
.ll{font-weight:700;font-size:11px;letter-spacing:.1em;color:#4caf50;flex-shrink:0}.lm{opacity:.75;font-size:12px}
.live-task{margin-left:auto;font-size:11px;display:flex;gap:8px;align-items:center}
.live-stream{background:#4a9eff22;color:#4a9eff;border:1px solid #4a9eff44;padding:1px 7px;border-radius:10px;font-weight:600;font-family:var(--vscode-editor-font-family,'monospace');font-size:10px}
.live-role{background:#9c6af722;color:#9c6af7;border:1px solid #9c6af744;padding:1px 7px;border-radius:10px;font-size:10px}
.stats{display:flex;gap:10px;padding:12px 16px;flex-shrink:0}
.sc{flex:1;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);border-radius:6px;padding:10px 14px;text-align:center}
.sn{font-size:26px;font-weight:700;color:#4a9eff;line-height:1}.sl{font-size:10px;opacity:.6;margin-top:3px;text-transform:uppercase;letter-spacing:.05em}
.main{display:flex;gap:10px;padding:0 16px 10px;flex:1;min-height:0}
.cl{flex:6;display:flex;flex-direction:column;gap:6px;overflow-y:auto}
.cr{flex:4;display:flex;flex-direction:column;gap:10px;overflow-y:auto}
.ttl{font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.5;margin-bottom:6px}
.card{background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);border-radius:6px;padding:8px 12px;transition:border-color .2s}
.active-card{border-color:#4a9eff66;background:rgba(74,158,255,.05)}
.active-dot{width:6px;height:6px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite;margin-left:4px;flex-shrink:0}
.st{display:flex;align-items:center;gap:8px}
.si{color:#4a9eff;flex-shrink:0}.spin{display:inline-block;animation:spin 2s linear infinite}
.ss{font-weight:600;font-family:var(--vscode-editor-font-family,'monospace')}
.badge{font-size:10px;padding:2px 7px;border-radius:10px;margin-left:auto;font-weight:600;white-space:nowrap}
.sa{margin-top:4px;font-size:11px;opacity:.6;padding-left:20px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.wr{padding:3px 0;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;opacity:.8}
.em{opacity:.4;font-size:12px;font-style:italic;line-height:1.7}code{font-family:var(--vscode-editor-font-family,'monospace');font-size:11px}
.ev{display:flex;align-items:center;gap:6px;padding:4px 0;border-bottom:1px solid var(--vscode-panel-border);font-size:11px}
.ev:last-child{border-bottom:none}
.ev-icon{flex-shrink:0;width:16px;text-align:center;font-size:10px;opacity:.7}
.ev-detail{flex:1;font-family:var(--vscode-editor-font-family,'monospace');opacity:.85;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ev-stream{font-size:10px;padding:1px 5px;border-radius:8px;background:#4a9eff15;color:#4a9eff;white-space:nowrap;flex-shrink:0}
.ev-time{font-size:10px;opacity:.45;white-space:nowrap;flex-shrink:0}
.footer{display:flex;flex-wrap:wrap;gap:6px;padding:8px 16px;border-top:1px solid var(--vscode-panel-border);flex-shrink:0;font-size:11px}
.fi{padding:2px 7px;border-radius:4px;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border)}
.role-fi{color:#9c6af7;border-color:#9c6af744}.ctx-fi{border:none;background:transparent;padding:2px 0}
.risk{color:#e8823a;border-color:#e8823a55}
.ctx-bar{font-family:var(--vscode-editor-font-family,'monospace');font-size:10px;letter-spacing:-1px}
</style></head><body>
<div class="hdr"><span class="logo">◆ AGENTBOARD</span><span class="sep">·</span><span class="proj">${projectName}</span>${branch ? `<span class="sep">·</span><span class="br">${branch}</span>` : ""}<button class="rbtn" onclick="vscode.postMessage({command:'refresh'})">↻ Refresh</button></div>
${hasLive ? `<div class="live"><span class="dot"></span><span class="ll">LIVE</span><span class="lm">${liveMeta}</span><span class="live-task">${activeStream ? `<span class="live-stream">${activeStream}</span>` : ""}${activeRole ? `<span class="live-role">◈ ${activeRole}</span>` : ""}</span></div>` : ""}
<div class="stats">
  <div class="sc"><div class="sn">${skillCount}</div><div class="sl">Skills</div></div>
  <div class="sc"><div class="sn">${roleCount}</div><div class="sl">Roles</div></div>
  <div class="sc"><div class="sn">${streams.length}</div><div class="sl">Streams</div></div>
  <div class="sc"><div class="sn">${worktrees.length}</div><div class="sl">Worktrees</div></div>
</div>
<div class="main">
  <div class="cl">
    <div><div class="ttl">Active Streams</div>${streamCards}</div>
    <div style="margin-top:8px"><div class="ttl">Recent Activity</div><div class="card" style="padding:6px 10px">${activityLines}</div></div>
  </div>
  <div class="cr">
    <div><div class="ttl">Worktrees</div>${wtLines}</div>
    <div><div class="ttl">Sessions</div>${sessionBlock}</div>
  </div>
</div>
${hudFooter}
<script>const vscode=acquireVsCodeApi();</script>
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
