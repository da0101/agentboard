"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseElapsedSeconds = parseElapsedSeconds;
exports.parsePsCodexProcesses = parsePsCodexProcesses;
exports.parseLsofCwd = parseLsofCwd;
exports.findProjectRoot = findProjectRoot;
exports.parseCodexEffort = parseCodexEffort;
exports.readRawCodexProcesses = readRawCodexProcesses;
exports.getRawCodexProcesses = getRawCodexProcesses;
exports.rawCodexProcessToSession = rawCodexProcessToSession;
const fs = require("fs");
const path = require("path");
const child_process_1 = require("child_process");
const catalogStore_1 = require("./catalogStore");
const sessionFiles_1 = require("./sessionFiles");
const RAW_CODEX_SCAN_TTL_MS = 10000;
const MAX_RAW_CODEX_PROCESSES = 20;
function parseElapsedSeconds(value) {
    const daySplit = value.split("-");
    const dayCount = daySplit.length === 2 ? Number(daySplit[0]) : 0;
    const timePart = daySplit.length === 2 ? daySplit[1] : daySplit[0];
    const parts = timePart.split(":").map(Number);
    if (parts.some(part => !Number.isFinite(part)))
        return 0;
    let seconds = 0;
    if (parts.length === 3)
        seconds = parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length === 2)
        seconds = parts[0] * 60 + parts[1];
    if (parts.length === 1)
        seconds = parts[0];
    return dayCount * 24 * 3600 + seconds;
}
function parsePsCodexProcesses(output) {
    const rows = [];
    for (const line of output.split(/\r?\n/)) {
        const match = line.match(/^\s*(\d+)\s+(\S+)\s+(.+)$/);
        if (!match)
            continue;
        const pid = Number(match[1]);
        const command = match[3].trim();
        const executable = command.split(/\s+/)[0] ?? "";
        if (!Number.isFinite(pid))
            continue;
        if (!/(^|\/)codex$/.test(executable))
            continue;
        rows.push({ pid, elapsedSeconds: parseElapsedSeconds(match[2]), command });
        if (rows.length >= MAX_RAW_CODEX_PROCESSES)
            break;
    }
    return rows;
}
function parseLsofCwd(output) {
    for (const line of output.split(/\r?\n/)) {
        if (line.startsWith("n/"))
            return line.slice(1).trim();
    }
    return "";
}
function findProjectRoot(cwd) {
    let dir = cwd;
    for (let i = 0; i < 30; i++) {
        if (fs.existsSync(path.join(dir, ".platform")) || fs.existsSync(path.join(dir, ".git")))
            return dir;
        const parent = path.dirname(dir);
        if (parent === dir)
            break;
        dir = parent;
    }
    return cwd;
}
function parseCodexEffort(command) {
    const match = command.match(/model_reasoning_effort=(?:"([^"]+)"|'([^']+)'|([^\s]+))/);
    return (match?.[1] || match?.[2] || match?.[3] || "medium").trim();
}
function readRawCodexProcesses() {
    if (process.platform === "win32")
        return [];
    let psOutput = "";
    try {
        psOutput = (0, child_process_1.execFileSync)("ps", ["-axo", "pid=,etime=,command="], { encoding: "utf8", timeout: 1500 });
    }
    catch {
        return [];
    }
    const processes = [];
    for (const proc of parsePsCodexProcesses(psOutput)) {
        try {
            const lsofOutput = (0, child_process_1.execFileSync)("lsof", ["-a", "-p", String(proc.pid), "-d", "cwd", "-Fn"], {
                encoding: "utf8",
                timeout: 1000,
            });
            const cwd = parseLsofCwd(lsofOutput);
            if (!cwd)
                continue;
            const root = findProjectRoot(cwd);
            processes.push({ ...proc, cwd, root, effort: parseCodexEffort(proc.command) });
        }
        catch {
            // Process may exit between ps and lsof, or lsof may be unavailable.
        }
    }
    return processes;
}
function getRawCodexProcesses(cache, now = Date.now()) {
    if (now - cache.ts < RAW_CODEX_SCAN_TTL_MS)
        return cache;
    return { ts: now, processes: readRawCodexProcesses() };
}
function elapsedFromSeconds(seconds) {
    if (seconds >= 3600)
        return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
    return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}
function rawCodexProcessToSession(proc, workspaceRoot, branch, now = Date.now(), options = {}) {
    if (!(0, sessionFiles_1.sessionRootMatchesWorkspace)(proc.root, workspaceRoot))
        return null;
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
        availableStreams: (0, catalogStore_1.readStreams)(proc.root).map(st => st.slug),
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
