"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.detectWorkspaceRoot = detectWorkspaceRoot;
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");
const hudProvider_1 = require("./hudProvider");
const streamsProvider_1 = require("./streamsProvider");
const catalogProvider_1 = require("./catalogProvider");
const sessionsProvider_1 = require("./sessionsProvider");
const worktreesProvider_1 = require("./worktreesProvider");
const dashboardPanel_1 = require("./dashboardPanel");
const workspaceRoot_1 = require("./workspaceRoot");
function detectWorkspaceRoot() {
    // A VS Code window opened on an Agentboard workspace should stay scoped to
    // that workspace. The global live pointer is only a fallback for generic
    // windows that do not already contain an Agentboard project.
    return (0, workspaceRoot_1.detectWorkspaceRootFromSources)((vscode.workspace.workspaceFolders ?? []).map(f => f.uri.fsPath));
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
    // Watch project HUD file for tree view updates
    const hudFile = path.join(workspaceRoot, "agentboard.hud-status.json");
    const watcher = vscode.workspace.createFileSystemWatcher(hudFile);
    watcher.onDidChange(() => { hudEmitter.fire(); sessionsProvider.refresh(); });
    watcher.onDidCreate(() => { hudEmitter.fire(); sessionsProvider.refresh(); });
    watcher.onDidDelete(() => { hudEmitter.fire(); sessionsProvider.refresh(); });
    context.subscriptions.push(watcher);
    // Poll ~/.agentboard/live.json every 3s to detect workspace switches
    // (avoids vscode.RelativePattern issues with paths outside workspace)
    const globalLive = path.join(os.homedir(), ".agentboard", "live.json");
    let lastLiveMtime = 0;
    const globalPoll = setInterval(() => {
        try {
            const mtime = fs.statSync(globalLive).mtimeMs;
            if (mtime !== lastLiveMtime) {
                lastLiveMtime = mtime;
                const newRoot = detectWorkspaceRoot();
                if (newRoot && newRoot !== workspaceRoot) {
                    workspaceRoot = newRoot;
                }
                dashboardPanel_1.DashboardPanel.forceUpdate(workspaceRoot);
                hudEmitter.fire();
                sessionsProvider.refresh();
            }
        }
        catch { /* file not yet written */ }
    }, 3000);
    context.subscriptions.push({ dispose: () => clearInterval(globalPoll) });
    context.subscriptions.push(vscode.commands.registerCommand("agentboard.refresh", () => {
        workspaceRoot = detectWorkspaceRoot();
        hudEmitter.fire();
        streamsEmitter.fire();
        catalogProvider.refresh();
        sessionsProvider.refresh();
        worktreesProvider.refresh();
        dashboardPanel_1.DashboardPanel.forceUpdate(workspaceRoot);
    }), vscode.commands.registerCommand("agentboard.openDashboard", () => {
        dashboardPanel_1.DashboardPanel.createOrShow(workspaceRoot, context.extensionUri);
    }), vscode.commands.registerCommand("agentboard.openBrief", async () => {
        const briefPath = path.join(workspaceRoot, ".platform", "work", "BRIEF.md");
        try {
            await vscode.window.showTextDocument(vscode.Uri.file(briefPath));
        }
        catch {
            void vscode.window.showErrorMessage("Could not open BRIEF.md — file may not exist.");
        }
    }));
    dashboardPanel_1.DashboardPanel.createOrShow(workspaceRoot, context.extensionUri);
}
function deactivate() { }
