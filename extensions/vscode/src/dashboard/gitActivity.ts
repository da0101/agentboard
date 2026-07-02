import * as fs from "fs";
import * as path from "path";
import { execFileSync } from "child_process";
import { SessionActivityItem } from "./types";

const NUMSTAT_TTL = 30_000;
const LINE_COUNT_TTL = 60_000;
const COMMITTED_TTL = 30_000;

export interface ActivityGitCaches {
  numstatCache: Map<string, { ts: number; diffMap: Map<string, { added: number; deleted: number }> }>;
  lineCountCache: Map<string, { ts: number; count: number }>;
  branchCommittedCache: Map<string, { ts: number; files: Set<string> }>;
}

interface ActivityFileLocation {
  absFile: string;
  gitRoot: string;
  gitRel: string;
}

function normalizeGitPath(file: string): string {
  return file.replace(/\\/g, "/");
}

function activityFileLocation(root: string, file: string): ActivityFileLocation | null {
  if (!file || file.startsWith("$ ")) return null;
  const rawAbsFile = path.isAbsolute(file) ? file : path.join(root, file);
  const absFile = (() => {
    try { return fs.realpathSync.native(rawAbsFile); } catch { return path.resolve(rawAbsFile); }
  })();
  let gitRoot = (() => {
    try { return fs.realpathSync.native(root); } catch { return path.resolve(root); }
  })();
  try {
    const dir = fs.existsSync(absFile) && fs.statSync(absFile).isDirectory() ? absFile : path.dirname(absFile);
    const rawGitRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: dir, timeout: 1000, encoding: "utf8" }).trim() || gitRoot;
    gitRoot = fs.realpathSync.native(rawGitRoot);
  } catch {
    // keep fallback root
  }
  const gitRel = normalizeGitPath(path.relative(gitRoot, absFile));
  if (!gitRel || gitRel.startsWith("..")) return { absFile, gitRoot, gitRel: normalizeGitPath(file) };
  return { absFile, gitRoot, gitRel };
}

export function applyGitStatus(
  activity: SessionActivityItem[],
  statusOut: string,
  nowIso = new Date().toISOString(),
  timestampForFile?: (file: string, xy: string) => string,
): void {
  const statusMap = new Map<string, string>();
  for (const line of statusOut.split("\n")) {
    if (line.length < 4) continue;
    const xy = line.slice(0, 2);
    const fpath = line.slice(3).trim().replace(/^"(.*)"$/, "$1");
    statusMap.set(normalizeGitPath(fpath), xy);
  }
  for (const entry of activity) {
    const xy = statusMap.get(normalizeGitPath(entry.file)) ?? "";
    if (xy === "??" || xy[0] === "A" || xy[1] === "A") entry.isNew = true;
    else if (xy[0] === "D" || xy[1] === "D") entry.isDeleted = true;
  }
  const existing = new Set(activity.map(entry => normalizeGitPath(entry.file)));
  for (const [file, xy] of statusMap) {
    const normalized = normalizeGitPath(file);
    if (existing.has(normalized)) continue;
    if (xy !== "??" && xy[0] !== "A" && xy[1] !== "A" && xy[0] !== "D" && xy[1] !== "D") continue;
    activity.push({
      file,
      tool: xy[0] === "D" || xy[1] === "D" ? "Delete" : "Write",
      count: 1,
      lastTs: timestampForFile?.(file, xy) || nowIso,
      isNew: xy === "??" || xy[0] === "A" || xy[1] === "A",
      isDeleted: xy[0] === "D" || xy[1] === "D",
    });
    existing.add(normalized);
  }
  activity.sort((a, b) => b.lastTs.localeCompare(a.lastTs));
}

