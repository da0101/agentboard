"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseFrontmatter = parseFrontmatter;
exports.extractProse = extractProse;
function parseFrontmatter(content) {
    const m = content.match(/^---\n([\s\S]*?)\n---/);
    if (!m)
        return {};
    const r = {};
    for (const line of m[1].split("\n")) {
        const i = line.indexOf(":");
        if (i === -1)
            continue;
        r[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, "");
    }
    return r;
}
function extractProse(body, maxChars = 600) {
    const lines = body.split("\n");
    const prose = [];
    let inCode = false;
    for (const raw of lines) {
        const l = raw.trim();
        if (l.startsWith("```")) {
            inCode = !inCode;
            continue;
        }
        if (inCode)
            continue;
        if (!l || l.startsWith("#") || l.startsWith(">") || l.startsWith("\\033") || l.includes("\x1b["))
            continue;
        prose.push(l);
    }
    return prose.join(" ").slice(0, maxChars).trim();
}
