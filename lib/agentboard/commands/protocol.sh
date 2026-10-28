# -----------------------------------------------------------------------------
# ab protocol [name] — print a procedure on demand.
#
# The always-loaded entry file keeps only hard rules and one-line triggers; the
# long procedures live in .platform/protocols/<name>.md and are read only when
# the task needs them (new task, closure, handoff, QA, ...). Pure bash.
# -----------------------------------------------------------------------------

protocol_usage() {
  cat <<'EOF2'
Usage: ab protocol            list the available protocols
       ab protocol <name>     print one protocol

Protocols are the long procedures kept out of the always-loaded entry file.
Run the one the entry file's trigger names, when that situation arises.
EOF2
}

cmd_protocol() {
  [[ -d "./.platform" ]] || die "No .platform/ found. Run 'ab init' first."
  local dir="./.platform/protocols" name="${1:-}" f when

  case "$name" in
    -h|--help) protocol_usage; return 0 ;;
    ""|list|--list|-l)
      [[ -d "$dir" ]] || die "No protocols installed. Run 'ab update' to add them."
      for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        when="$(awk '/^> /{sub(/^> */,""); print substr($0,1,96); exit}' "$f")"
        printf '  %s%-12s%s %s\n' "$C_BOLD" "$(basename "$f" .md)" "$C_RESET" "$when"
      done
      return 0 ;;
  esac

  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Protocol names are kebab-case (see: ab protocol)."
  f="$dir/${name}.md"
  [[ -f "$f" ]] || die "Unknown protocol: $name. Run 'ab protocol' to list them."
  cat "$f"
}
