# shellcheck shell=bash
# `cdt uninstall [--purge-data]`: remove every clone, LaunchServices entry, the helper
# and the registry. Data dirs and backups stay unless --purge-data.

cmd_uninstall() {
  local purge=0 a s running="" kept=""
  for a in "$@"; do
    case "$a" in
      --purge-data) purge=1 ;;
      *) die "usage: cdt uninstall [--purge-data]" ;;
    esac
  done

  for s in $(account_slugs); do
    if clone_is_running "$s" || [ -n "$(account_pid "$s")" ]; then
      running="$running $(account_label "$s")"
    fi
  done
  [ -z "$running" ] || die "quit these accounts first:$running"

  if [ "$purge" = 1 ]; then
    confirm "Move every account's data dir and all session backups to the Trash?" ||
      die "cancelled; nothing removed."
  fi

  for s in $(account_slugs); do
    local data
    data="$(account_data_dir "$s")"
    clone_remove "$s" || exit 1
    account_delete "$s"
    if [ -e "$data" ]; then
      case "$data" in
        "$CDT_PROFILES_DIR"/*)
          if [ "$purge" = 1 ]; then move_to_trash "$data"; else kept="$kept\n  $data"; fi ;;
        *)
          # Imported dirs belong to the user or another tool; never purge them.
          kept="$kept\n  $data (imported, never purged)" ;;
      esac
    fi
  done

  # Leftover clones whose registry entry is gone.
  local app
  for app in "$CDT_APPS_DIR"/*.app "$CDT_APPS_DIR"/.*.app; do
    [ -e "$app" ] || continue
    "$CDT_LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    rm -rf "$app" && info "removed: $app"
  done
  rm -rf "$CDT_APPS_DIR/.cdt-work"
  [ -d "$CDT_APPS_DIR" ] && rmdir "$CDT_APPS_DIR" 2>/dev/null

  rm -rf "$CDT_BIN_DIR" "$CDT_ACCOUNTS_DIR"
  if [ -d "$CDT_BACKUPS_DIR" ]; then
    if [ "$purge" = 1 ]; then move_to_trash "$CDT_BACKUPS_DIR"; else kept="$kept\n  $CDT_BACKUPS_DIR"; fi
  fi
  [ -d "$CDT_PROFILES_DIR" ] && rmdir "$CDT_PROFILES_DIR" 2>/dev/null
  [ -d "$CDT_DATA_ROOT" ] && rmdir "$CDT_DATA_ROOT" 2>/dev/null

  info "removed all clones, the helper and the registry."
  if [ -n "$kept" ]; then
    printf 'kept:%b\n' "$kept"
    info "remove them with: cdt uninstall --purge-data (imported dirs stay), or delete them yourself."
  fi
  info "to remove the command itself: brew uninstall claude-desktop-twins"
  return 0
}
