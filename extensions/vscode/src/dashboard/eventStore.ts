import * as fs from "fs";
import * as path from "path";
import { ActivityEvent } from "./types";

export function readRecentEvents(root: string, n = 20): ActivityEvent[] {
  try {
    return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
      .trim().split("\n").filter(Boolean).slice(-n).reverse()
      .map(line => {
        try {
          return JSON.parse(line) as ActivityEvent;
        } catch {
          return null;
        }
      })
      .filter((e): e is ActivityEvent => e !== null);
  } catch {
    return [];
  }
}

export function readTrendEvents(root: string, n = 2000): ActivityEvent[] {
  try {
    return fs.readFileSync(path.join(root, ".platform", "events.jsonl"), "utf8")
      .trim().split("\n").filter(Boolean).slice(-n)
      .map(line => { try { return JSON.parse(line) as ActivityEvent; } catch { return null; } })
      .filter((e): e is ActivityEvent => e !== null);
  } catch { return []; }
}

// Only surface a skill if it was invoked within the last 15 minutes — clears automatically once work is done.
const SKILL_FRESH_MS = 15 * 60 * 1000;

export function lastSkillFromEvents(events: ActivityEvent[]): { skill: string; sessionId: string } {
  const now = Date.now();
  for (const e of events) {
    if (e.tool !== "Skill") continue;
    if (now - new Date(e.ts).getTime() > SKILL_FRESH_MS) break; // events newest-first; first old one means all rest are older
    const sk = (e.skill || e.file || "").split("\n")[0].trim();
    if (sk) return { skill: sk, sessionId: e.session_id ?? "" };
  }
  return { skill: "", sessionId: "" };
}
