import * as vscode from "vscode";
import * as http from "http";
import { buildDashboardDataSync } from "./dashboard/dataBuilder";
import { handleDelegateFile } from "./dashboard/delegateFile";
import { handleDashboardMessage } from "./dashboard/messageRouter";
import { RawCodexProcessCache } from "./dashboard/rawCodexProcesses";
import { deleteSessionFile, deleteSessionFileByShellPid } from "./dashboard/sessionFiles";
import { getDashboardShell } from "./dashboard/shell";
import { ActivityEvent, CatalogItem, StreamEntry } from "./dashboard/types";

function httpGet(url: string, ms: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let d = ""; res.on("data", (c: Buffer) => { d += c.toString(); }); res.on("end", () => resolve(d));
    });
    req.setTimeout(ms, () => { req.destroy(); reject(new Error("t")); });
    req.on("error", reject);
  });
}

export class DashboardPanel {
  static currentPanel: DashboardPanel | undefined;
  static sessionPanels: Map<string, DashboardPanel> = new Map();
  static extensionUri: vscode.Uri | undefined;
  private readonly _panel: vscode.WebviewPanel;
  private _disposables: vscode.Disposable[] = [];
  private _interval: NodeJS.Timeout | undefined;
  private _initialized = false;

  private _eventsCache = new Map<string, ActivityEvent[]>();
  private _streamsCache: { mtime: number; data: StreamEntry[] } | null = null;
  private _skillsCache: { mtime: number; data: CatalogItem[] } | null = null;
  private _rolesCache: { mtime: number; data: CatalogItem[] } | null = null;
  private _branchCache: { value: string; ts: number } = { value: "", ts: 0 };
  private _numstatCache = new Map<string, { ts: number; diffMap: Map<string, { added: number; deleted: number }> }>();
  private _lineCountCache = new Map<string, { ts: number; count: number }>();
  private _branchCommittedCache = new Map<string, { ts: number; files: Set<string> }>();
  private _rawCodexProcessCache: RawCodexProcessCache = { ts: 0, processes: [] };
  private _httpFailStreak = 0;
  private _boundSessionId: string | null = null;
  private _lastDelegateKey = ""; // "<role>|<task>" dedup
  private _lastDelegateTs = 0;   // epoch ms of last handled delegate
  // nick → terminal name cache so focusTerminal can match by session nick
  private _sessionTerminalMap = new Map<string, string>(); // nick → terminal.name

  static _bootstrappedPanels: Set<string> = new Set();

  static createOrShow(workspaceRoot: string, extensionUri?: vscode.Uri): void {
    if (extensionUri) DashboardPanel.extensionUri = extensionUri;
    const col = vscode.window.activeTextEditor?.viewColumn ?? vscode.ViewColumn.One;
    if (DashboardPanel.currentPanel) {
      try { DashboardPanel.currentPanel._panel.reveal(col); } catch { /* panel may be disposed */ }
      return;
    }
    const panel = vscode.window.createWebviewPanel("agentboardDashboard", "Agentboard", col, {
      enableScripts: true,
      retainContextWhenHidden: true,
      localResourceRoots: extensionUri ? [vscode.Uri.joinPath(extensionUri, "media")] : [],
    });
    try {
      DashboardPanel.currentPanel = new DashboardPanel(panel, workspaceRoot);
    } catch (err) {
      panel.dispose();
      console.error("[agentboard] DashboardPanel constructor failed:", err);
    }
  }

  // Called by extension poll — updates the workspace root and pushes new data to webview
  static forceUpdate(workspaceRoot: string): void {
    if (!DashboardPanel.currentPanel) return;
    DashboardPanel.currentPanel._workspaceRoot = workspaceRoot;
    void DashboardPanel.currentPanel._update();
  }

  static refresh(): void {
    if (DashboardPanel.currentPanel) void DashboardPanel.currentPanel._update();
  }

