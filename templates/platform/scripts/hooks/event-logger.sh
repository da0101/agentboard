#!/usr/bin/env bash
# event-logger.sh — append AI agent tool-call events to .platform/events.jsonl
#
# Invoked by Claude Code hooks (PostToolUse + UserPromptSubmit) via stdin.
# Can also be called from Codex/Gemini hooks — any JSON payload on stdin is
# accepted. Fail-open: errors never block a tool call.
#
# Output format (one JSON object per line):
#   {"ts":"<ISO-8601>","provider":"<p>","stream":"<slug>","tool":"<name>","raw":<hook-payload>}
#
# This is the foundation of cross-provider orchestration: every agent writes
# to the same append-only log; the next agent reads the tail for context.

set -u
[[ -d ".platform" ]] || exit 0

log_file=".platform/events.jsonl"
mkdir -p "$(dirname "$log_file")" 2>/dev/null || exit 0

input="$(cat 2>/dev/null)"
[[ -n "$input" ]] || exit 0

# Guard against pathological input size (cap at 64 KB per event)
if (( ${#input} > 65536 )); then
  input="${input:0:65536}"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || exit 0
provider="${AGENTBOARD_PROVIDER:-claude}"

# Extract active stream slug: first file in work/ with status = active/planning/review
stream=""
for f in .platform/work/*.md; do
  [[ -f "$f" ]] || continue
  [[ "$f" == *"/ACTIVE.md" || "$f" == *"/BRIEF.md" || "$f" == *"/TEMPLATE.md" ]] && continue
  _status="$(awk '/^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }' "$f" 2>/dev/null)"
  case "$_status" in
    done|archived|closed) continue ;;
    *) stream="$(basename "$f" .md)"; break ;;
  esac
done

# Best-effort tool_name extraction without jq (works for Claude Code format)
tool=""
if [[ "$input" == *'"tool_name"'* ]]; then
  tool="$(printf '%s' "$input" | awk 'match($0, /"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"/) {
    s = substr($0, RSTART, RLENGTH)
    sub(/.*"tool_name"[[:space:]]*:[[:space:]]*"/, "", s)
    sub(/".*/, "", s)
    print s; exit
  }')"
fi

# Escape provider/stream/tool for JSON (they're simple but paranoid-safe)
_jsesc() {
  printf '%s' "$1" | awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s", $0 }'
}
provider_e="$(_jsesc "$provider")"
stream_e="$(_jsesc "$stream")"
tool_e="$(_jsesc "$tool")"

# Append one JSON line. Format string enforces the newline; malformed raw
# input only breaks its own line (append-only: never corrupts prior lines).
# Use flock for concurrent-write safety when available, best-effort otherwise.
if command -v flock >/dev/null 2>&1; then
  (
    flock -w 1 9 || exit 0
    printf '{"ts":"%s","provider":"%s","stream":"%s","tool":"%s","raw":%s}\n' \
      "$ts" "$provider_e" "$stream_e" "$tool_e" "$input" >&9
  ) 9>>"$log_file" 2>/dev/null
else
  printf '{"ts":"%s","provider":"%s","stream":"%s","tool":"%s","raw":%s}\n' \
    "$ts" "$provider_e" "$stream_e" "$tool_e" "$input" >> "$log_file" 2>/dev/null
fi

exit 0
