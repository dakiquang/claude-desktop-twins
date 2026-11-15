# shellcheck shell=bash
# List Claude Code sessions per account. Copying sessions between accounts is part of
# Claude Desktop Twins Premium; `cdt sessions copy` points there.
#
# Layout (checked on Claude 5.11492.5, undocumented by Anthropic):
#   <data dir>/claude-code-sessions/<accountUuid>/<orgUuid>/local_<uuid>.json
#   <data dir>/claude-code-sessions/<accountUuid>/<orgUuid>/archived-sessions.idx
#       {"v":1,"archived":["local_<uuid>", ...]}
# Transcripts live in the shared ~/.claude/projects/*/<cliSessionId>.jsonl.

_json() { osascript -l JavaScript "$(dirname "${BASH_SOURCE[0]}")/json.js" "$@"; }

# Data dir for an account query or "default" (plain Claude.app).
sessions_data_dir() { # query
  local slug
  if [ "$1" = "default" ]; then
    echo "$CDT_DEFAULT_DATA_DIR"
    return 0
  fi
  slug="$(account_resolve "$1")" || return 1
  account_data_dir "$slug"
}

sessions_name() { # query -> slug or "default", for backup names and messages
  if [ "$1" = "default" ]; then echo default; else account_resolve "$1"; fi
}

# Org dirs of a store, one per line.
sessions_org_dirs() { # data_dir
  local d
  for d in "$1"/claude-code-sessions/*/*/; do
    [ -d "$d" ] && echo "${d%/}"
  done
}

_count_sessions() { # org_dir
  local f n=0
  for f in "$1"/local_*.json; do [ -f "$f" ] && n=$((n + 1)); done
  echo "$n"
}

# The org dir that receives copies: the one with the most sessions, newest on a tie.
sessions_target_dir() { # data_dir
  local d best="" best_n=-1 best_t=0 n t
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n="$(_count_sessions "$d")"
    t="$(stat -f %m "$d")"
    if [ "$n" -gt "$best_n" ] || { [ "$n" -eq "$best_n" ] && [ "$t" -gt "$best_t" ]; }; then
      best="$d"; best_n="$n"; best_t="$t"
    fi
  done <<EOF
$(sessions_org_dirs "$1")
EOF
  [ -n "$best" ] && echo "$best"
}

_sessions_list_json() { # data_dir
  local data="$1" d rel orgs="" folders count folder total archived
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    rel="${d#"$data"/claude-code-sessions/}"
    total="$(_count_sessions "$d")"
    archived="$(_json archived "$d/archived-sessions.idx" | grep -c . || true)"
    folders=""
    if [ "$total" -gt 0 ]; then
      while read -r count folder; do
        [ -n "$folder" ] || continue
        folders="${folders:+$folders,}{\"folder\":$(json_str "$folder"),\"sessions\":$count}"
      done <<EOF2
$(_json scan "$d" | cut -d $'\x1f' -f2 | grep . | sort | uniq -c | sort -rn)
EOF2
    fi
    orgs="${orgs:+$orgs,}{$(json_join \
      "\"account_uuid\":$(json_str "${rel%%/*}")" \
      "\"org_uuid\":$(json_str "${rel##*/}")" \
      "\"sessions\":$total" \
      "\"archived\":$archived" \
      "\"folders\":[$folders]")}"
  done <<EOF
$(sessions_org_dirs "$data")
EOF
  printf '{"schema":%s,"data_dir":%s,"orgs":[%s]}\n' "$CDT_JSON_SCHEMA" "$(json_str "$data")" "$orgs"
}

sessions_list() { # query [--json]
  local data d total archived
  data="$(sessions_data_dir "$1")" || return 1
  if [ "${2:-}" = "--json" ]; then
    _sessions_list_json "$data"
    return 0
  fi
  if [ -z "$(sessions_org_dirs "$data")" ]; then
    info "no Code sessions in $data"
    return 0
  fi
  while IFS= read -r d; do
    total="$(_count_sessions "$d")"
    archived="$(_json archived "$d/archived-sessions.idx" | grep -c . || true)"
    info "account ${d%/*}" | sed "s#$data/claude-code-sessions/##"
    info "  org ${d##*/}: $total sessions, $archived archived"
    if [ "$total" -gt 0 ]; then
      info "  top working folders:"
      _json scan "$d" | cut -d $'\x1f' -f2 | grep . | sort | uniq -c | sort -rn | head -n 5 |
        sed 's/^ */    /'
    fi
  done <<EOF
$(sessions_org_dirs "$data")
EOF
}

cmd_sessions() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    list)
      [ -n "${1:-}" ] || die "usage: cdt sessions list <account|default> [--json]"
      case "${2:-}" in ""|--json) ;; *) die "usage: cdt sessions list <account|default> [--json]" ;; esac
      sessions_list "$1" "${2:-}" || exit 1 ;;
    copy)
      err "copying sessions between accounts is part of Claude Desktop Twins Premium."
      err "See $CDT_PREMIUM_URL"
      exit 1 ;;
    *) die "usage: cdt sessions list <account|default> [--json]" ;;
  esac
}
