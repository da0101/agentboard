"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const hudProvider_1 = require("./hudProvider");
const streamsProvider_1 = require("./streamsProvider");
const catalogProvider_1 = require("./catalogProvider");
const sessionsProvider_1 = require("./sessionsProvider");
const worktreesProvider_1 = require("./worktreesProvider");
const dashboardPanel_1 = require("./dashboardPanel");
function detectWorkspaceRoot() {
    const folders = vscode.workspace.workspaceFolders ?? [];
    if (!folders.length)
        return "";
    // Prefer the folder that has an active agentboard session (hud file or .platform/)
    const scored = folders.map(f => {
        const p = f.uri.fsPath;
        let score = 0;
        if (fs.existsSync(path.join(p, "agentboard.hud-status.json")))
            score += 10;
        if (fs.existsSync(path.join(p, ".platform", "work")))
            score += 5;
        if (fs.existsSync(path.join(p, ".platform")))
            score += 2;
        if (fs.existsSync(path.join(p, ".claude", "settings.json")))
            score += 1;
        return { p, score };
    }).sort((a, b) => b.score - a.score);
    return scored[0].p;
}
function activate(context) {
    let workspaceRoot = detectWorkspaceRoot();
    const hudEmitter = new vscode.EventEmitter();
    const streamsEmitter = new vscode.EventEmitter();
    const hudProvider = new hudProvider_1.HudProvider(workspaceRoot, hudEmitter);
    const streamsProvider = new streamsProvider_1.StreamsProvider(workspaceRoot, streamsEmitter);
    const catalogProvider = new catalogProvider_1.CatalogProvider(workspaceRoot);
    const sessionsProvider = new sessionsProvider_1.SessionsProvider(workspaceRoot);
    const worktreesProvider = new worktreesProvider_1.WorktreesProvider(workspaceRoot);
    context.subscriptions.push(vscode.window.registerTreeDataProvider("agentboard.hud", hudProvider), vscode.window.registerTreeDataProvider("agentboard.streams", streamsProvider), vscode.window.registerTreeDataProvider("agentboard.catalog", catalogProvider), vscode.window.registerTreeDataProvider("agentboard.sessions", sessionsProvider), vscode.window.registerTreeDataProvider("agentboard.worktrees", worktreesProvider));
    const hudFile = path.join(workspaceRoot, "agentboard.hud-status.json");
    const watcher = vscode.workspace.createFileSystemWatcher(hudFile);
    watcher.onDidChange(() => {
        hudEmitter.fire();
        sessionsProvider.refresh();
    });
    watcher.onDidCreate(() => {
        hudEmitter.fire();
        sessionsProvider.refresh();
    });
    watcher.onDidDelete(() => {
        hudEmitter.fire();
        sessionsProvider.refresh();
    });
    context.subscriptions.push(watcher);
    // Re-detect workspace when a HUD file appears in any folder (new Claude session)
    const anyHudWatcher = vscode.workspace.createFileSystemWatcher("**/agentboard.hud-status.json");
    anyHudWatcher.onDidCreate(() => {
        const best = detectWorkspaceRoot();
        if (best && best !== workspaceRoot) {
            workspaceRoot = best;
            dashboardPanel_1.DashboardPanel.createOrShow(workspaceRoot);
        }
    });
    context.subscriptions.push(anyHudWatcher);
    context.subscriptions.push(vscode.commands.registerCommand("agentboard.refresh", () => {
        workspaceRoot = detectWorkspaceRoot();
        hudEmitter.fire();
        streamsEmitter.fire();
        catalogProvider.refresh();
        sessionsProvider.refresh();
        worktreesProvider.refresh();
        dashboardPanel_1.DashboardPanel.createOrShow(workspaceRoot);
    }));
    context.subscriptions.push(vscode.commands.registerCommand("agentboard.openDashboard", () => {
        dashboardPanel_1.DashboardPanel.createOrShow(workspaceRoot);
    }));
    // Auto-open dashboard on activation
    dashboardPanel_1.DashboardPanel.createOrShow(workspaceRoot);
    context.subscriptions.push(vscode.commands.registerCommand("agentboard.openBrief", async () => {
        const briefPath = path.join(workspaceRoot, ".platform", "work", "BRIEF.md");
        const uri = vscode.Uri.file(briefPath);
        try {
            await vscode.window.showTextDocument(uri);
        }
        catch {
            void vscode.window.showErrorMessage("Could not open BRIEF.md — file may not exist.");
        }
    }));
}
function deactivate() { }
