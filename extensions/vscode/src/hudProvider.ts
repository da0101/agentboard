import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import { HudStatus } from "./hudTypes";

export class HudProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private readonly _onDidChangeTreeData: vscode.EventEmitter<vscode.TreeItem | undefined | null | void>;

  constructor(
    private readonly workspaceRoot: string,
    emitter: vscode.EventEmitter<vscode.TreeItem | undefined | null | void>
  ) {
    this._onDidChangeTreeData = emitter;
  }

  get onDidChangeTreeData(): vscode.Event<vscode.TreeItem | undefined | null | void> {
    return this._onDidChangeTreeData.event;
  }

  getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
    return element;
  }

  getChildren(): vscode.TreeItem[] {
    const hudPath = path.join(this.workspaceRoot, "agentboard.hud-status.json");

    let hud: HudStatus;
    try {
      const raw = fs.readFileSync(hudPath, "utf8");
      hud = JSON.parse(raw) as HudStatus;
    } catch {
      const item = new vscode.TreeItem("No HUD data — run a session first");
      item.iconPath = new vscode.ThemeIcon("info");
      return [item];
    }

    const items: vscode.TreeItem[] = [];

    const ctx = hud.context;
    if (ctx) {
      const modelLabel = [ctx.model, ctx.branch].filter(Boolean).join(" @ ");
      if (modelLabel) {
        const m = new vscode.TreeItem(modelLabel);
        m.iconPath = new vscode.ThemeIcon("symbol-namespace");
        items.push(m);
      }
      if (ctx.token_pressure) {
        const t = new vscode.TreeItem(`Token pressure: ${ctx.token_pressure}`);
        t.iconPath = new vscode.ThemeIcon("pulse");
        items.push(t);
      }
    }

    const agentCount = hud.active_agents?.length ?? 0;
    const agents = new vscode.TreeItem(`Active agents: ${agentCount}`);
    agents.iconPath = new vscode.ThemeIcon("robot");
    items.push(agents);

    const inProgress = hud.todos?.["in-progress"] ?? [];
    const todosItem = new vscode.TreeItem(
      `Todos in-progress: ${inProgress.length}`
    );
    todosItem.iconPath = new vscode.ThemeIcon("tasklist");
    if (inProgress.length > 0) {
      todosItem.tooltip = inProgress.join("\n");
    }
    items.push(todosItem);

    if (hud.checks?.ci_status) {
      const ci = new vscode.TreeItem(`CI: ${hud.checks.ci_status}`);
      ci.iconPath = new vscode.ThemeIcon(
        hud.checks.ci_status === "passing" ? "pass" : "error"
      );
      items.push(ci);
    }

    if (hud.cost?.session_usd !== undefined) {
      const cost = new vscode.TreeItem(
        `Cost: $${hud.cost.session_usd.toFixed(4)}`
      );
      cost.iconPath = new vscode.ThemeIcon("credit-card");
      items.push(cost);
    }

    const risk = hud.risk;
    if (risk) {
      const flags = [
        risk.dirty_worktree && "dirty worktree",
        risk.uncommitted_changes && "uncommitted changes",
        risk.open_conflicts && "open conflicts",
      ].filter(Boolean);
      const flagCount = flags.length + (risk.manual_review_flags?.length ?? 0);
      const riskItem = new vscode.TreeItem(`Risk flags: ${flagCount}`);
      riskItem.iconPath = new vscode.ThemeIcon(
        flagCount > 0 ? "warning" : "shield"
      );
      if (flagCount > 0) {
        riskItem.tooltip = [...flags, ...(risk.manual_review_flags ?? [])].join(
          "\n"
        );
      }
      items.push(riskItem);
    }

    const openPrs = hud.queue?.open_prs?.length ?? 0;
    const prsItem = new vscode.TreeItem(`Open PRs: ${openPrs}`);
    prsItem.iconPath = new vscode.ThemeIcon("git-pull-request");
    items.push(prsItem);

    return items;
  }
}
