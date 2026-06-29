import * as vscode from "vscode";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { readRoles } from "./catalogStore";
import { loadIgnoreSizes, saveIgnoreSizes, setBranchOverride, setStreamOverride } from "./panelPrefs";
import { buildProviderLaunchCommand, normalizeProvider, PROVIDER_CHOICES, providerLabel, providerWrapperScript } from "./providerLaunch";
import { buildExplainChangePrompt, buildRefactorPrompt, escapeForDoubleQuotedCli } from "./prompts";
import { findSessionTerminal, sendTextToSessionTerminal } from "./terminalFocus";

export interface DashboardMessageContext {
  workspaceRoot: string;
  update(): void;
  deleteSessionFile(sessionId: string): void;
  focusSessionTab(sessionId: string): void;
  sessionTerminalMap: Map<string, string>;
}

export function handleDashboardMessage(
  msg: { command: string; filePath?: string; sessionRoot?: string; sessionNick?: string },
  ctx: DashboardMessageContext,
): void {
        if (msg.command === "refresh") ctx.update();
        if (msg.command === "focusSessionTab") {
          const sid = (msg as {targetSessionId?: string}).targetSessionId ?? "";
          ctx.focusSessionTab(sid)
          return;
        }
        if (msg.command === "openChat") {
          // "Open Chat" button in session tab — delegate to focusTerminal via same PID-matching logic
          // (handled by the focusTerminal branch below; this branch is a no-op alias)
          (msg as Record<string, unknown>).command = "focusTerminal";
        }
        if (msg.command === "openStream") {
          const fp = String(msg.filePath ?? "");
          const allowed = ctx.workspaceRoot && fp.startsWith(ctx.workspaceRoot + path.sep);
          if (allowed && fp.endsWith(".md")) {
            void vscode.workspace.openTextDocument(fp).then(doc => vscode.window.showTextDocument(doc));
          }
          return;
        }
        if (msg.command === "openDiff") {
          const relPath = (msg as {filePath?: string; sessionRoot?: string; isNew?: boolean}).filePath ?? "";
          const sessRoot = (msg as {filePath?: string; sessionRoot?: string}).sessionRoot ?? ctx.workspaceRoot;
          const isNewFile = (msg as {isNew?: boolean}).isNew ?? false;
          if (!relPath) return;
          // Resolve absolute path — try sessRoot first, then workspaceRoot
          let absPath = path.isAbsolute(relPath) ? relPath : path.join(sessRoot, relPath);
          if (!fs.existsSync(absPath)) {
            const alt = path.join(ctx.workspaceRoot, relPath);
            if (fs.existsSync(alt)) absPath = alt;
          }
          const rightUri = vscode.Uri.file(absPath);
          // New/untracked files have no HEAD version — open the file directly
          if (isNewFile || !fs.existsSync(absPath)) {
            if (fs.existsSync(absPath)) {
              void vscode.window.showTextDocument(rightUri);
            } else {
              void vscode.window.showWarningMessage(`File not found: ${relPath}`);
            }
            return;
          }
          // Check if file is tracked by git before attempting diff
          try {
            const { execSync: _ex } = require("child_process") as typeof import("child_process");
            const status = _ex(`git -C "${sessRoot}" status --porcelain -- "${relPath}" 2>/dev/null`).toString().trim();
            if (status.startsWith("??")) {
              // Untracked — no HEAD version, just open the file
              void vscode.window.showTextDocument(rightUri);
              return;
            }
          } catch { /* fall through to diff attempt */ }
          const gitUri = rightUri.with({
            scheme: "git",
            query: JSON.stringify({ path: absPath, ref: "HEAD" }),
          });
          const fileName = path.basename(absPath);
          void vscode.commands.executeCommand("vscode.diff", gitUri, rightUri, `${fileName}: HEAD ↔ Working Tree`).then(undefined, () => {
            void vscode.window.showTextDocument(rightUri);
          });
          return;
        }
        if (msg.command === "closeSession") {
          const sessionId = (msg as {sessionId?: string}).sessionId ?? "";
          if (!sessionId) return;
          ctx.deleteSessionFile(sessionId);
          ctx.update();
          return;
        }
        if (msg.command === "launchRole") {
          const slug = (msg as {slug?: string; name?: string}).slug ?? "";
          const name = (msg as {slug?: string; name?: string}).name ?? slug;
          if (!slug) return;
          const terminal = vscode.window.createTerminal({ name: `Claude · ${name}`, cwd: ctx.workspaceRoot });
          terminal.show();
          const prompt = `Adopt the ${name} role for this session. Read .platform/roles/${slug}.md for your full protocol, mission, and responsibilities. Ask me 2–3 focused intake questions to understand what I need, then begin working.`;
          const escaped = prompt.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/`/g, "\\`");
          terminal.sendText(`claude "${escaped}"`, true);
          return;
        }
        if (msg.command === "explainChange") {
          const filePath = (msg as {filePath?: string}).filePath ?? "";
          const sessRoot = (msg as {sessionRoot?: string}).sessionRoot ?? ctx.workspaceRoot;
          const added = (msg as {added?: number}).added ?? 0;
          const deleted = (msg as {deleted?: number}).deleted ?? 0;
          const totalChanged = (msg as {totalChanged?: number}).totalChanged ?? 0;
          const shellPid = (msg as {shellPid?: number}).shellPid ?? 0;
          const sessionNick = (msg as {sessionNick?: string}).sessionNick ?? "";
          if (!filePath) return;
          const absPath = path.isAbsolute(filePath) ? filePath : path.join(sessRoot, filePath);
          const explainPrompt = buildExplainChangePrompt({ absPath, added, deleted, totalChanged });

          void (async () => { try {
            await sendTextToSessionTerminal(explainPrompt, {
              shellPid,
              nick: sessionNick,
              root: sessRoot,
              terminalMap: ctx.sessionTerminalMap,
              pickPlaceholder: "Pick the agent terminal to send the explanation request to",
            });
          } catch (err) {
            void vscode.window.showErrorMessage(`Explain change error: ${err instanceof Error ? err.message : String(err)}`);
          } })();
          return;
        }
        if (msg.command === "refactorInSession" || msg.command === "refactorNewSession") {
          const filePath = (msg as {filePath?: string}).filePath ?? "";
          const sessRoot = (msg as {sessionRoot?: string}).sessionRoot ?? ctx.workspaceRoot;
          const lineCount = (msg as {lineCount?: number}).lineCount ?? 0;
          if (!filePath) return;
          const absPath = path.isAbsolute(filePath) ? filePath : path.join(sessRoot, filePath);
          const refactorPrompt = buildRefactorPrompt({ absPath, lineCount });

          if (msg.command === "refactorInSession") {
            const shellPid = (msg as {shellPid?: number}).shellPid ?? 0;
            const sessionNick = (msg as {sessionNick?: string}).sessionNick ?? "";
            void (async () => { try {
              await sendTextToSessionTerminal(refactorPrompt, {
                shellPid,
                nick: sessionNick,
                root: sessRoot,
                terminalMap: ctx.sessionTerminalMap,
                pickPlaceholder: "Pick the agent terminal to send the refactor prompt to",
              });
            } catch (err) {
              void vscode.window.showErrorMessage(`Refactor error: ${err instanceof Error ? err.message : String(err)}`);
            } })();
          } else {
            const cwd = sessRoot || ctx.workspaceRoot;
            void (async () => { try {
              const requested = normalizeProvider((msg as {agentProvider?: string}).agentProvider);
              let provider = requested;
              if (!provider) {
                const preferred = normalizeProvider((msg as {sessionProvider?: string}).sessionProvider);
                const choices = preferred
                ? [...PROVIDER_CHOICES.filter(choice => choice.provider === preferred), ...PROVIDER_CHOICES.filter(choice => choice.provider !== preferred)]
                : PROVIDER_CHOICES;
                const picked = await vscode.window.showQuickPick(
                  choices.map(choice => ({ label: choice.label, description: choice.description, provider: choice.provider })),
                  { placeHolder: "Choose the agent for the new refactor session" },
                );
                if (!picked) return;
                provider = picked.provider;
              }
              const wrapper = providerWrapperScript(provider);
              const hasWrapper = !!wrapper && fs.existsSync(path.join(cwd, wrapper));
              const terminal = vscode.window.createTerminal({ name: `${providerLabel(provider)} · Code Cleanup`, cwd });
              terminal.show();
              const escaped = escapeForDoubleQuotedCli(refactorPrompt);
              terminal.sendText(buildProviderLaunchCommand(provider, escaped, hasWrapper), true);
            } catch (err) {
              void vscode.window.showErrorMessage(`Refactor launch error: ${err instanceof Error ? err.message : String(err)}`);
            } })();
          }
          return;
        }
        if (msg.command === "copyPath") {
          const relPath = (msg as {filePath?: string; sessionRoot?: string}).filePath ?? "";
          const sessRoot = (msg as {filePath?: string; sessionRoot?: string}).sessionRoot ?? ctx.workspaceRoot;
          if (!relPath) return;
          const absPath = path.isAbsolute(relPath) ? relPath : path.join(sessRoot, relPath);
          void vscode.env.clipboard.writeText(absPath).then(() => {
            void vscode.window.setStatusBarMessage(`Copied: ${absPath}`, 3000);
          });
          return;
        }
        if (msg.command === "webviewReady") {
          // Webview JS loaded (fresh HTML set or extension reloaded) — push data immediately
          ctx.update();
          return;
        }
        if (msg.command === "toggleIgnoreSize") {
          const filePath = (msg as {filePath?: string; sessionRoot?: string}).filePath ?? "";
          if (!filePath) return;
          const root = (msg as {filePath?: string; sessionRoot?: string}).sessionRoot || ctx.workspaceRoot || os.homedir();
          const set = loadIgnoreSizes(root);
          if (set.has(filePath)) { set.delete(filePath); } else { set.add(filePath); }
          saveIgnoreSizes(root);
          ctx.update();
          return;
        }
        if (msg.command === "setSessionStream") {
          const { sessionId, streamSlug, sessionRoot } = msg as {sessionId?: string; streamSlug?: string; sessionRoot?: string};
          const root = sessionRoot || ctx.workspaceRoot || os.homedir();
          if (sessionId !== undefined) {
            setStreamOverride(root, sessionId, streamSlug ?? "");
            ctx.update();
          }
          return;
        }
        if (msg.command === "setSessionBranch") {
          const { sessionId, branch, sessionRoot } = msg as {sessionId?: string; branch?: string; sessionRoot?: string};
          const root = sessionRoot || ctx.workspaceRoot || os.homedir();
          if (sessionId) {
            setBranchOverride(root, sessionId, branch ?? "");
            ctx.update();
          }
          return;
        }
        if (msg.command === "closeStream") {
          const { streamSlug, sessionRoot } = msg as {streamSlug?: string; sessionRoot?: string};
          if (!streamSlug) return;
          const cwd = sessionRoot || ctx.workspaceRoot;
          const term = vscode.window.createTerminal({ name: `Close · ${streamSlug}`, cwd });
          term.show();
          term.sendText(`agentboard close ${streamSlug}`, true);
          return;
        }
        if (msg.command === "focusTerminal") {
          const root = (msg as {sessionRoot?: string; sessionNick?: string; shellPid?: number}).sessionRoot ?? "";
          const nick = (msg as {sessionRoot?: string; sessionNick?: string; shellPid?: number}).sessionNick ?? "";
          const shellPid = (msg as {sessionRoot?: string; sessionNick?: string; shellPid?: number}).shellPid ?? 0;
          void (async () => { try {
            const target = await findSessionTerminal({ shellPid, nick, root, terminalMap: ctx.sessionTerminalMap });
            if (target) { target.show(true); return; }
            void vscode.window.showInformationMessage(`⌨ Chat not found for "${nick}". Wait for Claude's next tool call then try again.`);
          } catch (err) {
            void vscode.window.showErrorMessage(`focusTerminal error: ${err instanceof Error ? err.message : String(err)}`);
          } })();
          return;
        }

}
