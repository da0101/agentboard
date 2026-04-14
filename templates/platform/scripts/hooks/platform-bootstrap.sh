#!/bin/bash
# platform-bootstrap.sh — SessionStart hook
# Generates a structured state report for platform projects.
# Reads .platform/work/ACTIVE.md and stream files to surface:
#   - Active streams and their status
#   - Whether closure_approved is set
#   - Whether audit reports are present or pending
#   - The next action for each stream
#
# Output is advisory — never blocks. Exit 0 always.
# Only fires when .platform/work/ACTIVE.md exists.

ACTIVE_FILE=".platform/work/ACTIVE.md"

# Exit silently if not a platform project
[ -f "$ACTIVE_FILE" ] || exit 0

# Extract stream rows (pipe-delimited, skip header and separator)
STREAMS=$(grep -E '^\|[[:space:]]*[a-zA-Z]' "$ACTIVE_FILE" 2>/dev/null \
          | grep -v 'Stream\s*|' \
          | grep -v '\-\-\-')

echo "=== PLATFORM STATE ==="
echo ""

if [ -z "$STREAMS" ]; then
  echo "Active streams: none"
  echo "Next: ask the user what to work on."
  echo ""
  echo "Hard rules active:"
  echo "  ⛔ closure_approved: true required before closing any stream (enforced by hook)"
  echo "  ⛔ Only the human/owner declares a stream complete"
  echo "  ⛔ Audit reports must be anchored to stream file (not just chat)"
  echo "======================"
  exit 0
fi

STREAM_COUNT=$(echo "$STREAMS" | grep -c '^')
echo "Active streams: $STREAM_COUNT"
echo ""

while IFS= read -r row; do
  [ -z "$row" ] && continue

  # Parse columns — | slug | type | status | agent | date |
  SLUG=$(echo "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
  STATUS=$(echo "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}')

  [ -z "$SLUG" ] && continue

  echo "  [$SLUG] — $STATUS"

  STREAM_FILE=".platform/work/${SLUG}.md"

  if [ -f "$STREAM_FILE" ]; then
    # Check closure_approved
    if grep -qiE 'closure_approved[*: ]+true' "$STREAM_FILE" 2>/dev/null; then
      echo "    closure: ✅ approved — present evidence to user and wait for sign-off to archive"
    else
      echo "    closure: ⛔ not approved — stream stays open until human explicitly approves"
    fi

    # Check audit report status
    if grep -q "^## 🔍 Audit" "$STREAM_FILE" 2>/dev/null; then
      if grep -qE '_not yet run_|_TODO_|_todo_' "$STREAM_FILE" 2>/dev/null; then
        echo "    audit:   ⚠️  placeholder present — fill it in if audit was run"
      else
        echo "    audit:   ✅ present"
      fi
    else
      echo "    audit:   — not run yet"
    fi

    # Show next action if defined
    NEXT=$(awk '/^## Next action/{found=1; next} found{if(/^##/) exit; if(/^[^_[:space:]]/) {print; exit}}' "$STREAM_FILE" 2>/dev/null | head -1)
    [ -n "$NEXT" ] && echo "    next:    $NEXT"
  else
    echo "    ⚠️  stream file missing: $STREAM_FILE"
  fi

  echo ""
done <<< "$STREAMS"

echo "Hard rules active:"
echo "  ⛔ closure_approved: true required before closing any stream (enforced by hook)"
echo "  ⛔ Only the human/owner declares a stream complete"
echo "  ⛔ Audit reports must be anchored to stream file (not just chat)"
echo "======================"

exit 0
