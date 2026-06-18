"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SessionsProvider = void 0;
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const http = require("http");
function httpGet(url, timeoutMs) {
    return new Promise((resolve, reject) => {
        const req = http.get(url, (res) => {
            let data = "";
            res.on("data", (chunk) => { data += chunk.toString(); });
            res.on("end", () => resolve(data));
        });
        req.setTimeout(timeoutMs, () => { req.destroy(); reject(new Error("timeout")); });
        req.on("error", reject);
    });
}
function statusIcon(status) {
    switch (status) {
        case "running": return "play-circle";
        case "paused": return "debug-pause";
        case "done": return "check";
        case "error": return "error";
        default: return "play-circle";
    }
}
class SessionsProvider {
    constructor(workspaceRoot) {
        this.workspaceRoot = workspaceRoot;
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
    }
    refresh() {
        this._onDidChangeTreeData.fire();
    }
    getTreeItem(element) {
        return element;
    }
    async getChildren() {
        try {
            const raw = await httpGet("http://127.0.0.1:7842/sessions", 500);
            const sessions = JSON.parse(raw);
            if (!Array.isArray(sessions) || sessions.length === 0) {
                return [this.noSessionsItem()];
            }
            return sessions.map((s) => {
                const label = [s.role, s.stream_slug].filter(Boolean).join(" · ") || "session";
                const item = new vscode.TreeItem(label);
                item.description = s.status;
                item.iconPath = new vscode.ThemeIcon(statusIcon(s.status));
                return item;
            });
        }
        catch {
            return this.fromHudFile();
        }
    }
    fromHudFile() {
        const hudPath = path.join(this.workspaceRoot, "agentboard.hud-status.json");
        try {
            const raw = fs.readFileSync(hudPath, "utf8");
            const hud = JSON.parse(raw);
            const agents = hud.active_agents ?? [];
            if (agents.length === 0)
                return [this.controlPlaneDownItem()];
            return agents.map((a) => {
                const label = [a.label, a.phase].filter(Boolean).join(" · ") || "agent";
                const item = new vscode.TreeItem(label);
                item.description = a.objective;
                item.iconPath = new vscode.ThemeIcon("play-circle");
                return item;
            });
        }
        catch {
            return [this.controlPlaneDownItem()];
        }
    }
    controlPlaneDownItem() {
        const item = new vscode.TreeItem("Control plane not running — ab start");
        item.iconPath = new vscode.ThemeIcon("debug-disconnect");
        return item;
    }
    noSessionsItem() {
        const item = new vscode.TreeItem("No active sessions");
        item.iconPath = new vscode.ThemeIcon("info");
        return item;
    }
}
exports.SessionsProvider = SessionsProvider;
