"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.findSessionTerminal = findSessionTerminal;
exports.sendTextToSessionTerminal = sendTextToSessionTerminal;
const vscode = require("vscode");
async function findSessionTerminal(options) {
    const terminals = [...vscode.window.terminals];
    const termPids = await Promise.all(terminals.map(t => t.processId));
    if (options.shellPid > 0) {
        const byPid = terminals.find((_, i) => termPids[i] === options.shellPid);
        if (byPid)
            return byPid;
        try {
            const { execSync } = await Promise.resolve().then(() => require("child_process"));
            for (let i = 0; i < termPids.length; i++) {
                const tpid = termPids[i];
                if (!tpid)
                    continue;
                const children = execSync(`/usr/bin/pgrep -P ${tpid} 2>/dev/null || true`).toString().trim().split("\n").filter(Boolean).map(Number);
                if (children.includes(options.shellPid))
                    return terminals[i];
            }
        }
        catch {
            // fall through
        }
        try {
            const { execSync } = await Promise.resolve().then(() => require("child_process"));
            const ppidStr = execSync(`ps -p ${options.shellPid} -o ppid= 2>/dev/null`).toString().trim();
            const parentPid = parseInt(ppidStr, 10);
            if (parentPid > 0) {
                const byParentPid = terminals.find((_, i) => termPids[i] === parentPid);
                if (byParentPid)
                    return byParentPid;
            }
        }
        catch {
            // fall through
        }
    }
    if (options.nick && options.terminalMap?.has(options.nick)) {
        const cachedName = options.terminalMap.get(options.nick);
        const cached = terminals.find(t => t.name === cachedName);
        if (cached)
            return cached;
    }
    if (options.nick) {
        const nickLower = options.nick.toLowerCase();
        const byName = terminals.find(t => {
            const n = t.name.toLowerCase();
            return n.includes(nickLower) || n.endsWith(options.nick) || n === `claude · ${nickLower}`;
        });
        if (byName)
            return byName;
    }
    if (options.root) {
        const cwdMatches = terminals.filter(t => {
            const cwd = t.shellIntegration?.cwd?.fsPath ?? "";
            return cwd && (cwd === options.root || cwd.startsWith(options.root + "/") || cwd.startsWith(options.root));
        });
        if (cwdMatches.length === 1)
            return cwdMatches[0];
        if (cwdMatches.length > 1) {
            // Prefer terminals with "claude" in name (most specific); fall back to newest (last in array)
            const claudeMatches = cwdMatches.filter(t => t.name.toLowerCase().includes("claude"));
            const pool = claudeMatches.length ? claudeMatches : cwdMatches;
            return pool[pool.length - 1];
        }
    }
    // Last resort: newest terminal in the workspace whose name includes "claude"
    const fallback = [...terminals].reverse().find(t => t.name.toLowerCase().includes("claude"));
    return fallback;
}
async function sendTextToSessionTerminal(text, options) {
    const target = await findSessionTerminal(options);
    if (target) {
        target.show(false);
        target.sendText(text, true);
        return;
    }
    const picked = await vscode.window.showQuickPick(vscode.window.terminals.map(t => ({ label: t.name, terminal: t })), { placeHolder: options.pickPlaceholder });
    if (picked) {
        picked.terminal.show(false);
        picked.terminal.sendText(text, true);
    }
}
