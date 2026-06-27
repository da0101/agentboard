import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { fmtModel } from "./formatters";
import { ActivityEvent, TranscriptAgent, WorkflowPlan } from "./types";

export function readWorkflowTranscriptAgents(root: string, sessionId: string): TranscriptAgent[] {
  try {
    const projectSlug = root.replace(/\//g, "-");
    const wfBase = path.join(os.homedir(), ".claude", "projects", projectSlug, sessionId, "subagents", "workflows");
    if (!fs.existsSync(wfBase)) return [];
    const agents: TranscriptAgent[] = [];
    for (const wfFolder of fs.readdirSync(wfBase)) {
      const wfPath = path.join(wfBase, wfFolder);
      const journalPath = path.join(wfPath, "journal.jsonl");
      if (!fs.existsSync(journalPath)) continue;
      const journalMtime = fs.statSync(journalPath).mtimeMs;
      const journalStale = (Date.now() - journalMtime) > 5 * 60 * 1000;
      const journalLines = fs.readFileSync(journalPath, "utf8").trim().split("\n").filter(Boolean);
      const started = new Map<string, { agentId: string }>();
      const results = new Map<string, string>();
      for (const line of journalLines) {
        try {
          const e = JSON.parse(line) as { type: string; agentId?: string; result?: string };
          if (e.type === "started" && e.agentId) started.set(e.agentId, { agentId: e.agentId });
          if (e.type === "result" && e.agentId) results.set(e.agentId, (e.result ?? "").slice(0, 200));
        } catch {
          // bad journal line
        }
      }
      for (const [agentId] of started) {
        const isDone = results.has(agentId) || journalStale;
        const result = results.get(agentId) ?? "";
        let label = "";
        let model = "";
        let currentTool = "";
        let ts = "";
        const transcriptPath = path.join(wfPath, `agent-${agentId}.jsonl`);
        try {
          if (fs.existsSync(transcriptPath)) {
            const stat = fs.statSync(transcriptPath);
            const readLen = Math.min(3000, stat.size);
            const buf = Buffer.alloc(readLen);
            const fd = fs.openSync(transcriptPath, "r");
            try { fs.readSync(fd, buf, 0, readLen, 0); } finally { fs.closeSync(fd); }
            const chunk = buf.toString("utf8");
            for (const rawLine of chunk.split("\n")) {
              if (!rawLine.trim().startsWith("{")) continue;
              try {
                const e = JSON.parse(rawLine) as { type?: string; message?: { role?: string; content?: unknown; model?: string }; timestamp?: string };
                if (e.timestamp) ts = e.timestamp;
                if (e.type === "user" && e.message?.role === "user" && e.message.content && !label) {
                  const raw = typeof e.message.content === "string"
                    ? e.message.content
                    : (Array.isArray(e.message.content) ? (e.message.content as {type?: string; text?: string}[]).find(c => c.type === "text")?.text ?? "" : "");
                  const taskMatch = raw.match(/TASK:\s*([^\n]{1,120})/);
                  label = taskMatch ? taskMatch[1].trim() : raw.split("\n").find(l => l.trim())?.trim().slice(0, 120) ?? "";
                }
                if (e.message?.model && !model) model = fmtModel(e.message.model);
              } catch {
                // skip malformed transcript line
              }
            }
            if (!isDone && stat.size > 3000) {
              const lastLen = Math.min(2000, stat.size);
              const lastBuf = Buffer.alloc(lastLen);
              const fd2 = fs.openSync(transcriptPath, "r");
              try { fs.readSync(fd2, lastBuf, 0, lastLen, stat.size - lastLen); } finally { fs.closeSync(fd2); }
              for (const rawLine of lastBuf.toString("utf8").split("\n")) {
                if (!rawLine.trim().startsWith("{")) continue;
                try {
                  const e = JSON.parse(rawLine) as { message?: { model?: string; content?: unknown }; timestamp?: string };
                  if (e.timestamp) ts = e.timestamp;
                  if (e.message?.model) model = fmtModel(e.message.model);
                  if (Array.isArray(e.message?.content)) {
                    const tu = (e.message!.content as {type?: string; name?: string}[]).find(c => c.type === "tool_use");
                    if (tu?.name) currentTool = tu.name;
                  }
                } catch {
                  // skip malformed transcript line
                }
              }
            }
          }
        } catch {
          // transcript unreadable
        }
        agents.push({ agentId, label: label || `Agent ${agentId.slice(0, 8)}`, model, status: isDone ? "done" : "running", currentTool, ts, result });
      }
    }
    return agents;
  } catch {
    return [];
  }
}

export function readWorkflowPlan(root: string): WorkflowPlan | null {
  try {
    const raw = fs.readFileSync(path.join(root, "agentboard.workflow-agents.json"), "utf8");
    const d = JSON.parse(raw) as WorkflowPlan;
    if (!d || !Array.isArray(d.agents)) return null;
    const ageMs = Date.now() - new Date(d.started_at).getTime();
    if (d.status === "done" && ageMs > 30 * 60 * 1000) return null;
    return d;
  } catch {
    return null;
  }
}

export function readSessionWorkflowState(
  root: string,
  sessionId: string,
  getEventsForRoot: (root: string) => ActivityEvent[],
): {
  hasWorkflow: boolean;
  workflowAgentCount: number;
  workflowLabel: string;
  transcriptAgents: TranscriptAgent[];
} {
  let hasWorkflow = false;
  let workflowAgentCount = 0;
  let workflowLabel = "";
  let wfStartTs: string | null = null;
  const wfEvents = getEventsForRoot(root)
    .filter(ev => ev.session_id === sessionId && (ev.tool === "WorkflowStart" || ev.tool === "WorkflowEnd"))
    .reverse();
  for (const ev of wfEvents) {
    if (ev.tool === "WorkflowStart") {
      wfStartTs = ev.ts;
      hasWorkflow = true;
      workflowAgentCount = (ev as {agent_count?: number}).agent_count ?? 0;
      workflowLabel = (ev as {label?: string}).label ?? "workflow";
    } else if (ev.tool === "WorkflowEnd" && wfStartTs) {
      const dur = new Date(ev.ts).getTime() - new Date(wfStartTs).getTime();
      if (dur > 30_000) {
        hasWorkflow = false;
        workflowAgentCount = 0;
        workflowLabel = "";
      }
    }
  }
  const transcriptAgents = readWorkflowTranscriptAgents(root, sessionId);
  const hasRunningTranscriptAgent = transcriptAgents.some(a => a.status === "running");
  if (hasRunningTranscriptAgent) hasWorkflow = true;
  if (hasWorkflow && transcriptAgents.length > 0 && !hasRunningTranscriptAgent) hasWorkflow = false;
  return { hasWorkflow, workflowAgentCount, workflowLabel, transcriptAgents };
}
