import * as vscode from "vscode";
import * as path from "path";
import * as http from "http";
import { execSync } from "child_process";

interface CpWorktree { path?: string; branch?: string; isMain?: boolean; }

function httpGet(url: string, ms: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let d = "";
      res.on("data", (c: Buffer) => { d += c.toString(); });
      res.on("end", () => resolve(d));
    });
    req.setTimeout(ms, () => { req.destroy(); reject(new Error("timeout")); });
    req.on("error", reject);
  });
}

function parseGitWorktrees(raw: string): CpWorktree[] {
  const out: CpWorktree[] = [];
  let cur: Partial<CpWorktree> = {};
  for (const line of raw.split("\n")) {
    if (line.startsWith("worktree ")) {
      if (cur.path) out.push(cur as CpWorktree);
      cur = { path: line.slice(9).trim(), branch: "(detached)", isMain: false };
    } else if (line.startsWith("branch ")) {
      cur.branch = line.slice(7).trim().replace(/^refs\/heads\//, "");
    }
  }
  if (cur.path) out.push(cur as CpWorktree);
  if (out.length > 0) out[0].isMain = true;
  return out;
}

function toItem(w: CpWorktree): vscode.TreeItem {
  const item = new vscode.TreeItem(w.branch ?? "(detached)");
  item.description = w.path ? path.basename(w.path) : undefined;
  item.iconPath = new vscode.ThemeIcon(w.isMain ? "source-control" : "git-branch");
  return item;
}

export class WorktreesProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private readonly _onDidChangeTreeData =
    new vscode.EventEmitter<vscode.TreeItem | undefined | null | void>();
  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  constructor(private readonly workspaceRoot: string) {}

  refresh(): void { this._onDidChangeTreeData.fire(); }
  getTreeItem(e: vscode.TreeItem): vscode.TreeItem { return e; }

  async getChildren(): Promise<vscode.TreeItem[]> {
    try {
      const raw = await httpGet("http://127.0.0.1:7842/worktrees", 500);
      const list = JSON.parse(raw) as CpWorktree[];
      if (!Array.isArray(list) || list.length === 0) return [this.noneItem()];
      return list.map((w) => {
        const branch = (w.branch ?? "(detached)").replace(/^refs\/heads\//, "");
        const item = new vscode.TreeItem(branch);
        item.description = w.path ? path.basename(w.path) : undefined;
        item.iconPath = new vscode.ThemeIcon(w.isMain ? "source-control" : "git-branch");
        return item;
      });
    } catch {
      return this.fromGit();
    }
  }

  private fromGit(): vscode.TreeItem[] {
    try {
      const out = execSync("git worktree list --porcelain", {
        cwd: this.workspaceRoot, encoding: "utf8", timeout: 3000,
      });
      const wts = parseGitWorktrees(out);
      return wts.length > 0 ? wts.map(toItem) : [this.noneItem()];
    } catch {
      return [this.noneItem()];
    }
  }

  private noneItem(): vscode.TreeItem {
    const item = new vscode.TreeItem("No worktrees found");
    item.iconPath = new vscode.ThemeIcon("info");
    return item;
  }
}
