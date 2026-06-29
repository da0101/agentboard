"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildDashboardDataSync = buildDashboardDataSync;
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process_1 = require("child_process");
const workspaceRoot_1 = require("../workspaceRoot");
const activityBuilders_1 = require("./activityBuilders");
const catalogStore_1 = require("./catalogStore");
const constants_1 = require("./constants");
const eventStore_1 = require("./eventStore");
const trendBuilder_1 = require("./trendBuilder");
const formatters_1 = require("./formatters");
const gitActivity_1 = require("./gitActivity");
const hudFreshness_1 = require("./hudFreshness");
const panelPrefs_1 = require("./panelPrefs");
const rawCodexProcesses_1 = require("./rawCodexProcesses");
const sessionSummary_1 = require("./sessionSummary");
const workflowStore_1 = require("./workflowStore");
const sessionFiles_1 = require("./sessionFiles");
function buildDashboardDataSync(state) {
    const workspaceFolderRoot = (0, workspaceRoot_1.detectWorkspaceRootFromFolders)((vscode.workspace.workspaceFolders ?? []).map(f => f.uri.fsPath));
    if (workspaceFolderRoot && workspaceFolderRoot !== state.workspaceRoot) {
        state.setWorkspaceRoot(workspaceFolderRoot);
    }
    let hud = null;
    if (!workspaceFolderRoot) {
        // Generic VS Code windows can follow ~/.agentboard/live.json.
        // Project windows stay pinned to their own workspace.
        const globalLive = path.join(os.homedir(), ".agentboard", "live.json");
        try {
            const live = JSON.parse(fs.readFileSync(globalLive, "utf8"));
            if ((0, hudFreshness_1.isHudFresh)(live))
                hud = live;
            if (hud && live._root && live._root !== state.workspaceRoot) {
                state.setWorkspaceRoot(live._root);
            }
        }
        catch { /* ok — try local hud file */ }
    }
    // Fallback: read hud from workspaceRoot directly
    if (!hud) {
        try {
            const localHud = JSON.parse(fs.readFileSync(path.join(state.workspaceRoot, "agentboard.hud-status.json"), "utf8"));
            if ((0, hudFreshness_1.isHudFresh)(localHud))
                hud = localHud;
        }
        catch { /* ok */ }
    }
    // Branch: prefer HUD (already has it). Fallback: cached value refreshed at most every 30s via async exec.
    // Prefer the live git branch from the workspace root over the HUD branch.
    // The HUD may carry a worktree branch from a Claude session running in a
    // different checkout — that should show on the session card, not the header.
    const branch = state.branchCache.value || (hud?.context?.branch ?? "");
    // Refresh local branch list every 60 s for the branch selector dropdowns.
    // Use plain `git branch` — the %(refname:short) format string confuses /bin/sh
    // job-control expansion when passed through exec(), causing silent failure.
    if (Date.now() - state.localBranchesCache.ts > 60000) {
        state.localBranchesCache.ts = Date.now();
        (0, child_process_1.exec)("git branch", { cwd: state.workspaceRoot, timeout: 2000 }, (_err, stdout) => {
            if (stdout) {
                state.localBranchesCache.branches = stdout.trim().split("\n")
                    .map((b) => b.replace(/^[*+ ]+/, "").trim())
                    .filter((b) => b && !b.startsWith("("));
                state.localBranchesCache.ts = Date.now();
            }
        });
    }
    // Always poll git — never skip just because the HUD has a branch.
    // The HUD branch can be stale (deleted branch, worktree mismatch, etc).
    // Mutate the cache object in place: reassigning state.branchCache would only
    // update the local state reference, not the DashboardPanel._branchCache field.
    if (Date.now() - state.branchCache.ts > 30000) {
        state.branchCache.ts = Date.now(); // debounce — mutates the shared object
        (0, child_process_1.exec)("git rev-parse --abbrev-ref HEAD", { cwd: state.workspaceRoot, timeout: 1500 }, (_err, stdout) => {
            if (stdout) {
                state.branchCache.value = stdout.trim();
                state.branchCache.ts = Date.now();
            }
        });
    }
    const worktrees = []; // removed blocking execSync git worktree — not worth the cost
    const activeStream = (0, catalogStore_1.readActiveStream)(state.workspaceRoot);
    const streamRole = (0, catalogStore_1.readStreamRole)(state.workspaceRoot, activeStream);
    const hudRole = hud?.active_agents?.[0]?.role ?? "";
    const activeRole = (!hudRole || constants_1.MODEL_NAMES.has(hudRole.toLowerCase().split("-")[0])) ? streamRole : hudRole;
    const ctxPct = hud?.context?.context_remaining_pct ?? null;
    const rawModel = hud?.context?.model ?? hud?.active_agents?.[0]?.model ?? "";
    const model = rawModel ? (0, formatters_1.fmtModel)(rawModel) : "";
    const costUsd = hud?.cost?.session_usd ?? null;
    const cost = costUsd !== null ? `$${costUsd.toFixed(3)}` : "";
    const sessionTime = hud?.active_agents?.[0]?.started_at ? (0, formatters_1.elapsedStr)(hud.active_agents[0].started_at) : "";
    const hasLive = (hud?.active_agents?.length ?? 0) > 0;
    const currentSessionId = hud?.context?.session_id ?? hud?.active_agents?.[0]?.session_id ?? "";
    // Reset per-cycle event cache
    state.eventsCache.clear();
    // Cached skills/roles (read directory mtime; these files rarely change)
    const skillsDir = path.join(state.workspaceRoot, ".claude", "skills");
    const rolesDir = path.join(state.workspaceRoot, ".platform", "roles");
    const streamsDir = path.join(state.workspaceRoot, ".platform", "work");
    try {
        const mt = fs.statSync(skillsDir).mtimeMs;
        if (!state.skillsCache || mt > state.skillsCache.mtime)
            state.skillsCache = { mtime: mt, data: (0, catalogStore_1.readSkills)(state.workspaceRoot) };
    }
    catch {
        if (!state.skillsCache)
            state.skillsCache = { mtime: 0, data: [] };
    }
    try {
        const mt = fs.statSync(rolesDir).mtimeMs;
        if (!state.rolesCache || mt > state.rolesCache.mtime)
            state.rolesCache = { mtime: mt, data: (0, catalogStore_1.readRoles)(state.workspaceRoot) };
    }
    catch {
        if (!state.rolesCache)
            state.rolesCache = { mtime: 0, data: [] };
    }
    try {
        const mt = fs.statSync(streamsDir).mtimeMs;
        if (!state.streamsCache || mt > state.streamsCache.mtime)
            state.streamsCache = { mtime: mt, data: (0, catalogStore_1.readStreams)(state.workspaceRoot) };
    }
    catch {
        if (!state.streamsCache)
            state.streamsCache = { mtime: 0, data: [] };
    }
    const skills = state.skillsCache.data;
    const roles = state.rolesCache.data;
    // Read events once per root, cache for this cycle
    const getEventsForRoot = (root) => {
        if (state.eventsCache.has(root))
            return state.eventsCache.get(root);
        const evs = (0, eventStore_1.readRecentEvents)(root, 400);
        state.eventsCache.set(root, evs);
        return evs;
    };
    const allEvents = getEventsForRoot(state.workspaceRoot);
    // lastSkill computed after activeSessions is built so we can filter to active sessions only
    // Filter events to current session only (prevents stale events from previous /clear sessions bleeding through)
    const hasSessionIds = allEvents.some(e => e.session_id);
    const sessionEvents = (hasSessionIds && currentSessionId)
        ? allEvents.filter(e => !e.session_id || e.session_id === currentSessionId)
        : allEvents;
    const { totalUniqueFiles, fileActivity } = (0, activityBuilders_1.buildFileActivity)(sessionEvents, 20);
    // Stream description from body italic line
    const streamDesc = (() => {
        if (!activeStream)
            return "";
        try {
            const body = fs.readFileSync(path.join(state.workspaceRoot, ".platform", "work", `${activeStream}.md`), "utf8");
            return body.match(/^_([^_]+)_/m)?.[1]?.trim() ?? "";
        }
        catch {
            return "";
        }
    })();
    // Determine last event label for NOW block — use session-filtered events
    const WAIT_TOOLS = new Set(["AskUserQuestion", "AskUser"]);
    // Skip synthetic internal events — only show real user-visible tool calls
    const SYNTHETIC_TOOLS = new Set(["WorkflowStart", "WorkflowEnd", "AgentStart"]);
    const lastNonAgentEvent = sessionEvents.find(e => e.tool !== "Agent" && !SYNTHETIC_TOOLS.has(e.tool)) ?? null;
    const lastEventLabel = lastNonAgentEvent?.file
        ? path.basename(lastNonAgentEvent.file)
        : lastNonAgentEvent?.cmd
            ? lastNonAgentEvent.cmd.slice(0, 50)
            : lastNonAgentEvent?.skill
                ? `/${lastNonAgentEvent.skill}`
                : lastNonAgentEvent?.tool ?? "";
    const lastEventTs = lastNonAgentEvent?.ts ?? "";
    const secsSinceLastEvent = lastEventTs ? Math.floor((Date.now() - new Date(lastEventTs).getTime()) / 1000) : null;
    // Suppress "long op" warning when Claude is waiting for user input (AskUserQuestion)
    const isWaitingForUser = lastNonAgentEvent ? WAIT_TOOLS.has(lastNonAgentEvent.tool) : false;
    const isInLongOp = hasLive && !isWaitingForUser && secsSinceLastEvent !== null && secsSinceLastEvent > 90;
    // Detect active Workflow: WorkflowStart within 2h, not ended (or background launch still running)
    let activeWorkflow = null;
    let _wfStartTs = null;
    for (const ev of sessionEvents) {
        const secAgo = Math.floor((Date.now() - new Date(ev.ts).getTime()) / 1000);
        if (ev.tool === "WorkflowStart" && secAgo < 2 * 3600) { // 2h max — older = stale
            _wfStartTs = ev.ts;
            activeWorkflow = {
                label: ev.label ?? "workflow",
                agentCount: ev.agent_count ?? 0,
                ts: ev.ts,
                sessionId: ev.session_id ?? "",
            };
        }
        else if (ev.tool === "WorkflowEnd") {
            const duration = _wfStartTs ? new Date(ev.ts).getTime() - new Date(_wfStartTs).getTime() : Infinity;
            if (duration > 30000) {
                activeWorkflow = null; // foreground workflow completed
            }
            else if (_wfStartTs && (Date.now() - new Date(_wfStartTs).getTime()) > 30 * 60 * 1000) {
                // Background launch but WorkflowStart is >30min old — presume completed
                activeWorkflow = null;
            }
        }
    }
    const recentAgents = (0, activityBuilders_1.buildRecentAgents)(sessionEvents);
    const activeSessions = [];
    try {
        const files = (0, sessionFiles_1.listSessionFiles)(state.workspaceRoot);
        for (const f of files) {
            try {
                const s = (0, sessionFiles_1.readSessionFile)(state.workspaceRoot, f);
                if (!s)
                    continue;
                const lastUpdated = s._last_updated || s.last_updated || "";
                const ageMs = lastUpdated ? Date.now() - new Date(lastUpdated).getTime() : Infinity;
                if (ageMs > 30 * 60 * 1000)
                    continue; // 30 min since last status-bridge ping = session is idle
                const ctx = s.context || {};
                const agents = s.active_agents || [];
                const rawModel = ctx.model || agents[0]?.model || "";
                const costUsd = s.cost?.session_usd ?? 0;
                const sRoot = s._root || "";
                if (!(0, sessionFiles_1.sessionRootMatchesWorkspace)(sRoot, state.workspaceRoot))
                    continue;
                // For worktree sessions (different root), poll git in their directory.
                if (sRoot && sRoot !== state.workspaceRoot) {
                    const cached = state.worktreeBranchCache.get(sRoot);
                    if (!cached || Date.now() - cached.ts > 30000) {
                        state.worktreeBranchCache.set(sRoot, { ts: Date.now(), value: cached?.value ?? "" });
                        (0, child_process_1.exec)("git rev-parse --abbrev-ref HEAD", { cwd: sRoot, timeout: 1500 }, (_err, stdout) => {
                            if (stdout)
                                state.worktreeBranchCache.set(sRoot, { ts: Date.now(), value: stdout.trim() });
                        });
                    }
                }
                const sStartedAt = ctx.started_at || agents[0]?.started_at || "";
                const sCtxPct = ctx.context_remaining_pct ?? null;
                const sElapsed = sStartedAt ? (() => {
                    const sec = Math.floor((Date.now() - new Date(sStartedAt).getTime()) / 1000);
                    return sec < 3600 ? `${Math.floor(sec / 60)}m ${sec % 60}s` : `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m`;
                })() : "";
                // Per-session activity feed (deduplicated, most recent first)
                const sId = s._session_id || ctx.session_id || f.replace(".json", "");
                let scopedSessionEvents = [];
                let sActivity = [];
                if (sRoot) {
                    const allSEvents = getEventsForRoot(sRoot); // cached — no extra file read
                    // Strict session filter: only events with matching session_id.
                    const hasSessionIds = allSEvents.some(e => e.session_id);
                    const sEvents = hasSessionIds
                        ? allSEvents.filter(e => e.session_id === sId)
                        : allSEvents;
                    scopedSessionEvents = sEvents;
                    sActivity = (0, activityBuilders_1.buildFileActivity)(sEvents, 15).fileActivity;
                    (0, gitActivity_1.enrichActivityWithGit)(sRoot, sActivity, {
                        numstatCache: state.numstatCache,
                        lineCountCache: state.lineCountCache,
                        branchCommittedCache: state.branchCommittedCache,
                    });
                }
                // Skip ghost sessions: no tool events AND session started >15 min ago
                // Use startedAt age (not lastUpdated) so status-bridge pings don't keep ghosts alive
                const startedAtAgeMs = sStartedAt ? Date.now() - new Date(sStartedAt).getTime() : Infinity;
                if (sActivity.length === 0 && startedAtAgeMs > 15 * 60 * 1000)
                    continue;
                const sAgents = (0, activityBuilders_1.buildSessionAgents)(scopedSessionEvents, ageMs);
                const sAgentActivity = (0, activityBuilders_1.buildSessionAgentActivity)(scopedSessionEvents, sAgents);
                const workflowState = sRoot
                    ? (0, workflowStore_1.readSessionWorkflowState)(sRoot, sId, getEventsForRoot)
                    : { hasWorkflow: false, workflowAgentCount: 0, workflowLabel: "", transcriptAgents: [] };
                activeSessions.push({
                    sessionId: s._session_id || ctx.session_id || f.replace(".json", ""),
                    provider: s.provider || ctx.provider || "",
                    model: rawModel ? (0, formatters_1.fmtModel)(rawModel) : "",
                    costUsd,
                    cost: costUsd > 0 ? `$${costUsd.toFixed(3)}` : "",
                    // Branch resolution priority:
                    // 1. Manual override (user pinned a branch via the selector)
                    // 2. Live git branch when session is in the same workspace
                    // 3. Session file's recorded branch (for cross-root worktree sessions)
                    branch: (() => {
                        const sId2 = s._session_id || ctx.session_id || f.replace(".json", "");
                        const override = (0, panelPrefs_1.loadBranchOverride)(sRoot, sId2);
                        if (override)
                            return override;
                        // Same-workspace session: use live git branch
                        if ((0, sessionFiles_1.sessionRootMatchesWorkspace)(sRoot, state.workspaceRoot) && state.branchCache.value)
                            return state.branchCache.value;
                        // Worktree session: use per-worktree git poll result
                        const wtBranch = state.worktreeBranchCache.get(sRoot)?.value;
                        if (wtBranch)
                            return wtBranch;
                        return ctx.branch || "";
                    })(),
                    branchPinned: !!(0, panelPrefs_1.loadBranchOverride)(sRoot, s._session_id || ctx.session_id || f.replace(".json", "")),
                    availableBranches: state.localBranchesCache.branches,
                    root: sRoot,
                    shellPid: s._shell_pid || 0,
                    projectName: sRoot ? path.basename(sRoot) : "",
                    sessionLastSkill: "", sessionLastRole: "",
                    startedAt: sStartedAt,
                    lastUpdated,
                    ageSeconds: Math.floor(ageMs / 1000),
                    ctxPct: sCtxPct,
                    stream: sRoot ? (0, catalogStore_1.readSessionStream)(sRoot, sId, getEventsForRoot(sRoot), panelPrefs_1.loadStreamOverride) : "",
                    streamPinned: sRoot ? (0, panelPrefs_1.loadStreamOverride)(sRoot, sId) !== undefined : false,
                    availableStreams: sRoot ? (0, catalogStore_1.readStreams)(sRoot).map(st => st.slug) : [],
                    sessionTime: sElapsed,
                    activity: sActivity,
                    agents: sAgents,
                    agentActivity: sAgentActivity,
                    hasWorkflow: workflowState.hasWorkflow,
                    workflowAgentCount: workflowState.workflowAgentCount,
                    workflowLabel: workflowState.workflowLabel,
                    workflowTranscriptAgents: workflowState.transcriptAgents,
                    workflowPlan: sRoot ? (0, workflowStore_1.readWorkflowPlan)(sRoot) : null,
                    nick: "", // filled in after dedup by sessionNick()
                });
            }
            catch { /* skip malformed file */ }
        }
        const dedupedSessions = (0, sessionSummary_1.dedupeClearedSessions)(activeSessions);
        activeSessions.length = 0;
        activeSessions.push(...dedupedSessions);
    }
    catch { /* sessions dir doesn't exist yet */ }
    // Synthesize a session entry from HUD data when no session files exist.
    // This happens when the project hasn't run `ab start` / the status bridge
    // hasn't written a session file yet, but the HUD hook is active.
    if (activeSessions.length === 0 && hasLive && hud) {
        const hudBranch = state.branchCache.value || (hud.context?.branch ?? "");
        const hudActivity = (0, activityBuilders_1.buildFileActivity)(sessionEvents, 15).fileActivity;
        (0, gitActivity_1.enrichActivityWithGit)(state.workspaceRoot, hudActivity, {
            numstatCache: state.numstatCache,
            lineCountCache: state.lineCountCache,
            branchCommittedCache: state.branchCommittedCache,
        });
        const hudAgents = (0, activityBuilders_1.buildSessionAgents)(sessionEvents, 0);
        const hudAgentActivity = (0, activityBuilders_1.buildSessionAgentActivity)(sessionEvents, hudAgents);
        const hudWorkflow = (0, workflowStore_1.readSessionWorkflowState)(state.workspaceRoot, currentSessionId, getEventsForRoot);
        activeSessions.push({
            sessionId: currentSessionId || "hud-live",
            provider: "claude",
            model,
            costUsd: costUsd ?? 0,
            cost,
            branch: hudBranch,
            root: state.workspaceRoot,
            shellPid: 0,
            projectName: path.basename(state.workspaceRoot),
            sessionLastSkill: "", sessionLastRole: "",
            startedAt: hud.active_agents?.[0]?.started_at ?? "",
            lastUpdated: hud.last_updated ?? "",
            ageSeconds: 0,
            ctxPct,
            stream: (0, catalogStore_1.readSessionStream)(state.workspaceRoot, currentSessionId, getEventsForRoot(state.workspaceRoot), panelPrefs_1.loadStreamOverride),
            streamPinned: (0, panelPrefs_1.loadStreamOverride)(state.workspaceRoot, currentSessionId) !== undefined,
            availableStreams: state.streamsCache?.data.map((s) => s.slug) ?? [],
            branchPinned: !!(0, panelPrefs_1.loadBranchOverride)(state.workspaceRoot, currentSessionId),
            availableBranches: state.localBranchesCache.branches,
            sessionTime,
            activity: hudActivity,
            agents: hudAgents,
            agentActivity: hudAgentActivity,
            hasWorkflow: hudWorkflow.hasWorkflow,
            workflowAgentCount: hudWorkflow.workflowAgentCount,
            workflowLabel: hudWorkflow.workflowLabel,
            workflowTranscriptAgents: hudWorkflow.transcriptAgents,
            workflowPlan: (0, workflowStore_1.readWorkflowPlan)(state.workspaceRoot),
            nick: "",
        });
    }
    const hasBridgedCodexSession = activeSessions.some(sess => sess.provider === "codex" && (0, sessionFiles_1.sessionRootMatchesWorkspace)(sess.root, state.workspaceRoot));
    if (!hasBridgedCodexSession) {
        const rawCodexCache = (0, rawCodexProcesses_1.getRawCodexProcesses)(state.rawCodexProcessCache);
        state.setRawCodexProcessCache(rawCodexCache);
        const rawActivity = (0, activityBuilders_1.buildFileActivity)(sessionEvents, 15).fileActivity;
        (0, gitActivity_1.enrichActivityWithGit)(state.workspaceRoot, rawActivity, {
            numstatCache: state.numstatCache,
            lineCountCache: state.lineCountCache,
            branchCommittedCache: state.branchCommittedCache,
        });
        const rawAgents = (0, activityBuilders_1.buildSessionAgents)(sessionEvents, 0);
        const rawAgentActivity = (0, activityBuilders_1.buildSessionAgentActivity)(sessionEvents, rawAgents);
        for (const proc of rawCodexCache.processes) {
            const rawSession = (0, rawCodexProcesses_1.rawCodexProcessToSession)(proc, state.workspaceRoot, branch, Date.now(), {
                activity: rawActivity,
                agents: rawAgents,
                agentActivity: rawAgentActivity,
                stream: activeStream,
            });
            if (rawSession)
                activeSessions.push(rawSession);
        }
    }
    // lastSkill: only from currently active sessions (avoids stale closed-session data in footer)
    const activeSessionIds = new Set(activeSessions.map(s => s.sessionId));
    // Stamp nick onto each session entry so the frontend and tab titles can use it
    for (const sess of activeSessions)
        sess.nick = (0, activityBuilders_1.sessionNick)(sess.sessionId);
    const activeEventsForSkill = allEvents.filter(e => !e.session_id || activeSessionIds.has(e.session_id));
    const { skill: lastSkill, sessionId: lastSkillSessionId } = (0, eventStore_1.lastSkillFromEvents)(activeEventsForSkill);
    const lastSkillSession = (lastSkillSessionId && activeSessionIds.has(lastSkillSessionId)) ? (0, activityBuilders_1.sessionNick)(lastSkillSessionId) : "";
    const { skillsWithUsage, rolesWithUsage } = (0, sessionSummary_1.applySessionCatalogUsage)(activeSessions, skills, roles, getEventsForRoot);
    return {
        type: "update",
        hasLive, model, cost, sessionTime, activeStream, streamDesc, activeRole, lastSkill, lastSkillSession,
        ctxPct, branch, cpRunning: false, sessions: 0, totalUniqueFiles,
        activeSessions,
        activeWorkflow,
        streams: state.streamsCache?.data ?? [],
        fileActivity, recentAgents,
        lastEventLabel, lastEventTs, isInLongOp,
        worktrees,
        skillCount: skills.length, roleCount: roles.length,
        skills: skillsWithUsage, roles: rolesWithUsage,
        commands: constants_1.AB_CLI_COMMANDS,
        projectName: path.basename(state.workspaceRoot),
        ignoredSizeFiles: Array.from((0, panelPrefs_1.loadIgnoreSizes)(state.workspaceRoot)),
        availableBranches: state.localBranchesCache.branches,
        trendData: (0, trendBuilder_1.buildTrendData)((0, eventStore_1.readTrendEvents)(state.workspaceRoot, 2000), Date.now()),
    };
}
