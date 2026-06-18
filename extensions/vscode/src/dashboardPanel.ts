import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import { execSync } from "child_process";
import { HudStatus } from "./hudTypes";

const AB_CLI_COMMANDS: CatalogItem[] = [
  { name: "init", description: "Scaffold .platform/ into any project" },
  { name: "new-stream", description: "Open a new work stream" },
  { name: "new-domain", description: "Add a domain context file" },
  { name: "checkpoint", description: "Save progress snapshot to stream" },
  { name: "handoff", description: "Generate handoff packet for next session" },
  { name: "doctor", description: "Diagnose platform health" },
  { name: "brief", description: "Print session briefing from BRIEF.md" },
  { name: "progress", description: "Show stream progress summary" },
  { name: "close", description: "Close and archive a stream" },
  { name: "watch", description: "Watch active streams for updates" },
  { name: "migrate", description: "Migrate stream files to current format" },
  { name: "sync-skills", description: "Sync skill pack from agentboard" },
  { name: "validate", description: "Validate stream and platform files" },
  { name: "usage", description: "Token usage log and dashboard" },
];


interface ActivityEvent { ts: string; tool: string; stream: string; file?: string; cmd?: string; agent?: string; skill?: string; hook_event_name?: string; }
interface CatalogItem { name: string; description: string; }
interface StreamEntry {
  slug: string; type: string; status: string; role: string;
  objective: string; nextAction: string; branch: string;
  doneCriteria: Array<{ text: string; done: boolean }>;
  progress: string; filePath: string;
}

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
        const filePath = path.join(dir, f);
        const c = fs.readFileSync(filePath, "utf8");
        const fm = parseFrontmatter(c);
        const st = (fm.status ?? "").toLowerCase();
        if (["done", "archived", "closed"].includes(st)) return [];
        const body = c.replace(/^---[\s\S]*?---\n?/, "");
        const section = (headers: string[]) => {
          const pat = new RegExp(`##+ (?:${headers.join("|")})\\s*\\n([\\s\\S]*?)(?=\\n##|$)`, "i");
          return body.match(pat)?.[1]?.trim() ?? "";
        };
        const objective = fm.objective ?? section(["objective","goal","description","what","summary"]);
        const nextAction = fm.next_action ?? section(["next.?action","next.?step","now","current"]);
        const progressRaw = section(["progress","log","notes","session.?log"]);
        // parse done criteria checklist
        const criteriaBlock = section(["done.?criteria","done","acceptance","checklist","exit.?criteria"]);
        const doneCriteria = criteriaBlock.split("\n").filter(l => /^\s*-\s*\[/.test(l)).map(l => ({
          done: /^\s*-\s*\[x\]/i.test(l),
          text: l.replace(/^\s*-\s*\[.\]\s*/, "").trim(),
        }));
        return [{
          slug: fm.slug ?? path.basename(f, ".md"),
          status: fm.status ?? "active",
          type: fm.type ?? "task",
          role: fm.role ?? "",
          branch: fm.branch ?? "",
          objective: objective.slice(0, 300),
          nextAction: nextAction.split("\n")[0]?.trim().slice(0, 200) ?? "",
          doneCriteria: doneCriteria.slice(0, 12),
          progress: progressRaw.split("\n").filter(Boolean).slice(-3).join(" · ").slice(0, 200),
          filePath,
        }];
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
        return [{ name: fm.name ?? fm.slug ?? path.basename(f, ".md"), description: fm.mission ?? fm.description ?? fm.objective ?? "" }];
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

interface WorkflowAgentPlan { label: string; role: string; skill: string; model: string; phase: string; agentType: string; status: string }
interface WorkflowPlan { name: string; phases: string[]; agents: WorkflowAgentPlan[]; total: number; started_at: string; ended_at?: string; status: string }
function readWorkflowPlan(root: string): WorkflowPlan | null {
  try {
    const raw = fs.readFileSync(path.join(root, "agentboard.workflow-agents.json"), "utf8");
    const d = JSON.parse(raw) as WorkflowPlan;
    if (!d || !Array.isArray(d.agents)) return null;
    // Discard if older than 30 minutes and done
    const ageMs = Date.now() - new Date(d.started_at).getTime();
    if (d.status === "done" && ageMs > 30 * 60 * 1000) return null;
    return d;
  } catch { return null; }
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
    if (DashboardPanel.currentPanel) {
      // Update workspace root and refresh data even if panel already exists
      (DashboardPanel.currentPanel as unknown as { workspaceRoot: string }).workspaceRoot = workspaceRoot;
      void DashboardPanel.currentPanel._update();
      DashboardPanel.currentPanel._panel.reveal(col);
      return;
    }
    DashboardPanel.currentPanel = new DashboardPanel(
      vscode.window.createWebviewPanel("agentboardDashboard", "Agentboard", col, { enableScripts: true, retainContextWhenHidden: true }),
      workspaceRoot
    );
  }

  static refresh(): void {
    if (DashboardPanel.currentPanel) void DashboardPanel.currentPanel._update();
  }

  private constructor(panel: vscode.WebviewPanel, private readonly workspaceRoot: string) {
    this._panel = panel;
    this._panel.webview.html = this._getShell();
    this._initialized = true;
    void this._update();
    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(workspaceRoot, "{agentboard.hud-status.json,agentboard.workflow-agents.json,.platform/events.jsonl,.platform/work/*.md}")
    );
    watcher.onDidChange(() => void this._update(), null, this._disposables);
    watcher.onDidCreate(() => void this._update(), null, this._disposables);
    this._disposables.push(watcher);
    this._interval = setInterval(() => void this._update(), 4000);
    this._panel.webview.onDidReceiveMessage(
      (msg: { command: string; filePath?: string }) => {
        if (msg.command === "refresh") void this._update();
        if (msg.command === "openStream" && msg.filePath) {
          void vscode.workspace.openTextDocument(msg.filePath).then(doc => vscode.window.showTextDocument(doc, { preview: true, preserveFocus: false }));
        }
      },
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
    const costUsd = hud?.cost?.session_usd as number | null ?? null;
    const cost = costUsd !== null ? `$${costUsd.toFixed(3)}` : "";
    const sessionTime = hud?.active_agents?.[0]?.started_at ? elapsedStr(hud.active_agents[0].started_at) : "";
    const hasLive = (hud?.active_agents?.length ?? 0) > 0;
    const lastSkill = readLastSkill(this.workspaceRoot);
    const skills = readSkills(this.workspaceRoot);
    const roles = readRoles(this.workspaceRoot);
    const allEvents = readRecentEvents(this.workspaceRoot, 200);

    // Build deduplicated file activity: file → {tool, count, lastTs}
    const fileMap = new Map<string, { tool: string; count: number; lastTs: string }>();
    for (const ev of [...allEvents].reverse()) {
      if (!ev.file && !ev.cmd) continue;
      const key = ev.file ?? `$ ${(ev.cmd ?? "").slice(0, 60)}`;
      const existing = fileMap.get(key);
      if (!existing || ev.ts > existing.lastTs) {
        fileMap.set(key, { tool: ev.tool, count: (existing?.count ?? 0) + 1, lastTs: ev.ts });
      } else {
        fileMap.set(key, { ...existing, count: existing.count + 1 });
      }
    }
    const fileActivity = [...fileMap.entries()]
      .sort((a, b) => b[1].lastTs.localeCompare(a[1].lastTs))
      .slice(0, 12)
      .map(([file, info]) => ({ file, ...info }));

    // Stream description from body italic line
    const streamDesc = (() => {
      if (!activeStream) return "";
      try {
        const body = fs.readFileSync(path.join(this.workspaceRoot, ".platform", "work", `${activeStream}.md`), "utf8");
        return body.match(/^_([^_]+)_/m)?.[1]?.trim() ?? "";
      } catch { return ""; }
    })();

    const lastEvent = allEvents[0] ?? null;
    // Determine last event label for NOW block
    const lastNonAgentEvent = allEvents.find(e => e.tool !== "Agent") ?? null;
    const lastEventLabel = lastNonAgentEvent?.file
      ? path.basename(lastNonAgentEvent.file)
      : lastNonAgentEvent?.cmd
        ? (lastNonAgentEvent.cmd as string).slice(0, 50)
        : (lastNonAgentEvent as {skill?: string} | null)?.skill
          ? `/${(lastNonAgentEvent as {skill?: string}).skill}`
          : lastNonAgentEvent?.tool ?? "";
    const lastEventTs = lastNonAgentEvent?.ts ?? "";
    const secsSinceLastEvent = lastEventTs ? Math.floor((Date.now() - new Date(lastEventTs).getTime()) / 1000) : null;
    const isInLongOp = hasLive && secsSinceLastEvent !== null && secsSinceLastEvent > 90;

    // Detect active Workflow (WorkflowStart without matching WorkflowEnd within 30 min)
    let activeWorkflow: { label: string; agentCount: number; ts: string } | null = null;
    for (const ev of allEvents) {
      const secAgo = Math.floor((Date.now() - new Date(ev.ts).getTime()) / 1000);
      if (ev.tool === "WorkflowStart" && secAgo < 1800) {
        activeWorkflow = {
          label: (ev as {label?: string}).label ?? "workflow",
          agentCount: (ev as {agent_count?: number}).agent_count ?? 0,
          ts: ev.ts,
        };
      } else if (ev.tool === "WorkflowEnd") {
        activeWorkflow = null; // workflow finished
      }
    }

    // Build agents list from AgentStart events (PreToolUse) — role + skill per agent
    interface AgentEntry { label: string; role: string; skill: string; ts: string; done: boolean }
    const agentMap = new Map<string, AgentEntry>();
    for (const ev of allEvents) {
      const secAgo = Math.floor((Date.now() - new Date(ev.ts).getTime()) / 1000);
      if (ev.tool === "AgentStart") {
        const key = (ev as {label?: string}).label ?? ev.ts;
        if (secAgo < 600) agentMap.set(key, {
          label: (ev as {label?: string}).label ?? "agent",
          role: (ev as {role?: string}).role ?? "",
          skill: (ev as {skill?: string}).skill ?? "",
          ts: ev.ts,
          done: false,
        });
      } else if (ev.tool === "Agent" && (ev as {agent?: string}).agent) {
        const key = (ev as {agent?: string}).agent ?? "";
        const existing = agentMap.get(key);
        if (existing) agentMap.set(key, { ...existing, done: true });
      }
    }
    const recentAgents = Array.from(agentMap.values()).filter(a => {
      const secAgo = Math.floor((Date.now() - new Date(a.ts).getTime()) / 1000);
      return secAgo < 600;
    });

    const workflowPlan = readWorkflowPlan(this.workspaceRoot);

    void this._panel.webview.postMessage({
      type: "update",
      hasLive, model, cost, sessionTime, activeStream, streamDesc, activeRole, lastSkill,
      ctxPct, branch, cpRunning, sessions: sessions.length,
      activeWorkflow,
      workflowPlan,
      streams: readStreams(this.workspaceRoot),
      fileActivity, recentAgents,
      lastEventLabel, lastEventTs, isInLongOp,
      worktrees,
      skillCount: skills.length, roleCount: roles.length,
      skills, roles,
      commands: AB_CLI_COMMANDS,
      projectName: path.basename(this.workspaceRoot),
    });
  }

  private _getShell(): string { // eslint-disable-line
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--vscode-editor-background);color:var(--vscode-editor-foreground);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;height:100vh;display:flex;flex-direction:column;overflow:hidden}
#hdr{display:flex;align-items:center;gap:8px;padding:8px 14px;border-bottom:1px solid var(--vscode-panel-border);flex-shrink:0}
.logo{color:#4a9eff;font-weight:700;letter-spacing:.08em;font-size:11px}.sep{opacity:.25}.proj{opacity:.65;font-size:12px}.br{opacity:.4;font-size:11px}
.rbtn{margin-left:auto;background:transparent;border:1px solid var(--vscode-panel-border);color:inherit;border-radius:4px;padding:2px 8px;cursor:pointer;font-size:11px}
.rbtn:hover{background:var(--vscode-list-hoverBackground)}
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
.sec{padding:10px 14px;border-bottom:1px solid var(--vscode-panel-border)}
.sec:last-child{border-bottom:none}
.sec-ttl{font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;opacity:.35;margin-bottom:8px}
/* file activity */
.fa{display:grid;grid-template-columns:auto 1fr auto auto;gap:0 10px;align-items:center;padding:4px 0;border-bottom:1px solid rgba(128,128,128,.07);font-size:12px}
.fa:last-child{border-bottom:none}
.fa-icon{opacity:.45;font-size:11px;text-align:center;width:14px}
.fa-file{font-family:var(--vscode-editor-font-family,'monospace');overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.fa-cnt{font-size:10px;opacity:.3;white-space:nowrap}
.fa-t{font-size:10px;opacity:.35;white-space:nowrap}
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
</style></head><body>

<div id="hdr">
  <span class="logo">◆ AGENTBOARD</span><span class="sep">·</span>
  <span class="proj" id="h-proj">—</span><span class="sep" id="h-sep2" style="display:none">·</span><span class="br" id="h-br"></span>
  <button class="rbtn" onclick="vscode.postMessage({command:'refresh'})">↻ Refresh</button>
</div>

<div class="tabs">
  <button class="tab on" onclick="switchTab('live',this)">Live</button>
  <button class="tab" id="tab-catalog" onclick="switchTab('catalog',this)">Catalog</button>
</div>

<div id="live" class="view on">
  <!-- NOW block -->
  <div id="now">
    <div class="now-status">
      <span class="dot" id="now-dot"></span>
      <span class="now-state" id="now-state">IDLE</span>
      <span class="now-stats" id="now-stats"></span>
    </div>
    <div class="now-last">
      <span class="now-tool" id="now-tool"></span>
      <span class="now-file" id="now-file">No activity yet</span>
      <span class="now-ago" id="now-ago"></span>
    </div>
    <div class="now-desc" id="now-desc"></div>
    <div class="now-longop" id="now-longop">⟳ Running long operation — last tool call completed &gt;90s ago</div>
  </div>

  <div id="live-body">
    <!-- Left: files touched + streams -->
    <div class="col-l">
      <div class="sec">
        <div class="sec-ttl" id="fa-ttl">Files touched this session</div>
        <div id="fa-list"><div class="em">No activity yet</div></div>
      </div>
      <div class="sec">
        <div class="sec-ttl" id="sr-ttl">Active streams</div>
        <div id="sr-list"></div>
      </div>
    </div>
    <!-- Right: agents + session stats -->
    <div class="col-r">
      <div class="sec" id="sec-agents">
        <div class="sec-ttl" id="agents-ttl">Agents <span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none">· last 5 min</span></div>
        <div id="agents-list"><div class="em">No sub-agents dispatched — Claude is working solo</div></div>
      </div>
      <div class="sec">
        <div class="sec-ttl">Session</div>
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
        <div class="sec-ttl">Role / Skill</div>
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

<script>
const vscode = acquireVsCodeApi();
const TYPE_COLOR={bugfix:'#e8823a',feature:'#4caf84',task:'#4a9eff',maintenance:'#888',research:'#9c6af7'};
const TOOL_ICON={Edit:'✏',Write:'✏',Bash:'$',Read:'👁',WebSearch:'⌕',WebFetch:'⌕',Agent:'◈',Skill:'⚡'};
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function html(id,h){const el=document.getElementById(id);if(el)el.innerHTML=h;}
function txt(id,t){const el=document.getElementById(id);if(el)el.textContent=t;}
function switchTab(id,btn){
  document.querySelectorAll('.view').forEach(v=>v.classList.remove('on'));
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));
  document.getElementById(id).classList.add('on');btn.classList.add('on');
}
function relTime(iso){
  if(!iso)return'';
  const s=Math.floor((Date.now()-new Date(iso).getTime())/1000);
  if(s<60)return s+'s ago';if(s<3600)return Math.floor(s/60)+'m ago';return Math.floor(s/3600)+'h ago';
}
function toggleStream(id){
  const el=document.getElementById(id);
  if(!el)return;
  const open=el.style.display==='block';
  // close all first
  document.querySelectorAll('[id^="sr-detail-"]').forEach(function(e){e.style.display='none';});
  if(!open)el.style.display='block';
}
function openStream(fp){vscode.postMessage({command:'openStream',filePath:fp});}
function ctxBar(pct){
  if(pct===null||pct===undefined)return'—';
  const used=Math.round(100-pct);const fill=Math.floor(used/10);
  const c=used<50?'#4caf50':used<75?'#ff9800':'#f44336';
  return '<span class="ctx" style="color:'+c+'">'+'█'.repeat(fill)+'░'.repeat(10-fill)+'</span><span style="color:'+c+';font-size:11px"> '+used+'%</span>';
}
function renderCatalogCol(listId,items){
  const MAX=100;
  let h=items.slice(0,MAX).map(function(item){
    return '<div class="ci"><span class="ci-name">'+esc(item.name)+'</span>'+(item.description?'<span class="ci-desc">'+esc(item.description.slice(0,90))+'</span>':'')+'</div>';
  }).join('');
  if(items.length>MAX)h+='<div class="more">+' +(items.length-MAX)+' more</div>';
  html(listId,h);
}

