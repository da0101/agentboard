export interface ActivityEvent {
  ts: string;
  tool: string;
  stream: string;
  file?: string;
  cmd?: string;
  agent?: string;
  skill?: string;
  hook_event_name?: string;
  session_id?: string;
  agent_id?: string;
  agent_label?: string;
  parent_session_id?: string;
}

export interface SessionActivityItem {
  file: string;
  tool: string;
  count: number;
  lastTs: string;
  added?: number;
  deleted?: number;
  lineCount?: number;
  committed?: boolean;
  isNew?: boolean;
  isDeleted?: boolean;
  agentId?: string;
  agentLabel?: string;
}

export interface AgentEntry {
  agentId: string;
  label: string;
  role: string;
  skill: string;
  ts: string;
  done: boolean;
  activity?: SessionActivityItem[];
}

export interface CatalogItem {
  name: string;
  slug?: string;
  description: string;
  fullDescription?: string;
  usedBy?: string[];
  linkedSkills?: string[];
}

export interface StreamEntry {
  slug: string;
  type: string;
  status: string;
  role: string;
  objective: string;
  nextAction: string;
  branch: string;
  doneCriteria: Array<{ text: string; done: boolean }>;
  progress: string;
  filePath: string;
}

export interface WorkflowAgentPlan {
  label: string;
  role: string;
  skill: string;
  model: string;
  phase: string;
  agentType: string;
  status: string;
  unlabeled?: boolean;
}

export interface WorkflowPlan {
  name: string;
  phases: string[];
  agents: WorkflowAgentPlan[];
  total: number;
  started_at: string;
  ended_at?: string;
  status: string;
}

export interface TranscriptAgent {
  agentId: string;
  label: string;
  model: string;
  status: "running" | "done";
  currentTool: string;
  ts: string;
  result: string;
}

export interface DashboardSessionEntry {
  sessionId: string;
  provider?: string;
  model: string;
  costUsd: number;
  cost: string;
  branch: string;
  root: string;
  shellPid: number;
  projectName: string;
  sessionLastSkill: string;
  sessionLastRole: string;
  startedAt: string;
  lastUpdated: string;
  ageSeconds: number;
  ctxPct: number | null;
  stream: string;
  streamPinned: boolean;
  availableStreams: string[];
  sessionTime: string;
  activity: SessionActivityItem[];
  agents: AgentEntry[];
  agentActivity: AgentEntry[];
  hasWorkflow: boolean;
  workflowAgentCount: number;
  workflowLabel: string;
  workflowTranscriptAgents: TranscriptAgent[];
  workflowPlan: WorkflowPlan | null;
  nick: string;
}
