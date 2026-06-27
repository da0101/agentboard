"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleDelegateFile = handleDelegateFile;
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");
const catalogStore_1 = require("./catalogStore");
const prompts_1 = require("./prompts");
function handleDelegateFile(workspaceRoot, terminalMap, state) {
    const delegateFile = path.join(os.homedir(), ".agentboard", "delegate.json");
    if (!fs.existsSync(delegateFile))
        return;
    let raw;
    try {
        raw = fs.readFileSync(delegateFile, "utf8");
        fs.unlinkSync(delegateFile);
    }
    catch {
        return;
    }
    try {
        const d = JSON.parse(raw);
        if (!d.role || !d.task)
            return;
        const dedupeKey = `${d.role}|${d.task}`;
        if (dedupeKey === state.lastDelegateKey && (Date.now() - state.lastDelegateTs) < 60000)
            return;
        state.lastDelegateKey = dedupeKey;
        state.lastDelegateTs = Date.now();
        const roles = (0, catalogStore_1.readRoles)(d.root ?? workspaceRoot);
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
        lines.push("\nAsk me 2–3 focused intake questions if anything needs clarification, then begin.");
        const prompt = lines.join("\n");
        const cwd = d.root && fs.existsSync(d.root) ? d.root : workspaceRoot;
        const termName = `Claude · ${roleName}`;
        const terminal = vscode.window.createTerminal({ name: termName, cwd });
        terminal.show();
        terminal.sendText(`claude "${(0, prompts_1.escapeForDoubleQuotedCli)(prompt)}"`, true);
        terminalMap.set(d.role, termName);
    }
    catch {
        // malformed delegate.json
    }
}
