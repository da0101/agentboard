const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const { parseFrontmatter, extractProse } = require("../out/dashboard/markdown");
const { readStreams, readSessionStream, readStreamRole } = require("../out/dashboard/catalogStore");
const { readRecentEvents, lastSkillFromEvents } = require("../out/dashboard/eventStore");
const { fmtModel, elapsedStr } = require("../out/dashboard/formatters");
const { readWorkflowPlan, readWorkflowTranscriptAgents } = require("../out/dashboard/workflowStore");
const { buildFileActivity, buildSessionAgentActivity, buildSessionAgents } = require("../out/dashboard/activityBuilders");
const { applyGitStatus } = require("../out/dashboard/gitActivity");
const { buildExplainChangePrompt, buildRefactorPrompt, escapeForDoubleQuotedCli } = require("../out/dashboard/prompts");
const { applySessionCatalogUsage, dedupeClearedSessions } = require("../out/dashboard/sessionSummary");
const { sessionRootMatchesWorkspace } = require("../out/dashboard/sessionFiles");
const { isHudFresh } = require("../out/dashboard/hudFreshness");
const {
  parseCodexEffort,
  parseElapsedSeconds,
  parseLsofCwd,
  parsePsCodexProcesses,
  rawCodexProcessToSession,
} = require("../out/dashboard/rawCodexProcesses");

function test(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

test("parseFrontmatter reads quoted scalar values", () => {
  const got = parseFrontmatter("---\nslug: codex-dashboard\nstatus: \"active\"\n---\nBody");
  assert.deepStrictEqual(got, { slug: "codex-dashboard", status: "active" });
});

test("parseFrontmatter returns empty object without frontmatter", () => {
  assert.deepStrictEqual(parseFrontmatter("# Title\nBody"), {});
});

test("extractProse skips headings, quotes, and fenced code", () => {
  const got = extractProse("# Heading\n> quoted\n```sh\necho hidden\n```\nUseful text.\nMore text.");
  assert.strictEqual(got, "Useful text. More text.");
});

test("extractProse respects maxChars", () => {
  assert.strictEqual(extractProse("abcdef", 3), "abc");
});

function tempProject() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "ab-vscode-dashboard-"));
  fs.mkdirSync(path.join(root, ".platform", "work"), { recursive: true });
  fs.mkdirSync(path.join(root, ".platform", "roles"), { recursive: true });
  fs.mkdirSync(path.join(root, ".claude", "skills"), { recursive: true });
  return root;
}

test("readStreams returns active stream metadata", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, ".platform", "work", "feature-a.md"), [
    "---",
    "slug: feature-a",
    "status: active",
    "role: engineer",
    "---",
    "## Objective",
    "Build the feature.",
    "## Done Criteria",
    "- [x] First criterion",
    "- [ ] Second criterion",
  ].join("\n"));
  const streams = readStreams(root);
  assert.strictEqual(streams.length, 1);
  assert.strictEqual(streams[0].slug, "feature-a");
  assert.deepStrictEqual(streams[0].doneCriteria, [
    { done: true, text: "First criterion" },
    { done: false, text: "Second criterion" },
  ]);
});

test("readStreams ignores closed streams and missing roots", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, ".platform", "work", "closed.md"), "---\nstatus: closed\n---\n");
  assert.deepStrictEqual(readStreams(root), []);
  assert.deepStrictEqual(readStreams(path.join(root, "missing")), []);
});

test("readSessionStream respects explicit override, including empty none", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, ".platform", "work", "active.md"), "---\nstatus: active\n---\n");
  fs.writeFileSync(path.join(root, ".platform", ".session-streams.tsv"), "s1\tactive\n");
  assert.strictEqual(readSessionStream(root, "s1", [], () => ""), "");
});

