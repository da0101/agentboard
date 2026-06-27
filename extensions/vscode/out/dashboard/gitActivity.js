"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyGitStatus = applyGitStatus;
exports.enrichActivityWithGit = enrichActivityWithGit;
const fs = require("fs");
const path = require("path");
const child_process_1 = require("child_process");
const NUMSTAT_TTL = 30000;
const LINE_COUNT_TTL = 60000;
const COMMITTED_TTL = 30000;
function applyGitStatus(activity, statusOut, nowIso = new Date().toISOString()) {
    const statusMap = new Map();
    for (const line of statusOut.split("\n")) {
        if (line.length < 4)
            continue;
        const xy = line.slice(0, 2);
        const fpath = line.slice(3).trim().replace(/^"(.*)"$/, "$1");
        statusMap.set(fpath, xy);
    }
    for (const entry of activity) {
        const xy = statusMap.get(entry.file) ?? statusMap.get(entry.file.replace(/\\/g, "/")) ?? "";
        if (xy === "??" || xy[0] === "A" || xy[1] === "A")
            entry.isNew = true;
        else if (xy[0] === "D" || xy[1] === "D")
            entry.isDeleted = true;
    }
    const existing = new Set(activity.map(entry => entry.file.replace(/\\/g, "/")));
    for (const [file, xy] of statusMap) {
        const normalized = file.replace(/\\/g, "/");
        if (existing.has(normalized))
            continue;
        if (xy !== "??" && xy[0] !== "A" && xy[1] !== "A" && xy[0] !== "D" && xy[1] !== "D")
            continue;
        activity.push({
            file,
            tool: xy[0] === "D" || xy[1] === "D" ? "Delete" : "Write",
            count: 1,
            lastTs: nowIso,
            isNew: xy === "??" || xy[0] === "A" || xy[1] === "A",
            isDeleted: xy[0] === "D" || xy[1] === "D",
        });
        existing.add(normalized);
    }
    activity.sort((a, b) => b.lastTs.localeCompare(a.lastTs));
}
function enrichActivityWithGit(root, activity, caches, now = Date.now()) {
    enrichDiffStats(root, activity, caches.numstatCache, now);
    try {
        const statusOut = (0, child_process_1.execSync)(`git -C "${root}" status --porcelain --untracked-files=all 2>/dev/null`, { timeout: 3000, encoding: "utf8" });
        applyGitStatus(activity, statusOut, new Date(now).toISOString());
    }
    catch {
        // git unavailable
    }
    enrichLineCounts(root, activity, caches.lineCountCache, now);
    enrichCommittedMarkers(root, activity, caches.branchCommittedCache, now);
}
function enrichDiffStats(root, activity, cache, now) {
    try {
        const cached = cache.get(root);
        let diffMap;
        if (cached && (now - cached.ts) < NUMSTAT_TTL) {
            diffMap = cached.diffMap;
        }
        else {
            diffMap = new Map();
            const numstatOut = (0, child_process_1.execSync)("git diff --numstat HEAD", { cwd: root, timeout: 3000, encoding: "utf8" });
            for (const line of numstatOut.split("\n")) {
                const m = line.match(/^(\d+)\t(\d+)\t(.+)$/);
                if (m)
                    diffMap.set(m[3].trim(), { added: parseInt(m[1], 10), deleted: parseInt(m[2], 10) });
            }
            cache.set(root, { ts: now, diffMap });
        }
        for (const entry of activity) {
            if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
                const stats = diffMap.get(entry.file);
                if (stats) {
                    entry.added = stats.added;
                    entry.deleted = stats.deleted;
                }
            }
        }
    }
    catch {
        // git unavailable or repo not found
    }
}
function enrichLineCounts(root, activity, cache, now) {
    for (const entry of activity) {
        if (entry.file.startsWith("$ ") || !root)
            continue;
        const absFile = path.join(root, entry.file);
        try {
            const cached = cache.get(absFile);
            if (cached && (now - cached.ts) < LINE_COUNT_TTL) {
                entry.lineCount = cached.count;
            }
            else {
                const lines = fs.readFileSync(absFile, "utf8").split("\n").length;
                cache.set(absFile, { ts: now, count: lines });
                entry.lineCount = lines;
            }
        }
        catch {
            // file may not exist yet
        }
    }
}
function enrichCommittedMarkers(root, activity, cache, now) {
    try {
        const cached = cache.get(root);
        let committedFiles;
        if (cached && (now - cached.ts) < COMMITTED_TTL) {
            committedFiles = cached.files;
        }
        else {
            committedFiles = new Set();
            let mergeBase = "";
            for (const base of ["origin/develop", "origin/main", "HEAD~1"]) {
                try {
                    mergeBase = (0, child_process_1.execSync)(`git merge-base HEAD ${base}`, { cwd: root, timeout: 3000, encoding: "utf8" }).trim();
                    if (mergeBase)
                        break;
                }
                catch {
                    // try next
                }
            }
            if (mergeBase) {
                const nameOnly = (0, child_process_1.execSync)(`git diff --name-only ${mergeBase}..HEAD`, { cwd: root, timeout: 3000, encoding: "utf8" });
                for (const line of nameOnly.split("\n")) {
                    const f = line.trim();
                    if (f)
                        committedFiles.add(f);
                }
            }
            cache.set(root, { ts: now, files: committedFiles });
        }
        for (const entry of activity) {
            if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
                entry.committed = committedFiles.has(entry.file);
            }
        }
    }
    catch {
        // git unavailable
    }
}
