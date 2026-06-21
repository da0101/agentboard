"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DashboardPanel = void 0;
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");
const http = require("http");
const child_process_1 = require("child_process");
const AB_CLI_COMMANDS = [
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
function parseFrontmatter(content) {
    const m = content.match(/^---\n([\s\S]*?)\n---/);
    if (!m)
        return {};
    const r = {};
    for (const line of m[1].split("\n")) {
        const i = line.indexOf(":");
        if (i === -1)
            continue;
        r[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, "");
    }
    return r;
}
function readStreams(root) {
    const dir = path.join(root, ".platform", "work");
    const skip = new Set(["BRIEF.md", "TEMPLATE.md", "Status.md", "ACTIVE.md"]);
    try {
        return fs.readdirSync(dir).filter(f => f.endsWith(".md") && !skip.has(f)).flatMap(f => {
            try {
                const filePath = path.join(dir, f);
                const c = fs.readFileSync(filePath, "utf8");
                const fm = parseFrontmatter(c);
                const st = (fm.status ?? "").toLowerCase();
                if (["done", "archived", "closed"].includes(st))
                    return [];
                const body = c.replace(/^---[\s\S]*?---\n?/, "");
                const section = (headers) => {
                    const pat = new RegExp(`##+ (?:${headers.join("|")})\\s*\\n([\\s\\S]*?)(?=\\n##|$)`, "i");
                    return body.match(pat)?.[1]?.trim() ?? "";
                };
                const objective = fm.objective ?? section(["objective", "goal", "description", "what", "summary"]);
                const nextAction = fm.next_action ?? section(["next.?action", "next.?step", "now", "current"]);
                const progressRaw = section(["progress", "log", "notes", "session.?log"]);
                // parse done criteria checklist
                const criteriaBlock = section(["done.?criteria", "done", "acceptance", "checklist", "exit.?criteria"]);
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
            }
            catch {
                return [];
            }
        });
    }
    catch {
        return [];
    }
}
// Extract readable prose from a markdown body — skip headings, blockquotes, code fences, ANSI lines.
// Returns up to `maxChars` of the first substantive paragraph found.
function extractProse(body, maxChars = 600) {
    const lines = body.split("\n");
    const prose = [];
    let inCode = false;
    for (const raw of lines) {
        const l = raw.trim();
        if (l.startsWith("```")) {
            inCode = !inCode;
            continue;
        }
        if (inCode)
            continue;
        if (!l || l.startsWith("#") || l.startsWith(">") || l.startsWith("\\033") || l.includes("\x1b["))
            continue;
        // Section boundary — stop at first blank line after we've collected prose
        if (!l && prose.length)
            break;
        if (l)
            prose.push(l);
    }
    return prose.join(" ").slice(0, maxChars).trim();
}
function readSkills(root) {
    const dir = path.join(root, ".claude", "skills");
    try {
        return fs.readdirSync(dir).flatMap(name => {
            try {
                const content = fs.readFileSync(path.join(dir, name, "SKILL.md"), "utf8");
                const fm = parseFrontmatter(content);
                const afterFm = content.replace(/^---[\s\S]*?---\n?/, '').trim();
                const fullDescription = extractProse(afterFm);
                return [{ name: fm.name ?? name, slug: name, description: fm.description ?? '', fullDescription }];
            }
            catch {
                return [{ name, slug: name, description: '' }];
            }
        });
    }
    catch {
        return [];
    }
}
function readRoles(root) {
    const dir = path.join(root, ".platform", "roles");
    try {
        // Parse explicit pairs from INDEX.md: `role-slug`+ab-skill
        const indexPairs = new Map();
        try {
            const indexContent = fs.readFileSync(path.join(dir, "INDEX.md"), "utf8");
            const pairRe = /`([a-z][a-z-]+)`\+([a-z][a-z-]+)/g;
            let m;
            while ((m = pairRe.exec(indexContent)) !== null) {
                const [, roleSlug, skillSlug] = m;
                if (!indexPairs.has(roleSlug))
                    indexPairs.set(roleSlug, []);
                indexPairs.get(roleSlug).push(skillSlug);
            }
        }
        catch { /* no INDEX.md */ }
        return fs.readdirSync(dir).filter(f => f.endsWith(".md") && f !== "INDEX.md").flatMap(f => {
            try {
                const content = fs.readFileSync(path.join(dir, f), "utf8");
                const fm = parseFrontmatter(content);
                const slug = path.basename(f, ".md");
                const afterFm = content.replace(/^---[\s\S]*?---\n?/, '').trim();
                const fullDescription = extractProse(afterFm);
                // Merge INDEX.md pairs with ab-* mentions found in the role file body
                const linked = new Set(indexPairs.get(slug) ?? []);
                const bodyMatches = afterFm.match(/\bab-[a-z][a-z-]+/g) ?? [];
                for (const s of bodyMatches)
                    linked.add(s);
                const linkedSkills = [...linked];
                return [{ name: fm.name ?? fm.slug ?? slug, slug, description: fm.mission ?? fm.description ?? fm.objective ?? '', fullDescription, linkedSkills }];
            }
            catch {
                return [];
            }
        });
    }
    catch {
        return [];
    }
}
function readActiveStream(root) {
    try {
        const brief = fs.readFileSync(path.join(root, ".platform", "work", "BRIEF.md"), "utf8");
        const briefSlug = brief.match(/\*\*Stream file:\*\*\s*`work\/([^`]+)\.md`/)?.[1] ?? "";
        // Validate: brief stream must exist in ACTIVE.md as a non-closed stream
        if (briefSlug) {
            const active = fs.readFileSync(path.join(root, ".platform", "work", "ACTIVE.md"), "utf8");
            const isActive = active.split("\n").some(line => {
                const cols = line.split("|").map(c => c.trim());
                const slug = cols[1];
                const status = cols[4];
                return slug === briefSlug && status && !["done", "archived", "closed"].includes(status);
            });
            if (isActive)
                return briefSlug;
            // Brief is stale — find first active stream in ACTIVE.md
            for (const line of active.split("\n")) {
                const cols = line.split("|").map(c => c.trim());
                const slug = cols[1];
                const status = cols[4];
                if (slug && slug !== "Stream" && !slug.startsWith("-") && status && !["done", "archived", "closed", "", "Status"].includes(status)) {
                    return slug;
                }
            }
        }
    }
    catch { /* ignore */ }
    return "";
}
function readSessionStream(root, sessionId, eventsCache) {
    // 1. TSV lookup (first-write-wins, prevents cross-session contamination)
    try {
        const tsv = fs.readFileSync(path.join(root, ".platform", ".session-streams.tsv"), "utf8");
        for (const line of tsv.trim().split("\n")) {
            const [id, slug] = line.split("\t");
            if (id === sessionId && slug)
                return slug.trim();
        }
    }
    catch { /* no mapping yet */ }
    // 2. Fallback: scan session events for a stream field (catches sessions not yet in TSV)
    if (eventsCache) {
        for (const ev of eventsCache) {
            if (ev.session_id === sessionId && ev.stream) {
                return ev.stream;
            }
        }
    }
    return "";
}
function readStreamRole(root, slug) {
    if (!slug)
        return "";
    try {
        return parseFrontmatter(fs.readFileSync(path.join(root, ".platform", "work", `${slug}.md`), "utf8")).role ?? "";
    }
    catch {
        return "";
    }
}
function readRecentEvents(root, n = 20) {
    try {
        return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
            .trim().split("\n").filter(Boolean).slice(-n).reverse()
            .map(line => { try {
            return JSON.parse(line);
        }
        catch {
            return null;
        } })
            .filter((e) => e !== null);
    }
    catch {
        return [];
    }
}
function readWorkflowTranscriptAgents(root, sessionId) {
    try {
        const projectSlug = root.replace(/\//g, "-");
        const wfBase = path.join(os.homedir(), ".claude", "projects", projectSlug, sessionId, "subagents", "workflows");
        if (!fs.existsSync(wfBase))
            return [];
        const agents = [];
        for (const wfFolder of fs.readdirSync(wfBase)) {
            const wfPath = path.join(wfBase, wfFolder);
            const journalPath = path.join(wfPath, "journal.jsonl");
            if (!fs.existsSync(journalPath))
                continue;
            // If journal hasn't been modified in 5 min, workflow is done — all agents stale
            const journalMtime = fs.statSync(journalPath).mtimeMs;
            const journalStale = (Date.now() - journalMtime) > 5 * 60 * 1000;
            // Journal has: {type:"started",agentId} and {type:"result",agentId,result}
            const journalLines = fs.readFileSync(journalPath, "utf8").trim().split("\n").filter(Boolean);
            const started = new Map();
            const results = new Map(); // agentId → result summary
            for (const line of journalLines) {
                try {
                    const e = JSON.parse(line);
                    if (e.type === "started" && e.agentId)
                        started.set(e.agentId, { agentId: e.agentId });
                    if (e.type === "result" && e.agentId)
                        results.set(e.agentId, (e.result ?? "").slice(0, 200));
                }
                catch { /* bad line */ }
            }
            for (const [agentId] of started) {
                // Stale journal = workflow finished without writing all results; treat as done
                const isDone = results.has(agentId) || journalStale;
                const result = results.get(agentId) ?? "";
                // Read first ~3000 bytes of transcript for task label + model
                let label = "";
                let model = "";
                let currentTool = "";
                let ts = "";
                const transcriptPath = path.join(wfPath, `agent-${agentId}.jsonl`);
                try {
                    if (fs.existsSync(transcriptPath)) {
                        const stat = fs.statSync(transcriptPath);
                        const readLen = Math.min(3000, stat.size);
                        const buf = Buffer.alloc(readLen);
                        const fd = fs.openSync(transcriptPath, "r");
                        try {
                            fs.readSync(fd, buf, 0, readLen, 0);
                        }
                        finally {
                            fs.closeSync(fd);
                        }
                        const chunk = buf.toString("utf8");
                        for (const rawLine of chunk.split("\n")) {
                            if (!rawLine.trim().startsWith("{"))
                                continue;
                            try {
                                const e = JSON.parse(rawLine);
                                if (e.timestamp)
                                    ts = e.timestamp;
                                if (e.type === "user" && e.message?.role === "user" && e.message.content && !label) {
                                    const raw = typeof e.message.content === "string"
                                        ? e.message.content
                                        : (Array.isArray(e.message.content) ? e.message.content.find(c => c.type === "text")?.text ?? "" : "");
                                    // Extract TASK: line if present, else use first non-empty line
                                    const taskMatch = raw.match(/TASK:\s*([^\n]{1,120})/);
                                    label = taskMatch ? taskMatch[1].trim() : raw.split("\n").find(l => l.trim())?.trim().slice(0, 120) ?? "";
                                }
                                if (e.message?.model && !model)
                                    model = fmtModel(e.message.model);
                            }
                            catch { /* skip */ }
                        }
                        // Read last chunk for current tool + model if not found
                        if (!isDone && stat.size > 3000) {
                            const lastLen = Math.min(2000, stat.size);
                            const lastBuf = Buffer.alloc(lastLen);
                            const fd2 = fs.openSync(transcriptPath, "r");
                            try {
                                fs.readSync(fd2, lastBuf, 0, lastLen, stat.size - lastLen);
                            }
                            finally {
                                fs.closeSync(fd2);
                            }
                            for (const rawLine of lastBuf.toString("utf8").split("\n")) {
                                if (!rawLine.trim().startsWith("{"))
                                    continue;
                                try {
                                    const e = JSON.parse(rawLine);
                                    if (e.timestamp)
                                        ts = e.timestamp;
                                    if (e.message?.model)
                                        model = fmtModel(e.message.model);
                                    if (Array.isArray(e.message?.content)) {
                                        const tu = e.message.content.find(c => c.type === "tool_use");
                                        if (tu?.name)
                                            currentTool = tu.name;
                                    }
                                }
                                catch { /* skip */ }
                            }
                        }
                    }
                }
                catch { /* transcript unreadable */ }
                agents.push({ agentId, label: label || `Agent ${agentId.slice(0, 8)}`, model, status: isDone ? "done" : "running", currentTool, ts, result });
            }
        }
        return agents;
    }
    catch {
        return [];
    }
}
function readWorkflowPlan(root) {
    try {
        const raw = fs.readFileSync(path.join(root, "agentboard.workflow-agents.json"), "utf8");
        const d = JSON.parse(raw);
        if (!d || !Array.isArray(d.agents))
            return null;
        // Discard if older than 30 minutes and done
        const ageMs = Date.now() - new Date(d.started_at).getTime();
        if (d.status === "done" && ageMs > 30 * 60 * 1000)
            return null;
        return d;
    }
    catch {
        return null;
    }
}
function lastSkillFromEvents(events) {
    for (const e of events) {
        if (e.tool === "Skill" && e.skill)
            return { skill: e.skill, sessionId: e.session_id ?? "" };
    }
    return { skill: "", sessionId: "" };
}
function relTime(iso) {
    const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (s < 60)
        return `${s}s ago`;
    if (s < 3600)
        return `${Math.floor(s / 60)}m ago`;
    return `${Math.floor(s / 3600)}h ago`;
}
function elapsedStr(s) {
    if (!s)
        return "";
    const d = Math.floor((Date.now() - new Date(s).getTime()) / 1000);
    return `${Math.floor(d / 60)}m ${d % 60}s`;
}
function fmtModel(raw) {
    if (!raw)
        return "";
    return raw.replace(/^claude-/i, "").replace(/-\d{8}$/, "").replace(/-latest$/, "")
        .split("-").filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");
}
const MODEL_NAMES = new Set(["claude", "sonnet", "opus", "haiku", "fable", "gpt", "gemini", "codex"]);
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
    constructor(panel, workspaceRoot) {
        this._disposables = [];
        this._initialized = false;
        // Per-cycle event cache: root → events (reset each build cycle)
        this._eventsCache = new Map();
        // Mtime-gated caches for rarely-changing data
        this._streamsCache = null;
        this._skillsCache = null;
        this._rolesCache = null;
        // Branch cache: avoid spawning git every 10s
        this._branchCache = { value: "", ts: 0 };
        // Numstat cache: avoid blocking the extension host on every tick (30 s TTL per root)
        this._numstatCache = new Map();
        this._lineCountCache = new Map();
        // Branch-committed cache: files changed vs merge-base with develop/main (30 s TTL per root)
        this._branchCommittedCache = new Map();
        // HTTP backoff: slow down if server consistently absent
        this._httpFailStreak = 0;
        this._lastDelegateKey = ""; // "<role>|<task>" dedup
        this._lastDelegateTs = 0; // epoch ms of last handled delegate
        // nick → terminal name cache so focusTerminal can match by session nick
        this._sessionTerminalMap = new Map(); // nick → terminal.name
        this._workspaceRoot = workspaceRoot;
        this._panel = panel;
        const initialData = this._buildDataSync();
        this._panel.webview.html = this._getShell(initialData, panel.webview);
        this._initialized = true;
        // Use broad globs that work regardless of which folder VS Code has open
        try {
            const hudWatcher = vscode.workspace.createFileSystemWatcher("**/agentboard.hud-status.json");
            hudWatcher.onDidChange(() => void this._update(), null, this._disposables);
            hudWatcher.onDidCreate(() => void this._update(), null, this._disposables);
            this._disposables.push(hudWatcher);
        }
        catch { /* watcher failed — poll interval covers it */ }
        this._interval = setInterval(() => void this._update(), 5000);
        this._panel.webview.onDidReceiveMessage((msg) => {
            if (msg.command === "refresh")
                void this._update();
            if (msg.command === "openStream") {
                const fp = String(msg.filePath ?? "");
                const allowed = this._workspaceRoot && fp.startsWith(this._workspaceRoot + path.sep);
                if (allowed && fp.endsWith(".md")) {
                    void vscode.workspace.openTextDocument(fp).then(doc => vscode.window.showTextDocument(doc));
                }
                return;
            }
            if (msg.command === "openDiff") {
                const relPath = msg.filePath ?? "";
                const sessRoot = msg.sessionRoot ?? this._workspaceRoot;
                const isNewFile = msg.isNew ?? false;
                if (!relPath)
                    return;
                // Resolve absolute path — try sessRoot first, then workspaceRoot
                let absPath = path.isAbsolute(relPath) ? relPath : path.join(sessRoot, relPath);
                if (!fs.existsSync(absPath)) {
                    const alt = path.join(this._workspaceRoot, relPath);
                    if (fs.existsSync(alt))
                        absPath = alt;
                }
                const rightUri = vscode.Uri.file(absPath);
                // New/untracked files have no HEAD version — open the file directly
                if (isNewFile || !fs.existsSync(absPath)) {
                    if (fs.existsSync(absPath)) {
                        void vscode.window.showTextDocument(rightUri);
                    }
                    else {
                        void vscode.window.showWarningMessage(`File not found: ${relPath}`);
                    }
                    return;
                }
                // Check if file is tracked by git before attempting diff
                try {
                    const { execSync: _ex } = require("child_process");
                    const status = _ex(`git -C "${sessRoot}" status --porcelain -- "${relPath}" 2>/dev/null`).toString().trim();
                    if (status.startsWith("??")) {
                        // Untracked — no HEAD version, just open the file
                        void vscode.window.showTextDocument(rightUri);
                        return;
                    }
                }
                catch { /* fall through to diff attempt */ }
                const gitUri = rightUri.with({
                    scheme: "git",
                    query: JSON.stringify({ path: absPath, ref: "HEAD" }),
                });
                const fileName = path.basename(absPath);
                void vscode.commands.executeCommand("vscode.diff", gitUri, rightUri, `${fileName}: HEAD ↔ Working Tree`).then(undefined, () => {
                    void vscode.window.showTextDocument(rightUri);
                });
                return;
            }
            if (msg.command === "closeSession") {
                const sessionId = msg.sessionId ?? "";
                if (!sessionId)
                    return;
                this._deleteSessionFile(sessionId);
                void this._update();
                return;
            }
            if (msg.command === "launchRole") {
                const slug = msg.slug ?? "";
                const name = msg.name ?? slug;
                if (!slug)
                    return;
                const terminal = vscode.window.createTerminal({ name: `Claude · ${name}`, cwd: this._workspaceRoot });
                terminal.show();
                const prompt = `Adopt the ${name} role for this session. Read .platform/roles/${slug}.md for your full protocol, mission, and responsibilities. Ask me 2–3 focused intake questions to understand what I need, then begin working.`;
                const escaped = prompt.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/`/g, "\\`");
                terminal.sendText(`claude "${escaped}"`, true);
                return;
            }
            if (msg.command === "copyPath") {
                const relPath = msg.filePath ?? "";
                const sessRoot = msg.sessionRoot ?? this._workspaceRoot;
                if (!relPath)
                    return;
                const absPath = path.isAbsolute(relPath) ? relPath : path.join(sessRoot, relPath);
                void vscode.env.clipboard.writeText(absPath).then(() => {
                    void vscode.window.setStatusBarMessage(`Copied: ${absPath}`, 3000);
                });
                return;
            }
            if (msg.command === "focusTerminal") {
                const root = msg.sessionRoot ?? "";
                const nick = msg.sessionNick ?? "";
                const shellPid = msg.shellPid ?? 0;
                const terminals = [...vscode.window.terminals]; // snapshot — terminals list can change async
                void (async () => {
                    try {
                        const termPids = await Promise.all(terminals.map(t => t.processId));
                        // 1. Exact shell PID match (written by status-bridge hook on every tool call)
                        if (shellPid > 0) {
                            const byPid = terminals.find((_, i) => termPids[i] === shellPid);
                            if (byPid) {
                                byPid.show(true);
                                return;
                            }
                            // PID no longer matches a live terminal — check if it's a child of any terminal
                            // (handles cases where claude wraps inside an extra shell layer)
                            try {
                                const { execSync: _ex } = await Promise.resolve().then(() => require("child_process"));
                                for (let i = 0; i < termPids.length; i++) {
                                    const tpid = termPids[i];
                                    if (!tpid)
                                        continue;
                                    // Get all descendants of this terminal's shell
                                    const children = _ex(`/usr/bin/pgrep -P ${tpid} 2>/dev/null || true`).toString().trim().split("\n").filter(Boolean).map(Number);
                                    if (children.includes(shellPid)) {
                                        terminals[i].show(true);
                                        return;
                                    }
                                }
                            }
                            catch { /* fall through */ }
                        }
                        // 2. Nick-based name match — delegate terminals are named "Claude · <role-name>"
                        //    Regular sessions: try matching nick suffix in terminal name
                        const nickLower = nick.toLowerCase();
                        const byName = terminals.find(t => {
                            const n = t.name.toLowerCase();
                            return n.includes(nickLower) || n.endsWith(nick) || n === `claude · ${nickLower}`;
                        });
                        if (byName) {
                            byName.show(true);
                            return;
                        }
                        // 3. shellIntegration CWD match — only when exactly one terminal is in this root
                        if (root) {
                            const cwdMatches = terminals.filter(t => {
                                const cwd = t.shellIntegration?.cwd?.fsPath ?? "";
                                return cwd && cwd.startsWith(root);
                            });
                            if (cwdMatches.length === 1) {
                                cwdMatches[0].show(true);
                                return;
                            }
                        }
                        void vscode.window.showInformationMessage(`⌨ Chat not found for "${nick}". Wait for Claude's next tool call then try again.`);
                    }
                    catch (err) {
                        void vscode.window.showErrorMessage(`focusTerminal error: ${err instanceof Error ? err.message : String(err)}`);
                    }
                })();
                return;
            }
        }, null, this._disposables);
        this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
        vscode.window.onDidCloseTerminal(async (closed) => {
            const pid = await closed.processId;
            if (!pid)
                return;
            const sessDir = path.join(os.homedir(), ".agentboard", "sessions");
            try {
                for (const fname of fs.readdirSync(sessDir)) {
                    if (!fname.endsWith(".json"))
                        continue;
                    try {
                        const raw = fs.readFileSync(path.join(sessDir, fname), "utf8");
                        const d = JSON.parse(raw);
                        if (d._shell_pid === pid) {
                            fs.unlinkSync(path.join(sessDir, fname));
                            void this._update();
                        }
                    }
                    catch { /* skip */ }
                }
            }
            catch { /* dir missing */ }
        }, null, this._disposables);
    }
    _buildDataSync() {
        // Always try live.json first — works regardless of which VS Code window is open
        let hud = null;
        const globalLive = path.join(os.homedir(), ".agentboard", "live.json");
        try {
            const live = JSON.parse(fs.readFileSync(globalLive, "utf8"));
            hud = live;
            // If live.json has a root pointer, use it as the effective project root
            if (live._root && live._root !== this._workspaceRoot) {
                this._workspaceRoot = live._root;
            }
        }
        catch { /* ok — try local hud file */ }
        // Fallback: read hud from workspaceRoot directly
        if (!hud) {
            try {
                hud = JSON.parse(fs.readFileSync(path.join(this._workspaceRoot, "agentboard.hud-status.json"), "utf8"));
            }
            catch { /* ok */ }
        }
        // Branch: prefer HUD (already has it). Fallback: cached value refreshed at most every 30s via async exec.
        const branch = hud?.context?.branch ?? this._branchCache.value;
        if (!hud?.context?.branch && Date.now() - this._branchCache.ts > 30000) {
            this._branchCache.ts = Date.now(); // debounce
            (0, child_process_1.exec)("git rev-parse --abbrev-ref HEAD", { cwd: this._workspaceRoot, timeout: 1500 }, (_err, stdout) => {
                if (stdout)
                    this._branchCache = { value: stdout.trim(), ts: Date.now() };
            });
        }
        const worktrees = []; // removed blocking execSync git worktree — not worth the cost
        const activeStream = readActiveStream(this._workspaceRoot);
        const streamRole = readStreamRole(this._workspaceRoot, activeStream);
        const hudRole = hud?.active_agents?.[0]?.role ?? "";
        const activeRole = (!hudRole || MODEL_NAMES.has(hudRole.toLowerCase().split("-")[0])) ? streamRole : hudRole;
        const ctxPct = hud?.context?.context_remaining_pct ?? null;
        const rawModel = hud?.context?.model ?? hud?.active_agents?.[0]?.model ?? "";
        const model = rawModel ? fmtModel(rawModel) : "";
        const costUsd = hud?.cost?.session_usd ?? null;
        const cost = costUsd !== null ? `$${costUsd.toFixed(3)}` : "";
        const sessionTime = hud?.active_agents?.[0]?.started_at ? elapsedStr(hud.active_agents[0].started_at) : "";
        const hasLive = (hud?.active_agents?.length ?? 0) > 0;
        const currentSessionId = hud?.context?.session_id ?? hud?.active_agents?.[0]?.session_id ?? "";
        // Reset per-cycle event cache
        this._eventsCache.clear();
        // Cached skills/roles (read directory mtime; these files rarely change)
        const skillsDir = path.join(this._workspaceRoot, ".claude", "skills");
        const rolesDir = path.join(this._workspaceRoot, ".platform", "roles");
        const streamsDir = path.join(this._workspaceRoot, ".platform", "work");
        try {
            const mt = fs.statSync(skillsDir).mtimeMs;
            if (!this._skillsCache || mt > this._skillsCache.mtime)
                this._skillsCache = { mtime: mt, data: readSkills(this._workspaceRoot) };
        }
        catch {
            if (!this._skillsCache)
                this._skillsCache = { mtime: 0, data: [] };
        }
        try {
            const mt = fs.statSync(rolesDir).mtimeMs;
            if (!this._rolesCache || mt > this._rolesCache.mtime)
                this._rolesCache = { mtime: mt, data: readRoles(this._workspaceRoot) };
        }
        catch {
            if (!this._rolesCache)
                this._rolesCache = { mtime: 0, data: [] };
        }
        try {
            const mt = fs.statSync(streamsDir).mtimeMs;
            if (!this._streamsCache || mt > this._streamsCache.mtime)
                this._streamsCache = { mtime: mt, data: readStreams(this._workspaceRoot) };
        }
        catch {
            if (!this._streamsCache)
                this._streamsCache = { mtime: 0, data: [] };
        }
        const skills = this._skillsCache.data;
        const roles = this._rolesCache.data;
        // Read events once per root, cache for this cycle
        const getEventsForRoot = (root) => {
            if (this._eventsCache.has(root))
                return this._eventsCache.get(root);
            const evs = readRecentEvents(root, 400);
            this._eventsCache.set(root, evs);
            return evs;
        };
        const allEvents = getEventsForRoot(this._workspaceRoot);
        // lastSkill computed after activeSessions is built so we can filter to active sessions only
        // Filter events to current session only (prevents stale events from previous /clear sessions bleeding through)
        const hasSessionIds = allEvents.some(e => e.session_id);
        const sessionEvents = (hasSessionIds && currentSessionId)
            ? allEvents.filter(e => !e.session_id || e.session_id === currentSessionId)
            : allEvents;
        // Build deduplicated file activity: file → {tool, count, lastTs}
        const fileMap = new Map();
        for (const ev of [...sessionEvents].reverse()) {
            if (!ev.file && !ev.cmd)
                continue;
            const key = ev.file ?? `$ ${(ev.cmd ?? "").slice(0, 60)}`;
            const existing = fileMap.get(key);
            if (!existing || ev.ts > existing.lastTs) {
                fileMap.set(key, { tool: ev.tool, count: (existing?.count ?? 0) + 1, lastTs: ev.ts });
            }
            else {
                fileMap.set(key, { ...existing, count: existing.count + 1 });
            }
        }
        const totalUniqueFiles = fileMap.size;
        const fileActivity = [...fileMap.entries()]
            .sort((a, b) => b[1].lastTs.localeCompare(a[1].lastTs))
            .slice(0, 20)
            .map(([file, info]) => ({ file, ...info }));
        // Stream description from body italic line
        const streamDesc = (() => {
            if (!activeStream)
                return "";
            try {
                const body = fs.readFileSync(path.join(this._workspaceRoot, ".platform", "work", `${activeStream}.md`), "utf8");
                return body.match(/^_([^_]+)_/m)?.[1]?.trim() ?? "";
            }
            catch {
                return "";
            }
        })();
        // Determine last event label for NOW block — use session-filtered events
        const WAIT_TOOLS = new Set(["AskUserQuestion", "AskUser"]);
        // Skip synthetic internal events — only show real user-visible tool calls
        const SYNTHETIC_TOOLS = new Set(["WorkflowStart", "WorkflowEnd", "AgentStart"]);
        const lastNonAgentEvent = sessionEvents.find(e => e.tool !== "Agent" && !SYNTHETIC_TOOLS.has(e.tool)) ?? null;
        const lastEventLabel = lastNonAgentEvent?.file
            ? path.basename(lastNonAgentEvent.file)
            : lastNonAgentEvent?.cmd
                ? lastNonAgentEvent.cmd.slice(0, 50)
                : lastNonAgentEvent?.skill
                    ? `/${lastNonAgentEvent.skill}`
                    : lastNonAgentEvent?.tool ?? "";
        const lastEventTs = lastNonAgentEvent?.ts ?? "";
        const secsSinceLastEvent = lastEventTs ? Math.floor((Date.now() - new Date(lastEventTs).getTime()) / 1000) : null;
        // Suppress "long op" warning when Claude is waiting for user input (AskUserQuestion)
        const isWaitingForUser = lastNonAgentEvent ? WAIT_TOOLS.has(lastNonAgentEvent.tool) : false;
        const isInLongOp = hasLive && !isWaitingForUser && secsSinceLastEvent !== null && secsSinceLastEvent > 90;
        // Detect active Workflow: WorkflowStart within 2h, not ended (or background launch still running)
        let activeWorkflow = null;
        let _wfStartTs = null;
        for (const ev of sessionEvents) {
            const secAgo = Math.floor((Date.now() - new Date(ev.ts).getTime()) / 1000);
            if (ev.tool === "WorkflowStart" && secAgo < 2 * 3600) { // 2h max — older = stale
                _wfStartTs = ev.ts;
                activeWorkflow = {
                    label: ev.label ?? "workflow",
                    agentCount: ev.agent_count ?? 0,
                    ts: ev.ts,
                    sessionId: ev.session_id ?? "",
                };
            }
            else if (ev.tool === "WorkflowEnd") {
                const duration = _wfStartTs ? new Date(ev.ts).getTime() - new Date(_wfStartTs).getTime() : Infinity;
                if (duration > 30000) {
                    activeWorkflow = null; // foreground workflow completed
                }
                else if (_wfStartTs && (Date.now() - new Date(_wfStartTs).getTime()) > 30 * 60 * 1000) {
                    // Background launch but WorkflowStart is >30min old — presume completed
                    activeWorkflow = null;
                }
            }
        }
        const agentMap = new Map();
        for (const ev of sessionEvents) {
            const secAgo = Math.floor((Date.now() - new Date(ev.ts).getTime()) / 1000);
            if (ev.tool === "AgentStart") {
                const key = ev.label ?? ev.ts;
                if (secAgo < 1800)
                    agentMap.set(key, {
                        label: ev.label ?? "agent",
                        role: ev.role ?? "",
                        skill: ev.skill ?? "",
                        ts: ev.ts,
                        done: false,
                    });
            }
            else if (ev.tool === "Agent" && ev.agent) {
                const key = ev.agent ?? "";
                const existing = agentMap.get(key);
                if (existing)
                    agentMap.set(key, { ...existing, done: true });
            }
        }
        const recentAgents = Array.from(agentMap.values()).filter(a => {
            const secAgo = Math.floor((Date.now() - new Date(a.ts).getTime()) / 1000);
            return secAgo < 1800;
        });
        const sessionsDir = path.join(os.homedir(), ".agentboard", "sessions");
        const activeSessions = [];
        try {
            const files = fs.readdirSync(sessionsDir).filter((f) => f.endsWith(".json"));
            for (const f of files) {
                try {
                    const s = JSON.parse(fs.readFileSync(path.join(sessionsDir, f), "utf8"));
                    const lastUpdated = s._last_updated || s.last_updated || "";
                    const ageMs = lastUpdated ? Date.now() - new Date(lastUpdated).getTime() : Infinity;
                    if (ageMs > 30 * 60 * 1000)
                        continue; // 30 min since last status-bridge ping = session is idle
                    const ctx = s.context || {};
                    const agents = s.active_agents || [];
                    const rawModel = ctx.model || agents[0]?.model || "";
                    const costUsd = s.cost?.session_usd ?? 0;
                    const sRoot = s._root || "";
                    const sStartedAt = ctx.started_at || agents[0]?.started_at || "";
                    const sCtxPct = ctx.context_remaining_pct ?? null;
                    const sElapsed = sStartedAt ? (() => {
                        const sec = Math.floor((Date.now() - new Date(sStartedAt).getTime()) / 1000);
                        return sec < 3600 ? `${Math.floor(sec / 60)}m ${sec % 60}s` : `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m`;
                    })() : "";
                    // Per-session activity feed (deduplicated, most recent first)
                    const sActivity = [];
                    const sId = s._session_id || ctx.session_id || f.replace(".json", "");
                    if (sRoot) {
                        const allSEvents = getEventsForRoot(sRoot); // cached — no extra file read
                        // Strict session filter: only events with matching session_id.
                        const hasSessionIds = allSEvents.some(e => e.session_id);
                        const sEvents = hasSessionIds
                            ? allSEvents.filter(e => e.session_id === sId)
                            : allSEvents;
                        const sFileMap = new Map();
                        for (const ev of [...sEvents].reverse()) {
                            if (!ev.file && !ev.cmd)
                                continue;
                            const k = ev.file ?? `$ ${(ev.cmd ?? "").slice(0, 60)}`;
                            const ex = sFileMap.get(k);
                            if (!ex || ev.ts > ex.lastTs)
                                sFileMap.set(k, { tool: ev.tool, count: (ex?.count ?? 0) + 1, lastTs: ev.ts });
                            else
                                sFileMap.set(k, { ...ex, count: ex.count + 1 });
                        }
                        sActivity.push(...[...sFileMap.entries()]
                            .sort((a, b) => b[1].lastTs.localeCompare(a[1].lastTs))
                            .slice(0, 15)
                            .map(([file, info]) => ({ file, ...info })));
                        // Enrich Edit/Write entries with git diff numstat (cached per root, 30 s TTL)
                        try {
                            const NUMSTAT_TTL = 30000;
                            const cached = this._numstatCache.get(sRoot);
                            let diffMap;
                            if (cached && (Date.now() - cached.ts) < NUMSTAT_TTL) {
                                diffMap = cached.diffMap;
                            }
                            else {
                                diffMap = new Map();
                                const numstatOut = (0, child_process_1.execSync)("git diff --numstat HEAD", { cwd: sRoot, timeout: 3000, encoding: "utf8" });
                                for (const line of numstatOut.split("\n")) {
                                    const m = line.match(/^(\d+)\t(\d+)\t(.+)$/);
                                    if (m)
                                        diffMap.set(m[3].trim(), { added: parseInt(m[1], 10), deleted: parseInt(m[2], 10) });
                                }
                                this._numstatCache.set(sRoot, { ts: Date.now(), diffMap });
                            }
                            for (const entry of sActivity) {
                                if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
                                    const stats = diffMap.get(entry.file);
                                    if (stats) {
                                        entry.added = stats.added;
                                        entry.deleted = stats.deleted;
                                    }
                                }
                            }
                        }
                        catch { /* git unavailable or repo not found — skip diff stats */ }
                        // Enrich file entries with current line count (cached, 60 s TTL)
                        const LINE_COUNT_TTL = 60000;
                        for (const entry of sActivity) {
                            if (entry.file.startsWith("$ ") || !sRoot)
                                continue;
                            const absFile = path.join(sRoot, entry.file);
                            try {
                                const cached = this._lineCountCache.get(absFile);
                                if (cached && (Date.now() - cached.ts) < LINE_COUNT_TTL) {
                                    entry.lineCount = cached.count;
                                }
                                else {
                                    const lines = fs.readFileSync(absFile, "utf8").split("\n").length;
                                    this._lineCountCache.set(absFile, { ts: Date.now(), count: lines });
                                    entry.lineCount = lines;
                                }
                            }
                            catch { /* file may not exist yet */ }
                        }
                        // Mark files that have committed changes on this branch vs develop/main merge-base
                        try {
                            const COMMITTED_TTL = 30000;
                            const cacheKey = sRoot;
                            const cachedC = this._branchCommittedCache.get(cacheKey);
                            let committedFiles;
                            if (cachedC && (Date.now() - cachedC.ts) < COMMITTED_TTL) {
                                committedFiles = cachedC.files;
                            }
                            else {
                                committedFiles = new Set();
                                // Find merge-base with develop, then main, then fall back to HEAD~1
                                let mergeBase = "";
                                for (const base of ["origin/develop", "origin/main", "HEAD~1"]) {
                                    try {
                                        mergeBase = (0, child_process_1.execSync)(`git merge-base HEAD ${base}`, { cwd: sRoot, timeout: 3000, encoding: "utf8" }).trim();
                                        if (mergeBase)
                                            break;
                                    }
                                    catch { /* try next */ }
                                }
                                if (mergeBase) {
                                    const nameOnly = (0, child_process_1.execSync)(`git diff --name-only ${mergeBase}..HEAD`, { cwd: sRoot, timeout: 3000, encoding: "utf8" });
                                    for (const line of nameOnly.split("\n")) {
                                        const f2 = line.trim();
                                        if (f2)
                                            committedFiles.add(f2);
                                    }
                                }
                                this._branchCommittedCache.set(cacheKey, { ts: Date.now(), files: committedFiles });
                            }
                            for (const entry of sActivity) {
                                if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
                                    entry.committed = committedFiles.has(entry.file);
                                }
                            }
                        }
                        catch { /* git unavailable */ }
                    }
                    // Detect new/deleted files via git status --porcelain
                    if (sRoot) {
                        try {
                            const statusOut = (0, child_process_1.execSync)(`git -C "${sRoot}" status --porcelain 2>/dev/null`, { timeout: 3000, encoding: "utf8" });
                            const statusMap = new Map();
                            for (const line of statusOut.split("\n")) {
                                if (line.length < 4)
                                    continue;
                                const xy = line.slice(0, 2);
                                const fpath = line.slice(3).trim().replace(/^"(.*)"$/, "$1"); // git quotes paths with spaces
                                statusMap.set(fpath, xy);
                            }
                            for (const entry of sActivity) {
                                const xy = statusMap.get(entry.file) ?? statusMap.get(entry.file.replace(/\\/g, "/")) ?? "";
                                if (xy === "??" || xy[0] === "A" || xy[1] === "A")
                                    entry.isNew = true;
                                else if (xy[0] === "D" || xy[1] === "D")
                                    entry.isDeleted = true;
                            }
                        }
                        catch { /* git unavailable */ }
                    }
                    // Skip ghost sessions: no tool events AND session started >15 min ago
                    // Use startedAt age (not lastUpdated) so status-bridge pings don't keep ghosts alive
                    const startedAtAgeMs = sStartedAt ? Date.now() - new Date(sStartedAt).getTime() : Infinity;
                    if (sActivity.length === 0 && startedAtAgeMs > 15 * 60 * 1000)
                        continue;
                    // Per-session agents from AgentStart events — full session history, no time cap
                    const sAgentMap = new Map();
                    if (sRoot) {
                        const sAllEvents = getEventsForRoot(sRoot);
                        for (const ev of sAllEvents) {
                            if (!ev.session_id || ev.session_id !== sId)
                                continue;
                            if (ev.tool === "AgentStart") {
                                const key = ev.label ?? ev.ts;
                                sAgentMap.set(key, {
                                    label: ev.label ?? "agent",
                                    role: ev.role ?? "",
                                    skill: ev.skill ?? "",
                                    ts: ev.ts, done: false,
                                });
                            }
                            else if (ev.tool === "Agent" && ev.agent) {
                                const k = ev.agent ?? "";
                                const ex = sAgentMap.get(k);
                                if (ex)
                                    sAgentMap.set(k, { ...ex, done: true });
                            }
                        }
                    }
                    // Sort newest-first, cap at 50.
                    // Two-tier staleness:
                    // 1. Session idle >10 min → all pending agents are stale (session is dead/paused)
                    // 2. Per-agent: started >30 min ago with no completion → stale regardless of session state.
                    //    Workflow sub-agents never fire PostToolUse in the main session, so they'd stay
                    //    "running" forever. 30 min is a safe upper bound for any real agent task.
                    const sessionIdleMs = ageMs; // ageMs = Date.now() - new Date(lastUpdated)
                    const sessionIsIdle = sessionIdleMs > 10 * 60 * 1000;
                    const AGENT_STALE_MS = 30 * 60 * 1000; // 30 min per-agent timeout
                    const sAgents = Array.from(sAgentMap.values())
                        .map(a => {
                        if (a.done)
                            return a;
                        if (sessionIsIdle)
                            return { ...a, done: true };
                        const agentAgeMs = a.ts ? Date.now() - new Date(a.ts).getTime() : Infinity;
                        if (agentAgeMs > AGENT_STALE_MS)
                            return { ...a, done: true };
                        return a;
                    })
                        .sort((a, b) => b.ts.localeCompare(a.ts))
                        .slice(0, 50);
                    // Detect if THIS session has an active workflow.
                    // Events are newest-first; WorkflowStart/End pairs must be walked chronologically.
                    // Collect wf events for this session, then reverse to get oldest-first.
                    let sHasWorkflow = false;
                    let sWorkflowAgentCount = 0;
                    let sWorkflowLabel = "";
                    let sWfStartTs = null;
                    if (sRoot) {
                        const wfEvs = getEventsForRoot(sRoot)
                            .filter(ev => ev.session_id === sId && (ev.tool === "WorkflowStart" || ev.tool === "WorkflowEnd"))
                            .reverse(); // now chronological (oldest first)
                        for (const ev of wfEvs) {
                            if (ev.tool === "WorkflowStart") {
                                sWfStartTs = ev.ts;
                                sHasWorkflow = true;
                                sWorkflowAgentCount = ev.agent_count ?? 0;
                                sWorkflowLabel = ev.label ?? "workflow";
                            }
                            else if (ev.tool === "WorkflowEnd" && sWfStartTs) {
                                const dur = new Date(ev.ts).getTime() - new Date(sWfStartTs).getTime();
                                if (dur > 30000) {
                                    sHasWorkflow = false;
                                    sWorkflowAgentCount = 0;
                                    sWorkflowLabel = "";
                                }
                                // background launch (dur < 30s): keep sHasWorkflow = true
                            }
                        }
                    }
                    // Read transcript agents — always do it when we might have a workflow (events can be old)
                    // and use transcript to authoritatively determine if any agents are still running.
                    const transcriptAgents = sRoot ? readWorkflowTranscriptAgents(sRoot, sId) : [];
                    const hasRunningTranscriptAgent = transcriptAgents.some(a => a.status === "running");
                    // Override: if transcript shows running agents, workflow IS active even if events say otherwise
                    if (hasRunningTranscriptAgent) {
                        sHasWorkflow = true;
                    }
                    // Override: if workflow was background (no foreground WorkflowEnd) and ALL transcript agents are done, hide badge
                    if (sHasWorkflow && transcriptAgents.length > 0 && !hasRunningTranscriptAgent) {
                        sHasWorkflow = false;
                    }
                    activeSessions.push({
                        sessionId: s._session_id || ctx.session_id || f.replace(".json", ""),
                        model: rawModel ? fmtModel(rawModel) : "",
                        costUsd,
                        cost: costUsd > 0 ? `$${costUsd.toFixed(3)}` : "",
                        branch: ctx.branch || "",
                        root: sRoot,
                        shellPid: s._shell_pid || 0,
                        projectName: sRoot ? path.basename(sRoot) : "",
                        sessionLastSkill: "", sessionLastRole: "",
                        startedAt: sStartedAt,
                        lastUpdated,
                        ageSeconds: Math.floor(ageMs / 1000),
                        ctxPct: sCtxPct,
                        stream: sRoot ? readSessionStream(sRoot, sId, getEventsForRoot(sRoot)) : "",
                        sessionTime: sElapsed,
                        activity: sActivity,
                        agents: sAgents,
                        hasWorkflow: sHasWorkflow,
                        workflowAgentCount: sWorkflowAgentCount,
                        workflowLabel: sWorkflowLabel,
                        workflowTranscriptAgents: transcriptAgents,
                        workflowPlan: sRoot ? readWorkflowPlan(sRoot) : null,
                    });
                }
                catch { /* skip malformed file */ }
            }
            activeSessions.sort((a, b) => a.startedAt.localeCompare(b.startedAt));
            // Deduplicate ONLY for /clear — same (root, branch) where the new session started
            // within 2 minutes of the old session's last update (instant restart = /clear).
            // Two real parallel sessions have a longer gap and must stay separate.
            const slotMap = new Map();
            for (const s of activeSessions) {
                const slotKey = `${s.root}::${s.branch || s.sessionId}`;
                const existing = slotMap.get(slotKey);
                if (!existing) {
                    slotMap.set(slotKey, s);
                }
                else {
                    const older = existing.startedAt < s.startedAt ? existing : s;
                    const newer = existing.startedAt < s.startedAt ? s : existing;
                    const gapMs = new Date(newer.startedAt).getTime() - new Date(older.lastUpdated).getTime();
                    // /clear: old session stopped (lastUpdated < newer.startedAt) AND the gap is tiny
                    // Parallel sessions: older.lastUpdated > newer.startedAt → gapMs negative → keep both
                    if (gapMs >= 0 && gapMs < 2 * 60 * 1000) {
                        // Small positive gap → /clear scenario — keep only newer session
                        slotMap.set(slotKey, newer);
                    }
                    else {
                        // Two real parallel sessions → keep both under unique keys
                        slotMap.delete(slotKey);
                        slotMap.set(`${slotKey}::${older.sessionId}`, older);
                        slotMap.set(`${slotKey}::${newer.sessionId}`, newer);
                    }
                }
            }
            activeSessions.length = 0;
            activeSessions.push(...Array.from(slotMap.values()).sort((a, b) => a.startedAt.localeCompare(b.startedAt)));
        }
        catch { /* sessions dir doesn't exist yet */ }
        // lastSkill: only from currently active sessions (avoids stale closed-session data in footer)
        const activeSessionIds = new Set(activeSessions.map(s => s.sessionId));
        function sessionNick(id) {
            const ADJ = ['bold', 'calm', 'swift', 'bright', 'sharp', 'keen', 'wild', 'quiet', 'brave', 'cool', 'warm', 'soft', 'fast', 'wise', 'pure', 'deft', 'lean', 'sage', 'red', 'blue', 'gold', 'jade', 'iron', 'amber', 'violet', 'azure', 'coral', 'frost', 'storm', 'sand', 'ember', 'cedar', 'steel', 'nova', 'oak', 'ivy', 'clay', 'moss', 'dawn', 'rust'];
            const NON = ['falcon', 'tiger', 'wolf', 'eagle', 'raven', 'fox', 'bear', 'hawk', 'lynx', 'crane', 'otter', 'pike', 'heron', 'wren', 'viper', 'bison', 'moose', 'ibis', 'kite', 'wasp', 'colt', 'finch', 'puma', 'cobra', 'gecko', 'quail', 'trout', 'mink', 'stork', 'stoat', 'dingo', 'snipe', 'marten', 'condor', 'osprey', 'ferret', 'oriole', 'magpie', 'jaguar', 'marlin'];
            let h = 0;
            for (let i = 0; i < id.length; i++)
                h = (Math.imul(h, 31) + id.charCodeAt(i)) >>> 0;
            return ADJ[h % ADJ.length] + '-' + NON[(h >>> 8) % NON.length];
        }
        const activeEventsForSkill = allEvents.filter(e => !e.session_id || activeSessionIds.has(e.session_id));
        const { skill: lastSkill, sessionId: lastSkillSessionId } = lastSkillFromEvents(activeEventsForSkill);
        const lastSkillSession = (lastSkillSessionId && activeSessionIds.has(lastSkillSessionId)) ? sessionNick(lastSkillSessionId) : "";
        const skillUsage = new Map();
        const roleUsage = new Map();
        const sessionLastSkillMap = new Map();
        const sessionLastRoleMap = new Map();
        for (const sess of activeSessions) {
            if (!sess.root)
                continue;
            const evs = getEventsForRoot(sess.root).filter(e => e.session_id === sess.sessionId);
            const nick = sessionNick(sess.sessionId);
            for (const ev of evs) {
                if (ev.tool === 'Skill' && ev.skill) {
                    const sk = ev.skill;
                    if (!skillUsage.has(sk))
                        skillUsage.set(sk, []);
                    if (!skillUsage.get(sk).includes(nick))
                        skillUsage.get(sk).push(nick);
                    sessionLastSkillMap.set(sess.sessionId, sk); // last wins = most recent
                }
                // RoleAdopt: main session read a role file — slug-keyed
                if (ev.tool === 'RoleAdopt' && ev.role) {
                    const ro = ev.role;
                    if (!roleUsage.has(ro))
                        roleUsage.set(ro, []);
                    if (!roleUsage.get(ro).includes(nick))
                        roleUsage.get(ro).push(nick);
                    sessionLastRoleMap.set(sess.sessionId, ro);
                }
                // AgentStart with role label (sub-agents dispatched with role:<name>)
                if (ev.tool === 'AgentStart' && ev.role) {
                    const ro = ev.role;
                    if (!roleUsage.has(ro))
                        roleUsage.set(ro, []);
                    if (!roleUsage.get(ro).includes(nick))
                        roleUsage.get(ro).push(nick);
                    if (!sessionLastRoleMap.has(sess.sessionId))
                        sessionLastRoleMap.set(sess.sessionId, ro);
                }
            }
            sess.sessionLastSkill = sessionLastSkillMap.get(sess.sessionId) ?? "";
            sess.sessionLastRole = sessionLastRoleMap.get(sess.sessionId) ?? "";
        }
        const skillsWithUsage = skills.map(s => ({ ...s, usedBy: skillUsage.get(s.name) ?? skillUsage.get(s.slug ?? '') ?? [] }));
        // Match roles by slug first (RoleAdopt events use slug), then display name (AgentStart labels)
        const rolesWithUsage = roles.map(r => {
            const bySlug = r.slug ? (roleUsage.get(r.slug) ?? []) : [];
            const byName = roleUsage.get(r.name) ?? [];
            const merged = [...new Set([...bySlug, ...byName])];
            return { ...r, usedBy: merged };
        });
        return {
            type: "update",
            hasLive, model, cost, sessionTime, activeStream, streamDesc, activeRole, lastSkill, lastSkillSession,
            ctxPct, branch, cpRunning: false, sessions: 0, totalUniqueFiles,
            activeSessions,
            activeWorkflow,
            streams: this._streamsCache?.data ?? [],
            fileActivity, recentAgents,
            lastEventLabel, lastEventTs, isInLongOp,
            worktrees,
            skillCount: skills.length, roleCount: roles.length,
            skills: skillsWithUsage, roles: rolesWithUsage,
            commands: AB_CLI_COMMANDS,
            projectName: path.basename(this._workspaceRoot),
        };
    }
    _handleDelegateFile() {
        const delegateFile = path.join(os.homedir(), ".agentboard", "delegate.json");
        if (!fs.existsSync(delegateFile))
            return;
        let raw;
        try {
            raw = fs.readFileSync(delegateFile, "utf8");
            fs.unlinkSync(delegateFile); // delete first — prevent duplicate opens on next tick
        }
        catch {
            return;
        }
        try {
            const d = JSON.parse(raw);
            if (!d.role || !d.task)
                return;
            // Dedup: ignore if same role+task was already handled within 60 seconds
            const dedupeKey = `${d.role}|${d.task}`;
            if (dedupeKey === this._lastDelegateKey && (Date.now() - this._lastDelegateTs) < 60000)
                return;
            this._lastDelegateKey = dedupeKey;
            this._lastDelegateTs = Date.now();
            const roles = readRoles(d.root ?? this._workspaceRoot);
            const roleItem = roles.find(r => r.slug === d.role);
            const roleName = roleItem?.name ?? d.role;
            const lines = [
                `Adopt the ${roleName} role for this session.`,
                `Read .platform/roles/${d.role}.md for your full protocol, mission, and responsibilities.`,
            ];
            if (d.project || d.branch) {
                const from = [d.project, d.branch ? `branch: ${d.branch}` : ""].filter(Boolean).join(" — ");
                lines.push(`\nHandoff from: ${from}`);
            }
            if (d.context)
                lines.push(d.context);
            lines.push(`\nYour task: ${d.task}`);
            lines.push(`\nAsk me 2–3 focused intake questions if anything needs clarification, then begin.`);
            const prompt = lines.join("\n");
            const escaped = prompt.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/`/g, "\\`");
            const cwd = d.root && fs.existsSync(d.root) ? d.root : this._workspaceRoot;
            const termName = `Claude · ${roleName}`;
            const terminal = vscode.window.createTerminal({ name: termName, cwd });
            terminal.show();
            terminal.sendText(`claude "${escaped}"`, true);
            this._sessionTerminalMap.set(d.role, termName);
        }
        catch { /* malformed delegate.json — silently ignore */ }
    }
    _deleteSessionFile(sessionId) {
        const sessDir = path.join(os.homedir(), ".agentboard", "sessions");
        const f = path.join(sessDir, `${sessionId}.json`);
        try {
            fs.unlinkSync(f);
        }
        catch { /* already gone */ }
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
        const delivered = await this._panel.webview.postMessage(payload);
        if (!delivered) {
            this._panel.webview.html = this._getShell(payload, this._panel.webview);
        }
    }
    _getShell(data, webview) {
        const src = webview?.cspSource ?? "";
        const csp = `default-src 'none'; img-src 'none'; style-src 'unsafe-inline' ${src}; script-src ${src}; connect-src 'none';`;
        // Data injected as non-executable JSON element — works regardless of script CSP
        const dataEl = data
            ? `<script id="ab-data" type="application/json">${JSON.stringify(data).replace(/<\/script>/gi, "<\\/script>")}</script>`
            : "";
        // External script loaded via webview URI (allowed by cspSource)
        let scriptTag = "";
        if (webview && DashboardPanel.extensionUri) {
            const uri = webview.asWebviewUri(vscode.Uri.joinPath(DashboardPanel.extensionUri, "media", "dashboard.js"));
            scriptTag = `<script src="${uri.toString()}"></script>`;
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
#live-body.multi{flex-direction:column;overflow:hidden}
#session-cols{display:flex;flex-wrap:wrap;align-content:flex-start;overflow-y:auto;overflow-x:hidden}
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
</style></head><body>

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

  <div id="live-body">
    <!-- Multi-session: N activity columns (shown by JS when activeSessions.length > 1) -->
    <div id="session-cols" style="display:none"></div>
    <div class="streams-row" id="streams-row" style="display:none">
      <div class="sec">
        <div class="sec-ttl" id="sr-ttl2">Active streams</div>
        <div id="sr-list2"></div>
      </div>
    </div>
    <!-- Single-session: Left: files touched + streams -->
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
      <div class="sec" id="sec-sessions" style="display:none">
        <div class="sec-ttl">Sessions</div>
        <div id="sessions-list"></div>
      </div>
      <div class="sec" id="sec-session-single">
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

${scriptTag}
</body></html>`;
    }
    dispose() {
        if (this._interval)
            clearInterval(this._interval);
        DashboardPanel.currentPanel = undefined;
        this._panel.dispose();
        for (const d of this._disposables)
            d.dispose();
        this._disposables = [];
    }
}
exports.DashboardPanel = DashboardPanel;