test("readSessionStream ignores mappings to inactive streams", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, ".platform", "work", "closed.md"), "---\nstatus: closed\n---\n");
  fs.writeFileSync(path.join(root, ".platform", ".session-streams.tsv"), "s1\tclosed\n");
  assert.strictEqual(readSessionStream(root, "s1"), "");
});

test("readStreamRole returns role or empty string", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, ".platform", "work", "active.md"), "---\nrole: reviewer\n---\n");
  assert.strictEqual(readStreamRole(root, "active"), "reviewer");
  assert.strictEqual(readStreamRole(root, "missing"), "");
});

test("readRecentEvents returns newest valid json events first", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, ".platform", "events.jsonl"), [
    JSON.stringify({ ts: "2026-01-01T00:00:00Z", tool: "Edit", stream: "s", file: "a.ts" }),
    "not-json",
    JSON.stringify({ ts: "2026-01-01T00:01:00Z", tool: "Skill", stream: "s", skill: "ab-review", session_id: "sid" }),
  ].join("\n"));
  const events = readRecentEvents(root, 10);
  assert.strictEqual(events.length, 2);
  assert.strictEqual(events[0].tool, "Skill");
  assert.deepStrictEqual(lastSkillFromEvents(events), { skill: "ab-review", sessionId: "sid" });
});

test("readRecentEvents handles missing events file", () => {
  assert.deepStrictEqual(readRecentEvents(tempProject()), []);
  assert.deepStrictEqual(lastSkillFromEvents([]), { skill: "", sessionId: "" });
});

test("fmtModel normalizes common provider model names", () => {
  assert.strictEqual(fmtModel("claude-opus-4-20260101"), "Opus 4");
  assert.strictEqual(fmtModel("gpt-5.5-high-latest"), "Gpt 5.5 High");
});

test("elapsedStr returns compact elapsed duration or empty string", () => {
  assert.strictEqual(elapsedStr(""), "");
  const started = new Date(Date.now() - 65_000).toISOString();
  assert.match(elapsedStr(started), /^1m \d+s$/);
});

test("readWorkflowPlan returns active workflow plan", () => {
  const root = tempProject();
  fs.writeFileSync(path.join(root, "agentboard.workflow-agents.json"), JSON.stringify({
    name: "audit",
    phases: ["scan"],
    agents: [{ label: "a", role: "r", skill: "s", model: "m", phase: "scan", agentType: "default", status: "running" }],
    total: 1,
    started_at: new Date().toISOString(),
    status: "running",
  }));
  assert.strictEqual(readWorkflowPlan(root).name, "audit");
});

test("workflow readers handle absent or stale workflow state", () => {
  const root = tempProject();
  assert.strictEqual(readWorkflowPlan(root), null);
  assert.deepStrictEqual(readWorkflowTranscriptAgents(root, "missing-session"), []);
});

test("buildFileActivity deduplicates files and keeps agent identity", () => {
  const events = [
    { ts: "2026-01-01T00:00:00Z", tool: "Edit", stream: "s", file: "a.ts", agent_id: "agent-1", agent_label: "auditor" },
    { ts: "2026-01-01T00:01:00Z", tool: "Edit", stream: "s", file: "a.ts", agent_id: "agent-1", agent_label: "auditor" },
    { ts: "2026-01-01T00:02:00Z", tool: "Bash", stream: "s", cmd: "npm test" },
  ];
  const got = buildFileActivity(events, 10);
  assert.strictEqual(got.totalUniqueFiles, 2);
  assert.strictEqual(got.fileActivity[0].file, "$ npm test");
  assert.strictEqual(got.fileActivity[1].count, 2);
  assert.strictEqual(got.fileActivity[1].agentId, "agent-1");
});

test("buildSessionAgents marks idle running agents done", () => {
  const events = [{ ts: "2026-01-01T00:00:00Z", tool: "AgentStart", stream: "s", agent_id: "a1", agent_label: "default" }];
  const agents = buildSessionAgents(events, 11 * 60 * 1000, new Date("2026-01-01T00:01:00Z").getTime());
  assert.strictEqual(agents[0].done, true);
});

