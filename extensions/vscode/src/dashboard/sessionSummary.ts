import { sessionNick } from "./activityBuilders";
import { ActivityEvent, CatalogItem, DashboardSessionEntry } from "./types";

export function dedupeClearedSessions(sessions: DashboardSessionEntry[]): DashboardSessionEntry[] {
  const sorted = [...sessions].sort((a, b) => a.startedAt.localeCompare(b.startedAt));
  const slotMap = new Map<string, DashboardSessionEntry>();
  for (const s of sorted) {
    const slotKey = `${s.root}::${s.branch || s.sessionId}`;
    const existing = slotMap.get(slotKey);
    if (!existing) {
      slotMap.set(slotKey, s);
      continue;
    }
    const older = existing.startedAt < s.startedAt ? existing : s;
    const newer = existing.startedAt < s.startedAt ? s : existing;
    const gapMs = new Date(newer.startedAt).getTime() - new Date(older.lastUpdated).getTime();
    if (gapMs >= 0 && gapMs < 2 * 60 * 1000) {
      slotMap.set(slotKey, newer);
    } else {
      slotMap.delete(slotKey);
      slotMap.set(`${slotKey}::${older.sessionId}`, older);
      slotMap.set(`${slotKey}::${newer.sessionId}`, newer);
    }
  }
  return Array.from(slotMap.values()).sort((a, b) => a.startedAt.localeCompare(b.startedAt));
}

export function applySessionCatalogUsage(
  sessions: DashboardSessionEntry[],
  skills: CatalogItem[],
  roles: CatalogItem[],
  getEventsForRoot: (root: string) => ActivityEvent[],
): { skillsWithUsage: CatalogItem[]; rolesWithUsage: CatalogItem[] } {
  const skillUsage = new Map<string, string[]>();
  const roleUsage = new Map<string, string[]>();
  const sessionLastSkillMap = new Map<string, string>();
  const sessionLastRoleMap = new Map<string, string>();
  for (const sess of sessions) {
    if (!sess.root) continue;
    const evs = getEventsForRoot(sess.root).filter(e => e.session_id === sess.sessionId);
    const nick = sessionNick(sess.sessionId);
    for (const ev of evs) {
      if (ev.tool === "Skill") {
        const sk = ev.skill || ev.file || "";
        if (sk) {
          if (!skillUsage.has(sk)) skillUsage.set(sk, []);
          if (!skillUsage.get(sk)!.includes(nick)) skillUsage.get(sk)!.push(nick);
          sessionLastSkillMap.set(sess.sessionId, sk);
        }
      }
      if (ev.tool === "RoleAdopt" && (ev as {role?: string}).role) {
        const ro = (ev as {role?: string}).role!;
        if (!roleUsage.has(ro)) roleUsage.set(ro, []);
        if (!roleUsage.get(ro)!.includes(nick)) roleUsage.get(ro)!.push(nick);
        sessionLastRoleMap.set(sess.sessionId, ro);
      }
      if (ev.tool === "AgentStart" && (ev as {role?: string}).role) {
        const ro = (ev as {role?: string}).role!;
        if (!roleUsage.has(ro)) roleUsage.set(ro, []);
        if (!roleUsage.get(ro)!.includes(nick)) roleUsage.get(ro)!.push(nick);
        if (!sessionLastRoleMap.has(sess.sessionId)) sessionLastRoleMap.set(sess.sessionId, ro);
      }
    }
    sess.sessionLastSkill = sessionLastSkillMap.get(sess.sessionId) ?? "";
    sess.sessionLastRole = sessionLastRoleMap.get(sess.sessionId) ?? "";
  }
  const skillsWithUsage = skills.map(s => ({ ...s, usedBy: skillUsage.get(s.name) ?? skillUsage.get(s.slug ?? "") ?? [] }));
  const rolesWithUsage = roles.map(r => {
    const bySlug = r.slug ? (roleUsage.get(r.slug) ?? []) : [];
    const byName = roleUsage.get(r.name) ?? [];
    const merged = [...new Set([...bySlug, ...byName])];
    return { ...r, usedBy: merged };
  });
  return { skillsWithUsage, rolesWithUsage };
}
