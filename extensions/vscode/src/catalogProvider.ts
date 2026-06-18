import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";

const CLI_COMMANDS = ["init", "new-stream", "new-domain", "checkpoint", "handoff",
  "doctor", "brief", "progress", "close", "watch", "migrate", "sync-skills", "validate", "usage"];

export type CatalogKind = "skills" | "roles" | "commands" | "item";

export class CatalogItem extends vscode.TreeItem {
  constructor(
    public readonly kind: CatalogKind,
    label: string,
    description?: string,
    iconId?: string,
    collapsible = vscode.TreeItemCollapsibleState.None
  ) {
    super(label, collapsible);
    this.description = description;
    if (iconId) {
      this.iconPath = new vscode.ThemeIcon(iconId);
    }
  }
}

export class CatalogProvider implements vscode.TreeDataProvider<CatalogItem> {
  private readonly _onDidChangeTreeData =
    new vscode.EventEmitter<CatalogItem | undefined | null | void>();

  readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

  constructor(private readonly workspaceRoot: string) {}

  refresh(): void {
    this._onDidChangeTreeData.fire();
  }

  getTreeItem(element: CatalogItem): CatalogItem {
    return element;
  }

  getChildren(element?: CatalogItem): CatalogItem[] {
    if (!element) {
      return this.rootGroups();
    }
    if (element.kind === "skills") return this.skillItems();
    if (element.kind === "roles") return this.roleItems();
    if (element.kind === "commands") return this.commandItems();
    return [];
  }

  private rootGroups(): CatalogItem[] {
    const skillCount = this.listSkillDirs().length;
    const roleCount = this.listRoleFiles().length;

    const skills = new CatalogItem(
      "skills", "Skills", `${skillCount}`, "folder",
      vscode.TreeItemCollapsibleState.Collapsed
    );
    const roles = new CatalogItem(
      "roles", "Roles", `${roleCount}`, "person",
      vscode.TreeItemCollapsibleState.Collapsed
    );
    const commands = new CatalogItem(
      "commands", "Commands", `${CLI_COMMANDS.length}`, "terminal",
      vscode.TreeItemCollapsibleState.Collapsed
    );
    return [skills, roles, commands];
  }

  private skillItems(): CatalogItem[] {
    return this.listSkillDirs().map((dir) => {
      const desc = this.readSkillDescription(dir);
      return new CatalogItem("item", path.basename(dir), desc, "symbol-function");
    });
  }

  private roleItems(): CatalogItem[] {
    return this.listRoleFiles().map((file) => {
      const label = path.basename(file, ".md");
      return new CatalogItem("item", label, undefined, "person");
    });
  }

  private commandItems(): CatalogItem[] {
    return CLI_COMMANDS.map(
      (cmd) => new CatalogItem("item", cmd, undefined, "terminal")
    );
  }

  private listSkillDirs(): string[] {
    const skillsDir = path.join(this.workspaceRoot, ".claude", "skills");
    try {
      return fs
        .readdirSync(skillsDir, { withFileTypes: true })
        .filter((d: fs.Dirent) => d.isDirectory())
        .map((d: fs.Dirent) => path.join(skillsDir, d.name));
    } catch {
      return [];
    }
  }

  private listRoleFiles(): string[] {
    for (const sub of [".platform/roles", "templates/platform/roles"]) {
      const dir = path.join(this.workspaceRoot, sub);
      try {
        return fs.readdirSync(dir)
          .filter((f: string) => f.endsWith(".md") && f !== "INDEX.md")
          .map((f: string) => path.join(dir, f));
      } catch { continue; }
    }
    return [];
  }

  private readSkillDescription(dir: string): string | undefined {
    try {
      const content = fs.readFileSync(path.join(dir, "SKILL.md"), "utf8");
      for (const line of content.split("\n")) {
        const match = /^description:\s*(.+)/i.exec(line.trim());
        if (match) return match[1].trim();
      }
    } catch {
      // no SKILL.md or unreadable
    }
    return undefined;
  }
}
