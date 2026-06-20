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

export function detectWorkspaceRoot(): string {
  // Primary: ~/.agentboard/live.json written by status-bridge.js on every Claude turn
  const globalLive = path.join(os.homedir(), ".agentboard", "live.json");
  try {
    const live = JSON.parse(fs.readFileSync(globalLive, "utf8")) as { _root?: string; last_updated?: string };
    const root = live._root ?? "";
    if (root && fs.existsSync(path.join(root, ".platform"))) {
      const ageMs = Date.now() - new Date(live.last_updated ?? 0).getTime();
      if (ageMs < 4 * 60 * 60 * 1000) return root;
    }
  } catch { /* fall through */ }

  // Fallback: score open workspace folders by evidence of agentboard usage
  const folders = vscode.workspace.workspaceFolders ?? [];
  if (!folders.length) return "";
  const scored = folders.map(f => {
    const p = f.uri.fsPath;
    let score = 0;
    if (fs.existsSync(path.join(p, "agentboard.hud-status.json"))) score += 10;
    if (fs.existsSync(path.join(p, ".platform", "work"))) score += 5;
    if (fs.existsSync(path.join(p, ".platform"))) score += 2;
    if (fs.existsSync(path.join(p, ".claude", "settings.json"))) score += 1;
    return { p, score };
  }).sort((a, b) => b.score - a.score);
  return scored[0]?.p ?? "";
}

export function activate(context: vscode.ExtensionContext): void {
  let workspaceRoot = detectWorkspaceRoot();

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
        DashboardPanel.forceUpdate(workspaceRoot);
        hudEmitter.fire();
        sessionsProvider.refresh();
      }
    } catch { /* file not yet written */ }
  }, 3000);
  context.subscriptions.push({ dispose: () => clearInterval(globalPoll) });

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
