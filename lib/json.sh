# shellcheck shell=bash
# Minimal JSON output for Bash 3.2, used by `--json` flags so other programs (the
# menu bar app, scripts) can read the CLI without parsing text. Every document starts
# with "schema": CDT_JSON_SCHEMA; bump it when a field changes meaning or goes away.

# shellcheck disable=SC2034 # read by the other lib files
CDT_JSON_SCHEMA=1

# A JSON string: escape backslash and quote, turn newline, carriage return and tab into
# their escapes, drop other control characters. UTF-8 passes through unchanged.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s="$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')"
  printf '"%s"' "$s"
}

# A string, or null when empty.
json_str_or_null() {
  if [ -n "$1" ]; then json_str "$1"; else printf 'null'; fi
}

# A number, or null when empty or not digits.
json_num_or_null() {
  case "$1" in
    ''|*[!0-9]*) printf 'null' ;;
    *) printf '%s' "$1" ;;
  esac
}

json_bool() { # 0 = true (shell success), anything else = false
  if [ "$1" = 0 ]; then printf 'true'; else printf 'false'; fi
}

# Join already-encoded JSON values given as arguments with commas.
json_join() {
  local first=1 v
  for v in "$@"; do
    if [ "$first" = 1 ]; then first=0; else printf ','; fi
    printf '%s' "$v"
  done
}
