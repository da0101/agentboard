"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleDashboardMessage = handleDashboardMessage;
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");
const panelPrefs_1 = require("./panelPrefs");
const providerLaunch_1 = require("./providerLaunch");
const prompts_1 = require("./prompts");
const terminalFocus_1 = require("./terminalFocus");
function handleDashboardMessage(msg, ctx) {
    if (msg.command === "refresh")
        ctx.update();
    if (msg.command === "focusSessionTab") {
        const sid = msg.targetSessionId ?? "";
        ctx.focusSessionTab(sid);
        return;
    }
    if (msg.command === "openChat") {
        // "Open Chat" button in session tab — delegate to focusTerminal via same PID-matching logic
        // (handled by the focusTerminal branch below; this branch is a no-op alias)
        msg.command = "focusTerminal";
    }
    if (msg.command === "openStream") {
        const fp = String(msg.filePath ?? "");
        const allowed = ctx.workspaceRoot && fp.startsWith(ctx.workspaceRoot + path.sep);
        if (allowed && fp.endsWith(".md")) {
            void vscode.workspace.openTextDocument(fp).then(doc => vscode.window.showTextDocument(doc));
        }
        return;
    }
    if (msg.command === "openDiff") {
        const relPath = msg.filePath ?? "";
        const sessRoot = msg.sessionRoot ?? ctx.workspaceRoot;
        const isNewFile = msg.isNew ?? false;
        if (!relPath)
            return;
        // Resolve absolute path — try sessRoot first, then workspaceRoot
        let absPath = path.isAbsolute(relPath) ? relPath : path.join(sessRoot, relPath);
        if (!fs.existsSync(absPath)) {
            const alt = path.join(ctx.workspaceRoot, relPath);
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
        ctx.deleteSessionFile(sessionId);
        ctx.update();
        return;
    }
    if (msg.command === "launchRole") {
        const slug = msg.slug ?? "";
        const name = msg.name ?? slug;
        if (!slug)
            return;
        const terminal = vscode.window.createTerminal({ name: `Claude · ${name}`, cwd: ctx.workspaceRoot });
        terminal.show();
        const prompt = `Adopt the ${name} role for this session. Read .platform/roles/${slug}.md for your full protocol, mission, and responsibilities. Ask me 2–3 focused intake questions to understand what I need, then begin working.`;
        const escaped = prompt.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/`/g, "\\`");
        terminal.sendText(`claude "${escaped}"`, true);
        return;
    }
    if (msg.command === "explainChange") {
        const filePath = msg.filePath ?? "";
        const sessRoot = msg.sessionRoot ?? ctx.workspaceRoot;
        const added = msg.added ?? 0;
        const deleted = msg.deleted ?? 0;
        const totalChanged = msg.totalChanged ?? 0;
        const shellPid = msg.shellPid ?? 0;
        const sessionNick = msg.sessionNick ?? "";
        if (!filePath)
            return;
        const absPath = path.isAbsolute(filePath) ? filePath : path.join(sessRoot, filePath);
        const explainPrompt = (0, prompts_1.buildExplainChangePrompt)({ absPath, added, deleted, totalChanged });
        void (async () => {
            try {
                await (0, terminalFocus_1.sendTextToSessionTerminal)(explainPrompt, {
                    shellPid,
                    nick: sessionNick,
                    root: sessRoot,
                    terminalMap: ctx.sessionTerminalMap,
                    pickPlaceholder: "Pick the agent terminal to send the explanation request to",
                });
            }
            catch (err) {
                void vscode.window.showErrorMessage(`Explain change error: ${err instanceof Error ? err.message : String(err)}`);
            }
        })();
        return;
    }
    if (msg.command === "refactorInSession" || msg.command === "refactorNewSession") {
        const filePath = msg.filePath ?? "";
        const sessRoot = msg.sessionRoot ?? ctx.workspaceRoot;
        const lineCount = msg.lineCount ?? 0;
        if (!filePath)
            return;
        const absPath = path.isAbsolute(filePath) ? filePath : path.join(sessRoot, filePath);
        const refactorPrompt = (0, prompts_1.buildRefactorPrompt)({ absPath, lineCount });
        if (msg.command === "refactorInSession") {
            const shellPid = msg.shellPid ?? 0;
            const sessionNick = msg.sessionNick ?? "";
            void (async () => {
                try {
                    await (0, terminalFocus_1.sendTextToSessionTerminal)(refactorPrompt, {
                        shellPid,
                        nick: sessionNick,
                        root: sessRoot,
                        terminalMap: ctx.sessionTerminalMap,
                        pickPlaceholder: "Pick the agent terminal to send the refactor prompt to",
                    });
                }
                catch (err) {
                    void vscode.window.showErrorMessage(`Refactor error: ${err instanceof Error ? err.message : String(err)}`);
                }
            })();
        }
        else {
            const cwd = sessRoot || ctx.workspaceRoot;
            void (async () => {
                try {
                    const requested = (0, providerLaunch_1.normalizeProvider)(msg.agentProvider);
                    let provider = requested;
                    if (!provider) {
                        const preferred = (0, providerLaunch_1.normalizeProvider)(msg.sessionProvider);
                        const choices = preferred
                            ? [...providerLaunch_1.PROVIDER_CHOICES.filter(choice => choice.provider === preferred), ...providerLaunch_1.PROVIDER_CHOICES.filter(choice => choice.provider !== preferred)]
                            : providerLaunch_1.PROVIDER_CHOICES;
                        const picked = await vscode.window.showQuickPick(choices.map(choice => ({ label: choice.label, description: choice.description, provider: choice.provider })), { placeHolder: "Choose the agent for the new refactor session" });
                        if (!picked)
                            return;
                        provider = picked.provider;
                    }
                    const wrapper = (0, providerLaunch_1.providerWrapperScript)(provider);
                    const hasWrapper = !!wrapper && fs.existsSync(path.join(cwd, wrapper));
                    const terminal = vscode.window.createTerminal({ name: `${(0, providerLaunch_1.providerLabel)(provider)} · Code Cleanup`, cwd });
                    terminal.show();
                    const escaped = (0, prompts_1.escapeForDoubleQuotedCli)(refactorPrompt);
                    terminal.sendText((0, providerLaunch_1.buildProviderLaunchCommand)(provider, escaped, hasWrapper), true);
                }
                catch (err) {
                    void vscode.window.showErrorMessage(`Refactor launch error: ${err instanceof Error ? err.message : String(err)}`);
                }
            })();
        }
        return;
    }
    if (msg.command === "copyPath") {
        const relPath = msg.filePath ?? "";
        const sessRoot = msg.sessionRoot ?? ctx.workspaceRoot;
        if (!relPath)
            return;
        const absPath = path.isAbsolute(relPath) ? relPath : path.join(sessRoot, relPath);
        void vscode.env.clipboard.writeText(absPath).then(() => {
            void vscode.window.setStatusBarMessage(`Copied: ${absPath}`, 3000);
        });
        return;
    }
    if (msg.command === "webviewReady") {
        // Webview JS loaded (fresh HTML set or extension reloaded) — push data immediately
        ctx.update();
        return;
    }
    if (msg.command === "toggleIgnoreSize") {
        const filePath = msg.filePath ?? "";
        if (!filePath)
            return;
        const root = msg.sessionRoot || ctx.workspaceRoot || os.homedir();
        const set = (0, panelPrefs_1.loadIgnoreSizes)(root);
        if (set.has(filePath)) {
            set.delete(filePath);
        }
        else {
            set.add(filePath);
        }
        (0, panelPrefs_1.saveIgnoreSizes)(root);
        ctx.update();
        return;
    }
    if (msg.command === "setSessionStream") {
        const { sessionId, streamSlug, sessionRoot } = msg;
        const root = sessionRoot || ctx.workspaceRoot || os.homedir();
        if (sessionId !== undefined) {
            (0, panelPrefs_1.setStreamOverride)(root, sessionId, streamSlug ?? "");
            ctx.update();
        }
        return;
    }
    if (msg.command === "setSessionBranch") {
        const { sessionId, branch, sessionRoot } = msg;
        const root = sessionRoot || ctx.workspaceRoot || os.homedir();
        if (sessionId) {
            (0, panelPrefs_1.setBranchOverride)(root, sessionId, branch ?? "");
            ctx.update();
        }
        return;
    }
    if (msg.command === "closeStream") {
        const { streamSlug, sessionRoot } = msg;
        if (!streamSlug)
            return;
        const cwd = sessionRoot || ctx.workspaceRoot;
        const term = vscode.window.createTerminal({ name: `Close · ${streamSlug}`, cwd });
        term.show();
        term.sendText(`agentboard close ${streamSlug}`, true);
        return;
    }
    if (msg.command === "focusTerminal") {
        const root = msg.sessionRoot ?? "";
        const nick = msg.sessionNick ?? "";
        const shellPid = msg.shellPid ?? 0;
        void (async () => {
            try {
                const target = await (0, terminalFocus_1.findSessionTerminal)({ shellPid, nick, root, terminalMap: ctx.sessionTerminalMap });
                if (target) {
                    target.show(true);
                    return;
                }
                void vscode.window.showInformationMessage(`⌨ Chat not found for "${nick}". Wait for Claude's next tool call then try again.`);
            }
            catch (err) {
                void vscode.window.showErrorMessage(`focusTerminal error: ${err instanceof Error ? err.message : String(err)}`);
            }
        })();
        return;
    }
}
