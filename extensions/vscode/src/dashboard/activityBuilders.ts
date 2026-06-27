import { ActivityEvent, AgentEntry, SessionActivityItem } from "./types";

const RECENT_AGENT_MS = 30 * 60 * 1000;
const SESSION_IDLE_AGENT_STALE_MS = 10 * 60 * 1000;
const AGENT_STALE_MS = 30 * 60 * 1000;

function activityKey(ev: ActivityEvent): string {
  const skillName = ev.tool === "Skill" ? (ev.skill || ev.file || "") : "";
  return skillName ? `/${skillName}` : (ev.file ?? `$ ${(ev.cmd ?? "").slice(0, 60)}`);
}

export function buildFileActivity(events: ActivityEvent[], limit: number): { totalUniqueFiles: number; fileActivity: SessionActivityItem[] } {
  const fileMap = new Map<string, { tool: string; count: number; lastTs: string; agentId?: string; agentLabel?: string }>();
  for (const ev of [...events].reverse()) {
    if (!ev.file && !ev.cmd && ev.tool !== "Skill") continue;
    const key = activityKey(ev);
    const existing = fileMap.get(key);
    const agentId = ev.agent_id || ev.agent || "";
    const agentLabel = ev.agent_label || agentId;
    if (!existing || ev.ts > existing.lastTs) {
      fileMap.set(key, { tool: ev.tool, count: (existing?.count ?? 0) + 1, lastTs: ev.ts, agentId, agentLabel });
    } else {
      fileMap.set(key, { ...existing, count: existing.count + 1 });
    }
  }
  return {
    totalUniqueFiles: fileMap.size,
    fileActivity: [...fileMap.entries()]
      .sort((a, b) => b[1].lastTs.localeCompare(a[1].lastTs))
      .slice(0, limit)
      .map(([file, info]) => ({ file, ...info })),
  };
}

export function buildRecentAgents(events: ActivityEvent[], now = Date.now()): AgentEntry[] {
  const agentMap = new Map<string, AgentEntry>();
  for (const ev of events) {
    const secAgo = Math.floor((now - new Date(ev.ts).getTime()) / 1000);
    if (ev.tool === "AgentStart") {
      const key = ev.agent_id || (ev as {label?: string}).label || ev.ts;
      if (secAgo < RECENT_AGENT_MS / 1000) {
        agentMap.set(key, {
          agentId: key,
          label: (ev as {label?: string}).label ?? ev.agent_label ?? "agent",
          role: (ev as {role?: string}).role ?? "",
          skill: ev.skill ?? "",
          ts: ev.ts,
          done: false,
        });
      }
    } else if (ev.tool === "AgentDone") {
      const key = ev.agent_id || (ev as {label?: string}).label || "";
      const existing = agentMap.get(key);
      if (existing) agentMap.set(key, { ...existing, done: true });
    }
  }
  return Array.from(agentMap.values()).filter(a => {
    const secAgo = Math.floor((now - new Date(a.ts).getTime()) / 1000);
    return secAgo < RECENT_AGENT_MS / 1000;
  });
}

export function buildSessionAgents(events: ActivityEvent[], sessionIdleMs: number, now = Date.now()): AgentEntry[] {
  const agentMap = new Map<string, AgentEntry>();
  for (const ev of events) {
    if (ev.tool === "AgentStart") {
      const key = ev.agent_id || (ev as {label?: string}).label || ev.ts;
      agentMap.set(key, {
        agentId: key,
        label: (ev as {label?: string}).label ?? ev.agent_label ?? "agent",
        role: (ev as {role?: string}).role ?? "",
        skill: ev.skill ?? "",
        ts: ev.ts,
        done: false,
      });
    } else if (ev.tool === "AgentDone") {
      const key = ev.agent_id || (ev as {label?: string}).label || "";
      const existing = agentMap.get(key);
      if (existing) agentMap.set(key, { ...existing, done: true });
    }
  }
  const sessionIsIdle = sessionIdleMs > SESSION_IDLE_AGENT_STALE_MS;
  return Array.from(agentMap.values())
    .map(a => {
      if (a.done) return a;
      if (sessionIsIdle) return { ...a, done: true };
      const agentAgeMs = a.ts ? now - new Date(a.ts).getTime() : Infinity;
      if (agentAgeMs > AGENT_STALE_MS) return { ...a, done: true };
      return a;
    })
    .sort((a, b) => b.ts.localeCompare(a.ts))
    .slice(0, 50);
}

export function buildSessionAgentActivity(events: ActivityEvent[], agents: AgentEntry[]): AgentEntry[] {
  const activityMap = new Map<string, AgentEntry>();
  for (const agent of agents) activityMap.set(agent.agentId || agent.label, { ...agent, activity: [] });
  for (const ev of [...events].reverse()) {
    const agentId = ev.agent_id || ev.agent || "";
    if (!agentId) continue;
    const skillName = ev.tool === "Skill" ? (ev.skill || ev.file || "") : "";
    if (!ev.file && !ev.cmd && !skillName) continue;
    const label = ev.agent_label || agentId;
    const itemKey = activityKey(ev);
    const entry = activityMap.get(agentId) ?? { agentId, label, role: "", skill: "", ts: ev.ts, done: false, activity: [] };
    const existing = (entry.activity ?? []).find(a => a.file === itemKey);
    if (existing) {
      existing.count += 1;
      if (ev.ts > existing.lastTs) {
        existing.lastTs = ev.ts;
        existing.tool = ev.tool;
      }
    } else {
      (entry.activity ??= []).push({ file: itemKey, tool: ev.tool, count: 1, lastTs: ev.ts, agentId, agentLabel: label });
    }
    if (ev.ts > entry.ts) entry.ts = ev.ts;
    activityMap.set(agentId, entry);
  }
  return Array.from(activityMap.values())
    .map(agent => ({
      ...agent,
      activity: (agent.activity ?? []).sort((a, b) => b.lastTs.localeCompare(a.lastTs)).slice(0, 8),
    }))
    .filter(agent => agent.activity && agent.activity.length > 0)
    .sort((a, b) => b.ts.localeCompare(a.ts))
    .slice(0, 20);
}

export function sessionNick(id: string): string {
  const adjectives = ["bold", "calm", "swift", "bright", "sharp", "keen", "wild", "quiet", "brave", "cool", "warm", "soft", "fast", "wise", "pure", "deft", "lean", "sage", "red", "blue", "gold", "jade", "iron", "amber", "violet", "azure", "coral", "frost", "storm", "sand", "ember", "cedar", "steel", "nova", "oak", "ivy", "clay", "moss", "dawn", "rust"];
  const nouns = ["falcon", "tiger", "wolf", "eagle", "raven", "fox", "bear", "hawk", "lynx", "crane", "otter", "pike", "heron", "wren", "viper", "bison", "moose", "ibis", "kite", "wasp", "colt", "finch", "puma", "cobra", "gecko", "quail", "trout", "mink", "stork", "stoat", "dingo", "snipe", "marten", "condor", "osprey", "ferret", "oriole", "magpie", "jaguar", "marlin"];
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (Math.imul(h, 31) + id.charCodeAt(i)) >>> 0;
  return adjectives[h % adjectives.length] + "-" + nouns[(h >>> 8) % nouns.length];
}
