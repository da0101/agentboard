import * as fs from "fs";
import * as os from "os";
import * as path from "path";

type ExistsFn = (filePath: string) => boolean;
type ReadFileFn = (filePath: string) => string;

interface GlobalLiveOptions {
  homeDir?: string;
  nowMs?: number;
  exists?: ExistsFn;
  readFile?: ReadFileFn;
}

export function detectWorkspaceRootFromFolders(
  folders: readonly string[],
  exists: ExistsFn = fs.existsSync
): string {
  if (!folders.length) return "";
  const scored = folders.map(p => {
    let score = 0;
    if (exists(path.join(p, "agentboard.hud-status.json"))) score += 10;
    if (exists(path.join(p, ".platform", "work"))) score += 5;
    if (exists(path.join(p, ".platform"))) score += 2;
    if (exists(path.join(p, ".claude", "settings.json"))) score += 1;
    return { p, score };
  }).filter(f => f.score > 0).sort((a, b) => b.score - a.score);
  return scored[0]?.p ?? "";
}

export function detectWorkspaceRootFromGlobalLive(options: GlobalLiveOptions = {}): string {
  const exists = options.exists ?? fs.existsSync;
  const readFile = options.readFile ?? ((filePath: string) => fs.readFileSync(filePath, "utf8"));
  const nowMs = options.nowMs ?? Date.now();
  const homeDir = options.homeDir ?? os.homedir();
  const globalLive = path.join(homeDir, ".agentboard", "live.json");
  try {
    const live = JSON.parse(readFile(globalLive)) as { _root?: string; last_updated?: string };
    const root = live._root ?? "";
    if (root && exists(path.join(root, ".platform"))) {
      const ageMs = nowMs - new Date(live.last_updated ?? 0).getTime();
      if (ageMs < 4 * 60 * 60 * 1000) return root;
    }
  } catch { /* fall through */ }
  return "";
}

export function detectWorkspaceRootFromSources(
  folders: readonly string[],
  globalLiveOptions: GlobalLiveOptions = {}
): string {
  const workspaceRoot = detectWorkspaceRootFromFolders(folders, globalLiveOptions.exists);
  if (workspaceRoot) return workspaceRoot;
  return detectWorkspaceRootFromGlobalLive(globalLiveOptions);
}
