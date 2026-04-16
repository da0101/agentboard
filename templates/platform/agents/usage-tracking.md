# Global Usage Tracking Protocol (Token Monitoring & Optimization)

> **Audience:** Claude Code, Codex CLI, Gemini CLI.
> **Goal:** Track token consumption globally across all projects in a central SQLite database.

---

## 📊 The Global Data Store

All usage data is stored in a central SQLite database at `~/.agentboard/usage.db`. This database is private to your machine and aggregates data from all repositories where `agentboard` is used.

### Schema

```sql
CREATE TABLE IF NOT EXISTS usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    agent_provider TEXT NOT NULL, -- 'gemini', 'claude', 'codex'
    model TEXT,                    -- e.g., 'claude-3-5-sonnet', 'gemini-1.5-pro'
    stream_slug TEXT,              -- slug from work/<slug>.md
    repo TEXT,                     -- the repository being worked on (auto-detected)
    task_type TEXT,                -- 'research', 'implementation', 'debug', 'audit', 'chore'
    input_tokens INTEGER,
    output_tokens INTEGER,
    total_tokens INTEGER,
    estimated_cost REAL,           -- in USD (optional)
    session_id TEXT                -- to group multiple turns in one session
);
```

---

## 📝 Logging Protocol

### When to Log

1.  **Turn End (Optional/Granular):** If the CLI provider outputs token usage after every turn, you may log it immediately.
2.  **Stream Closure (Mandatory):** During the **Stream Closure Protocol** (Stage 6), you MUST aggregate the total usage for the task and record a final entry.

### How to Log

Use the `agentboard usage log` command via `run_shell_command`.

**Example Command:**
```bash
agentboard usage log --provider 'gemini' --model 'gemini-1.5-pro' --stream 'add-usage-tracking' --type 'implementation' --input 1500 --output 500
```
*Note: The `repo` field is automatically detected from the current directory name.*

---

## 🔍 Optimization & Study

As an AI agent, you should use this global data to improve efficiency across the platform:

1.  **Cross-Project Audit:** Before starting a **Medium+** task, query the global database for similar tasks in *any* project.
    *   *Question:* "How many tokens do 'refactors' usually take for this user?"
    *   *Action:* If historical data shows high consumption for this task type, propose a more "surgical" approach (e.g., reading specific line ranges instead of full files).
2.  **Stack Efficiency:** Identify which repositories or stacks are the most "expensive" and suggest specific conventions to reduce context size.
3.  **Efficiency Reporting:** During Stream Closure, report the total token "investment" for the feature and how it compares to the global average for similar tasks.

### Useful Global Queries

- **Usage by Repo:**
  `SELECT repo, SUM(total_tokens) FROM usage GROUP BY repo ORDER BY SUM(total_tokens) DESC;`
- **Most expensive task types globally:**
  `SELECT task_type, AVG(total_tokens) FROM usage GROUP BY task_type;`
- **Total consumption across all projects (last 30 days):**
  `SELECT SUM(total_tokens) FROM usage WHERE timestamp > date('now', '-30 days');`

---

## 🛠️ Maintenance

- **Location:** The database is at `~/.agentboard/usage.db`.
- **Cleanup:** Periodically run `DELETE FROM usage WHERE timestamp < date('now', '-30 days');` to keep only recent data for analysis.
