import * as vscode from "vscode";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { exec } from "child_process";
import { HudStatus } from "../hudTypes";
import { detectWorkspaceRootFromFolders } from "../workspaceRoot";
import { buildFileActivity, buildRecentAgents, buildSessionAgentActivity, buildSessionAgents, sessionNick } from "./activityBuilders";
import { readActiveStream, readRoles, readSessionStream, readSkills, readStreamRole, readStreams } from "./catalogStore";
import { AB_CLI_COMMANDS, MODEL_NAMES } from "./constants";
import { readRecentEvents, lastSkillFromEvents } from "./eventStore";
import { elapsedStr, fmtModel, relTime } from "./formatters";
import { enrichActivityWithGit } from "./gitActivity";
import { isHudFresh } from "./hudFreshness";
import { loadIgnoreSizes, loadStreamOverride } from "./panelPrefs";
import { getRawCodexProcesses, rawCodexProcessToSession, RawCodexProcessCache } from "./rawCodexProcesses";
import { applySessionCatalogUsage, dedupeClearedSessions } from "./sessionSummary";
import { readWorkflowPlan, readSessionWorkflowState } from "./workflowStore";
import { ActivityEvent, CatalogItem, DashboardSessionEntry, SessionActivityItem, StreamEntry } from "./types";
import { sessionRootMatchesWorkspace } from "./sessionFiles";

export interface DashboardDataState {
  workspaceRoot: string;
  setWorkspaceRoot(root: string): void;
  eventsCache: Map<string, ActivityEvent[]>;
  streamsCache: { mtime: number; data: StreamEntry[] } | null;
  setStreamsCache(cache: { mtime: number; data: StreamEntry[] }): void;
  skillsCache: { mtime: number; data: CatalogItem[] } | null;
  setSkillsCache(cache: { mtime: number; data: CatalogItem[] }): void;
  rolesCache: { mtime: number; data: CatalogItem[] } | null;
  setRolesCache(cache: { mtime: number; data: CatalogItem[] }): void;
  branchCache: { value: string; ts: number };
  numstatCache: Map<string, { ts: number; diffMap: Map<string, { added: number; deleted: number }> }>;
  lineCountCache: Map<string, { ts: number; count: number }>;
  branchCommittedCache: Map<string, { ts: number; files: Set<string> }>;
  rawCodexProcessCache: RawCodexProcessCache;
  setRawCodexProcessCache(cache: RawCodexProcessCache): void;
}

