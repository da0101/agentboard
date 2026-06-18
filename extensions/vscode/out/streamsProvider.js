"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.StreamsProvider = void 0;
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
function iconForStatus(status) {
    const s = status.toLowerCase();
    if (s.includes("awaiting") || s.includes("verif")) {
        return "warning";
    }
    if (s.includes("block")) {
        return "error";
    }
    return "sync";
}
function parseTableRows(content) {
    const rows = [];
    const lines = content.split("\n");
    let inTable = false;
    let headerParsed = false;
    for (const raw of lines) {
        const line = raw.trim();
        if (!line.startsWith("|")) {
            if (inTable) {
                break;
            }
            continue;
        }
        if (!inTable) {
            inTable = true;
        }
        if (!headerParsed) {
            headerParsed = true;
            continue;
        }
        if (/^\|[-| ]+\|$/.test(line)) {
            continue;
        }
        const cells = line
            .split("|")
            .map((c) => c.trim())
            .filter((_, i, arr) => i > 0 && i < arr.length - 1);
        if (cells.length < 1) {
            continue;
        }
        rows.push({
            name: cells[0] ?? "",
            status: cells[1] ?? "",
            lastUpdated: cells[2] ?? "",
        });
    }
    return rows;
}
class StreamsProvider {
    constructor(workspaceRoot, emitter) {
        this.workspaceRoot = workspaceRoot;
        this._onDidChangeTreeData = emitter;
    }
    get onDidChangeTreeData() {
        return this._onDidChangeTreeData.event;
    }
    getTreeItem(element) {
        return element;
    }
    getChildren() {
        const activePath = path.join(this.workspaceRoot, ".platform", "work", "ACTIVE.md");
        let content;
        try {
            content = fs.readFileSync(activePath, "utf8");
        }
        catch {
            const item = new vscode.TreeItem("No ACTIVE.md found");
            item.iconPath = new vscode.ThemeIcon("info");
            return [item];
        }
        const rows = parseTableRows(content);
        if (rows.length === 0) {
            const item = new vscode.TreeItem("No active streams");
            item.iconPath = new vscode.ThemeIcon("dash");
            return [item];
        }
        return rows.map((row) => {
            const label = row.name || "(unnamed)";
            const item = new vscode.TreeItem(label);
            item.description = row.status;
            item.tooltip = row.lastUpdated
                ? `Last updated: ${row.lastUpdated}`
                : undefined;
            item.iconPath = new vscode.ThemeIcon(iconForStatus(row.status));
            return item;
        });
    }
}
exports.StreamsProvider = StreamsProvider;
