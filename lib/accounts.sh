# shellcheck shell=bash
# Account registry: one plist per account at $CDT_ACCOUNTS_DIR/<slug>.plist with
# Label, Slug, BundleId, DataDir, SourceVersion and Created.

account_file() { printf '%s/%s.plist' "$CDT_ACCOUNTS_DIR" "$1"; }
account_exists() { [ -f "$(account_file "$1")" ]; }
account_get() { plist_get "$(account_file "$1")" "$2"; }
account_set() { plist_set_string "$(account_file "$1")" "$2" "$3"; }

account_label() { account_get "$1" Label; }
account_bundle_id() { account_get "$1" BundleId; }
account_data_dir() { account_get "$1" DataDir; }

account_create() { # slug label data_dir
  local f
  f="$(account_file "$1")"
  mkdir -p "$CDT_ACCOUNTS_DIR" || return 1
  cat > "$f" <<'EOF' || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
EOF
  plist_set_string "$f" Label "$2" &&
    plist_set_string "$f" Slug "$1" &&
    plist_set_string "$f" BundleId "$(bundle_id_for "$1")" &&
    plist_set_string "$f" DataDir "$3" &&
    plist_set_string "$f" SourceVersion "" &&
    plist_set_string "$f" Created "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

account_delete() { rm -f "$(account_file "$1")"; }

# All registered slugs, one per line, sorted.
account_slugs() {
  local f
  [ -d "$CDT_ACCOUNTS_DIR" ] || return 0
  for f in "$CDT_ACCOUNTS_DIR"/*.plist; do
    [ -f "$f" ] || continue
    basename "$f" .plist
  done
}

# Slug of the account registered on a data dir, if any.
account_for_data_dir() {
  local s
  for s in $(account_slugs); do
    [ "$(account_data_dir "$s")" = "$1" ] && { echo "$s"; return 0; }
  done
  return 1
}

account_is_empty() { dir_is_empty "$(account_data_dir "$1")"; }

# Reject labels that cannot become an account: no letters or digits, a leading dot
# (hidden app), or the reserved words "default" (plain Claude.app in `sessions`) and
# "premium" (its slug would give a clone the bundle id of the Premium menu bar app).
label_check() { # label
  local slug
  slug="$(slugify "$1")"
  if [ -z "$slug" ]; then err "account name must contain letters or digits: '$1'"; return 1; fi
  case "$1" in .*) err "account name must not start with a dot: '$1'"; return 1 ;; esac
  if [ "$slug" = default ]; then err "'default' is reserved for plain Claude.app"; return 1; fi
  if [ "$slug" = premium ]; then err "'premium' is reserved for Claude Desktop Twins Premium"; return 1; fi
}

# Resolve exactly (slug or label, ignoring case and punctuation). Commands that change
# or delete things use this, so a partial name never hits the wrong account.
account_resolve_exact() { # query
  local q s guess
  q="$(_norm "$1")"
  for s in $(account_slugs); do
    if [ "$s" = "$q" ] || [ "$(_norm "$(account_label "$s")")" = "$q" ]; then
      echo "$s"; return 0
    fi
  done
  guess="$(account_resolve "$1" 2>/dev/null)"
  if [ -n "$guess" ]; then
    err "no account named '$1'. Did you mean: $(account_label "$guess")? Use the full name."
  else
    err "no account named '$1'. See: cdt list"
  fi
  return 1
}

_norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }

# Resolve a user query to exactly one slug. Matching ignores case and punctuation;
# an exact match on label or slug wins; among several matches, accounts with an
# empty data dir are dropped. Prints the slug, or explains and returns 1.
account_resolve() {
  local query="$1" q s l hits="" exact="" used="" n
  q="$(_norm "$query")"
  [ -n "$q" ] || { err "empty account name"; return 1; }
  for s in $(account_slugs); do
    l="$(_norm "$(account_label "$s")")"
    if [ "$s" = "$q" ] || [ "$l" = "$q" ]; then exact="$exact $s"; fi
    case "$s $l" in *"$q"*) hits="$hits $s" ;; esac
  done
  # shellcheck disable=SC2086
  set -- $exact
  if [ $# -eq 1 ]; then echo "$1"; return 0; fi
  # shellcheck disable=SC2086
  set -- $hits
  n=$#
  if [ "$n" -gt 1 ]; then
    for s in "$@"; do account_is_empty "$s" || used="$used $s"; done
    # shellcheck disable=SC2086
    set -- $used
    if [ $# -eq 1 ]; then echo "$1"; return 0; fi
    # shellcheck disable=SC2086
    set -- $hits
  fi
  if [ "$n" -eq 0 ]; then
    err "no account matches '$query'. See: cdt list"
    return 1
  fi
  if [ "$n" -gt 1 ]; then
    err "several accounts match '$query':"
    for s in "$@"; do printf '  %s (%s)\n' "$(account_label "$s")" "$s" >&2; done
    return 1
  fi
  echo "$1"
}
