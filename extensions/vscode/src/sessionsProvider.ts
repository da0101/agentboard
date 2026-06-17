import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import { HudStatus, HudAgent } from "./hudTypes";

interface ControlPlaneSession {
  role?: string;
  stream_slug?: string;
  status?: string;
}

function httpGet(url: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let data = "";
      res.on("data", (chunk: Buffer) => { data += chunk.toString(); });
      res.on("end", () => resolve(data));
    });
    req.setTimeout(timeoutMs, () => { req.destroy(); reject(new Error("timeout")); });
    req.on("error", reject);
  });
}

function statusIcon(status?: string): string {
  switch (status) {
    case "running": return "play-circle";
    case "paused": return "debug-pause";
    case "done": return "check";
    case "error": return "error";
    default: return "play-circle";
  }
}

export class SessionsProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private readonly _onDidChangeTreeData =
    new vscode.EventEmitter<vscode.TreeItem | undefined | null | void>();

  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  constructor(private readonly workspaceRoot: string) {}

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  async getChildren(): Promise<vscode.TreeItem[]> {
    try {
      const raw = await httpGet("http://127.0.0.1:7842/sessions", 500);
      const sessions = JSON.parse(raw) as ControlPlaneSession[];
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
    } catch {
      return this.fromHudFile();
    }
  }

  private fromHudFile(): vscode.TreeItem[] {
    const hudPath = path.join(this.workspaceRoot, "agentboard.hud-status.json");
    try {
      const raw = fs.readFileSync(hudPath, "utf8");
      const hud = JSON.parse(raw) as HudStatus;
      const agents = hud.active_agents ?? [];
      if (agents.length === 0) return [this.controlPlaneDownItem()];
      return agents.map((a: HudAgent) => {
        const label = [a.label, a.phase].filter(Boolean).join(" · ") || "agent";
        const item = new vscode.TreeItem(label);
        item.description = a.objective;
        item.iconPath = new vscode.ThemeIcon("play-circle");
        return item;
      });
    } catch {
      return [this.controlPlaneDownItem()];
    }
  }

  private controlPlaneDownItem(): vscode.TreeItem {
    const item = new vscode.TreeItem("Control plane not running — ab start");
    item.iconPath = new vscode.ThemeIcon("debug-disconnect");
    return item;
  }

  private noSessionsItem(): vscode.TreeItem {
    const item = new vscode.TreeItem("No active sessions");
    item.iconPath = new vscode.ThemeIcon("info");
    return item;
  }
}