test("buildSessionAgentActivity nests activity under the matching agent", () => {
  const events = [
    { ts: "2026-01-01T00:00:00Z", tool: "AgentStart", stream: "s", agent_id: "a1", agent_label: "default" },
    { ts: "2026-01-01T00:01:00Z", tool: "Write", stream: "s", file: "new.ts", agent_id: "a1", agent_label: "default" },
  ];
  const agents = buildSessionAgents(events, 0, new Date("2026-01-01T00:01:30Z").getTime());
  const activity = buildSessionAgentActivity(events, agents);
  assert.strictEqual(activity.length, 1);
  assert.strictEqual(activity[0].agentId, "a1");
  assert.strictEqual(activity[0].activity[0].file, "new.ts");
});

test("applyGitStatus marks new and deleted activity rows", () => {
  const activity = [
    { file: "new.ts", tool: "Write", count: 1, lastTs: "2026-01-01T00:00:00Z" },
    { file: "gone.ts", tool: "Edit", count: 1, lastTs: "2026-01-01T00:00:00Z" },
    { file: "kept.ts", tool: "Edit", count: 1, lastTs: "2026-01-01T00:00:00Z" },
  ];
  applyGitStatus(activity, "?? new.ts\n D gone.ts\n M kept.ts\n");
  assert.strictEqual(activity[0].isNew, true);
  assert.strictEqual(activity[1].isDeleted, true);
  assert.strictEqual(activity[2].isNew, undefined);
});

test("applyGitStatus adds missing new files as activity rows", () => {
  const activity = [
    { file: "existing.ts", tool: "Edit", count: 1, lastTs: "2026-01-01T00:00:00Z" },
  ];
  applyGitStatus(activity, " M existing.ts\n?? extensions/vscode/src/dashboard/new-helper.ts\n", "2026-01-01T00:01:00Z");
  const added = activity.find(item => item.file === "extensions/vscode/src/dashboard/new-helper.ts");
  assert.ok(added);
  assert.strictEqual(added.tool, "Write");
  assert.strictEqual(added.isNew, true);
  assert.strictEqual(added.lastTs, "2026-01-01T00:01:00Z");
  assert.strictEqual(activity[0].file, "extensions/vscode/src/dashboard/new-helper.ts");
});

test("prompt builders include target file and cleanup phase gate", () => {
  assert.match(buildExplainChangePrompt({ absPath: "/tmp/a.ts", added: 1, deleted: 2, totalChanged: 3 }), /\/tmp\/a\.ts/);
  const refactor = buildRefactorPrompt({ absPath: "/tmp/b.ts", lineCount: 1000 });
  assert.match(refactor, /CRITICAL/);
  assert.match(refactor, /DO NOT proceed to Phase 3/);
});

test("escapeForDoubleQuotedCli escapes shell-sensitive characters", () => {
  assert.strictEqual(escapeForDoubleQuotedCli('a"b`c\\d'), 'a\\"b\\`c\\\\d');
});

function session(overrides) {
  return Object.assign({
    sessionId: "s1", model: "", costUsd: 0, cost: "", branch: "develop", root: "/repo",
    shellPid: 0, projectName: "repo", sessionLastSkill: "", sessionLastRole: "",
    startedAt: "2026-01-01T00:00:00Z", lastUpdated: "2026-01-01T00:01:00Z",
    ageSeconds: 0, ctxPct: null, stream: "", streamPinned: false, availableStreams: [],
    sessionTime: "", activity: [], agents: [], agentActivity: [],
    hasWorkflow: false, workflowAgentCount: 0, workflowLabel: "",
    workflowTranscriptAgents: [], workflowPlan: null, nick: "",
  }, overrides);
}

