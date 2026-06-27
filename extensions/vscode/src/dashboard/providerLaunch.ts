export type AgentProvider = "codex" | "claude" | "gemini";

export interface ProviderChoice {
  provider: AgentProvider;
  label: string;
  description: string;
}

const PROVIDER_LABELS: Record<AgentProvider, string> = {
  codex: "Codex",
  claude: "Claude",
  gemini: "Gemini",
};

const WRAPPER_SCRIPTS: Partial<Record<AgentProvider, string>> = {
  codex: ".platform/scripts/codex-ab",
  gemini: ".platform/scripts/gemini-ab",
};

export const PROVIDER_CHOICES: ProviderChoice[] = [
  { provider: "codex", label: "Codex", description: "Use the Agentboard Codex wrapper when present" },
  { provider: "claude", label: "Claude", description: "Launch Claude Code directly" },
  { provider: "gemini", label: "Gemini", description: "Use the Agentboard Gemini wrapper when present" },
];

export function normalizeProvider(raw: string | undefined): AgentProvider | "" {
  const value = String(raw || "").toLowerCase();
  if (value.includes("codex") || value.includes("gpt")) return "codex";
  if (value.includes("claude") || value.includes("opus") || value.includes("sonnet") || value.includes("haiku")) return "claude";
  if (value.includes("gemini")) return "gemini";
  return "";
}

export function providerLabel(provider: AgentProvider): string {
  return PROVIDER_LABELS[provider];
}

export function providerWrapperScript(provider: AgentProvider): string {
  return WRAPPER_SCRIPTS[provider] || "";
}

export function buildProviderLaunchCommand(provider: AgentProvider, escapedPrompt: string, hasWrapper: boolean): string {
  const wrapper = providerWrapperScript(provider);
  if (hasWrapper && wrapper) return `bash ${wrapper} "${escapedPrompt}"`;
  return `${provider} "${escapedPrompt}"`;
}
