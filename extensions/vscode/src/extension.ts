import * as vscode from "vscode";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { HudProvider } from "./hudProvider";
import { StreamsProvider } from "./streamsProvider";
import { CatalogProvider } from "./catalogProvider";
import { SessionsProvider } from "./sessionsProvider";
import { WorktreesProvider } from "./worktreesProvider";
import { DashboardPanel } from "./dashboardPanel";
import { detectWorkspaceRootFromFolders, detectWorkspaceRootFromSources } from "./workspaceRoot";

export function detectWorkspaceRoot(): string {
  // A VS Code window opened on an Agentboard workspace should stay scoped to
  // that workspace. The global live pointer is only a fallback for generic
  // windows that do not already contain an Agentboard project.
  return detectWorkspaceRootFromSources(
    (vscode.workspace.workspaceFolders ?? []).map(f => f.uri.fsPath)
  );
}

export function activate(context: vscode.ExtensionContext): void {
  let workspaceRoot = detectWorkspaceRoot();
  const isProjectWindow = !!detectWorkspaceRootFromFolders(
    (vscode.workspace.workspaceFolders ?? []).map(f => f.uri.fsPath)
  );

  const hudEmitter = new vscode.EventEmitter<vscode.TreeItem | undefined | null | void>();
  const streamsEmitter = new vscode.EventEmitter<vscode.TreeItem | undefined | null | void>();
  const hudProvider = new HudProvider(workspaceRoot, hudEmitter);
  const streamsProvider = new StreamsProvider(workspaceRoot, streamsEmitter);
  const catalogProvider = new CatalogProvider(workspaceRoot);
  const sessionsProvider = new SessionsProvider(workspaceRoot);
  const worktreesProvider = new WorktreesProvider(workspaceRoot);

  context.subscriptions.push(
    vscode.window.registerTreeDataProvider("agentboard.hud", hudProvider),
    vscode.window.registerTreeDataProvider("agentboard.streams", streamsProvider),
    vscode.window.registerTreeDataProvider("agentboard.catalog", catalogProvider),
    vscode.window.registerTreeDataProvider("agentboard.sessions", sessionsProvider),
    vscode.window.registerTreeDataProvider("agentboard.worktrees", worktreesProvider)
  );

  // Watch project HUD file for tree view updates
  const hudFile = path.join(workspaceRoot, "agentboard.hud-status.json");
  const watcher = vscode.workspace.createFileSystemWatcher(hudFile);
  watcher.onDidChange(() => { hudEmitter.fire(); sessionsProvider.refresh(); });
  watcher.onDidCreate(() => { hudEmitter.fire(); sessionsProvider.refresh(); });
  watcher.onDidDelete(() => { hudEmitter.fire(); sessionsProvider.refresh(); });
  context.subscriptions.push(watcher);

  if (!isProjectWindow) {
    // Legacy fallback for generic VS Code windows only. Project windows never
    // poll global state; they are pinned to their own workspace runtime store.
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
          DashboardPanel.forceUpdate(workspaceRoot);
          hudEmitter.fire();
          sessionsProvider.refresh();
        }
      } catch { /* file not yet written */ }
    }, 3000);
    context.subscriptions.push({ dispose: () => clearInterval(globalPoll) });
  }

  context.subscriptions.push(
    vscode.commands.registerCommand("agentboard.refresh", () => {
      workspaceRoot = detectWorkspaceRoot();
      hudEmitter.fire(); streamsEmitter.fire();
      catalogProvider.refresh(); sessionsProvider.refresh(); worktreesProvider.refresh();
      DashboardPanel.forceUpdate(workspaceRoot);
    }),
    vscode.commands.registerCommand("agentboard.openDashboard", () => {
      DashboardPanel.createOrShow(workspaceRoot, context.extensionUri);
    }),
    vscode.commands.registerCommand("agentboard.openBrief", async () => {
      const briefPath = path.join(workspaceRoot, ".platform", "work", "BRIEF.md");
      try {
        await vscode.window.showTextDocument(vscode.Uri.file(briefPath));
      } catch {
        void vscode.window.showErrorMessage("Could not open BRIEF.md — file may not exist.");
      }
    })
  );

  DashboardPanel.createOrShow(workspaceRoot, context.extensionUri);
}

export function deactivate(): void {}
