"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.WorktreesProvider = void 0;
const vscode = require("vscode");
const path = require("path");
const http = require("http");
const child_process_1 = require("child_process");
function httpGet(url, ms) {
    return new Promise((resolve, reject) => {
        const req = http.get(url, (res) => {
            let d = "";
            res.on("data", (c) => { d += c.toString(); });
            res.on("end", () => resolve(d));
        });
        req.setTimeout(ms, () => { req.destroy(); reject(new Error("timeout")); });
        req.on("error", reject);
    });
}
function parseGitWorktrees(raw) {
    const out = [];
    let cur = {};
    for (const line of raw.split("\n")) {
        if (line.startsWith("worktree ")) {
            if (cur.path)
                out.push(cur);
            cur = { path: line.slice(9).trim(), branch: "(detached)", isMain: false };
        }
        else if (line.startsWith("branch ")) {
            cur.branch = line.slice(7).trim().replace(/^refs\/heads\//, "");
        }
    }
    if (cur.path)
        out.push(cur);
    if (out.length > 0)
        out[0].isMain = true;
    return out;
}
function toItem(w) {
    const item = new vscode.TreeItem(w.branch ?? "(detached)");
    item.description = w.path ? path.basename(w.path) : undefined;
    item.iconPath = new vscode.ThemeIcon(w.isMain ? "source-control" : "git-branch");
    return item;
}
class WorktreesProvider {
    constructor(workspaceRoot) {
        this.workspaceRoot = workspaceRoot;
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
    }
    refresh() { this._onDidChangeTreeData.fire(); }
    getTreeItem(e) { return e; }
    async getChildren() {
        try {
            const raw = await httpGet("http://127.0.0.1:7842/worktrees", 500);
            const list = JSON.parse(raw);
            if (!Array.isArray(list) || list.length === 0)
                return [this.noneItem()];
            return list.map((w) => {
                const branch = (w.branch ?? "(detached)").replace(/^refs\/heads\//, "");
                const item = new vscode.TreeItem(branch);
                item.description = w.path ? path.basename(w.path) : undefined;
                item.iconPath = new vscode.ThemeIcon(w.isMain ? "source-control" : "git-branch");
                return item;
            });
        }
        catch {
            return this.fromGit();
        }
    }
    fromGit() {
        try {
            const out = (0, child_process_1.execSync)("git worktree list --porcelain", {
                cwd: this.workspaceRoot, encoding: "utf8", timeout: 3000,
            });
            const wts = parseGitWorktrees(out);
            return wts.length > 0 ? wts.map(toItem) : [this.noneItem()];
        }
        catch {
            return [this.noneItem()];
        }
    }
    noneItem() {
        const item = new vscode.TreeItem("No worktrees found");
        item.iconPath = new vscode.ThemeIcon("info");
        return item;
    }
}
exports.WorktreesProvider = WorktreesProvider;