export function buildDashboardDataSync(state: DashboardDataState): object {
    const workspaceFolderRoot = detectWorkspaceRootFromFolders(
      (vscode.workspace.workspaceFolders ?? []).map(f => f.uri.fsPath)
    );
    if (workspaceFolderRoot && workspaceFolderRoot !== state.workspaceRoot) {
      state.setWorkspaceRoot(workspaceFolderRoot);
    }

    let hud: HudStatus | null = null;
    if (!workspaceFolderRoot) {
      // Generic VS Code windows can follow ~/.agentboard/live.json.
      // Project windows stay pinned to their own workspace.
      const globalLive = path.join(os.homedir(), ".agentboard", "live.json");
      try {
        const live = JSON.parse(fs.readFileSync(globalLive, "utf8")) as HudStatus & { _root?: string };
        if (isHudFresh(live)) hud = live;
        if (hud && live._root && live._root !== state.workspaceRoot) {
          state.setWorkspaceRoot(live._root);
        }
      } catch { /* ok — try local hud file */ }
    }

    // Fallback: read hud from workspaceRoot directly
    if (!hud) {
      try {
        const localHud = JSON.parse(fs.readFileSync(path.join(state.workspaceRoot, "agentboard.hud-status.json"), "utf8")) as HudStatus;
        if (isHudFresh(localHud)) hud = localHud;
      } catch { /* ok */ }
    }

    // Branch: prefer HUD (already has it). Fallback: cached value refreshed at most every 30s via async exec.
    const branch = hud?.context?.branch ?? state.branchCache.value;
    if (!hud?.context?.branch && Date.now() - state.branchCache.ts > 30_000) {
      state.branchCache.ts = Date.now(); // debounce
      exec("git rev-parse --abbrev-ref HEAD", { cwd: state.workspaceRoot, timeout: 1500 }, (_err: Error | null, stdout: string) => {
        if (stdout) state.branchCache = { value: stdout.trim(), ts: Date.now() };
      });
    }
    const worktrees: string[] = []; // removed blocking execSync git worktree — not worth the cost
    const activeStream = readActiveStream(state.workspaceRoot);
    const streamRole = readStreamRole(state.workspaceRoot, activeStream);
    const hudRole = hud?.active_agents?.[0]?.role ?? "";
    const activeRole = (!hudRole || MODEL_NAMES.has(hudRole.toLowerCase().split("-")[0])) ? streamRole : hudRole;
    const ctxPct: number | null = hud?.context?.context_remaining_pct ?? null;
    const rawModel = hud?.context?.model ?? hud?.active_agents?.[0]?.model ?? "";
    const model = rawModel ? fmtModel(rawModel) : "";
    const costUsd = hud?.cost?.session_usd as number | null ?? null;
    const cost = costUsd !== null ? `$${costUsd.toFixed(3)}` : "";
    const sessionTime = hud?.active_agents?.[0]?.started_at ? elapsedStr(hud.active_agents[0].started_at) : "";
    const hasLive = (hud?.active_agents?.length ?? 0) > 0;
    const currentSessionId = hud?.context?.session_id ?? (hud?.active_agents?.[0] as {session_id?: string} | undefined)?.session_id ?? "";
    // Reset per-cycle event cache
    state.eventsCache.clear();

    // Cached skills/roles (read directory mtime; these files rarely change)
    const skillsDir = path.join(state.workspaceRoot, ".claude", "skills");
    const rolesDir = path.join(state.workspaceRoot, ".platform", "roles");
    const streamsDir = path.join(state.workspaceRoot, ".platform", "work");
    try { const mt = fs.statSync(skillsDir).mtimeMs; if (!state.skillsCache || mt > state.skillsCache.mtime) state.skillsCache = { mtime: mt, data: readSkills(state.workspaceRoot) }; } catch { if (!state.skillsCache) state.skillsCache = { mtime: 0, data: [] }; }
    try { const mt = fs.statSync(rolesDir).mtimeMs; if (!state.rolesCache || mt > state.rolesCache.mtime) state.rolesCache = { mtime: mt, data: readRoles(state.workspaceRoot) }; } catch { if (!state.rolesCache) state.rolesCache = { mtime: 0, data: [] }; }
    try { const mt = fs.statSync(streamsDir).mtimeMs; if (!state.streamsCache || mt > state.streamsCache.mtime) state.streamsCache = { mtime: mt, data: readStreams(state.workspaceRoot) }; } catch { if (!state.streamsCache) state.streamsCache = { mtime: 0, data: [] }; }
    const skills = state.skillsCache.data;
    const roles = state.rolesCache.data;

    // Read events once per root, cache for this cycle
    const getEventsForRoot = (root: string): ActivityEvent[] => {
      if (state.eventsCache.has(root)) return state.eventsCache.get(root)!;
      const evs = readRecentEvents(root, 400);
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

    const { totalUniqueFiles, fileActivity } = buildFileActivity(sessionEvents, 20);

    // Stream description from body italic line
    const streamDesc = (() => {
      if (!activeStream) return "";
      try {
        const body = fs.readFileSync(path.join(state.workspaceRoot, ".platform", "work", `${activeStream}.md`), "utf8");
        return body.match(/^_([^_]+)_/m)?.[1]?.trim() ?? "";
      } catch { return ""; }
    })();

    // Determine last event label for NOW block — use session-filtered events
    const WAIT_TOOLS = new Set(["AskUserQuestion", "AskUser"]);
    // Skip synthetic internal events — only show real user-visible tool calls
    const SYNTHETIC_TOOLS = new Set(["WorkflowStart", "WorkflowEnd", "AgentStart"]);
    const lastNonAgentEvent = sessionEvents.find(e => e.tool !== "Agent" && !SYNTHETIC_TOOLS.has(e.tool)) ?? null;
    const lastEventLabel = lastNonAgentEvent?.file
      ? path.basename(lastNonAgentEvent.file)
      : lastNonAgentEvent?.cmd
        ? (lastNonAgentEvent.cmd as string).slice(0, 50)
        : (lastNonAgentEvent as {skill?: string} | null)?.skill
          ? `/${(lastNonAgentEvent as {skill?: string}).skill}`
          : lastNonAgentEvent?.tool ?? "";
    const lastEventTs = lastNonAgentEvent?.ts ?? "";
    const secsSinceLastEvent = lastEventTs ? Math.floor((Date.now() - new Date(lastEventTs).getTime()) / 1000) : null;
    // Suppress "long op" warning when Claude is waiting for user input (AskUserQuestion)
    const isWaitingForUser = lastNonAgentEvent ? WAIT_TOOLS.has(lastNonAgentEvent.tool) : false;
    const isInLongOp = hasLive && !isWaitingForUser && secsSinceLastEvent !== null && secsSinceLastEvent > 90;

    // Detect active Workflow: WorkflowStart within 2h, not ended (or background launch still running)
    let activeWorkflow: { label: string; agentCount: number; ts: string; sessionId: string } | null = null;
    let _wfStartTs: string | null = null;
    for (const ev of sessionEvents) {
      const secAgo = Math.floor((Date.now() - new Date(ev.ts).getTime()) / 1000);
      if (ev.tool === "WorkflowStart" && secAgo < 2 * 3600) { // 2h max — older = stale
        _wfStartTs = ev.ts;
        activeWorkflow = {
          label: (ev as {label?: string}).label ?? "workflow",
          agentCount: (ev as {agent_count?: number}).agent_count ?? 0,
          ts: ev.ts,
          sessionId: (ev as {session_id?: string}).session_id ?? "",
        };
      } else if (ev.tool === "WorkflowEnd") {
        const duration = _wfStartTs ? new Date(ev.ts).getTime() - new Date(_wfStartTs).getTime() : Infinity;
        if (duration > 30_000) {
          activeWorkflow = null; // foreground workflow completed
        } else if (_wfStartTs && (Date.now() - new Date(_wfStartTs).getTime()) > 30 * 60 * 1000) {
          // Background launch but WorkflowStart is >30min old — presume completed
          activeWorkflow = null;
        }
      }
    }

    const recentAgents = buildRecentAgents(sessionEvents);

    const sessionsDir = path.join(os.homedir(), ".agentboard", "sessions");
    const activeSessions: DashboardSessionEntry[] = [];
    try {
      const files = fs.readdirSync(sessionsDir).filter((f: string) => f.endsWith(".json"));
      for (const f of files) {
        try {
          const s = JSON.parse(fs.readFileSync(path.join(sessionsDir, f), "utf8")) as Record<string, unknown>;
          const lastUpdated = (s._last_updated as string) || (s.last_updated as string) || "";
          const ageMs = lastUpdated ? Date.now() - new Date(lastUpdated).getTime() : Infinity;
          if (ageMs > 30 * 60 * 1000) continue; // 30 min since last status-bridge ping = session is idle
          const ctx = (s.context as Record<string, unknown>) || {};
          const agents = (s.active_agents as Array<Record<string, unknown>>) || [];
          const rawModel = (ctx.model as string) || (agents[0]?.model as string) || "";
          const costUsd = ((s.cost as Record<string, unknown>)?.session_usd as number) ?? 0;
          const sRoot = (s._root as string) || "";
          if (!sessionRootMatchesWorkspace(sRoot, state.workspaceRoot)) continue;
          const sStartedAt = (ctx.started_at as string) || (agents[0]?.started_at as string) || "";
          const sCtxPct = (ctx.context_remaining_pct as number | null) ?? null;
          const sElapsed = sStartedAt ? (() => {
            const sec = Math.floor((Date.now() - new Date(sStartedAt).getTime()) / 1000);
            return sec < 3600 ? `${Math.floor(sec / 60)}m ${sec % 60}s` : `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m`;
          })() : "";
          // Per-session activity feed (deduplicated, most recent first)
          const sId = (s._session_id as string) || (ctx.session_id as string) || f.replace(".json", "");
          let scopedSessionEvents: ActivityEvent[] = [];
          let sActivity: SessionActivityItem[] = [];
          if (sRoot) {
            const allSEvents = getEventsForRoot(sRoot); // cached — no extra file read
            // Strict session filter: only events with matching session_id.
            const hasSessionIds = allSEvents.some(e => e.session_id);
            const sEvents = hasSessionIds
              ? allSEvents.filter(e => e.session_id === sId)
              : allSEvents;
            scopedSessionEvents = sEvents;
            sActivity = buildFileActivity(sEvents, 15).fileActivity;
            enrichActivityWithGit(sRoot, sActivity, {
              numstatCache: state.numstatCache,
              lineCountCache: state.lineCountCache,
              branchCommittedCache: state.branchCommittedCache,
            });
          }
          // Skip ghost sessions: no tool events AND session started >15 min ago
          // Use startedAt age (not lastUpdated) so status-bridge pings don't keep ghosts alive
          const startedAtAgeMs = sStartedAt ? Date.now() - new Date(sStartedAt).getTime() : Infinity;
          if (sActivity.length === 0 && startedAtAgeMs > 15 * 60 * 1000) continue;
          const sAgents = buildSessionAgents(scopedSessionEvents, ageMs);
          const sAgentActivity = buildSessionAgentActivity(scopedSessionEvents, sAgents);

          const workflowState = sRoot
            ? readSessionWorkflowState(sRoot, sId, getEventsForRoot)
            : { hasWorkflow: false, workflowAgentCount: 0, workflowLabel: "", transcriptAgents: [] };
          activeSessions.push({
            sessionId: (s._session_id as string) || (ctx.session_id as string) || f.replace(".json", ""),
            provider: (s.provider as string) || (ctx.provider as string) || "",
            model: rawModel ? fmtModel(rawModel) : "",
            costUsd,
            cost: costUsd > 0 ? `$${costUsd.toFixed(3)}` : "",
            branch: (ctx.branch as string) || "",
            root: sRoot,
            shellPid: (s._shell_pid as number) || 0,
            projectName: sRoot ? path.basename(sRoot) : "",
            sessionLastSkill: "", sessionLastRole: "",
            startedAt: sStartedAt,
            lastUpdated,
            ageSeconds: Math.floor(ageMs / 1000),
            ctxPct: sCtxPct,
            stream: sRoot ? readSessionStream(sRoot, sId, getEventsForRoot(sRoot), loadStreamOverride) : "",
            streamPinned: sRoot ? loadStreamOverride(sRoot, sId) !== undefined : false,
            availableStreams: sRoot ? readStreams(sRoot).map(st => st.slug) : [],
            sessionTime: sElapsed,
            activity: sActivity,
            agents: sAgents,
            agentActivity: sAgentActivity,
            hasWorkflow: workflowState.hasWorkflow,
            workflowAgentCount: workflowState.workflowAgentCount,
            workflowLabel: workflowState.workflowLabel,
            workflowTranscriptAgents: workflowState.transcriptAgents,
            workflowPlan: sRoot ? readWorkflowPlan(sRoot) : null,
            nick: "", // filled in after dedup by sessionNick()
          });
        } catch { /* skip malformed file */ }
      }
      const dedupedSessions = dedupeClearedSessions(activeSessions);
      activeSessions.length = 0;
      activeSessions.push(...dedupedSessions);
    } catch { /* sessions dir doesn't exist yet */ }

    const hasBridgedCodexSession = activeSessions.some(sess =>
      sess.provider === "codex" && sessionRootMatchesWorkspace(sess.root, state.workspaceRoot)
    );
    if (!hasBridgedCodexSession) {
      const rawCodexCache = getRawCodexProcesses(state.rawCodexProcessCache);
      state.setRawCodexProcessCache(rawCodexCache);
      for (const proc of rawCodexCache.processes) {
        const rawSession = rawCodexProcessToSession(proc, state.workspaceRoot, branch);
        if (rawSession) activeSessions.push(rawSession);
      }
    }

    // lastSkill: only from currently active sessions (avoids stale closed-session data in footer)
    const activeSessionIds = new Set(activeSessions.map(s => s.sessionId));
    // Stamp nick onto each session entry so the frontend and tab titles can use it
    for (const sess of activeSessions) sess.nick = sessionNick(sess.sessionId);
    const activeEventsForSkill = allEvents.filter(e => !e.session_id || activeSessionIds.has(e.session_id));
    const { skill: lastSkill, sessionId: lastSkillSessionId } = lastSkillFromEvents(activeEventsForSkill);
    const lastSkillSession = (lastSkillSessionId && activeSessionIds.has(lastSkillSessionId)) ? sessionNick(lastSkillSessionId) : "";

    const { skillsWithUsage, rolesWithUsage } = applySessionCatalogUsage(activeSessions, skills, roles, getEventsForRoot);

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
      commands: AB_CLI_COMMANDS,
      projectName: path.basename(state.workspaceRoot),
      ignoredSizeFiles: Array.from(loadIgnoreSizes(state.workspaceRoot)),
    };
}