export function enrichActivityWithGit(root: string, activity: SessionActivityItem[], caches: ActivityGitCaches, now = Date.now()): void {
  enrichDiffStats(root, activity, caches.numstatCache, now);
  try {
    const statusOut = execFileSync("git", ["-C", root, "status", "--porcelain", "--untracked-files=all"], {
      timeout: 3000,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const fallbackTs = new Date(now).toISOString();
    applyGitStatus(activity, statusOut, fallbackTs, (file, xy) => {
      if (xy[0] === "D" || xy[1] === "D") return fallbackTs;
      try {
        return fs.statSync(path.join(root, file)).mtime.toISOString();
      } catch {
        return fallbackTs;
      }
    });
  } catch {
    // git unavailable
  }
  enrichLineCounts(root, activity, caches.lineCountCache, now);
  enrichCommittedMarkers(root, activity, caches.branchCommittedCache, now);
}

function enrichDiffStats(
  root: string,
  activity: SessionActivityItem[],
  cache: Map<string, { ts: number; diffMap: Map<string, { added: number; deleted: number }> }>,
  now: number,
): void {
  const diffMapForRoot = (gitRoot: string): Map<string, { added: number; deleted: number }> => {
    const cached = cache.get(gitRoot);
    let diffMap: Map<string, { added: number; deleted: number }>;
    if (cached && (now - cached.ts) < NUMSTAT_TTL) {
      diffMap = cached.diffMap;
    } else {
      diffMap = new Map<string, { added: number; deleted: number }>();
      const numstatOut = execFileSync("git", ["diff", "--numstat", "HEAD"], { cwd: gitRoot, timeout: 3000, encoding: "utf8" });
      for (const line of numstatOut.split("\n")) {
        const m = line.match(/^(\d+)\t(\d+)\t(.+)$/);
        if (m) diffMap.set(normalizeGitPath(m[3].trim()), { added: parseInt(m[1], 10), deleted: parseInt(m[2], 10) });
      }
      cache.set(gitRoot, { ts: now, diffMap });
    }
    return diffMap;
  };

  try {
    for (const entry of activity) {
      if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
        const loc = activityFileLocation(root, entry.file);
        if (!loc) continue;
        const stats = diffMapForRoot(loc.gitRoot).get(loc.gitRel);
        if (stats) {
          entry.added = stats.added;
          entry.deleted = stats.deleted;
        }
      }
    }
  } catch {
    // git unavailable or repo not found
  }
}

function enrichLineCounts(root: string, activity: SessionActivityItem[], cache: Map<string, { ts: number; count: number }>, now: number): void {
  for (const entry of activity) {
    if (!root) continue;
    const loc = activityFileLocation(root, entry.file);
    if (!loc) continue;
    try {
      const cached = cache.get(loc.absFile);
      if (cached && (now - cached.ts) < LINE_COUNT_TTL) {
        entry.lineCount = cached.count;
      } else {
        const lines = fs.readFileSync(loc.absFile, "utf8").split("\n").length;
        cache.set(loc.absFile, { ts: now, count: lines });
        entry.lineCount = lines;
      }
    } catch {
      // file may not exist yet
    }
  }
}

function enrichCommittedMarkers(root: string, activity: SessionActivityItem[], cache: Map<string, { ts: number; files: Set<string> }>, now: number): void {
  try {
    const cached = cache.get(root);
    let committedFiles: Set<string>;
    if (cached && (now - cached.ts) < COMMITTED_TTL) {
      committedFiles = cached.files;
    } else {
      committedFiles = new Set<string>();
      let mergeBase = "";
      for (const base of ["origin/develop", "origin/main", "HEAD~1"]) {
        try {
          mergeBase = execFileSync("git", ["merge-base", "HEAD", base], { cwd: root, timeout: 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
          if (mergeBase) break;
        } catch {
          // try next
        }
      }
      if (mergeBase) {
        const nameOnly = execFileSync("git", ["diff", "--name-only", `${mergeBase}..HEAD`], { cwd: root, timeout: 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
        for (const line of nameOnly.split("\n")) {
          const f = line.trim();
          if (f) committedFiles.add(f);
        }
      }
      cache.set(root, { ts: now, files: committedFiles });
    }
    for (const entry of activity) {
      if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
        const loc = activityFileLocation(root, entry.file);
        entry.committed = loc ? committedFiles.has(loc.gitRel) : false;
      }
    }
  } catch {
    // git unavailable
  }
}
