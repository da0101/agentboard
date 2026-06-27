import { CatalogItem } from "./types";

export const AB_CLI_COMMANDS: CatalogItem[] = [
  { name: "init", description: "Scaffold .platform/ into any project" },
  { name: "new-stream", description: "Open a new work stream" },
  { name: "new-domain", description: "Add a domain context file" },
  { name: "checkpoint", description: "Save progress snapshot to stream" },
  { name: "handoff", description: "Generate handoff packet for next session" },
  { name: "doctor", description: "Diagnose platform health" },
  { name: "brief", description: "Print session briefing from BRIEF.md" },
  { name: "progress", description: "Show stream progress summary" },
  { name: "close", description: "Close and archive a stream" },
  { name: "watch", description: "Watch active streams for updates" },
  { name: "migrate", description: "Migrate stream files to current format" },
  { name: "sync-skills", description: "Sync skill pack from agentboard" },
  { name: "validate", description: "Validate stream and platform files" },
  { name: "usage", description: "Token usage log and dashboard" },
];

export const MODEL_NAMES = new Set(["claude", "sonnet", "opus", "haiku", "fable", "gpt", "gemini", "codex"]);
