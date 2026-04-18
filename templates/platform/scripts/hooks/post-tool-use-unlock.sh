#!/usr/bin/env bash
# post-tool-use-unlock.sh — release file lock after Claude writes a file
# Registered as a PostToolUse hook in .claude/settings.json
# Fail-open: silently skips if daemon is unreachable.

set -uo pipefail

[[ -d ".platform" ]] || exit 0
_port_file=".platform/.daemon-port"
[[ -f "$_port_file" ]] || exit 0
command -v curl >/dev/null 2>&1 || exit 0
_port="$(cat "$_port_file" 2>/dev/null)"
[[ "$_port" =~ ^[0-9]+$ ]] || exit 0
_provider="${AGENTBOARD_PROVIDER:-claude}"
_input="$(cat)"
[[ -n "$_input" ]] || exit 0

_tool="$(printf '%s' "$_input" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')"
case "$_tool" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

if command -v jq >/dev/null 2>&1; then
  _files="$(printf '%s' "$_input" | jq -r '
    .tool_input.file_path,
    .tool_input.new_file_path,
    (.tool_input.edits[]?.file_path // empty)
    | select(. != null and . != "")
  ' 2>/dev/null | sort -u)"
else
  _files="$(printf '%s' "$_input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' | sort -u)"
fi

[[ -n "$_files" ]] || exit 0

while IFS= read -r _file; do
  [[ -n "$_file" ]] || continue
  _f="${_file#./}"
  curl -sf -m 2 -X DELETE "http://127.0.0.1:$_port/lock" \
    -H 'Content-Type: application/json' \
    -d "{\"file\":\"$_f\",\"provider\":\"$_provider\"}" >/dev/null 2>&1 || true
done <<< "$_files"

exit 0
