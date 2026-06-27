"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runtimeDirForRoot = runtimeDirForRoot;
exports.sessionsDirForRoot = sessionsDirForRoot;
exports.sessionRootMatchesWorkspace = sessionRootMatchesWorkspace;
exports.listSessionFiles = listSessionFiles;
exports.readSessionFile = readSessionFile;
exports.deleteSessionFile = deleteSessionFile;
exports.deleteSessionFileByShellPid = deleteSessionFileByShellPid;
const fs = require("fs");
const path = require("path");
const RUNTIME_DIR = path.join(".platform", "runtime", "agentboard");
function runtimeDirForRoot(workspaceRoot) {
    return path.join(workspaceRoot, RUNTIME_DIR);
}
function sessionsDirForRoot(workspaceRoot) {
    return path.join(runtimeDirForRoot(workspaceRoot), "sessions");
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
function listSessionFiles(workspaceRoot) {
    try {
        return fs.readdirSync(sessionsDirForRoot(workspaceRoot))
            .filter((f) => f.endsWith(".json"));
    }
    catch {
        return [];
    }
}
function readSessionFile(workspaceRoot, fileName) {
    try {
        return JSON.parse(fs.readFileSync(path.join(sessionsDirForRoot(workspaceRoot), fileName), "utf8"));
    }
    catch {
        return null;
    }
}
function deleteSessionFile(workspaceRoot, sessionId) {
    const f = path.join(sessionsDirForRoot(workspaceRoot), `${sessionId}.json`);
    try {
        fs.unlinkSync(f);
    }
    catch { /* already gone */ }
}
function deleteSessionFileByShellPid(workspaceRoot, pid) {
    if (!pid)
        return false;
    for (const fname of listSessionFiles(workspaceRoot)) {
        try {
            const raw = fs.readFileSync(path.join(sessionsDirForRoot(workspaceRoot), fname), "utf8");
            const d = JSON.parse(raw);
            if (d._shell_pid === pid) {
                fs.unlinkSync(path.join(sessionsDirForRoot(workspaceRoot), fname));
                return true;
            }
        }
        catch {
            // skip malformed session file
        }
    }
    return false;
}
