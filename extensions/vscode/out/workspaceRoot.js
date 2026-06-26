"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.detectWorkspaceRootFromFolders = detectWorkspaceRootFromFolders;
exports.detectWorkspaceRootFromGlobalLive = detectWorkspaceRootFromGlobalLive;
exports.detectWorkspaceRootFromSources = detectWorkspaceRootFromSources;
const fs = require("fs");
const os = require("os");
const path = require("path");
function detectWorkspaceRootFromFolders(folders, exists = fs.existsSync) {
    if (!folders.length)
        return "";
    const scored = folders.map(p => {
        let score = 0;
        if (exists(path.join(p, "agentboard.hud-status.json")))
            score += 10;
        if (exists(path.join(p, ".platform", "work")))
            score += 5;
        if (exists(path.join(p, ".platform")))
            score += 2;
        if (exists(path.join(p, ".claude", "settings.json")))
            score += 1;
        return { p, score };
    }).filter(f => f.score > 0).sort((a, b) => b.score - a.score);
    return scored[0]?.p ?? "";
}
function detectWorkspaceRootFromGlobalLive(options = {}) {
    const exists = options.exists ?? fs.existsSync;
    const readFile = options.readFile ?? ((filePath) => fs.readFileSync(filePath, "utf8"));
    const nowMs = options.nowMs ?? Date.now();
    const homeDir = options.homeDir ?? os.homedir();
    const globalLive = path.join(homeDir, ".agentboard", "live.json");
    try {
        const live = JSON.parse(readFile(globalLive));
        const root = live._root ?? "";
        if (root && exists(path.join(root, ".platform"))) {
            const ageMs = nowMs - new Date(live.last_updated ?? 0).getTime();
            if (ageMs < 4 * 60 * 60 * 1000)
                return root;
        }
    }
    catch { /* fall through */ }
    return "";
}
function detectWorkspaceRootFromSources(folders, globalLiveOptions = {}) {
    const workspaceRoot = detectWorkspaceRootFromFolders(folders, globalLiveOptions.exists);
    if (workspaceRoot)
        return workspaceRoot;
    return detectWorkspaceRootFromGlobalLive(globalLiveOptions);
}
