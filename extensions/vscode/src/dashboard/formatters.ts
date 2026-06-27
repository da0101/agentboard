export function relTime(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

export function elapsedStr(s?: string): string {
  if (!s) return "";
  const d = Math.floor((Date.now() - new Date(s).getTime()) / 1000);
  return `${Math.floor(d / 60)}m ${d % 60}s`;
}

export function fmtModel(raw: string): string {
  if (!raw) return "";
  return raw.replace(/^claude-/i, "").replace(/-\d{8}$/, "").replace(/-latest$/, "")
    .split("-").filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");
}
