# shellcheck shell=bash
# `cdt import <data dir> --as <account>`: register an existing data dir (for example
# one made by another launcher) without moving it, then build its clone.

import_dir() { # data_dir label
  local given="$1" label="$2" slug dir
  [ -d "$given" ] || { err "not a directory: $given"; return 1; }
  given="$(cd "$given" && pwd)" || return 1
  dir="$(cd "$given" && pwd -P)" || return 1
  label_check "$label" || return 1
  slug="$(slugify "$label")"
  # Plain Claude.app runs on the default data dir without telling anyone; sharing it
  # with a clone would mean two writers on one profile.
  if [ "$dir" = "$(cd "$CDT_DEFAULT_DATA_DIR" 2>/dev/null && pwd -P)" ]; then
    err "$given is the data dir of plain Claude.app and cannot be imported."
    err "Add a new account instead with: cdt add <account>"
    return 1
  fi
  if account_exists "$slug"; then
    err "account '$label' already exists ($slug). See: cdt list"
    return 1
  fi
  local p
  for p in "$given" "$dir"; do
    if account_for_data_dir "$p" >/dev/null; then
      err "$p is already registered as $(account_label "$(account_for_data_dir "$p")")"
      return 1
    fi
  done
  # A running instance may have been started on the path as given or resolved.
  if [ -n "$(data_dir_pids "$given")$(data_dir_pids "$dir")" ]; then
    err "$dir is in use by a running Claude; quit it first."
    return 1
  fi
  if [ -e "$CDT_APPS_DIR/$(app_name_for "$label").app" ]; then
    err "an app already exists at $CDT_APPS_DIR/$(app_name_for "$label").app"
    return 1
  fi
  account_create "$slug" "$label" "$dir" || { err "cannot write the account registry"; return 1; }
  if ! clone_build "$slug"; then
    account_delete "$slug"
    return 1
  fi
  clone_request_permission "$slug"
  info "imported $dir as $label. Open it with: cdt open $label"
}

cmd_import() {
  local dir="" label="" a
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --as) label="${1:-}"; shift ;;
      -*) die "unknown option: $a" ;;
      *) dir="$a" ;;
    esac
  done
  [ -n "$dir" ] && [ -n "$label" ] || die "usage: cdt import <data dir> --as <account>"
  import_dir "$dir" "$label" || exit 1
}
