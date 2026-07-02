import * as path from "path";
import { buildFileActivity, buildSessionAgentActivity, buildSessionAgents } from "./activityBuilders";
import { ActivityEvent, DashboardSessionEntry } from "./types";

const EVENT_ONLY_SESSION_FRESH_MS = 30 * 60 * 1000;

export interface EventOnlySessionOptions {
  workspaceRoot: string;
  branch: string;
  activeStream: string;
  availableStreams: string[];
  existingSessionIds?: Set<string>;
  now?: number;
}

export function buildEventOnlySessions(
  events: ActivityEvent[],
  options: EventOnlySessionOptions,
): DashboardSessionEntry[] {
  const now = options.now ?? Date.now();
  const existing = options.existingSessionIds ?? new Set<string>();
  const bySession = new Map<string, ActivityEvent[]>();
  for (const ev of events) {
    if (!ev.session_id || existing.has(ev.session_id)) continue;
    if (!ev.provider && !ev.file && !ev.cmd) continue;
    const tsMs = new Date(ev.ts).getTime();
    if (!Number.isFinite(tsMs) || now - tsMs > EVENT_ONLY_SESSION_FRESH_MS) continue;
    const list = bySession.get(ev.session_id) ?? [];
    list.push(ev);
    bySession.set(ev.session_id, list);
  }

  return Array.from(bySession.entries()).map(([sessionId, sessionEvents]) => {
    const sorted = [...sessionEvents].sort((a, b) => a.ts.localeCompare(b.ts));
    const first = sorted[0];
    const last = sorted[sorted.length - 1];
    const provider = [...sorted].reverse().find(ev => ev.provider)?.provider ?? "";
    const activity = buildFileActivity(sorted, 15).fileActivity;
    const ageMs = now - new Date(last.ts).getTime();
    const agents = buildSessionAgents(sorted, ageMs, now);
    return {
      sessionId,
      provider,
      model: "",
      costUsd: 0,
      cost: "",
      branch: options.branch,
      root: options.workspaceRoot,
      shellPid: 0,
      projectName: path.basename(options.workspaceRoot),
      sessionLastSkill: "",
      sessionLastRole: "",
      startedAt: first.ts,
      lastUpdated: last.ts,
      ageSeconds: Math.max(0, Math.floor(ageMs / 1000)),
      ctxPct: null,
      stream: options.activeStream,
      streamPinned: false,
      availableStreams: options.availableStreams,
      branchPinned: false,
      availableBranches: [],
      sessionTime: "",
      activity,
      agents,
      agentActivity: buildSessionAgentActivity(sorted, agents),
      hasWorkflow: false,
      workflowAgentCount: 0,
      workflowLabel: "",
      workflowTranscriptAgents: [],
      workflowPlan: null,
      nick: "",
    };
  }).sort((a, b) => a.startedAt.localeCompare(b.startedAt));
}
