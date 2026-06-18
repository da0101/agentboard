export interface HudContext {
  model?: string;
  repo?: string;
  branch?: string;
  token_pressure?: string;
  active_session_id?: string;
  session_id?: string;
  started_at?: string;
  context_remaining_pct?: number;
  context_tokens?: number;
}

export interface HudAgent {
  label?: string;
  objective?: string;
  phase?: string;
  started_at?: string;
  role?: string;
  model?: string;
  session_id?: string;
}

export interface HudCost {
  session_usd?: number;
  session_tokens?: number;
}

export interface HudRisk {
  dirty_worktree?: boolean;
  uncommitted_changes?: boolean;
  open_conflicts?: boolean;
  manual_review_flags?: string[];
}

export interface HudChecks {
  ci_status?: string;
  local_tests?: string;
  last_run?: string;
}

export interface HudPr {
  number?: number;
  title?: string;
  status?: string;
}

export interface HudQueue {
  open_prs?: HudPr[];
  merge_queue_depth?: number;
  open_issues_count?: number;
}

export interface HudStatus {
  context?: HudContext;
  tool_calls?: number;
  active_agents?: HudAgent[];
  todos?: Record<string, string[]>;
  checks?: HudChecks;
  cost?: HudCost;
  risk?: HudRisk;
  queue?: HudQueue;
}
