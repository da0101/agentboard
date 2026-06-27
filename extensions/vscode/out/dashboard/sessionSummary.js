"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.dedupeClearedSessions = dedupeClearedSessions;
exports.applySessionCatalogUsage = applySessionCatalogUsage;
const activityBuilders_1 = require("./activityBuilders");
function dedupeClearedSessions(sessions) {
    const sorted = [...sessions].sort((a, b) => a.startedAt.localeCompare(b.startedAt));
    const slotMap = new Map();
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
        }
        else {
            slotMap.delete(slotKey);
            slotMap.set(`${slotKey}::${older.sessionId}`, older);
            slotMap.set(`${slotKey}::${newer.sessionId}`, newer);
        }
    }
    return Array.from(slotMap.values()).sort((a, b) => a.startedAt.localeCompare(b.startedAt));
}
function applySessionCatalogUsage(sessions, skills, roles, getEventsForRoot) {
    const skillUsage = new Map();
    const roleUsage = new Map();
    const sessionLastSkillMap = new Map();
    const sessionLastRoleMap = new Map();
    for (const sess of sessions) {
        if (!sess.root)
            continue;
        const evs = getEventsForRoot(sess.root).filter(e => e.session_id === sess.sessionId);
        const nick = (0, activityBuilders_1.sessionNick)(sess.sessionId);
        for (const ev of evs) {
            if (ev.tool === "Skill") {
                const sk = ev.skill || ev.file || "";
                if (sk) {
                    if (!skillUsage.has(sk))
                        skillUsage.set(sk, []);
                    if (!skillUsage.get(sk).includes(nick))
                        skillUsage.get(sk).push(nick);
                    sessionLastSkillMap.set(sess.sessionId, sk);
                }
            }
            if (ev.tool === "RoleAdopt" && ev.role) {
                const ro = ev.role;
                if (!roleUsage.has(ro))
                    roleUsage.set(ro, []);
                if (!roleUsage.get(ro).includes(nick))
                    roleUsage.get(ro).push(nick);
                sessionLastRoleMap.set(sess.sessionId, ro);
            }
            if (ev.tool === "AgentStart" && ev.role) {
                const ro = ev.role;
                if (!roleUsage.has(ro))
                    roleUsage.set(ro, []);
                if (!roleUsage.get(ro).includes(nick))
                    roleUsage.get(ro).push(nick);
                if (!sessionLastRoleMap.has(sess.sessionId))
                    sessionLastRoleMap.set(sess.sessionId, ro);
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
