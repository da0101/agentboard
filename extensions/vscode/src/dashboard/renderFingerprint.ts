const VOLATILE_RENDER_KEYS = new Set(["ageSeconds", "lastUpdated", "sessionTime"]);

function stableRenderValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableRenderValue);
  if (!value || typeof value !== "object") return value;
  const input = value as Record<string, unknown>;
  const output: Record<string, unknown> = {};
  for (const key of Object.keys(input).sort()) {
    if (VOLATILE_RENDER_KEYS.has(key)) continue;
    output[key] = stableRenderValue(input[key]);
  }
  return output;
}

export function dashboardRenderFingerprint(payload: object): string {
  return JSON.stringify(stableRenderValue(payload));
}
