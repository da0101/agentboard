import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import { execSync } from "child_process";
import { HudStatus } from "./hudTypes";

interface StreamEntry { slug: string; status: string; type: string; next_action: string; }
interface DashData {
  hud: HudStatus | null; streams: StreamEntry[]; skillCount: number;
  roleCount: number; sessions: unknown[]; worktrees: string[];
  projectName: string; branch: string; cpRunning: boolean;
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
      return [{ slug: fm.slug ?? path.basename(f, ".md"), status: fm.status ?? "active", type: fm.type ?? "task", next_action: na }];
    } catch { return []; }
  });
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
    const watcher = vscode.workspace.createFileSystemWatcher(hudFile);
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
    this._panel.webview.html = this._getHtml({
      hud, streams: readStreams(this.workspaceRoot),
      skillCount: countDirs(path.join(this.workspaceRoot, ".claude", "skills")),
      roleCount: countMd(path.join(this.workspaceRoot, ".platform", "roles"), ["INDEX.md"]),
      sessions, worktrees, projectName: path.basename(this.workspaceRoot), branch, cpRunning,
    });
  }

  private _getHtml(d: DashData): string {
    const { hud, streams, skillCount, roleCount, sessions, worktrees, projectName, branch, cpRunning } = d;
    const agents = hud?.active_agents ?? [];
    const hasLive = agents.length > 0 || sessions.length > 0;
    const model = hud?.context?.model ?? "claude";
    const tokens = hud?.cost?.session_tokens ? `${(hud.cost.session_tokens / 1000).toFixed(1)}k tokens` : "";
    const cost = hud?.cost?.session_usd ? `$${hud.cost.session_usd.toFixed(3)}` : "";
    const time = agents[0] ? elapsed(agents[0].started_at) : "";
    const liveMeta = [model, tokens, cost, time].filter(Boolean).join(" · ");
    const typeColor: Record<string, string> = { bugfix: "#e8823a", feature: "#4caf84", task: "#4a9eff", maintenance: "#888" };
    const badge = (t: string) => { const c = typeColor[t.toLowerCase()] ?? "#888"; return `<span class="badge" style="background:${c}22;color:${c};border:1px solid ${c}55">${t}</span>`; };
    const streamCards = streams.length ? streams.map((s) => `<div class="card"><div class="st"><span class="si">↻</span><span class="ss">${s.slug}</span>${badge(s.type)}</div>${s.next_action ? `<div class="sa">→ ${s.next_action}</div>` : ""}</div>`).join("") : `<div class="em">No active streams</div>`;
    const wtLines = worktrees.length ? worktrees.map((w) => `<div class="wr">⎇ ${w}</div>`).join("") : `<div class="em">No worktrees</div>`;
    const sessionBlock = !cpRunning
      ? `<div class="em">Control plane not running<br><code>$ ab start</code></div>`
      : sessions.length
        ? `<div style="color:#4caf50">● ${sessions.length} active session${sessions.length > 1 ? "s" : ""}</div>`
        : `<div class="em" style="color:#4caf84">● Control plane running</div><div class="em">No sessions yet</div>`;
    const hudFooter = hud ? `<div class="footer">${[model && `<span class="fi">⬡ ${model}</span>`, branch && `<span class="fi">⎇ ${branch}</span>`, hud.checks?.ci_status && `<span class="fi ci-${hud.checks.ci_status.toLowerCase()}">CI ${hud.checks.ci_status}</span>`, cost && `<span class="fi">${cost}</span>`, hud.risk?.dirty_worktree && `<span class="fi risk">⚠ dirty</span>`, hud.risk?.open_conflicts && `<span class="fi risk">⚠ conflicts</span>`].filter(Boolean).join("")}</div>` : "";

    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;height:100vh;display:flex;flex-direction:column}
