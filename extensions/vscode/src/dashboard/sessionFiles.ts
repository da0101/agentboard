import * as fs from "fs";
import * as os from "os";
import * as path from "path";

function sessionsDir(): string {
  return path.join(os.homedir(), ".agentboard", "sessions");
}

function normalizeRoot(root: string): string {
  const resolved = (() => {
    try { return fs.realpathSync.native(root); } catch { return path.resolve(root); }
  })();
  return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}

export function sessionRootMatchesWorkspace(sessionRoot: string, workspaceRoot: string): boolean {
  if (!sessionRoot || !workspaceRoot) return false;
  return normalizeRoot(sessionRoot) === normalizeRoot(workspaceRoot);
}

export function deleteSessionFile(sessionId: string): void {
  const f = path.join(sessionsDir(), `${sessionId}.json`);
  try { fs.unlinkSync(f); } catch { /* already gone */ }
}

export function deleteSessionFileByShellPid(pid: number): boolean {
  if (!pid) return false;
  try {
    for (const fname of fs.readdirSync(sessionsDir())) {
      if (!fname.endsWith(".json")) continue;
      try {
        const raw = fs.readFileSync(path.join(sessionsDir(), fname), "utf8");
        const d = JSON.parse(raw) as { _shell_pid?: number };
        if (d._shell_pid === pid) {
          fs.unlinkSync(path.join(sessionsDir(), fname));
          return true;
        }
      } catch {
        // skip malformed session file
      }
    }
  } catch {
    // sessions dir missing
  }
  return false;
}