test("dedupeClearedSessions keeps newer quick restart", () => {
  const older = session({ sessionId: "old", startedAt: "2026-01-01T00:00:00Z", lastUpdated: "2026-01-01T00:01:00Z" });
  const newer = session({ sessionId: "new", startedAt: "2026-01-01T00:01:30Z", lastUpdated: "2026-01-01T00:02:00Z" });
  const got = dedupeClearedSessions([older, newer]);
  assert.strictEqual(got.length, 1);
  assert.strictEqual(got[0].sessionId, "new");
});

test("sessionRootMatchesWorkspace scopes sessions to the current project root", () => {
  const root = tempProject();
  const otherRoot = tempProject();
  assert.strictEqual(sessionRootMatchesWorkspace(root, root), true);
  assert.strictEqual(sessionRootMatchesWorkspace(otherRoot, root), false);
  assert.strictEqual(sessionRootMatchesWorkspace("", root), false);
});

test("isHudFresh rejects stale local HUD status", () => {
  const now = new Date("2026-06-27T12:00:00Z").getTime();
  assert.strictEqual(isHudFresh({ last_updated: "2026-06-27T11:45:00Z" }, now), true);
  assert.strictEqual(isHudFresh({ last_updated: "2026-06-25T14:31:09.131Z" }, now), false);
  assert.strictEqual(isHudFresh({ active_agents: [{}] }, now), false);
});

test("parsePsCodexProcesses keeps native Codex processes only", () => {
  const rows = parsePsCodexProcesses([
    "35888    20:39:25 node /opt/homebrew/bin/codex -c model_reasoning_effort=\"high\"",
    "35889    20:39:25 /opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex -c model_reasoning_effort=\"high\"",
    "77570       00:00 rg codex",
  ].join("\n"));
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].pid, 35889);
  assert.strictEqual(rows[0].elapsedSeconds, 20 * 3600 + 39 * 60 + 25);
  assert.strictEqual(parseCodexEffort(rows[0].command), "high");
  assert.strictEqual(parseElapsedSeconds("02-00:59:29"), 2 * 86400 + 59 * 60 + 29);
});

test("rawCodexProcessToSession scopes process fallback to workspace root", () => {
  const root = tempProject();
  const otherRoot = tempProject();
  const proc = {
    pid: 123,
    elapsedSeconds: 65,
    command: "/bin/codex -c model_reasoning_effort=\"high\"",
    cwd: root,
    root,
    effort: "high",
  };
  const session = rawCodexProcessToSession(proc, root, "develop", new Date("2026-06-27T12:00:00Z").getTime());
  assert.ok(session);
  assert.strictEqual(session.sessionId, "raw-codex-123");
  assert.strictEqual(session.provider, "codex");
  assert.strictEqual(session.model, "Codex high");
  assert.strictEqual(session.root, root);
  assert.strictEqual(rawCodexProcessToSession(proc, otherRoot, "develop"), null);
  assert.strictEqual(parseLsofCwd("p123\nn/tmp/project\n"), "/tmp/project");
});

test("applySessionCatalogUsage annotates used skills and roles", () => {
  const sessions = [session({ sessionId: "s1" })];
  const events = [
    { ts: "2026-01-01T00:00:00Z", tool: "Skill", stream: "s", skill: "ab-review", session_id: "s1" },
    { ts: "2026-01-01T00:01:00Z", tool: "RoleAdopt", stream: "s", role: "reviewer", session_id: "s1" },
  ];
  const result = applySessionCatalogUsage(
    sessions,
    [{ name: "ab-review", slug: "ab-review", description: "" }],
    [{ name: "Reviewer", slug: "reviewer", description: "" }],
    () => events,
  );
  assert.strictEqual(sessions[0].sessionLastSkill, "ab-review");
  assert.strictEqual(sessions[0].sessionLastRole, "reviewer");
  assert.strictEqual(result.skillsWithUsage[0].usedBy.length, 1);
  assert.strictEqual(result.rolesWithUsage[0].usedBy.length, 1);
});
