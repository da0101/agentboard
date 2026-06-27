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

export function lastSkillFromEvents(events: ActivityEvent[]): { skill: string; sessionId: string } {
  for (const e of events) {
    if (e.tool !== "Skill") continue;
    const sk = e.skill || e.file || "";
    if (sk) return { skill: sk, sessionId: e.session_id ?? "" };
  }
  return { skill: "", sessionId: "" };
}
