"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DashboardPanel = void 0;
const vscode = require("vscode");
const http = require("http");
const child_process_1 = require("child_process");
const dataBuilder_1 = require("./dashboard/dataBuilder");
const delegateFile_1 = require("./dashboard/delegateFile");
const messageRouter_1 = require("./dashboard/messageRouter");
const renderFingerprint_1 = require("./dashboard/renderFingerprint");
const sessionFiles_1 = require("./dashboard/sessionFiles");
const shell_1 = require("./dashboard/shell");
function httpGet(url, ms) {
    return new Promise((resolve, reject) => {
        const req = http.get(url, (res) => {
            let d = "";
            res.on("data", (c) => { d += c.toString(); });
            res.on("end", () => resolve(d));
        });
        req.setTimeout(ms, () => { req.destroy(); reject(new Error("t")); });
        req.on("error", reject);
    });
}
class DashboardPanel {
    static createOrShow(workspaceRoot, extensionUri) {
        if (extensionUri)
            DashboardPanel.extensionUri = extensionUri;
        const col = vscode.window.activeTextEditor?.viewColumn ?? vscode.ViewColumn.One;
        if (DashboardPanel.currentPanel) {
            try {
                DashboardPanel.currentPanel._panel.reveal(col);
            }
            catch { /* panel may be disposed */ }
            return;
        }
        const panel = vscode.window.createWebviewPanel("agentboardDashboard", "Agentboard", col, {
            enableScripts: true,
            retainContextWhenHidden: true,
            localResourceRoots: extensionUri ? [vscode.Uri.joinPath(extensionUri, "media")] : [],
        });
        try {
            DashboardPanel.currentPanel = new DashboardPanel(panel, workspaceRoot);
        }
        catch (err) {
            panel.dispose();
            console.error("[agentboard] DashboardPanel constructor failed:", err);
        }
    }
    // Called by extension poll — updates the workspace root and pushes new data to webview
    static forceUpdate(workspaceRoot) {
        if (!DashboardPanel.currentPanel)
            return;
        DashboardPanel.currentPanel._workspaceRoot = workspaceRoot;
        void DashboardPanel.currentPanel._update();
    }
    static refresh() {
        if (DashboardPanel.currentPanel)
            void DashboardPanel.currentPanel._update();
    }
    // Open (or reveal) a per-session tab for the given session.
    static openSession(sessionId, nick, workspaceRoot) {
        if (this.sessionPanels.has(sessionId)) {
            try {
                this.sessionPanels.get(sessionId)._panel.reveal(undefined, true);
            }
            catch { /* disposed */ }
            return;
        }
        if (!this.extensionUri)
            return;
        const panel = vscode.window.createWebviewPanel("agentboardSession", nick || sessionId.slice(0, 8), { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true }, {
            enableScripts: true,
            retainContextWhenHidden: true,
            localResourceRoots: [vscode.Uri.joinPath(this.extensionUri, "media")],
        });
        try {
            const instance = new DashboardPanel(panel, workspaceRoot, sessionId);
            this.sessionPanels.set(sessionId, instance);
        }
        catch (err) {
            panel.dispose();
            console.error("[agentboard] SessionPanel constructor failed:", err);
        }
    }
    // Called by the main panel on each update cycle to sync session tabs.
    static _syncSessionPanels(payload, workspaceRoot) {
        const sessions = payload.activeSessions ?? [];
        const activeIds = new Set(sessions.map(s => s.sessionId));
        // Open new tabs for newly detected sessions
        for (const sess of sessions) {
            if (!this.sessionPanels.has(sess.sessionId)) {
                this.openSession(sess.sessionId, sess.nick || sess.sessionId.slice(0, 8), workspaceRoot);
            }
            else {
                // Update title if nick changed and session still active
                const p = this.sessionPanels.get(sess.sessionId);
                const title = sess.nick || sess.sessionId.slice(0, 8);
                if (!p._panel.title.endsWith(" ✓") && p._panel.title !== title)
                    p._panel.title = title;
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
    constructor(panel, workspaceRoot, boundSessionId) {
        this._disposables = [];
        this._initialized = false;
        this._eventsCache = new Map();
        this._streamsCache = null;
        this._skillsCache = null;
        this._rolesCache = null;
        this._branchCache = { value: "", ts: 0 };
        this._numstatCache = new Map();
        this._lineCountCache = new Map();
        this._branchCommittedCache = new Map();
        this._rawCodexProcessCache = { ts: 0, processes: [] };
        this._localBranchesCache = { ts: 0, branches: [] };
        this._worktreeBranchCache = new Map();
        this._httpFailStreak = 0;
        this._boundSessionId = null;
        this._lastDelegateKey = ""; // "<role>|<task>" dedup
        this._lastDelegateTs = 0; // epoch ms of last handled delegate
        this._lastRenderFingerprint = "";
        // nick → terminal name cache so focusTerminal can match by session nick
        this._sessionTerminalMap = new Map(); // nick → terminal.name
        this._boundSessionId = boundSessionId ?? null;
        this._workspaceRoot = workspaceRoot;
        this._panel = panel;
        // Pre-populate branch cache synchronously so the very first render uses the
        // real git branch, not whatever stale value the HUD file has.
        try {
            const b = (0, child_process_1.execSync)("git rev-parse --abbrev-ref HEAD", { cwd: workspaceRoot, timeout: 800 }).toString().trim();
            if (b)
                this._branchCache = { value: b, ts: Date.now() };
        }
        catch { /* git unavailable — async poll will fill it in */ }
        const initialData = this._buildDataSync();
        let initialDisplay = initialData;
        if (this._boundSessionId) {
            const sessions = initialData.activeSessions ?? [];
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
            }
            catch { /* watcher failed — poll interval covers it */ }
            this._interval = setInterval(() => void this._update(), 5000);
        }
        else {
            // Session panel: 60 s fallback self-refresh (main panel drives it at 5 s via _syncSessionPanels)
            this._interval = setInterval(() => void this._update(), 60000);
        }
        this._panel.webview.onDidReceiveMessage((msg) => {
            (0, messageRouter_1.handleDashboardMessage)(msg, {
                workspaceRoot: this._workspaceRoot,
                update: () => { void this._update(); },
                deleteSessionFile: (sessionId) => (0, sessionFiles_1.deleteSessionFile)(this._workspaceRoot, sessionId),
                focusSessionTab: (sessionId) => {
                    const sp = DashboardPanel.sessionPanels.get(sessionId);
                    if (sp)
                        try {
                            sp._panel.reveal(undefined, false);
                        }
                        catch { /* disposed */ }
                },
                sessionTerminalMap: this._sessionTerminalMap,
            });
        }, null, this._disposables);
        this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
        vscode.window.onDidCloseTerminal(async (closed) => {
            const pid = await closed.processId;
            if (pid && (0, sessionFiles_1.deleteSessionFileByShellPid)(this._workspaceRoot, pid))
                void this._update();
        }, null, this._disposables);
    }
    _buildDataSync() {
        const panel = this;
        return (0, dataBuilder_1.buildDashboardDataSync)({
            get workspaceRoot() { return panel._workspaceRoot; },
            setWorkspaceRoot(root) { panel._workspaceRoot = root; },
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
            localBranchesCache: this._localBranchesCache,
            worktreeBranchCache: this._worktreeBranchCache,
        });
    }
    _handleDelegateFile() {
        const panel = this;
        (0, delegateFile_1.handleDelegateFile)(this._workspaceRoot, this._sessionTerminalMap, {
            get lastDelegateKey() { return panel._lastDelegateKey; },
            set lastDelegateKey(value) { panel._lastDelegateKey = value; },
            get lastDelegateTs() { return panel._lastDelegateTs; },
            set lastDelegateTs(value) { panel._lastDelegateTs = value; },
        });
    }
    async _update() {
        if (!this._initialized)
            return;
        this._handleDelegateFile();
        const data = this._buildDataSync();
        // HTTP calls for sessions/worktrees: skip entirely when server is consistently absent (backoff)
        let sessions = [];
        let cpRunning = false;
        const worktrees = data.worktrees;
        if (this._httpFailStreak < 10) {
            const [sRaw, wRaw] = await Promise.all([
                httpGet("http://127.0.0.1:7842/sessions", 200).catch(() => null),
                httpGet("http://127.0.0.1:7842/worktrees", 200).catch(() => null),
            ]);
            const anyHit = sRaw || wRaw;
            if (!anyHit) {
                this._httpFailStreak++;
            }
            else {
                this._httpFailStreak = 0;
            }
            try {
                if (sRaw) {
                    const p = JSON.parse(sRaw);
                    cpRunning = true;
                    sessions = Array.isArray(p) ? p : (p.sessions ?? []);
                }
            }
            catch { /* ok */ }
        } // else: server not running — skip HTTP entirely until extension reloads
        const payload = { ...data, cpRunning, sessions: sessions.length, worktrees };
        // Main panel: sync per-session tabs, then push full data to its own webview.
        // Session-bound panels: push filtered data (only their session) to their webview.
        const payloadRec = payload;
        if (!this._boundSessionId) {
            DashboardPanel._syncSessionPanels(payloadRec, this._workspaceRoot);
            // Push filtered data (+ family context) to each open session panel
            const allActiveSess = payloadRec.activeSessions ?? [];
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
                    sp._lastRenderFingerprint = (0, renderFingerprint_1.dashboardRenderFingerprint)(spPayload);
                    DashboardPanel._bootstrappedPanels.add(sid);
                }
                else {
                    void sp._postPayloadIfChanged(spPayload);
                }
            }
        }
        let postPayload = payload;
        if (this._boundSessionId) {
            const activeSess = payloadRec.activeSessions ?? [];
            const mySession = activeSess.find(s => s.sessionId === this._boundSessionId);
            postPayload = {
                ...payloadRec,
                activeSessions: mySession ? [mySession] : [],
                isSessionTab: true,
                sessionTabSiblings: activeSess,
            };
        }
        await this._postPayloadIfChanged(postPayload);
    }
    async _postPayloadIfChanged(postPayload) {
        const fingerprint = (0, renderFingerprint_1.dashboardRenderFingerprint)(postPayload);
        if (fingerprint === this._lastRenderFingerprint)
            return;
        this._lastRenderFingerprint = fingerprint;
        const delivered = await this._panel.webview.postMessage(postPayload);
        if (!delivered) {
            this._panel.webview.html = this._getShell(postPayload, this._panel.webview);
        }
    }
    _getShell(data, webview) {
        return (0, shell_1.getDashboardShell)(data, webview, DashboardPanel.extensionUri);
    }
    dispose() {
        if (this._interval)
            clearInterval(this._interval);
        if (this._boundSessionId) {
            DashboardPanel.sessionPanels.delete(this._boundSessionId);
            DashboardPanel._bootstrappedPanels.delete(this._boundSessionId);
        }
        else {
            DashboardPanel.currentPanel = undefined;
        }
        this._panel.dispose();
        for (const d of this._disposables)
            d.dispose();
        this._disposables = [];
    }
}
exports.DashboardPanel = DashboardPanel;
DashboardPanel.sessionPanels = new Map();
DashboardPanel._bootstrappedPanels = new Set();
