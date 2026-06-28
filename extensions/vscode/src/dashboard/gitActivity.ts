import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";
import { SessionActivityItem } from "./types";

const NUMSTAT_TTL = 30_000;
const LINE_COUNT_TTL = 60_000;
const COMMITTED_TTL = 30_000;

export interface ActivityGitCaches {
  numstatCache: Map<string, { ts: number; diffMap: Map<string, { added: number; deleted: number }> }>;
  lineCountCache: Map<string, { ts: number; count: number }>;
  branchCommittedCache: Map<string, { ts: number; files: Set<string> }>;
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
    statusMap.set(fpath, xy);
  }
  for (const entry of activity) {
    const xy = statusMap.get(entry.file) ?? statusMap.get(entry.file.replace(/\\/g, "/")) ?? "";
    if (xy === "??" || xy[0] === "A" || xy[1] === "A") entry.isNew = true;
    else if (xy[0] === "D" || xy[1] === "D") entry.isDeleted = true;
  }
  const existing = new Set(activity.map(entry => entry.file.replace(/\\/g, "/")));
  for (const [file, xy] of statusMap) {
    const normalized = file.replace(/\\/g, "/");
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
    const statusOut = execSync(`git -C "${root}" status --porcelain --untracked-files=all 2>/dev/null`, { timeout: 3000, encoding: "utf8" });
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
  try {
    const cached = cache.get(root);
    let diffMap: Map<string, { added: number; deleted: number }>;
    if (cached && (now - cached.ts) < NUMSTAT_TTL) {
      diffMap = cached.diffMap;
    } else {
      diffMap = new Map<string, { added: number; deleted: number }>();
      const numstatOut = execSync("git diff --numstat HEAD", { cwd: root, timeout: 3000, encoding: "utf8" });
      for (const line of numstatOut.split("\n")) {
        const m = line.match(/^(\d+)\t(\d+)\t(.+)$/);
        if (m) diffMap.set(m[3].trim(), { added: parseInt(m[1], 10), deleted: parseInt(m[2], 10) });
      }
      cache.set(root, { ts: now, diffMap });
    }
    for (const entry of activity) {
      if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
        const stats = diffMap.get(entry.file);
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
    if (entry.file.startsWith("$ ") || !root) continue;
    const absFile = path.join(root, entry.file);
    try {
      const cached = cache.get(absFile);
      if (cached && (now - cached.ts) < LINE_COUNT_TTL) {
        entry.lineCount = cached.count;
      } else {
        const lines = fs.readFileSync(absFile, "utf8").split("\n").length;
        cache.set(absFile, { ts: now, count: lines });
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
          mergeBase = execSync(`git merge-base HEAD ${base}`, { cwd: root, timeout: 3000, encoding: "utf8" }).trim();
          if (mergeBase) break;
        } catch {
          // try next
        }
      }
      if (mergeBase) {
        const nameOnly = execSync(`git diff --name-only ${mergeBase}..HEAD`, { cwd: root, timeout: 3000, encoding: "utf8" });
        for (const line of nameOnly.split("\n")) {
          const f = line.trim();
          if (f) committedFiles.add(f);
        }
      }
      cache.set(root, { ts: now, files: committedFiles });
    }
    for (const entry of activity) {
      if (entry.tool === "Edit" || entry.tool === "Write" || entry.tool === "MultiEdit") {
        entry.committed = committedFiles.has(entry.file);
      }
    }
  } catch {
    // git unavailable
  }
}
