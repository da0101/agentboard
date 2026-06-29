"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildTrendData = buildTrendData;
const N = 20;
const WINDOW_MS = {
    "10m": 10 * 60000, "30m": 30 * 60000, "1h": 60 * 60000,
    "3h": 180 * 60000, "6h": 360 * 60000, "12h": 720 * 60000,
};
function bucketize(events, windowMs, now) {
    const bMs = windowMs / N;
    // Snap the window end to the next bucket boundary so the grid is stable between
    // refreshes — a given event stays in the same bucket until an entire bMs has elapsed.
    const windowEnd = Math.ceil(now / bMs) * bMs;
    const start = windowEnd - windowMs;
    const b = Array.from({ length: N }, (_, i) => ({
        ts: start + i * bMs, edits: 0, agents: 0, cmds: 0, skills: 0, workflows: 0,
    }));
    // Track workflow spans: a WorkflowStart before or within the window stays active until a
    // WorkflowEnd (or end of window). This makes a multi-hour workflow show across all buckets
    // in the current time window instead of a single spike at launch time.
    let activeWfCount = 0;
    for (const ev of events) {
        const t = new Date(ev.ts).getTime();
        const tool = ev.tool;
        if (tool === "WorkflowStart" && t < start)
            activeWfCount++;
        if (tool === "WorkflowEnd" && t < start)
            activeWfCount = Math.max(0, activeWfCount - 1);
    }
    if (activeWfCount > 0) {
        for (const bucket of b)
            bucket.workflows = activeWfCount;
    }
    for (const ev of events) {
        const t = new Date(ev.ts).getTime();
        if (t < start || t >= windowEnd)
            continue;
        const bi = Math.min(Math.floor((t - start) / bMs), N - 1);
        const tool = ev.tool;
        if (tool === "Edit" || tool === "Write" || tool === "MultiEdit")
            b[bi].edits++;
        else if (tool === "AgentStart")
            b[bi].agents++;
        else if (tool === "Bash")
            b[bi].cmds++;
        else if (tool === "Skill")
            b[bi].skills++;
        else if (tool === "WorkflowStart") {
            // Span from this bucket to the end of the window
            for (let i = bi; i < N; i++)
                b[i].workflows = Math.max(b[i].workflows, 1);
        }
        else if (tool === "WorkflowEnd") {
            // Clear from this bucket forward (workflow finished)
            for (let i = bi; i < N; i++)
                b[i].workflows = 0;
        }
    }
    return b;
}
function buildTrendData(events, now) {
    const result = {};
    for (const [w, ms] of Object.entries(WINDOW_MS))
        result[w] = bucketize(events, ms, now);
    // "all": span from earliest event to now — window size snapped to bucket grid inside bucketize
    let earliest = now - 3600000;
    for (const ev of events) {
        const t = new Date(ev.ts).getTime();
        if (t < earliest)
            earliest = t;
    }
    const allWindowMs = Math.max(now - earliest, 60000);
    const allBMs = allWindowMs / N;
    const allWindowEnd = Math.ceil(now / allBMs) * allBMs;
    result["all"] = bucketize(events, allWindowEnd - earliest, now);
    return result;
}
