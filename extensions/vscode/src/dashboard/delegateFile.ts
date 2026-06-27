import * as vscode from "vscode";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { readRoles } from "./catalogStore";
import { escapeForDoubleQuotedCli } from "./prompts";

export interface DelegateState {
  lastDelegateKey: string;
  lastDelegateTs: number;
}

export function handleDelegateFile(workspaceRoot: string, terminalMap: Map<string, string>, state: DelegateState): void {
  const delegateFile = path.join(os.homedir(), ".agentboard", "delegate.json");
  if (!fs.existsSync(delegateFile)) return;
  let raw: string;
  try {
    raw = fs.readFileSync(delegateFile, "utf8");
    fs.unlinkSync(delegateFile);
  } catch {
    return;
  }
  try {
    const d = JSON.parse(raw) as { role?: string; task?: string; context?: string; branch?: string; root?: string; project?: string };
    if (!d.role || !d.task) return;
    const dedupeKey = `${d.role}|${d.task}`;
    if (dedupeKey === state.lastDelegateKey && (Date.now() - state.lastDelegateTs) < 60_000) return;
    state.lastDelegateKey = dedupeKey;
    state.lastDelegateTs = Date.now();
    const roles = readRoles(d.root ?? workspaceRoot);
    const roleItem = roles.find(r => r.slug === d.role);
    const roleName = roleItem?.name ?? d.role;
    const lines: string[] = [
      `Adopt the ${roleName} role for this session.`,
      `Read .platform/roles/${d.role}.md for your full protocol, mission, and responsibilities.`,
    ];
    if (d.project || d.branch) {
      const from = [d.project, d.branch ? `branch: ${d.branch}` : ""].filter(Boolean).join(" — ");
      lines.push(`\nHandoff from: ${from}`);
    }
    if (d.context) lines.push(d.context);
    lines.push(`\nYour task: ${d.task}`);
    lines.push("\nAsk me 2–3 focused intake questions if anything needs clarification, then begin.");
    const prompt = lines.join("\n");
    const cwd = d.root && fs.existsSync(d.root) ? d.root : workspaceRoot;
    const termName = `Claude · ${roleName}`;
    const terminal = vscode.window.createTerminal({ name: termName, cwd });
    terminal.show();
    terminal.sendText(`claude "${escapeForDoubleQuotedCli(prompt)}"`, true);
    terminalMap.set(d.role, termName);
  } catch {
    // malformed delegate.json
  }
}
