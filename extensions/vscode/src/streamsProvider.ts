import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";

interface StreamRow {
  name: string;
  status: string;
  lastUpdated: string;
}

function iconForStatus(status: string): string {
  const s = status.toLowerCase();
  if (s.includes("awaiting") || s.includes("verif")) {
    return "warning";
  }
  if (s.includes("block")) {
    return "error";
  }
  return "sync";
}

function parseTableRows(content: string): StreamRow[] {
  const rows: StreamRow[] = [];
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

export class StreamsProvider
  implements vscode.TreeDataProvider<vscode.TreeItem>
{
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
    const activePath = path.join(
      this.workspaceRoot,
      ".platform",
      "work",
      "ACTIVE.md"
    );

    let content: string;
    try {
      content = fs.readFileSync(activePath, "utf8");
    } catch {
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
