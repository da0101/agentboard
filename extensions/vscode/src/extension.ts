import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import { HudProvider } from "./hudProvider";
import { StreamsProvider } from "./streamsProvider";
import { CatalogProvider } from "./catalogProvider";
import { SessionsProvider } from "./sessionsProvider";
import { WorktreesProvider } from "./worktreesProvider";
import { DashboardPanel } from "./dashboardPanel";

function detectWorkspaceRoot(): string {
  const folders = vscode.workspace.workspaceFolders ?? [];
  if (!folders.length) return "";
  // Prefer the folder that has an active agentboard session (hud file or .platform/)
  const scored = folders.map(f => {
    const p = f.uri.fsPath;
    let score = 0;
    if (fs.existsSync(path.join(p, "agentboard.hud-status.json"))) score += 10;
    if (fs.existsSync(path.join(p, ".platform", "work"))) score += 5;
    if (fs.existsSync(path.join(p, ".platform"))) score += 2;
    if (fs.existsSync(path.join(p, ".claude", "settings.json"))) score += 1;
    return { p, score };
  }).sort((a, b) => b.score - a.score);
  return scored[0].p;
}

export function activate(context: vscode.ExtensionContext): void {
  let workspaceRoot = detectWorkspaceRoot();

  const hudEmitter = new vscode.EventEmitter<
    vscode.TreeItem | undefined | null | void
  >();
  const streamsEmitter = new vscode.EventEmitter<
    vscode.TreeItem | undefined | null | void
  >();

  const hudProvider = new HudProvider(workspaceRoot, hudEmitter);
  const streamsProvider = new StreamsProvider(workspaceRoot, streamsEmitter);
  const catalogProvider = new CatalogProvider(workspaceRoot);
  const sessionsProvider = new SessionsProvider(workspaceRoot);
  const worktreesProvider = new WorktreesProvider(workspaceRoot);

  context.subscriptions.push(
    vscode.window.registerTreeDataProvider("agentboard.hud", hudProvider),
    vscode.window.registerTreeDataProvider(
      "agentboard.streams",
      streamsProvider
    ),
    vscode.window.registerTreeDataProvider("agentboard.catalog", catalogProvider),
    vscode.window.registerTreeDataProvider("agentboard.sessions", sessionsProvider),
    vscode.window.registerTreeDataProvider("agentboard.worktrees", worktreesProvider)
  );

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
      DashboardPanel.createOrShow(workspaceRoot);
    }
  });
  context.subscriptions.push(anyHudWatcher);

  context.subscriptions.push(
    vscode.commands.registerCommand("agentboard.refresh", () => {
      workspaceRoot = detectWorkspaceRoot();
      hudEmitter.fire();
      streamsEmitter.fire();
      catalogProvider.refresh();
      sessionsProvider.refresh();
      worktreesProvider.refresh();
      DashboardPanel.createOrShow(workspaceRoot);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("agentboard.openDashboard", () => {
      DashboardPanel.createOrShow(workspaceRoot);
    })
  );
  // Auto-open dashboard on activation
  DashboardPanel.createOrShow(workspaceRoot);

  context.subscriptions.push(
    vscode.commands.registerCommand("agentboard.openBrief", async () => {
      const briefPath = path.join(
        workspaceRoot,
        ".platform",
        "work",
        "BRIEF.md"
      );
      const uri = vscode.Uri.file(briefPath);
      try {
        await vscode.window.showTextDocument(uri);
      } catch {
        void vscode.window.showErrorMessage(
          "Could not open BRIEF.md — file may not exist."
        );
      }
    })
  );
}

export function deactivate(): void {}
