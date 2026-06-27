"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.readStreams = readStreams;
exports.readSkills = readSkills;
exports.readRoles = readRoles;
exports.readActiveStream = readActiveStream;
exports.isStreamActive = isStreamActive;
exports.isValidSkillName = isValidSkillName;
exports.readSessionStream = readSessionStream;
exports.readStreamRole = readStreamRole;
const fs = require("fs");
const path = require("path");
const markdown_1 = require("./markdown");
function readStreams(root) {
    const dir = path.join(root, ".platform", "work");
    const skip = new Set(["BRIEF.md", "TEMPLATE.md", "Status.md", "ACTIVE.md"]);
    try {
        return fs.readdirSync(dir).filter(f => f.endsWith(".md") && !skip.has(f)).flatMap(f => {
            try {
                const filePath = path.join(dir, f);
                const c = fs.readFileSync(filePath, "utf8");
                const fm = (0, markdown_1.parseFrontmatter)(c);
                const st = (fm.status ?? "").toLowerCase();
                if (["done", "archived", "closed"].includes(st))
                    return [];
                const body = c.replace(/^---[\s\S]*?---\n?/, "");
                const section = (headers) => {
                    const pat = new RegExp(`##+ (?:${headers.join("|")})\\s*\\n([\\s\\S]*?)(?=\\n##|$)`, "i");
                    return body.match(pat)?.[1]?.trim() ?? "";
                };
                const objective = fm.objective ?? section(["objective", "goal", "description", "what", "summary"]);
                const nextAction = fm.next_action ?? section(["next.?action", "next.?step", "now", "current"]);
                const progressRaw = section(["progress", "log", "notes", "session.?log"]);
                const criteriaBlock = section(["done.?criteria", "done", "acceptance", "checklist", "exit.?criteria"]);
                const doneCriteria = criteriaBlock.split("\n").filter(l => /^\s*-\s*\[/.test(l)).map(l => ({
                    done: /^\s*-\s*\[x\]/i.test(l),
                    text: l.replace(/^\s*-\s*\[.\]\s*/, "").trim(),
                }));
                return [{
                        slug: fm.slug ?? path.basename(f, ".md"),
                        status: fm.status ?? "active",
                        type: fm.type ?? "task",
                        role: fm.role ?? "",
                        branch: fm.branch ?? "",
                        objective: objective.slice(0, 300),
                        nextAction: nextAction.split("\n")[0]?.trim().slice(0, 200) ?? "",
                        doneCriteria: doneCriteria.slice(0, 12),
                        progress: progressRaw.split("\n").filter(Boolean).slice(-3).join(" · ").slice(0, 200),
                        filePath,
                    }];
            }
            catch {
                return [];
            }
        });
    }
    catch {
        return [];
    }
}
function readSkills(root) {
    const dir = path.join(root, ".claude", "skills");
    try {
        return fs.readdirSync(dir).flatMap(name => {
            try {
                const content = fs.readFileSync(path.join(dir, name, "SKILL.md"), "utf8");
                const fm = (0, markdown_1.parseFrontmatter)(content);
                const afterFm = content.replace(/^---[\s\S]*?---\n?/, "").trim();
                const fullDescription = (0, markdown_1.extractProse)(afterFm);
                return [{ name: fm.name ?? name, slug: name, description: fm.description ?? "", fullDescription }];
            }
            catch {
                return [{ name, slug: name, description: "" }];
            }
        });
    }
    catch {
        return [];
    }
}
function readRoles(root) {
    const dir = path.join(root, ".platform", "roles");
    try {
        const indexPairs = new Map();
        try {
            const indexContent = fs.readFileSync(path.join(dir, "INDEX.md"), "utf8");
            const pairRe = /`([a-z][a-z-]+)`\+([a-z][a-z-]+)/g;
            let m;
            while ((m = pairRe.exec(indexContent)) !== null) {
                const [, roleSlug, skillSlug] = m;
                if (!indexPairs.has(roleSlug))
                    indexPairs.set(roleSlug, []);
                indexPairs.get(roleSlug).push(skillSlug);
            }
        }
        catch {
            // INDEX.md is optional.
        }
        return fs.readdirSync(dir).filter(f => f.endsWith(".md") && f !== "INDEX.md").flatMap(f => {
            try {
                const content = fs.readFileSync(path.join(dir, f), "utf8");
                const fm = (0, markdown_1.parseFrontmatter)(content);
                const slug = path.basename(f, ".md");
                const afterFm = content.replace(/^---[\s\S]*?---\n?/, "").trim();
                const fullDescription = (0, markdown_1.extractProse)(afterFm);
                const linked = new Set(indexPairs.get(slug) ?? []);
                const bodyMatches = afterFm.match(/\bab-[a-z][a-z-]+/g) ?? [];
                for (const s of bodyMatches)
                    linked.add(s);
                const linkedSkills = [...linked];
                return [{ name: fm.name ?? fm.slug ?? slug, slug, description: fm.mission ?? fm.description ?? fm.objective ?? "", fullDescription, linkedSkills }];
            }
            catch {
                return [];
            }
        });
    }
    catch {
        return [];
    }
}
function readActiveStream(root) {
    try {
        const brief = fs.readFileSync(path.join(root, ".platform", "work", "BRIEF.md"), "utf8");
        const briefSlug = brief.match(/\*\*Stream file:\*\*\s*`work\/([^`]+)\.md`/)?.[1] ?? "";
        if (briefSlug) {
            const active = fs.readFileSync(path.join(root, ".platform", "work", "ACTIVE.md"), "utf8");
            const isActive = active.split("\n").some(line => {
                const cols = line.split("|").map(c => c.trim());
                const slug = cols[1];
                const status = cols[3];
                return slug === briefSlug && status && !["done", "archived", "closed"].includes(status);
            });
            if (isActive)
                return briefSlug;
            for (const line of active.split("\n")) {
                const cols = line.split("|").map(c => c.trim());
                const slug = cols[1];
                const status = cols[3];
                if (slug && slug !== "Stream" && !slug.startsWith("-") && status && !["done", "archived", "closed", "", "Status"].includes(status)) {
                    return slug;
                }
            }
        }
    }
    catch {
        // Fall through to no active stream.
    }
    return "";
}
function isStreamActive(root, slug) {
    if (!slug)
        return false;
    try {
        const c = fs.readFileSync(path.join(root, ".platform", "work", `${slug}.md`), "utf8");
        const st = ((0, markdown_1.parseFrontmatter)(c).status ?? "").toLowerCase();
        return !["done", "archived", "closed"].includes(st);
    }
    catch {
        return false;
    }
}
function isValidSkillName(s) {
    return !!s && !s.includes("/") && !s.includes("\n") && !s.includes("\\n") && s.length <= 60;
}
function readSessionStream(root, sessionId, eventsCache, loadStreamOverride) {
    const override = loadStreamOverride?.(root, sessionId);
    if (override !== undefined)
        return override;
    try {
        const tsv = fs.readFileSync(path.join(root, ".platform", ".session-streams.tsv"), "utf8");
        for (const line of tsv.trim().split("\n")) {
            const [id, slug] = line.split("\t");
            if (id === sessionId && slug) {
                const s = slug.trim();
                return isStreamActive(root, s) ? s : "";
            }
        }
    }
    catch {
        // no mapping yet
    }
    if (eventsCache) {
        for (const ev of eventsCache) {
            if (ev.session_id === sessionId && ev.stream) {
                const s = ev.stream;
                return isStreamActive(root, s) ? s : "";
            }
        }
    }
    return "";
}
function readStreamRole(root, slug) {
    if (!slug)
        return "";
    try {
        return (0, markdown_1.parseFrontmatter)(fs.readFileSync(path.join(root, ".platform", "work", `${slug}.md`), "utf8")).role ?? "";
    }
    catch {
        return "";
    }
}