.hdr{display:flex;align-items:center;gap:10px;padding:10px 16px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.logo{color:var(--vscode-activityBarBadge-background);font-weight:700;letter-spacing:.08em}.sep{opacity:.4}.proj{opacity:.7}.br{opacity:.5;font-size:12px}
.rbtn{margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:var(--vscode-editor-foreground);border-radius:4px;padding:3px 10px;cursor:pointer;font-size:12px}
.rbtn:hover{background:var(--vscode-list-hoverBackground)}
.live{display:flex;align-items:center;gap:8px;padding:8px 16px;background:rgba(76,175,80,.07);border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.dot{width:8px;height:8px;border-radius:50%;background:#4caf50;animation:pulse 1.5s ease-in-out infinite}
@keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.5;transform:scale(1.3)}}
.ll{font-weight:700;font-size:11px;letter-spacing:.1em;color:#4caf50}.lm{opacity:.75;font-size:12px}
.stats{display:flex;gap:12px;padding:14px 16px;flex-shrink:0}
.sc{flex:1;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);border-radius:6px;padding:12px 16px;text-align:center}
.sn{font-size:28px;font-weight:700;color:var(--vscode-activityBarBadge-background);line-height:1}
.sl{font-size:11px;opacity:.6;margin-top:4px;text-transform:uppercase;letter-spacing:.05em}
.main{display:flex;gap:12px;padding:0 16px 16px;flex:1;min-height:0}
.cl{flex:6;display:flex;flex-direction:column;gap:8px;overflow-y:auto}
.cr{flex:4;display:flex;flex-direction:column;gap:12px;overflow-y:auto}
.ttl{font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.5;margin-bottom:6px}
.card{background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border);border-radius:6px;padding:10px 12px}
.st{display:flex;align-items:center;gap:8px}.si{color:var(--vscode-activityBarBadge-background)}
.ss{font-weight:600;font-family:var(--vscode-editor-font-family,'monospace')}
.badge{font-size:10px;padding:2px 7px;border-radius:10px;margin-left:auto;font-weight:600}
.sa{margin-top:5px;font-size:12px;opacity:.6;padding-left:20px}
.wr{padding:4px 0;font-family:var(--vscode-editor-font-family,'monospace');font-size:12px;opacity:.8}
.em{opacity:.4;font-size:12px;font-style:italic;line-height:1.7}code{font-family:var(--vscode-editor-font-family,'monospace');font-size:11px}
.footer{display:flex;flex-wrap:wrap;gap:8px;padding:8px 16px;border-top:1px solid var(--vscode-panel-border);flex-shrink:0;opacity:.7;font-size:11px}
.fi{padding:2px 6px;border-radius:4px;background:var(--vscode-sideBar-background);border:1px solid var(--vscode-panel-border)}
.risk{color:#e8823a;border-color:#e8823a55}.ci-pass,.ci-success{color:#4caf50}.ci-fail,.ci-failure{color:#f44336}
</style></head><body>
<div class="hdr"><span class="logo">◆ AGENTBOARD</span><span class="sep">·</span><span class="proj">${projectName}</span>${branch ? `<span class="sep">·</span><span class="br">${branch}</span>` : ""}<button class="rbtn" onclick="vscode.postMessage({command:'refresh'})">↻ Refresh</button></div>
${hasLive ? `<div class="live"><span class="dot"></span><span class="ll">LIVE</span><span class="lm">${liveMeta}</span></div>` : ""}
<div class="stats">
  <div class="sc"><div class="sn">${skillCount}</div><div class="sl">Skills</div></div>
  <div class="sc"><div class="sn">${roleCount}</div><div class="sl">Roles</div></div>
  <div class="sc"><div class="sn">${streams.length}</div><div class="sl">Streams</div></div>
  <div class="sc"><div class="sn">${worktrees.length}</div><div class="sl">Worktrees</div></div>
</div>
<div class="main">
  <div class="cl"><div class="ttl">Active Streams</div>${streamCards}</div>
  <div class="cr"><div><div class="ttl">Worktrees</div>${wtLines}</div><div><div class="ttl">Sessions</div>${sessionBlock}</div></div>
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
