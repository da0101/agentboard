import * as fs from "fs";
import * as path from "path";
import { execFileSync } from "child_process";
import { readStreams } from "./catalogStore";
import { sessionRootMatchesWorkspace } from "./sessionFiles";
import { AgentEntry, DashboardSessionEntry, SessionActivityItem } from "./types";

const RAW_CODEX_SCAN_TTL_MS = 10_000;
const MAX_RAW_CODEX_PROCESSES = 20;

export interface RawCodexProcess {
  pid: number;
  elapsedSeconds: number;
  command: string;
  cwd: string;
  root: string;
  effort: string;
}

export interface RawCodexProcessCache {
  ts: number;
  processes: RawCodexProcess[];
}

export interface RawCodexSessionOptions {
  activity?: SessionActivityItem[];
  agents?: AgentEntry[];
  agentActivity?: AgentEntry[];
  stream?: string;
}

export function parseElapsedSeconds(value: string): number {
  const daySplit = value.split("-");
  const dayCount = daySplit.length === 2 ? Number(daySplit[0]) : 0;
  const timePart = daySplit.length === 2 ? daySplit[1] : daySplit[0];
  const parts = timePart.split(":").map(Number);
  if (parts.some(part => !Number.isFinite(part))) return 0;
  let seconds = 0;
  if (parts.length === 3) seconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) seconds = parts[0] * 60 + parts[1];
  if (parts.length === 1) seconds = parts[0];
  return dayCount * 24 * 3600 + seconds;
}

export function parsePsCodexProcesses(output: string): Array<{ pid: number; elapsedSeconds: number; command: string }> {
  const rows: Array<{ pid: number; elapsedSeconds: number; command: string }> = [];
  for (const line of output.split(/\r?\n/)) {
    const match = line.match(/^\s*(\d+)\s+(\S+)\s+(.+)$/);
    if (!match) continue;
    const pid = Number(match[1]);
    const command = match[3].trim();
    const executable = command.split(/\s+/)[0] ?? "";
    if (!Number.isFinite(pid)) continue;
    if (!/(^|\/)codex$/.test(executable)) continue;
    rows.push({ pid, elapsedSeconds: parseElapsedSeconds(match[2]), command });
    if (rows.length >= MAX_RAW_CODEX_PROCESSES) break;
  }
  return rows;
}

export function parseLsofCwd(output: string): string {
  for (const line of output.split(/\r?\n/)) {
    if (line.startsWith("n/")) return line.slice(1).trim();
  }
  return "";
}

export function findProjectRoot(cwd: string): string {
  let dir = cwd;
  for (let i = 0; i < 30; i++) {
    if (fs.existsSync(path.join(dir, ".platform")) || fs.existsSync(path.join(dir, ".git"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return cwd;
}

export function parseCodexEffort(command: string): string {
  const match = command.match(/model_reasoning_effort=(?:"([^"]+)"|'([^']+)'|([^\s]+))/);
  return (match?.[1] || match?.[2] || match?.[3] || "medium").trim();
}

export function readRawCodexProcesses(): RawCodexProcess[] {
  if (process.platform === "win32") return [];
  let psOutput = "";
  try {
    psOutput = execFileSync("ps", ["-axo", "pid=,etime=,command="], { encoding: "utf8", timeout: 1500 });
  } catch {
    return [];
  }

  const processes: RawCodexProcess[] = [];
  for (const proc of parsePsCodexProcesses(psOutput)) {
    try {
      const lsofOutput = execFileSync("lsof", ["-a", "-p", String(proc.pid), "-d", "cwd", "-Fn"], {
        encoding: "utf8",
        timeout: 1000,
      });
      const cwd = parseLsofCwd(lsofOutput);
      if (!cwd) continue;
      const root = findProjectRoot(cwd);
      processes.push({ ...proc, cwd, root, effort: parseCodexEffort(proc.command) });
    } catch {
      // Process may exit between ps and lsof, or lsof may be unavailable.
    }
  }
  return processes;
}

export function getRawCodexProcesses(cache: RawCodexProcessCache, now = Date.now()): RawCodexProcessCache {
  if (now - cache.ts < RAW_CODEX_SCAN_TTL_MS) return cache;
  return { ts: now, processes: readRawCodexProcesses() };
}

function elapsedFromSeconds(seconds: number): string {
  if (seconds >= 3600) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

export function rawCodexProcessToSession(
  proc: RawCodexProcess,
  workspaceRoot: string,
  branch: string,
  now = Date.now(),
  options: RawCodexSessionOptions = {},
): DashboardSessionEntry | null {
  if (!sessionRootMatchesWorkspace(proc.root, workspaceRoot)) return null;
  const sessionId = `raw-codex-${proc.pid}`;
  const startedAt = new Date(now - proc.elapsedSeconds * 1000).toISOString();
  const lastUpdated = new Date(now).toISOString();
  return {
    sessionId,
    provider: "codex",
    model: `Codex ${proc.effort}`,
    costUsd: 0,
    cost: "",
    branch,
    root: proc.root,
    shellPid: proc.pid,
    projectName: path.basename(proc.root),
    sessionLastSkill: "",
    sessionLastRole: "",
    startedAt,
    lastUpdated,
    ageSeconds: 0,
    ctxPct: null,
    stream: options.stream ?? "",
    streamPinned: false,
    availableStreams: readStreams(proc.root).map(st => st.slug),
    sessionTime: elapsedFromSeconds(proc.elapsedSeconds),
    activity: options.activity ?? [],
    agents: options.agents ?? [],
    agentActivity: options.agentActivity ?? [],
    hasWorkflow: false,
    workflowAgentCount: 0,
    workflowLabel: "",
    workflowTranscriptAgents: [],
    workflowPlan: null,
    nick: "",
  };
}
