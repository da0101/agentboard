"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PROVIDER_CHOICES = void 0;
exports.normalizeProvider = normalizeProvider;
exports.providerLabel = providerLabel;
exports.providerWrapperScript = providerWrapperScript;
exports.buildProviderLaunchCommand = buildProviderLaunchCommand;
const PROVIDER_LABELS = {
    codex: "Codex",
    claude: "Claude",
    gemini: "Gemini",
};
const WRAPPER_SCRIPTS = {
    codex: ".platform/scripts/codex-ab",
    gemini: ".platform/scripts/gemini-ab",
};
exports.PROVIDER_CHOICES = [
    { provider: "codex", label: "Codex", description: "Use the Agentboard Codex wrapper when present" },
    { provider: "claude", label: "Claude", description: "Launch Claude Code directly" },
    { provider: "gemini", label: "Gemini", description: "Use the Agentboard Gemini wrapper when present" },
];
function normalizeProvider(raw) {
    const value = String(raw || "").toLowerCase();
    if (value.includes("codex") || value.includes("gpt"))
        return "codex";
    if (value.includes("claude") || value.includes("opus") || value.includes("sonnet") || value.includes("haiku"))
        return "claude";
    if (value.includes("gemini"))
        return "gemini";
    return "";
}
function providerLabel(provider) {
    return PROVIDER_LABELS[provider];
}
function providerWrapperScript(provider) {
    return WRAPPER_SCRIPTS[provider] || "";
}
function buildProviderLaunchCommand(provider, escapedPrompt, hasWrapper) {
    const wrapper = providerWrapperScript(provider);
    if (hasWrapper && wrapper)
        return `bash ${wrapper} "${escapedPrompt}"`;
    return `${provider} "${escapedPrompt}"`;
}
