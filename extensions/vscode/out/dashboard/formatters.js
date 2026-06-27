"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.relTime = relTime;
exports.elapsedStr = elapsedStr;
exports.fmtModel = fmtModel;
function relTime(iso) {
    const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (s < 60)
        return `${s}s ago`;
    if (s < 3600)
        return `${Math.floor(s / 60)}m ago`;
    return `${Math.floor(s / 3600)}h ago`;
}
function elapsedStr(s) {
    if (!s)
        return "";
    const d = Math.floor((Date.now() - new Date(s).getTime()) / 1000);
    return `${Math.floor(d / 60)}m ${d % 60}s`;
}
function fmtModel(raw) {
    if (!raw)
        return "";
    return raw.replace(/^claude-/i, "").replace(/-\d{8}$/, "").replace(/-latest$/, "")
        .split("-").filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(" ");
}
