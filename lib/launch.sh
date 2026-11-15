# shellcheck shell=bash
# Open, focus and list accounts. Opening never starts a second instance on a data dir
# that is in use: Claude does not always hand off to the running instance, and two
# writers on one profile corrupt IndexedDB.

CDT_OPEN="${CDT_OPEN:-open}"

# PIDs of Claude main processes running on a data dir, one per line. Only processes
# whose executable is a Claude binary count, so a shell whose command line mentions
# the path is never mistaken for a running account.
#
# The flag must be followed by the next flag or the end of the command line, so
# "/x/Claude" does not match a process on "/x/Claude Work". Plain Claude.app runs on
# the default data dir without the flag, so for that dir a flagless process counts.
data_dir_pids() { # data_dir
  local pid cmd is_default=0
  [ "$1" = "$CDT_DEFAULT_DATA_DIR" ] && is_default=1
  for pid in $(ps -axo pid=,comm= | awk '/\/Contents\/MacOS\/Claude$/ {print $1}'); do
    cmd="$(ps -o command= -p "$pid" 2>/dev/null) "
    case "$cmd" in
      *" --user-data-dir=$1 -"*|*" --user-data-dir=$1 ") echo "$pid" ;;
      *" --user-data-dir="*) ;;
      *) [ "$is_default" = 1 ] && echo "$pid" ;;
    esac
  done
  return 0
}

account_pid() { # slug -> first main PID, empty when not running
  data_dir_pids "$(account_data_dir "$1")" | head -n 1
}

account_focus() { # slug pid
  local h
  h="$(clone_path "$1")/Contents/MacOS/cdt-helper"
  if [ -x "$h" ] && "$h" --focus "$2" >/dev/null 2>&1; then
    return 0
  fi
  info "could not bring $(account_label "$1") forward; switch to it with Cmd-Tab."
  return 1
}

account_open() { # slug
  local slug="$1" label pid app
  label="$(account_label "$slug")"
  pid="$(account_pid "$slug")"
  if [ -n "$pid" ]; then
    info "$label is running (pid $pid); bringing it forward."
    account_focus "$slug" "$pid"
    return 0
  fi
  app="$(clone_path "$slug")"
  [ -d "$app" ] || { err "no app for $label at $app. Run: cdt rebuild $label"; return 1; }
  clone_is_stale "$slug" && info "$(stale_message "$slug")"
  info "opening $label"
  "$CDT_OPEN" "$app"
}

describe_account() { # slug -> one line for menus and list
  local s="$1" tags=""
  [ -n "$(account_pid "$s")" ] && tags="$tags [running]"
  account_is_empty "$s" && tags="$tags [empty, sign in needed]"
  clone_is_stale "$s" && tags="$tags [stale]"
  printf '%s (%s)%s' "$(account_label "$s")" "$s" "$tags"
}

cmd_open() {
  local slug
  if [ -z "${1:-}" ]; then
    cmd_menu
    return
  fi
  slug="$(account_resolve "$1")" || exit 1
  account_open "$slug" || exit 1
}

cmd_menu() {
  local slugs=() opts=() s
  for s in $(account_slugs); do
    slugs+=("$s")
    opts+=("$(describe_account "$s")")
  done
  if [ ${#slugs[@]} -eq 0 ]; then
    info "no accounts yet: run cdt add <account>"
    return 0
  fi
  PS3="Account number (Ctrl-C to quit): "
  select _ in "${opts[@]}"; do
    case "$REPLY" in
      ''|*[!0-9]*) info "not a number in the list"; continue ;;
    esac
    if [ "$REPLY" -lt 1 ] || [ "$REPLY" -gt ${#slugs[@]} ]; then
      info "not a number in the list"
      continue
    fi
    account_open "${slugs[$((REPLY - 1))]}" || exit 1
    return 0
  done
  return 1
}

cmd_list() {
  local s current any=0 running version empty state
  current="$(claude_version)"
  printf '%-32s %-24s %-8s %-14s %s\n' LABEL SLUG RUNNING CLONE STATE
  for s in $(account_slugs); do
    any=1
    running=no; [ -n "$(account_pid "$s")" ] && running=yes
    version="$(clone_version "$s")"; [ -n "$version" ] || version="missing"
    empty=""; account_is_empty "$s" && empty="empty data dir"
    if [ "$version" = "missing" ]; then
      state="no app; run: cdt rebuild $(account_label "$s")"
    elif clone_is_stale "$s"; then
      state="stale"
    else
      state="current"
    fi
    [ -n "$empty" ] && state="$state, $empty"
    printf '%-32s %-24s %-8s %-14s %s\n' "$(account_label "$s")" "$s" "$running" "$version" "$state"
  done
  [ "$any" = 1 ] || info "no accounts yet: run cdt add <account>"
  info "Claude.app: ${current:-not found at $CLAUDE_APP}"
  for s in $(account_slugs); do
    if [ -n "$(clone_version "$s")" ] && clone_is_stale "$s"; then
      info "$(stale_message "$s")"
    fi
  done
}
