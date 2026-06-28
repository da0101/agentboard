"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.dashboardRenderFingerprint = dashboardRenderFingerprint;
const VOLATILE_RENDER_KEYS = new Set(["ageSeconds", "lastUpdated", "sessionTime"]);
function stableRenderValue(value) {
    if (Array.isArray(value))
        return value.map(stableRenderValue);
    if (!value || typeof value !== "object")
        return value;
    const input = value;
    const output = {};
    for (const key of Object.keys(input).sort()) {
        if (VOLATILE_RENDER_KEYS.has(key))
            continue;
        output[key] = stableRenderValue(input[key]);
    }
    return output;
}
function dashboardRenderFingerprint(payload) {
    return JSON.stringify(stableRenderValue(payload));
}
