"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.readRecentEvents = readRecentEvents;
exports.readTrendEvents = readTrendEvents;
exports.lastSkillFromEvents = lastSkillFromEvents;
const fs = require("fs");
const path = require("path");
function readRecentEvents(root, n = 20) {
    try {
        return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
            .trim().split("\n").filter(Boolean).slice(-n).reverse()
            .map(line => {
            try {
                return JSON.parse(line);
            }
            catch {
                return null;
            }
        })
            .filter((e) => e !== null);
    }
    catch {
        return [];
    }
}
function readTrendEvents(root, n = 2000) {
    try {
        return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
            .trim().split("\n").filter(Boolean).slice(-n)
            .map(line => { try {
            return JSON.parse(line);
        }
        catch {
            return null;
        } })
            .filter((e) => e !== null);
    }
    catch {
        return [];
    }
}
// Only surface a skill if it was invoked within the last 15 minutes — clears automatically once work is done.
const SKILL_FRESH_MS = 15 * 60 * 1000;
function lastSkillFromEvents(events) {
    const now = Date.now();
    for (const e of events) {
        if (e.tool !== "Skill")
            continue;
        if (now - new Date(e.ts).getTime() > SKILL_FRESH_MS)
            break; // events newest-first; first old one means all rest are older
        const sk = (e.skill || e.file || "").split("\n")[0].trim();
        if (sk)
            return { skill: sk, sessionId: e.session_id ?? "" };
    }
    return { skill: "", sessionId: "" };
}
