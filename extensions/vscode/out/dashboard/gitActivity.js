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
function normalizeGitPath(file) {
    return file.replace(/\\/g, "/");
}
function activityFileLocation(root, file) {
    if (!file || file.startsWith("$ "))
        return null;
    const rawAbsFile = path.isAbsolute(file) ? file : path.join(root, file);
    const absFile = (() => {
        try {
            return fs.realpathSync.native(rawAbsFile);
        }
        catch {
            return path.resolve(rawAbsFile);
        }
    })();
    let gitRoot = (() => {
        try {
            return fs.realpathSync.native(root);
        }
        catch {
            return path.resolve(root);
        }
    })();
    try {
        const dir = fs.existsSync(absFile) && fs.statSync(absFile).isDirectory() ? absFile : path.dirname(absFile);
        const rawGitRoot = (0, child_process_1.execFileSync)("git", ["rev-parse", "--show-toplevel"], { cwd: dir, timeout: 1000, encoding: "utf8" }).trim() || gitRoot;
        gitRoot = fs.realpathSync.native(rawGitRoot);
    }
    catch {
        // keep fallback root
    }
    const gitRel = normalizeGitPath(path.relative(gitRoot, absFile));
    if (!gitRel || gitRel.startsWith(".."))
        return { absFile, gitRoot, gitRel: normalizeGitPath(file) };
    return { absFile, gitRoot, gitRel };
}
function applyGitStatus(activity, statusOut, nowIso = new Date().toISOString(), timestampForFile) {
    const statusMap = new Map();
    for (const line of statusOut.split("\n")) {
        if (line.length < 4)
            continue;
        const xy = line.slice(0, 2);
        const fpath = line.slice(3).trim().replace(/^"(.*)"$/, "$1");
        statusMap.set(normalizeGitPath(fpath), xy);
    }
    for (const entry of activity) {
        const xy = statusMap.get(normalizeGitPath(entry.file)) ?? "";
        if (xy === "??" || xy[0] === "A" || xy[1] === "A")
            entry.isNew = true;
        else if (xy[0] === "D" || xy[1] === "D")
            entry.isDeleted = true;
    }
    const existing = new Set(activity.map(entry => normalizeGitPath(entry.file)));
    for (const [file, xy] of statusMap) {
        const normalized = normalizeGitPath(file);
        if (existing.has(normalized))
            continue;
        if (xy !== "??" && xy[0] !== "A" && xy[1] !== "A" && xy[0] !== "D" && xy[1] !== "D")
            continue;
        activity.push({
            file,
            tool: xy[0] === "D" || xy[1] === "D" ? "Delete" : "Write",
            count: 1,
            lastTs: timestampForFile?.(file, xy) || nowIso,
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
        const statusOut = (0, child_process_1.execFileSync)("git", ["-C", root, "status", "--porcelain", "--untracked-files=all"], {
            timeout: 3000,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "ignore"],
        });
        const fallbackTs = new Date(now).toISOString();
        applyGitStatus(activity, statusOut, fallbackTs, (file, xy) => {
            if (xy[0] === "D" || xy[1] === "D")
                return fallbackTs;
            try {
                return fs.statSync(path.join(root, file)).mtime.toISOString();
            }
            catch {
                return fallbackTs;
            }
        });
    }
    catch {
        // git unavailable
    }
    enrichLineCounts(root, activity, caches.lineCountCache, now);
    enrichCommittedMarkers(root, activity, caches.branchCommittedCache, now);
}
function enrichDiffStats(root, activity, cache, now) {
    const diffMapForRoot = (gitRoot) => {
        const cached = cache.get(gitRoot);
        let diffMap;
        if (cached && (now - cached.ts) < NUMSTAT_TTL) {
            diffMap = cached.diffMap;
        }
        else {
            diffMap = new Map();
            const numstatOut = (0, child_process_1.execFileSync)("git", ["diff", "--numstat", "HEAD"], { cwd: gitRoot, timeout: 3000, encoding: "utf8" });
            for (const line of numstatOut.split("\n")) {
                const m = line.match(/^(\d+)\t(\d+)\t(.+)$/);
                if (m)
                    diffMap.set(normalizeGitPath(m[3].trim()), { added: parseInt(m[1], 10), deleted: parseInt(m[2], 10) });
            }
            cache.set(gitRoot, { ts: now, diffMap });
        }
        return diffMap;
    };
    try {
        for (const entry of activity) {
            if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
                const loc = activityFileLocation(root, entry.file);
                if (!loc)
                    continue;
                const stats = diffMapForRoot(loc.gitRoot).get(loc.gitRel);
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
        if (!root)
            continue;
        const loc = activityFileLocation(root, entry.file);
        if (!loc)
            continue;
        try {
            const cached = cache.get(loc.absFile);
            if (cached && (now - cached.ts) < LINE_COUNT_TTL) {
                entry.lineCount = cached.count;
            }
            else {
                const lines = fs.readFileSync(loc.absFile, "utf8").split("\n").length;
                cache.set(loc.absFile, { ts: now, count: lines });
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
                    mergeBase = (0, child_process_1.execFileSync)("git", ["merge-base", "HEAD", base], { cwd: root, timeout: 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
                    if (mergeBase)
                        break;
                }
                catch {
                    // try next
                }
            }
            if (mergeBase) {
                const nameOnly = (0, child_process_1.execFileSync)("git", ["diff", "--name-only", `${mergeBase}..HEAD`], { cwd: root, timeout: 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
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
                const loc = activityFileLocation(root, entry.file);
                entry.committed = loc ? committedFiles.has(loc.gitRel) : false;
            }
        }
    }
    catch {
        // git unavailable
    }
}
