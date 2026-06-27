"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HUD_STALE_MS = void 0;
exports.isHudFresh = isHudFresh;
exports.HUD_STALE_MS = 30 * 60 * 1000;
function isHudFresh(hud, now = Date.now()) {
    if (!hud)
        return false;
    const ts = hud.last_updated || hud.context?.started_at || "";
    if (!ts)
        return false;
    const updatedMs = new Date(ts).getTime();
    return Number.isFinite(updatedMs) && now - updatedMs <= exports.HUD_STALE_MS;
}
