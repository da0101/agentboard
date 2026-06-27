"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.readRecentEvents = readRecentEvents;
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
function lastSkillFromEvents(events) {
    for (const e of events) {
        if (e.tool !== "Skill")
            continue;
        const sk = e.skill || e.file || "";
        if (sk)
            return { skill: sk, sessionId: e.session_id ?? "" };
    }
    return { skill: "", sessionId: "" };
}
