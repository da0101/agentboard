"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CatalogProvider = exports.CatalogItem = void 0;
const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const CLI_COMMANDS = ["init", "new-stream", "new-domain", "checkpoint", "handoff",
    "doctor", "brief", "progress", "close", "watch", "migrate", "sync-skills", "validate", "usage"];
class CatalogItem extends vscode.TreeItem {
    constructor(kind, label, description, iconId, collapsible = vscode.TreeItemCollapsibleState.None) {
        super(label, collapsible);
        this.kind = kind;
        this.description = description;
        if (iconId) {
            this.iconPath = new vscode.ThemeIcon(iconId);
        }
    }
}
exports.CatalogItem = CatalogItem;
class CatalogProvider {
    constructor(workspaceRoot) {
        this.workspaceRoot = workspaceRoot;
        this._onDidChangeTreeData = new vscode.EventEmitter();
        this.onDidChangeTreeData = this._onDidChangeTreeData.event;
    }
    refresh() {
        this._onDidChangeTreeData.fire();
    }
    getTreeItem(element) {
        return element;
    }
    getChildren(element) {
        if (!element) {
            return this.rootGroups();
        }
        if (element.kind === "skills")
            return this.skillItems();
        if (element.kind === "roles")
            return this.roleItems();
        if (element.kind === "commands")
            return this.commandItems();
        return [];
    }
    rootGroups() {
        const skillCount = this.listSkillDirs().length;
        const roleCount = this.listRoleFiles().length;
        const skills = new CatalogItem("skills", "Skills", `${skillCount}`, "folder", vscode.TreeItemCollapsibleState.Collapsed);
        const roles = new CatalogItem("roles", "Roles", `${roleCount}`, "person", vscode.TreeItemCollapsibleState.Collapsed);
        const commands = new CatalogItem("commands", "Commands", `${CLI_COMMANDS.length}`, "terminal", vscode.TreeItemCollapsibleState.Collapsed);
        return [skills, roles, commands];
    }
    skillItems() {
        return this.listSkillDirs().map((dir) => {
            const desc = this.readSkillDescription(dir);
            return new CatalogItem("item", path.basename(dir), desc, "symbol-function");
        });
    }
    roleItems() {
        return this.listRoleFiles().map((file) => {
            const label = path.basename(file, ".md");
            return new CatalogItem("item", label, undefined, "person");
        });
    }
    commandItems() {
        return CLI_COMMANDS.map((cmd) => new CatalogItem("item", cmd, undefined, "terminal"));
    }
    listSkillDirs() {
        const skillsDir = path.join(this.workspaceRoot, ".claude", "skills");
        try {
            return fs
                .readdirSync(skillsDir, { withFileTypes: true })
                .filter((d) => d.isDirectory())
                .map((d) => path.join(skillsDir, d.name));
        }
        catch {
            return [];
        }
    }
    listRoleFiles() {
        for (const sub of [".platform/roles", "templates/platform/roles"]) {
            const dir = path.join(this.workspaceRoot, sub);
            try {
                return fs.readdirSync(dir)
                    .filter((f) => f.endsWith(".md") && f !== "INDEX.md")
                    .map((f) => path.join(dir, f));
            }
            catch {
                continue;
            }
        }
        return [];
    }
    readSkillDescription(dir) {
        try {
            const content = fs.readFileSync(path.join(dir, "SKILL.md"), "utf8");
            for (const line of content.split("\n")) {
                const match = /^description:\s*(.+)/i.exec(line.trim());
                if (match)
                    return match[1].trim();
            }
        }
        catch {
            // no SKILL.md or unreadable
        }
        return undefined;
    }
}
exports.CatalogProvider = CatalogProvider;
