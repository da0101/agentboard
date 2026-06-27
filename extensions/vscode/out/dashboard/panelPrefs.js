"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.loadIgnoreSizes = loadIgnoreSizes;
exports.saveIgnoreSizes = saveIgnoreSizes;
exports.loadStreamOverride = loadStreamOverride;
exports.setStreamOverride = setStreamOverride;
const fs = require("fs");
const os = require("os");
const path = require("path");
const ignoreSizes = new Map();
const streamOverrides = new Map();
function ignoreSizePath() {
    return path.join(os.homedir(), ".agentboard", "ignore-sizes.json");
}
function overridesPath() {
    return path.join(os.homedir(), ".agentboard", "session-stream-overrides.json");
}
function loadIgnoreSizes(root) {
    if (ignoreSizes.has(root))
        return ignoreSizes.get(root);
    try {
        const obj = JSON.parse(fs.readFileSync(ignoreSizePath(), "utf8"));
        const set = new Set(obj[root] ?? []);
        ignoreSizes.set(root, set);
        return set;
    }
    catch {
        const s = new Set();
        ignoreSizes.set(root, s);
        return s;
    }
}
function saveIgnoreSizes(root) {
    try {
        const fp = ignoreSizePath();
        let obj = {};
        try {
            obj = JSON.parse(fs.readFileSync(fp, "utf8"));
        }
        catch { /* new */ }
        const set = ignoreSizes.get(root) ?? new Set();
        if (set.size > 0) {
            obj[root] = [...set];
        }
        else {
            delete obj[root];
        }
        fs.mkdirSync(path.dirname(fp), { recursive: true });
        fs.writeFileSync(fp, JSON.stringify(obj, null, 2));
    }
    catch {
        // Ignore preference persistence failures.
    }
}
function loadStreamOverride(root, sessionId) {
    const key = `${root}::${sessionId}`;
    if (streamOverrides.has(key))
        return streamOverrides.get(key);
    try {
        const obj = JSON.parse(fs.readFileSync(overridesPath(), "utf8"));
        for (const [k, v] of Object.entries(obj))
            streamOverrides.set(k, v);
        return streamOverrides.get(key);
    }
    catch {
        return undefined;
    }
}
function setStreamOverride(root, sessionId, slug) {
    const key = `${root}::${sessionId}`;
    streamOverrides.set(key, slug);
    try {
        const fp = overridesPath();
        let obj = {};
        try {
            obj = JSON.parse(fs.readFileSync(fp, "utf8"));
        }
        catch { /* new */ }
        obj[key] = slug;
        fs.mkdirSync(path.dirname(fp), { recursive: true });
        fs.writeFileSync(fp, JSON.stringify(obj, null, 2));
    }
    catch {
        // Ignore preference persistence failures.
    }
}
