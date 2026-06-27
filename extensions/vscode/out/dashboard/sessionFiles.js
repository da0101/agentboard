"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sessionRootMatchesWorkspace = sessionRootMatchesWorkspace;
exports.deleteSessionFile = deleteSessionFile;
exports.deleteSessionFileByShellPid = deleteSessionFileByShellPid;
const fs = require("fs");
const os = require("os");
const path = require("path");
function sessionsDir() {
    return path.join(os.homedir(), ".agentboard", "sessions");
}
function normalizeRoot(root) {
    const resolved = (() => {
        try {
            return fs.realpathSync.native(root);
        }
        catch {
            return path.resolve(root);
        }
    })();
    return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}
function sessionRootMatchesWorkspace(sessionRoot, workspaceRoot) {
    if (!sessionRoot || !workspaceRoot)
        return false;
    return normalizeRoot(sessionRoot) === normalizeRoot(workspaceRoot);
}
function deleteSessionFile(sessionId) {
    const f = path.join(sessionsDir(), `${sessionId}.json`);
    try {
        fs.unlinkSync(f);
    }
    catch { /* already gone */ }
}
function deleteSessionFileByShellPid(pid) {
    if (!pid)
        return false;
    try {
        for (const fname of fs.readdirSync(sessionsDir())) {
            if (!fname.endsWith(".json"))
                continue;
            try {
                const raw = fs.readFileSync(path.join(sessionsDir(), fname), "utf8");
                const d = JSON.parse(raw);
                if (d._shell_pid === pid) {
                    fs.unlinkSync(path.join(sessionsDir(), fname));
                    return true;
                }
            }
            catch {
                // skip malformed session file
            }
        }
    }
    catch {
        // sessions dir missing
    }
    return false;
}