  // Open (or reveal) a per-session tab for the given session.
  static openSession(sessionId: string, nick: string, workspaceRoot: string): void {
    if (this.sessionPanels.has(sessionId)) {
      try { this.sessionPanels.get(sessionId)!._panel.reveal(undefined, true); } catch { /* disposed */ }
      return;
    }
    if (!this.extensionUri) return;
    const panel = vscode.window.createWebviewPanel(
      "agentboardSession",
      nick || sessionId.slice(0, 8),
      { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true },
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [vscode.Uri.joinPath(this.extensionUri, "media")],
      }
    );
    try {
      const instance = new DashboardPanel(panel, workspaceRoot, sessionId);
      this.sessionPanels.set(sessionId, instance);
    } catch (err) {
      panel.dispose();
      console.error("[agentboard] SessionPanel constructor failed:", err);
    }
  }

  // Called by the main panel on each update cycle to sync session tabs.
  private static _syncSessionPanels(payload: Record<string, unknown>, workspaceRoot: string): void {
    const sessions = (payload.activeSessions as Array<{ sessionId: string; nick: string }> | undefined) ?? [];
    const activeIds = new Set(sessions.map(s => s.sessionId));

    // Open new tabs for newly detected sessions
    for (const sess of sessions) {
      if (!this.sessionPanels.has(sess.sessionId)) {
        this.openSession(sess.sessionId, sess.nick || sess.sessionId.slice(0, 8), workspaceRoot);
      } else {
        // Update title if nick changed and session still active
        const p = this.sessionPanels.get(sess.sessionId)!;
        const title = sess.nick || sess.sessionId.slice(0, 8);
        if (!p._panel.title.endsWith(" ✓") && p._panel.title !== title) p._panel.title = title;
      }
    }

    // Close panels whose sessions are no longer part of the current workspace payload.
    // This prevents live tabs from one Agentboard project lingering in another VS Code workspace.
    for (const [id, p] of this.sessionPanels) {
      if (!activeIds.has(id)) {
        p.dispose();
      }
    }
  }

  private _workspaceRoot: string;

  private constructor(panel: vscode.WebviewPanel, workspaceRoot: string, boundSessionId?: string) {
    this._boundSessionId = boundSessionId ?? null;
    this._workspaceRoot = workspaceRoot;
    this._panel = panel;
    const initialData = this._buildDataSync() as Record<string, unknown>;
    let initialDisplay: object = initialData;
    if (this._boundSessionId) {
      const sessions = (initialData.activeSessions as Array<{ sessionId: string }> | undefined) ?? [];
      const my = sessions.find(s => s.sessionId === this._boundSessionId);
      initialDisplay = { ...initialData, activeSessions: my ? [my] : [] };
    }
    this._panel.webview.html = this._getShell(initialDisplay, panel.webview);
    this._initialized = true;
    if (!this._boundSessionId) {
      // Main panel: file system watcher + fast poll
      try {
        const hudWatcher = vscode.workspace.createFileSystemWatcher("**/agentboard.hud-status.json");
        hudWatcher.onDidChange(() => void this._update(), null, this._disposables);
        hudWatcher.onDidCreate(() => void this._update(), null, this._disposables);
        this._disposables.push(hudWatcher);
      } catch { /* watcher failed — poll interval covers it */ }
      this._interval = setInterval(() => void this._update(), 5_000);
    } else {
      // Session panel: 60 s fallback self-refresh (main panel drives it at 5 s via _syncSessionPanels)
      this._interval = setInterval(() => void this._update(), 60_000);
    }
    this._panel.webview.onDidReceiveMessage(
      (msg: { command: string; filePath?: string; sessionRoot?: string; sessionNick?: string }) => {
        handleDashboardMessage(msg, {
          workspaceRoot: this._workspaceRoot,
          update: () => { void this._update(); },
          deleteSessionFile,
          focusSessionTab: (sessionId: string) => {
            const sp = DashboardPanel.sessionPanels.get(sessionId);
            if (sp) try { sp._panel.reveal(undefined, false); } catch { /* disposed */ }
          },
          sessionTerminalMap: this._sessionTerminalMap,
        });
      },
      null, this._disposables
    );
    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
    vscode.window.onDidCloseTerminal(async (closed) => {
      const pid = await closed.processId;
      if (pid && deleteSessionFileByShellPid(pid)) void this._update();
    }, null, this._disposables);
  }

  private _buildDataSync(): object {
    const panel = this;
    return buildDashboardDataSync({
      get workspaceRoot() { return panel._workspaceRoot; },
      setWorkspaceRoot(root: string) { panel._workspaceRoot = root; },
      eventsCache: this._eventsCache,
      streamsCache: this._streamsCache,
      setStreamsCache: (cache) => { this._streamsCache = cache; },
      skillsCache: this._skillsCache,
      setSkillsCache: (cache) => { this._skillsCache = cache; },
      rolesCache: this._rolesCache,
      setRolesCache: (cache) => { this._rolesCache = cache; },
      branchCache: this._branchCache,
      numstatCache: this._numstatCache,
      lineCountCache: this._lineCountCache,
      branchCommittedCache: this._branchCommittedCache,
      rawCodexProcessCache: this._rawCodexProcessCache,
      setRawCodexProcessCache: (cache) => { this._rawCodexProcessCache = cache; },
    });
  }

  private _handleDelegateFile(): void {
    const panel = this;
    handleDelegateFile(this._workspaceRoot, this._sessionTerminalMap, {
      get lastDelegateKey() { return panel._lastDelegateKey; },
      set lastDelegateKey(value: string) { panel._lastDelegateKey = value; },
      get lastDelegateTs() { return panel._lastDelegateTs; },
      set lastDelegateTs(value: number) { panel._lastDelegateTs = value; },
    });
  }

  private async _update(): Promise<void> {
    if (!this._initialized) return;

    this._handleDelegateFile();
    const data = this._buildDataSync() as Record<string, unknown>;

    // HTTP calls for sessions/worktrees: skip entirely when server is consistently absent (backoff)
    let sessions: unknown[] = []; let cpRunning = false;
    const worktrees = data.worktrees as string[];
    if (this._httpFailStreak < 10) {
      const [sRaw, wRaw] = await Promise.all([
        httpGet("http://127.0.0.1:7842/sessions", 200).catch(() => null),
        httpGet("http://127.0.0.1:7842/worktrees", 200).catch(() => null),
      ]);
      const anyHit = sRaw || wRaw;
      if (!anyHit) { this._httpFailStreak++; } else { this._httpFailStreak = 0; }
      try { if (sRaw) { const p = JSON.parse(sRaw); cpRunning = true; sessions = Array.isArray(p) ? p : (p.sessions ?? []); } } catch { /* ok */ }
    } // else: server not running — skip HTTP entirely until extension reloads

    const payload = { ...data, cpRunning, sessions: sessions.length, worktrees };

    // Main panel: sync per-session tabs, then push full data to its own webview.
    // Session-bound panels: push filtered data (only their session) to their webview.
    const payloadRec = payload as Record<string, unknown>;
    if (!this._boundSessionId) {
      DashboardPanel._syncSessionPanels(payloadRec, this._workspaceRoot);
      // Push filtered data (+ family context) to each open session panel
      const allActiveSess = (payloadRec.activeSessions as Array<{ sessionId: string }> | undefined) ?? [];
      for (const [sid, sp] of DashboardPanel.sessionPanels) {
        const mySession = allActiveSess.find(s => s.sessionId === sid);
        const spPayload = {
          ...payloadRec,
          activeSessions: mySession ? [mySession] : [],
          isSessionTab: true,
          sessionTabSiblings: allActiveSess,
        };
        if (!DashboardPanel._bootstrappedPanels.has(sid)) {
          // First push in this extension run — set HTML to ensure fresh JS is loaded
          sp._panel.webview.html = sp._getShell(spPayload, sp._panel.webview);
          DashboardPanel._bootstrappedPanels.add(sid);
        } else {
          void sp._panel.webview.postMessage(spPayload);
        }
      }
    }

    let postPayload: object = payload;
    if (this._boundSessionId) {
      const activeSess = (payloadRec.activeSessions as Array<{ sessionId: string }> | undefined) ?? [];
      const mySession = activeSess.find(s => s.sessionId === this._boundSessionId);
      postPayload = {
        ...payloadRec,
        activeSessions: mySession ? [mySession] : [],
        isSessionTab: true,
        sessionTabSiblings: activeSess,
      };
    }

    const delivered = await this._panel.webview.postMessage(postPayload);
    if (!delivered) {
      this._panel.webview.html = this._getShell(postPayload, this._panel.webview);
    }
  }

  private _getShell(data?: object, webview?: vscode.Webview): string { // eslint-disable-line
    return getDashboardShell(data, webview, DashboardPanel.extensionUri);
  }

  dispose(): void {
    if (this._interval) clearInterval(this._interval);
    if (this._boundSessionId) {
      DashboardPanel.sessionPanels.delete(this._boundSessionId);
      DashboardPanel._bootstrappedPanels.delete(this._boundSessionId);
    } else {
      DashboardPanel.currentPanel = undefined;
    }
    this._panel.dispose();
    for (const d of this._disposables) d.dispose();
    this._disposables = [];
  }
}
