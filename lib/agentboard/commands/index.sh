#!/usr/bin/env bash
# agentboard index — build ~/.agentboard/index.db from .platform/knowledge/*.jsonl

_INDEX_DB="$HOME/.agentboard/index.db"

# ---------------------------------------------------------------------------
# Schema DDL
# ---------------------------------------------------------------------------

_INDEX_DDL='
CREATE TABLE IF NOT EXISTS knowledge (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    type     TEXT NOT NULL,
    slug     TEXT,
    date     TEXT,
    domain   TEXT,
    title    TEXT,
    body     TEXT,
    tags     TEXT,
    raw_json TEXT NOT NULL,
    UNIQUE(type, slug, raw_json)
);
CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts
    USING fts5(type, slug, domain, title, body,
               content="knowledge", content_rowid="id");
'

_index_init_db() {
  local db="$1"
  mkdir -p "$(dirname "$db")"
  sqlite3 "$db" "$_INDEX_DDL"
}

# ---------------------------------------------------------------------------
# Field extractors — pure awk, no Python
# Field order mirrors schema definitions above.
# ---------------------------------------------------------------------------

# _json_field <field> <json-line>  → echoes value or empty string
_json_field() {
  local field="$1" line="$2"
  printf '%s' "$line" \
    | awk -v f="\"$field\"" '
        {
          idx = index($0, f)
          if (!idx) { print ""; next }
          rest = substr($0, idx + length(f))
          # skip whitespace and colon
          gsub(/^[[:space:]]*:[[:space:]]*/, "", rest)
          if (substr(rest, 1, 1) == "\"") {
            # string value — extract between quotes, handle \" escapes
            val = ""
            i = 2
            while (i <= length(rest)) {
              c = substr(rest, i, 1)
              if (c == "\\" && substr(rest, i+1, 1) == "\"") {
                val = val "\""
                i += 2
              } else if (c == "\"") {
                break
              } else {
                val = val c
                i++
              }
            }
            print val
          } else if (substr(rest, 1, 1) == "[") {
            # array — return raw array text (used for tags)
            depth = 0; val = ""
            for (i = 1; i <= length(rest); i++) {
              c = substr(rest, i, 1)
              val = val c
              if (c == "[") depth++
              else if (c == "]") { depth--; if (depth == 0) break }
            }
            print val
          } else {
            # number / bool / null — extract up to delimiter
            match(rest, /[^,}[:space:]]+/)
            print substr(rest, RSTART, RLENGTH)
          }
        }
      '
}

# Escape single quotes for SQLite
_sq_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

# ---------------------------------------------------------------------------
# Insert one JSONL file into the DB
# ---------------------------------------------------------------------------

_index_file() {
  local db="$1" jsonl="$2" count=0

  [[ -f "$jsonl" ]] || return 0

  local sql_batch=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local type slug date domain title body tags raw

    type="$(_json_field "type"     "$line")"
    slug="$(_json_field "slug"     "$line")"

    # streams use "slug"; others use "id" or "stream_slug" as secondary key
    [[ -z "$slug" ]] && slug="$(_json_field "id"         "$line")"
    [[ -z "$slug" ]] && slug="$(_json_field "stream_slug" "$line")"

    date="$(_json_field    "date"       "$line")"
    [[ -z "$date" ]] && date="$(_json_field "closed_at" "$line")"

    domain="$(_json_field  "domain"     "$line")"
    title="$(_json_field   "title"      "$line")"

    # body: "body", "summary", "description", "root_cause", or "decision"
    body="$(_json_field    "body"       "$line")"
    [[ -z "$body" ]] && body="$(_json_field "summary"     "$line")"
    [[ -z "$body" ]] && body="$(_json_field "description" "$line")"
    [[ -z "$body" ]] && body="$(_json_field "root_cause"  "$line")"
    [[ -z "$body" ]] && body="$(_json_field "decision"    "$line")"

    tags="$(_json_field    "tags"       "$line")"

    raw="$line"

    # Escape for SQL
    local t s dt d ti b tg r
    t="$(_sq_escape  "$type")"
    s="$(_sq_escape  "$slug")"
    dt="$(_sq_escape "$date")"
    d="$(_sq_escape  "$domain")"
    ti="$(_sq_escape "$title")"
    b="$(_sq_escape  "$body")"
    tg="$(_sq_escape "$tags")"
    r="$(_sq_escape  "$raw")"

    sql_batch+="INSERT OR REPLACE INTO knowledge
      (type, slug, date, domain, title, body, tags, raw_json)
      VALUES ('$t','$s','$dt','$d','$ti','$b','$tg','$r');
"
    count=$(( count + 1 ))

  done < "$jsonl"

  if [[ $count -gt 0 ]]; then
    sqlite3 "$db" "BEGIN; ${sql_batch} COMMIT;"
  fi

  printf '%d' "$count"
}

