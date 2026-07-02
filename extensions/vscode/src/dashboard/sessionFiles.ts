import * as fs from "fs";
import * as path from "path";

const RUNTIME_DIR = path.join(".platform", "runtime", "agentboard");
const SAFE_SESSION_ID = /^[A-Za-z0-9_.:-]{1,160}$/;

export function runtimeDirForRoot(workspaceRoot: string): string {
  return path.join(workspaceRoot, RUNTIME_DIR);
}

export function sessionsDirForRoot(workspaceRoot: string): string {
  return path.join(runtimeDirForRoot(workspaceRoot), "sessions");
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

export function listSessionFiles(workspaceRoot: string): string[] {
  try {
    return fs.readdirSync(sessionsDirForRoot(workspaceRoot))
      .filter((f: string) => f.endsWith(".json"));
  } catch {
    return [];
  }
}

export function readSessionFile(workspaceRoot: string, fileName: string): Record<string, unknown> | null {
  try {
    return JSON.parse(fs.readFileSync(path.join(sessionsDirForRoot(workspaceRoot), fileName), "utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function sessionFilePath(workspaceRoot: string, sessionId: string): string | null {
  if (!SAFE_SESSION_ID.test(sessionId)) return null;
  const dir = path.resolve(sessionsDirForRoot(workspaceRoot));
  const filePath = path.resolve(dir, `${sessionId}.json`);
  const rel = path.relative(dir, filePath);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) return null;
  return filePath;
}

export function deleteSessionFile(workspaceRoot: string, sessionId: string): boolean {
  const f = sessionFilePath(workspaceRoot, sessionId);
  if (!f) return false;
  try { fs.unlinkSync(f); } catch { /* already gone */ }
  return true;
}

export function deleteWorkspaceSessionFile(workspaceRoot: string, sessionRoot: string, sessionId: string): boolean {
  const root = sessionRoot || workspaceRoot;
  if (!sessionRootMatchesWorkspace(root, workspaceRoot)) return false;
  return deleteSessionFile(root, sessionId);
}

export function deleteSessionFileByShellPid(workspaceRoot: string, pid: number): boolean {
  if (!pid) return false;
  for (const fname of listSessionFiles(workspaceRoot)) {
    try {
      const raw = fs.readFileSync(path.join(sessionsDirForRoot(workspaceRoot), fname), "utf8");
      const d = JSON.parse(raw) as { _shell_pid?: number };
      if (d._shell_pid === pid) {
        fs.unlinkSync(path.join(sessionsDirForRoot(workspaceRoot), fname));
        return true;
      }
    } catch {
      // skip malformed session file
    }
  }
  return false;
}
