import { HudStatus } from "../hudTypes";

export const HUD_STALE_MS = 30 * 60 * 1000;

export function isHudFresh(hud: HudStatus | null, now = Date.now()): boolean {
  if (!hud) return false;
  const ts = hud.last_updated || hud.context?.started_at || "";
  if (!ts) return false;
  const updatedMs = new Date(ts).getTime();
  return Number.isFinite(updatedMs) && now - updatedMs <= HUD_STALE_MS;
}