window.addEventListener('message',function(e){
  const d=e.data;if(d.type!=='update')return;

  // header
  txt('h-proj',d.projectName||'—');
  const br=document.getElementById('h-br'),sep=document.getElementById('h-sep2');
  if(br&&sep){br.textContent=d.branch||'';sep.style.display=d.branch?'':'none';}

  // tabs
  const tc=document.getElementById('tab-catalog');
  if(tc)tc.textContent='Catalog · '+(d.skillCount+d.roleCount);

  // NOW block
  const nowEl=document.getElementById('now');
  const dot=document.getElementById('now-dot');
  const stateEl=document.getElementById('now-state');
  const ctxNow=d.ctxPct!==null&&d.ctxPct!==undefined?Math.round(100-d.ctxPct):0;
  const isWorkflow=!!(d.activeWorkflow);
  if(d.hasLive){
    nowEl.classList.remove('idle');dot.classList.remove('idle');
    const isCompact=d.isInLongOp&&ctxNow>=75;
    if(isWorkflow){
      stateEl.textContent='WORKFLOW';stateEl.style.color='#4a9eff';
      dot.style.background='#4a9eff';dot.style.animation='pulse 0.6s ease-in-out infinite';
    } else if(isCompact){
      stateEl.textContent='COMPACTING';stateEl.style.color='#9c6af7';
      dot.style.background='#9c6af7';dot.style.animation='pulse 0.6s ease-in-out infinite';
    } else {
      stateEl.textContent='LIVE';stateEl.style.color='#4caf50';
      dot.style.background='#4caf50';dot.style.animation='pulse 1.5s ease-in-out infinite';
    }
  } else {
    nowEl.classList.add('idle');dot.classList.add('idle');
    stateEl.textContent='IDLE';stateEl.style.color='#666';dot.style.background='#666';
  }
  txt('now-stats',[d.model,d.cost,d.sessionTime].filter(Boolean).join(' · '));
  if(d.lastEventLabel){
    const fa0=d.fileActivity&&d.fileActivity[0];
    const isSkill=fa0&&fa0.tool==='Skill';
    const nowFile=document.getElementById('now-file');
    const nowTool=document.getElementById('now-tool');
    if(nowFile){
      nowFile.textContent=d.lastEventLabel;
      nowFile.style.color=isSkill?'#4caf84':'#e8e8e8';
    }
    txt('now-ago',relTime(d.lastEventTs));
    if(nowTool){
      nowTool.textContent=isSkill?'⚡ skill':fa0?fa0.tool:'';
      nowTool.style.background=isSkill?'rgba(76,175,132,.15)':'rgba(255,255,255,.08)';
      nowTool.style.color=isSkill?'#4caf84':'inherit';
    }
  }
  txt('now-desc',d.streamDesc||'');
  // determine long-op message: compacting vs generic
  const ctxUsed=d.ctxPct!==null&&d.ctxPct!==undefined?Math.round(100-d.ctxPct):0;
  const isCompacting=d.isInLongOp&&ctxUsed>=75;
  const lopEl=document.getElementById('now-longop');
  if(lopEl){
    lopEl.className='now-longop'+(d.isInLongOp?' on':'');
    lopEl.textContent=isCompacting
      ?'⟳ Context at '+ctxUsed+'% — compaction in progress (will update when complete)'
      :'⟳ Running long operation — last tool call completed >90s ago';
    lopEl.style.color=isCompacting?'#9c6af7':'#ff9800';
  }

  // file activity
  txt('fa-ttl','Activity this session'+(d.fileActivity&&d.fileActivity.length?' ('+d.fileActivity.length+' unique)':''));
  html('fa-list', d.fileActivity&&d.fileActivity.length ? d.fileActivity.map(function(f){
    const isSkillEntry=f.tool==='Skill';
    const isBash=f.tool==='Bash';
    const icon=TOOL_ICON[f.tool]||'·';
    let fname;
    if(isSkillEntry) fname='/'+f.file;
    else if(isBash) fname=f.file.length>60?f.file.slice(0,60)+'…':f.file;
    else fname=f.file.split('/').slice(-2).join('/');
    const color=isSkillEntry?'color:#4caf84;font-weight:600':isBash?'color:#ff9800':'';
    return '<div class="fa">'
      +'<span class="fa-icon" style="'+(isSkillEntry?'color:#4caf84':'')+'">'+icon+'</span>'
      +'<span class="fa-file" style="'+color+'">'+esc(fname)+'</span>'
      +(f.count>1?'<span class="fa-cnt">×'+f.count+'</span>':'<span></span>')
      +'<span class="fa-t">'+relTime(f.lastTs)+'</span>'
      +'</div>';
  }).join('') : '<div class="em">No activity yet — starts logging on next tool call</div>');

  // agents / workflow panel
  const agentsEl=document.getElementById('agents-list');
  const agentsTtl=document.getElementById('agents-ttl');
  const wp=d.workflowPlan;
  const hasWf=wp||(d.activeWorkflow&&d.activeWorkflow.label);

  function renderAgentCard(a,i){
    const done=a.status==='done';
    const pulse=done
      ?'<span style="width:6px;height:6px;border-radius:50%;background:#4caf50;display:inline-block;flex-shrink:0;margin-top:3px"></span>'
      :'<span class="ag-pulse" style="margin-top:3px"></span>';
    const roleTag=a.role?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">'+esc(a.role)+'</span>':'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#88888820;color:#888">no role</span>';
    const skillTag=a.skill?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4caf8422;color:#4caf84">'+esc(a.skill)+'</span>':'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#88888820;color:#888">no skill</span>';
    const modelRaw=a.model||'';
    const modelLabel=modelRaw.replace('claude-','').replace(/-\d{8}$/,'').replace('-latest','');
    const modelColor=modelRaw.includes('opus')?'#9c6af7':modelRaw.includes('haiku')?'#4a9eff':'#ff9800';
    const modelTag=modelLabel?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+modelColor+'22;color:'+modelColor+'">'+esc(modelLabel)+'</span>':'';
    const phaseTag=a.phase?'<span style="font-size:10px;opacity:.35;padding:1px 4px">'+esc(a.phase)+'</span>':'';
    const num='<span style="font-size:10px;opacity:.25;flex-shrink:0;min-width:18px;margin-top:1px">'+(i+1)+'</span>';
    return '<div class="ag-row" style="align-items:flex-start;gap:5px;padding:6px 0;border-bottom:1px solid rgba(128,128,128,.07)">'
      +num+pulse
      +'<div style="flex:1;min-width:0">'
      +'<div style="font-size:11px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;margin-bottom:4px;'+(done?'text-decoration:line-through;opacity:.4':'')+'">'+esc(a.label)+'</div>'
      +'<div style="display:flex;flex-wrap:wrap;gap:3px">'+roleTag+skillTag+modelTag+phaseTag+'</div>'
      +'</div>'
      +'</div>';
  }

  if(agentsEl&&hasWf){
    const isDone=wp&&wp.status==='done';
    const wfName=wp?wp.name:(d.activeWorkflow?d.activeWorkflow.label:'workflow');
    const agentCount=wp?wp.total:(d.activeWorkflow?d.activeWorkflow.agentCount:0);
    const dotColor=isDone?'#4caf50':'#4a9eff';
    const stateLabel=isDone?'✓ WORKFLOW DONE':'⟳ WORKFLOW';
    if(agentsTtl)agentsTtl.innerHTML='<span style="color:'+dotColor+';font-weight:700">'+stateLabel+'</span>'
      +(agentCount?' <span style="color:'+dotColor+';font-weight:700"> · '+agentCount+' agents</span>':'')
      +' <span style="font-weight:400;opacity:.35;font-size:10px;text-transform:none;letter-spacing:0;margin-left:4px">'+esc(wfName)+'</span>';
    // phase pills
    let phasePills='';
    if(wp&&wp.phases&&wp.phases.length){
      phasePills='<div style="display:flex;flex-wrap:wrap;gap:4px;margin-bottom:8px">'
        +wp.phases.map(function(p){
          return '<span style="font-size:10px;padding:1px 7px;border-radius:10px;background:#4a9eff22;color:#4a9eff;border:1px solid #4a9eff44">'+esc(p)+'</span>';
        }).join('')+'</div>';
    }
    // agent cards
    let cards='';
    if(wp&&wp.agents&&wp.agents.length){
      cards=wp.agents.map(renderAgentCard).join('');
    } else {
      cards='<div style="font-size:11px;opacity:.4;padding:6px 0">Agent details not available — add <code style="font-size:10px">label: "role:X · skill:Y · task"</code> to each agent() call in the workflow script</div>';
    }
    agentsEl.innerHTML=phasePills+cards;
  } else if(agentsEl&&d.recentAgents&&d.recentAgents.length){
    // Fallback: AgentStart events (direct Agent tool, no Workflow)
    const running=d.recentAgents.filter(function(a){return !a.done;});
    const done=d.recentAgents.filter(function(a){return a.done;});
    if(agentsTtl)agentsTtl.innerHTML='Agents'
      +(running.length?' <span style="color:#4caf50;font-weight:700">'+running.length+' running</span>':'')
      +(done.length?' <span style="opacity:.4;font-size:11px"> '+done.length+' done</span>':'')
      +'<span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none"> · last 10 min</span>';
    agentsEl.innerHTML=d.recentAgents.map(function(a){
      const pulse=a.done?'<span style="width:6px;height:6px;border-radius:50%;background:#555;display:inline-block;flex-shrink:0"></span>':'<span class="ag-pulse"></span>';
      const roleTag=a.role?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">'+esc(a.role)+'</span>':'';
      const skillTag=a.skill?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4caf8422;color:#4caf84">'+esc(a.skill)+'</span>':'';
      return '<div class="ag-row">'+pulse+'<span class="ag-label" style="'+(a.done?'opacity:.4':'')+'">'+esc(a.label)+'</span>'+roleTag+skillTag+'<span class="ag-t">'+relTime(a.ts)+'</span></div>';
    }).join('');
  } else if(agentsEl){
    if(agentsTtl)agentsTtl.innerHTML='Agents <span style="font-weight:400;opacity:.5;font-size:10px;letter-spacing:0;text-transform:none">· last 10 min</span>';
    agentsEl.innerHTML='<div class="em">No sub-agents — Claude is working solo</div>';
  }

  // streams — interactive accordion
  txt('sr-ttl','Active streams ('+d.streams.length+')');
  if(!d.streams.length){html('sr-list','<div class="em">No active streams</div>');}
  else {
    const srList=document.getElementById('sr-list');
    if(srList){
      srList.innerHTML=d.streams.map(function(s,i){
        const isA=s.slug===d.activeStream;
        const c=TYPE_COLOR[s.type]||'#888';
        const statColor={active:'#4caf50','in-progress':'#4caf50','awaiting-verification':'#ff9800',blocked:'#f44336',paused:'#888'}[s.status]||'#888';
        const doneCount=s.doneCriteria?s.doneCriteria.filter(function(x){return x.done;}).length:0;
        const totalCount=s.doneCriteria?s.doneCriteria.length:0;
        const pct=totalCount>0?Math.round(doneCount/totalCount*100):null;
        const pctBar=pct!==null?'<span style="font-size:10px;opacity:.5;margin-left:6px">'+pct+'%</span>':'';

        // header row (always visible, clickable)
        let header='<div class="sr-hdr" onclick="toggleStream(\'sr-detail-'+i+'\')" style="cursor:pointer;display:flex;align-items:center;gap:6px;padding:6px 4px;border-radius:4px;transition:background .15s" onmouseover="this.style.background=\'rgba(255,255,255,.04)\'" onmouseout="this.style.background=\'\'">'
          +'<span style="width:7px;height:7px;border-radius:50%;background:'+(isA?'#4caf50':c)+';flex-shrink:0"></span>'
          +'<span style="font-size:12px;font-weight:'+(isA?'600':'400')+';color:'+(isA?'#4caf84':'#ccc')+';flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+esc(s.slug)+'</span>'
          +(pct!==null?'<span style="font-size:10px;opacity:.45">'+doneCount+'/'+totalCount+'</span>':'')
          +'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+c+'22;color:'+c+'">'+esc(s.type)+'</span>'
          +'<span style="font-size:10px;opacity:.4">▾</span>'
          +'</div>';

        // detail panel (collapsed by default, active stream expanded)
        let detail='<div id="sr-detail-'+i+'" style="display:'+(isA?'block':'none')+';padding:0 4px 8px 18px;border-left:2px solid '+c+'44;margin-left:3px">';
        // status + role
        detail+='<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:6px">'
          +'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:'+statColor+'22;color:'+statColor+'">'+esc(s.status)+'</span>'
          +(s.role?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#9c6af722;color:#9c6af7">'+esc(s.role)+'</span>':'')
          +(s.branch?'<span style="font-size:10px;padding:1px 6px;border-radius:10px;background:#4a9eff22;color:#4a9eff;font-family:monospace">'+esc(s.branch)+'</span>':'')
          +'</div>';
        // objective
        if(s.objective){
          detail+='<div style="font-size:11px;opacity:.65;margin-bottom:6px;line-height:1.5">'+esc(s.objective.slice(0,200))+'</div>';
        }
        // done criteria
        if(s.doneCriteria&&s.doneCriteria.length){
          detail+='<div style="font-size:10px;opacity:.35;text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px">Done criteria</div>';
          detail+=s.doneCriteria.map(function(cr){
            return '<div style="display:flex;gap:5px;font-size:11px;margin-bottom:3px;'+(cr.done?'opacity:.4':'opacity:.8')+'">'
              +'<span style="flex-shrink:0;color:'+(cr.done?'#4caf50':'#666')+'">'+(cr.done?'✓':'○')+'</span>'
              +'<span style="'+(cr.done?'text-decoration:line-through':'')+'">'+esc(cr.text)+'</span>'
              +'</div>';
          }).join('');
        }
        // next action
        if(s.nextAction){
          detail+='<div style="margin-top:6px;font-size:10px;opacity:.35;text-transform:uppercase;letter-spacing:.06em">Next action</div>'
            +'<div style="font-size:11px;color:#ff9800;margin-top:2px">→ '+esc(s.nextAction)+'</div>';
        }
        // open button
        detail+='<div style="margin-top:8px">'
          +'<button onclick="openStream(\''+esc(s.filePath)+'\')" style="font-size:10px;padding:3px 10px;border-radius:4px;background:#4a9eff22;color:#4a9eff;border:1px solid #4a9eff44;cursor:pointer">Open stream file ↗</button>'
          +'</div>';
        detail+='</div>';

        return '<div class="sr-item">'+header+detail+'</div>';
      }).join('');
    }
  }

  // session stats
  txt('sv-model',d.model||'—');
  txt('sv-stream',d.activeStream||'—');
  txt('sv-cost',d.cost||'—');
  txt('sv-time',d.sessionTime||'—');
  const svCtx=document.getElementById('sv-ctx');if(svCtx)svCtx.innerHTML=ctxBar(d.ctxPct);
  txt('sv-branch',d.branch||'—');

  // role/skill — only show section if we have something
  const secRole=document.getElementById('sec-role');
  const rg=document.getElementById('role-grid');
  const rows=[];
  if(d.activeRole)rows.push('<span class="sk">Role</span><span class="sv sv-role">'+esc(d.activeRole)+'</span>');
  if(d.lastSkill)rows.push('<span class="sk">Skill</span><span class="sv sv-skill">/'+esc(d.lastSkill)+'</span>');
  if(secRole&&rg){secRole.style.display=rows.length?'':'none';rg.innerHTML=rows.join('');}

  // catalog
  txt('cnt-skills',String(d.skillCount));
  txt('cnt-roles',String(d.roleCount));
  txt('cnt-cmds',String(d.commands.length));
  renderCatalogCol('list-skills',d.skills);
  renderCatalogCol('list-roles',d.roles);
  renderCatalogCol('list-cmds',d.commands);

  // footer
  const fp=[];
  if(d.model)fp.push('<span class="fi">⬡ '+esc(d.model)+'</span>');
  if(d.cost)fp.push('<span class="fi">'+esc(d.cost)+'</span>');
  if(d.branch)fp.push('<span class="fi" style="font-family:monospace;font-size:10px">⎇ '+esc(d.branch)+'</span>');
  if(d.activeRole)fp.push('<span class="fi" style="color:#9c6af7;border-color:#9c6af744">◈ '+esc(d.activeRole)+'</span>');
  if(d.lastSkill)fp.push('<span class="fi" style="color:#4caf84">/'+esc(d.lastSkill)+'</span>');
  fp.push('<span style="margin-left:auto;opacity:.25;font-size:10px">'+d.skillCount+' skills · '+d.roleCount+' roles · '+d.streams.length+' streams</span>');
  html('footer',fp.join(''));
});
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
