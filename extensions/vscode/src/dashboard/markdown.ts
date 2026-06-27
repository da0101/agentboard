export function parseFrontmatter(content: string): Record<string, string> {
  const m = content.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return {};
  const r: Record<string, string> = {};
  for (const line of m[1].split("\n")) {
    const i = line.indexOf(":");
    if (i === -1) continue;
    r[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, "");
  }
  return r;
}

export function extractProse(body: string, maxChars = 600): string {
  const lines = body.split("\n");
  const prose: string[] = [];
  let inCode = false;
  for (const raw of lines) {
    const l = raw.trim();
    if (l.startsWith("```")) {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;
    if (!l || l.startsWith("#") || l.startsWith(">") || l.startsWith("\\033") || l.includes("\x1b[")) continue;
    prose.push(l);
  }
  return prose.join(" ").slice(0, maxChars).trim();
}