# ---------------------------------------------------------------------------
# FTS rebuild
# ---------------------------------------------------------------------------

_index_rebuild_fts() {
  local db="$1"
  sqlite3 "$db" "INSERT INTO knowledge_fts(knowledge_fts) VALUES('rebuild');"
}

# ---------------------------------------------------------------------------
# Public command
# ---------------------------------------------------------------------------

cmd_index() {
  local db="$_INDEX_DB" knowledge_dir="./.platform/knowledge"
  local quiet=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --db)     db="${2:?'--db requires a path'}"; shift 2 ;;
      --dir)    knowledge_dir="${2:?'--dir requires a path'}"; shift 2 ;;
      -q|--quiet) quiet=1; shift ;;
      -h|--help) _index_help; return 0 ;;
      *) die "Unknown flag: $1. Run 'agentboard index --help'." ;;
    esac
  done

  command -v sqlite3 >/dev/null 2>&1 \
    || die "sqlite3 is required for 'agentboard index'. Install it first."

  [[ -d "$knowledge_dir" ]] \
    || die "Knowledge dir not found: $knowledge_dir. Run 'agentboard distill' first."

  (( quiet )) || say "Initialising index at ${db} ..."
  _index_init_db "$db"

  local total=0
  local -a known_files=(
    streams.jsonl
    learnings.jsonl
    decisions.jsonl
    bugs.jsonl
    changes.jsonl
  )

  local file n
  for file in "${known_files[@]}"; do
    local path="${knowledge_dir}/${file}"
    [[ -f "$path" ]] || continue
    n="$(_index_file "$db" "$path")"
    total=$(( total + n ))
    (( quiet )) || ok "${file}: ${n} record(s) indexed"
  done

  # Also pick up any extra *.jsonl files not in the known list
  while IFS= read -r path; do
    local base; base="$(basename "$path")"
    # Skip if already processed
    local already=0
    for file in "${known_files[@]}"; do
      [[ "$base" == "$file" ]] && already=1 && break
    done
    (( already )) && continue
    n="$(_index_file "$db" "$path")"
    total=$(( total + n ))
    (( quiet )) || ok "${base}: ${n} record(s) indexed"
  done < <(find "$knowledge_dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | sort)

  (( quiet )) || say ""

  if [[ $total -eq 0 ]]; then
    warn "No records found in ${knowledge_dir}. Run 'agentboard distill <slug>' to populate."
    return 0
  fi

  _index_rebuild_fts "$db"
  (( quiet )) || ok "FTS index rebuilt"
  (( quiet )) || say ""

  ok "Indexed ${total} total record(s) → ${db}"
}

_index_help() {
  cat <<'EOF'
agentboard index [flags]

Build (or refresh) the full-text search index at ~/.agentboard/index.db from
all .platform/knowledge/*.jsonl files in the current project.

Run this after 'agentboard distill <slug>' to make new knowledge searchable.
Then use 'agentboard search <query>' to query across all indexed records.

OPTIONS
  --db <path>    Override DB path (default: ~/.agentboard/index.db)
  --dir <path>   Override knowledge dir (default: .platform/knowledge/)
  -q, --quiet    Suppress per-file output; only print final ok/error line
  -h, --help     Show this help

EXAMPLES
  agentboard index
  agentboard index --quiet
  agentboard index --db /tmp/test.db --dir /path/to/knowledge

TABLES
  knowledge       — one row per JSONL record (INSERT OR REPLACE deduplication)
  knowledge_fts   — FTS5 virtual table over type, slug, domain, title, body
EOF
}
