import * as fs from "fs";
import * as os from "os";
import * as path from "path";

const ignoreSizes = new Map<string, Set<string>>();
const streamOverrides = new Map<string, string>();

function ignoreSizePath(): string {
  return path.join(os.homedir(), ".agentboard", "ignore-sizes.json");
}

function overridesPath(): string {
  return path.join(os.homedir(), ".agentboard", "session-stream-overrides.json");
}

export function loadIgnoreSizes(root: string): Set<string> {
  if (ignoreSizes.has(root)) return ignoreSizes.get(root)!;
  try {
    const obj = JSON.parse(fs.readFileSync(ignoreSizePath(), "utf8")) as Record<string, string[]>;
    const set = new Set<string>(obj[root] ?? []);
    ignoreSizes.set(root, set);
    return set;
  } catch {
    const s = new Set<string>();
    ignoreSizes.set(root, s);
    return s;
  }
}

export function saveIgnoreSizes(root: string): void {
  try {
    const fp = ignoreSizePath();
    let obj: Record<string, string[]> = {};
    try { obj = JSON.parse(fs.readFileSync(fp, "utf8")); } catch { /* new */ }
    const set = ignoreSizes.get(root) ?? new Set();
    if (set.size > 0) {
      obj[root] = [...set];
    } else {
      delete obj[root];
    }
    fs.mkdirSync(path.dirname(fp), { recursive: true });
    fs.writeFileSync(fp, JSON.stringify(obj, null, 2));
  } catch {
    // Ignore preference persistence failures.
  }
}

export function loadStreamOverride(root: string, sessionId: string): string | undefined {
  const key = `${root}::${sessionId}`;
  if (streamOverrides.has(key)) return streamOverrides.get(key);
  try {
    const obj = JSON.parse(fs.readFileSync(overridesPath(), "utf8")) as Record<string, string>;
    for (const [k, v] of Object.entries(obj)) streamOverrides.set(k, v);
    return streamOverrides.get(key);
  } catch {
    return undefined;
  }
}

export function setStreamOverride(root: string, sessionId: string, slug: string): void {
  const key = `${root}::${sessionId}`;
  streamOverrides.set(key, slug);
  try {
    const fp = overridesPath();
    let obj: Record<string, string> = {};
    try { obj = JSON.parse(fs.readFileSync(fp, "utf8")); } catch { /* new */ }
    obj[key] = slug;
    fs.mkdirSync(path.dirname(fp), { recursive: true });
    fs.writeFileSync(fp, JSON.stringify(obj, null, 2));
  } catch {
    // Ignore preference persistence failures.
  }
}
