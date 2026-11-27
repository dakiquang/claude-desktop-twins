# shellcheck shell=bash
# Build, refresh and delete a per-account clone of Claude.app.
#
# A clone is an APFS copy of Claude.app with its own bundle id. Only the main
# executable, the launcher, the helper and the outer seal are re-signed (ad-hoc), so
# the clone shares almost all its blocks with Claude.app. Updates are not touched:
# the clone's ad-hoc signature fails Squirrel's check, so the user updates the
# original Claude.app and then runs `cdt rebuild <account>`.

clone_path() { # slug
  printf '%s/%s.app' "$CDT_APPS_DIR" "$(app_name_for "$(account_label "$1")")"
}

clone_version() { # slug -> Claude version the clone was built from
  plist_get "$(clone_path "$1")/Contents/Info.plist" LocalSourceVersion
}

# Stale = the clone was built from a different Claude.app version than the one
# installed now. Public: the later menu bar app reuses it.
clone_is_stale() { # slug
  local built current
  built="$(clone_version "$1")"
  current="$(claude_version)"
  [ -n "$current" ] && [ "$built" != "$current" ]
}

stale_message() { # slug
  printf 'stale: built for %s, Claude.app is %s. Run: cdt rebuild %s' \
    "$(clone_version "$1")" "$(claude_version)" "$(account_label "$1")"
}

# True when a process runs the clone's own executable. Matches by executable path
# (ps comm), never by command line, so a shell that mentions the path is ignored.
clone_is_running() { # slug
  # shellcheck disable=SC2009 # pgrep -f matches command lines, which is the bug avoided here
  # grep without -q reads all input: with pipefail, an early exit would kill ps with
  # SIGPIPE and make a running account look stopped.
  ps -axo comm= | grep -xF "$(clone_path "$1")/Contents/MacOS/Claude" >/dev/null
}

# Path of a usable helper binary: the one Homebrew built, else one built on demand.
helper_path() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [ -x "$root/libexec/cdt-helper" ]; then
    echo "$root/libexec/cdt-helper"
  else
    echo "$CDT_BIN_DIR/cdt-helper"
  fi
}

helper_source() {
  printf '%s/helper/cdt-helper.swift' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

# Build the universal helper once into $CDT_BIN_DIR.
helper_build() {
  local src out tmp
  src="$(helper_source)"
  out="$CDT_BIN_DIR/cdt-helper"
  [ -f "$src" ] || { err "helper source not found: $src"; return 1; }
  command -v swiftc >/dev/null 2>&1 ||
    { err "swiftc not found. Install the Command Line Tools: xcode-select --install"; return 1; }
  mkdir -p "$CDT_BIN_DIR" || return 1
  tmp="$(mktemp -d -t cdt-helper)" || return 1
  info "building cdt-helper (one time)"
  step swiftc -O -target arm64-apple-macos12 -o "$tmp/arm64" "$src" &&
    step swiftc -O -target x86_64-apple-macos12 -o "$tmp/x86_64" "$src" &&
    step lipo -create -output "$out" "$tmp/arm64" "$tmp/x86_64"
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

helper_ensure() {
  local h
  h="$(helper_path)"
  [ -x "$h" ] && return 0
  helper_build
}

_write_launcher() { # file data_dir
  {
    printf '#!/bin/bash\n'
    printf '# Starts this account on its own data dir. exec keeps the PID, so LaunchServices\n'
    printf '# sees the bundle.\n'
    # shellcheck disable=SC2016 # the launcher expands these itself
    printf 'exec "$(dirname "$0")/Claude" --user-data-dir=%q "$@"\n' "$2"
  } > "$1" && chmod +x "$1"
}

_write_entitlements() { # file
  cat > "$1" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.virtualization</key><true/>
</dict></plist>
EOF
}

# Build the clone into a temp path next to the target, verify it, then swap it in.
# A failure at any step leaves the previous clone untouched.
clone_build() { # slug
  local slug="$1" label bid data dst tmp old c ent version helper
  label="$(account_label "$slug")"
  bid="$(account_bundle_id "$slug")"
  data="$(account_data_dir "$slug")"
  dst="$(clone_path "$slug")"
  # Build artefacts live in a work dir, so no account label can collide with them.
  tmp="$CDT_APPS_DIR/.cdt-work/$slug.building.app"
  old="$CDT_APPS_DIR/.cdt-work/$slug.old.app"

  claude_app_ok || { err "Claude.app not found at $CLAUDE_APP"; return 1; }
  if clone_is_running "$slug"; then
    err "$label is running; quit it first."
    return 1
  fi
  helper_ensure || return 1
  helper="$(helper_path)"
  version="$(claude_version)"

  # An interrupted rebuild can leave the only clone at $old: put it back first.
  if [ -e "$old" ] && [ ! -e "$dst" ]; then
    step mv "$old" "$dst" || return 1
  fi
  # Never recreate a missing imported data dir: that would hide a moved or deleted profile.
  if [ ! -d "$data" ]; then
    case "$data" in
      "$CDT_PROFILES_DIR"/*) ;;
      *) err "data dir not found: $data"; return 1 ;;
    esac
  fi
  mkdir -p "$CDT_APPS_DIR/.cdt-work" "$data" || return 1
  rm -rf "$tmp" "$old"
  step cp -cR "$CLAUDE_APP" "$tmp" || { rm -rf "$tmp"; return 1; }
  c="$tmp/Contents"
  ent="$(mktemp -t cdt-ent)"
  if ! _clone_customize "$c" "$bid" "$label" "$data" "$version" "$helper" "$ent" "$(account_get "$slug" IconFile 2>/dev/null)"; then
    rm -rf "$tmp" "$ent"
    err "build failed; the previous clone (if any) is unchanged."
    return 1
  fi
  rm -f "$ent"

  if [ -e "$dst" ]; then
    "$CDT_LSREGISTER" -u "$dst" >/dev/null 2>&1 || true
    step mv "$dst" "$old" || { rm -rf "$tmp"; return 1; }
  fi
  if ! step mv "$tmp" "$dst"; then
    [ -e "$old" ] && mv "$old" "$dst"
    return 1
  fi
  rm -rf "$old"
  "$CDT_LSREGISTER" -f "$dst" >/dev/null 2>&1 || warn "lsregister could not register $dst"
  account_set "$slug" SourceVersion "$version"
  update_block_apply "$slug"
  info "built: $dst ($bid, Claude $version)"
}

_clone_customize() { # contents bundle_id label data_dir version helper entitlements [icon]
  local c="$1" bid="$2" label="$3" data="$4" version="$5" helper="$6" ent="$7" icon="${8:-}"
  # Identity: own bundle id and name; drop URL schemes so claude:// stays with the
  # original app; the provisioning profile is bound to Anthropic's team id.
  step plutil -replace CFBundleIdentifier -string "$bid" "$c/Info.plist" || return 1
  step plutil -replace CFBundleDisplayName -string "Claude · $label" "$c/Info.plist" || return 1
  plutil -remove CFBundleURLTypes "$c/Info.plist" >/dev/null 2>&1 || true
  rm -f "$c/embedded.provisionprofile"
  step plutil -replace LocalSourceVersion -string "$version" "$c/Info.plist" || return 1
  # Which cdt built this clone, so another tool can tell a clone it can adopt.
  step plutil -replace CDTBuilderVersion -string "$CDT_VERSION" "$c/Info.plist" || return 1

  # A custom icon replaces the one from Assets.car: macOS prefers CFBundleIconName, so
  # drop it and point CFBundleIconFile at our icns. Set before signing.
  if [ -n "$icon" ]; then
    [ -f "$icon" ] || { err "icon file missing: $icon (run: cdt icon reset <account>)"; return 1; }
    step cp "$icon" "$c/Resources/cdt-account.icns" || return 1
    plutil -remove CFBundleIconName "$c/Info.plist" >/dev/null 2>&1 || true
    step plutil -replace CFBundleIconFile -string cdt-account.icns "$c/Info.plist" || return 1
  fi

  step _write_launcher "$c/MacOS/launcher" "$data" || return 1
  step plutil -replace CFBundleExecutable -string launcher "$c/Info.plist" || return 1

  # The signing identifier must equal the bundle id: usernotificationsd checks that
  # they match before it lets a process ask for or post notifications. Keep only
  # entitlements that do not need Anthropic's team id; no hardened runtime, so the
  # ad-hoc main binary may load the Anthropic-signed frameworks.
  step _write_entitlements "$ent" || return 1
  step codesign --force --sign - --identifier "$bid" --entitlements "$ent" "$c/MacOS/Claude" 2>/dev/null || return 1
  step cp "$helper" "$c/MacOS/cdt-helper" || return 1
  step codesign --force --sign - --identifier "$bid" "$c/MacOS/cdt-helper" 2>/dev/null || return 1
  step codesign --force --sign - "${c%/Contents}" 2>/dev/null || return 1
  step codesign --verify --strict "${c%/Contents}" || return 1
}

# Unregister and delete the clone. Refuses while the account runs.
clone_remove() { # slug
  local dst
  dst="$(clone_path "$1")"
  if clone_is_running "$1"; then
    err "$(account_label "$1") is running; quit it first."
    return 1
  fi
  [ -e "$dst" ] || return 0
  "$CDT_LSREGISTER" -u "$dst" >/dev/null 2>&1 || true
  rm -rf "$dst" && info "removed: $dst"
}

# Run the clone's helper so macOS asks for notification permission on its behalf.
clone_request_permission() { # slug
  local h rc label
  label="$(account_label "$1")"
  h="$(clone_path "$1")/Contents/MacOS/cdt-helper"
  info "asking macOS for notification permission for $label (click Allow)"
  "$h" >/dev/null 2>&1
  rc=$?
  case $rc in
    0) info "notifications: allowed" ;;
    1) warn "notifications were not allowed for $label. Allow them in System Settings > Notifications, or retry: \"$h\"" ;;
    *) warn "no answer to the notification prompt for $label. Retry: \"$h\"" ;;
  esac
  return 0
}

cmd_add() {
  local label="${1:-}" slug data
  [ -n "$label" ] || die "usage: cdt add <account>"
  label_check "$label" || exit 1
  slug="$(slugify "$label")"
  account_exists "$slug" && die "account '$label' already exists ($slug). See: cdt list"
  data="$CDT_PROFILES_DIR/$slug"
  [ -e "$CDT_APPS_DIR/$(app_name_for "$label").app" ] &&
    die "an app already exists at $CDT_APPS_DIR/$(app_name_for "$label").app"
  mkdir -p "$data" || die "cannot create $data"
  account_create "$slug" "$label" "$data" || die "cannot write the account registry"
  if ! clone_build "$slug"; then
    account_delete "$slug"
    dir_is_empty "$data" && rmdir "$data"
    exit 1
  fi
  clone_request_permission "$slug"
  info "open it with: cdt open $label"
}

# macOS keeps each app's notification icon in usernoted and NotificationCenter and does
# not notice a new icns, so banners keep showing the old icon after `cdt icon`. Both
# services restart on their own within a second; restarting them picks up the new icon
# (checked on macOS 26, 27/11/2026: a stale teal badge turned orange-red).
_notification_icons_refresh() {
  "$CDT_KILLALL" usernoted NotificationCenter >/dev/null 2>&1 || true
}

# `cdt icon set <account> <file.icns>` / `cdt icon reset <account>`: give an account's
# app its own Dock and Cmd-Tab icon. The file is copied into the tool's data folder and
# applied on every rebuild.
cmd_icon() {
  local sub="${1:-}" slug file dest
  [ $# -gt 0 ] && shift
  case "$sub" in
    set)
      [ $# -eq 2 ] || die "usage: cdt icon set <account> <file.icns>"
      slug="$(account_resolve_exact "$1")" || exit 1
      file="$2"
      [ -f "$file" ] || die "file not found: $file"
      # Real .icns files start with the magic bytes "icns"; sips trusts the extension.
      [ "$(head -c 4 "$file" 2>/dev/null)" = icns ] || die "not an .icns file: $file"
      clone_is_running "$slug" && die "$(account_label "$slug") is running; quit it first."
      mkdir -p "$CDT_ICONS_DIR" || exit 1
      dest="$CDT_ICONS_DIR/$slug.icns"
      if ! { cp "$file" "$dest.tmp" && mv -f "$dest.tmp" "$dest"; }; then die "cannot copy $file"; fi
      account_set "$slug" IconFile "$dest" || exit 1
      clone_build "$slug" || exit 1
      _notification_icons_refresh
      info "icon set for $(account_label "$slug"); the Dock may need a moment to refresh"
      ;;
    reset)
      [ $# -eq 1 ] || die "usage: cdt icon reset <account>"
      slug="$(account_resolve_exact "$1")" || exit 1
      clone_is_running "$slug" && die "$(account_label "$slug") is running; quit it first."
      plutil -remove IconFile "$(account_file "$slug")" >/dev/null 2>&1 || true
      rm -f "$CDT_ICONS_DIR/$slug.icns"
      clone_build "$slug" || exit 1
      _notification_icons_refresh
      info "icon reset for $(account_label "$slug")"
      ;;
    *) die "usage: cdt icon set <account> <file.icns> | cdt icon reset <account>" ;;
  esac
}

cmd_rebuild() {
  local slug
  [ -n "${1:-}" ] || die "usage: cdt rebuild <account>"
  slug="$(account_resolve_exact "$1")" || exit 1
  clone_build "$slug" || exit 1
}

cmd_remove() {
  local query="" purge=0 slug data label a
  for a in "$@"; do
    case "$a" in
      --purge) purge=1 ;;
      -*) die "unknown option: $a" ;;
      *) query="$a" ;;
    esac
  done
  [ -n "$query" ] || die "usage: cdt remove <account> [--purge]"
  slug="$(account_resolve_exact "$query")" || exit 1
  data="$(account_data_dir "$slug")"
  label="$(account_label "$slug")"
  # Any Claude on this data dir counts, also one started by another launcher.
  if clone_is_running "$slug" || [ -n "$(account_pid "$slug")" ]; then
    die "$label is running; quit it first."
  fi
  # Only data dirs this tool created are ever purged; imported ones belong to the user.
  case "$data" in
    "$CDT_PROFILES_DIR"/*) ;;
    *) [ "$purge" = 1 ] && info "imported data dir, never purged: $data"; purge=0 ;;
  esac
  if [ "$purge" = 1 ] && [ -e "$data" ]; then
    confirm "Move the data dir of $label to the Trash? $data" ||
      die "cancelled; nothing removed."
  fi
  clone_remove "$slug" || exit 1
  update_block_remove "$data"
  rm -f "$CDT_ICONS_DIR/$slug.icns"
  account_delete "$slug"
  info "unregistered: $label"
  if [ "$purge" = 1 ] && [ -e "$data" ]; then
    move_to_trash "$data" || exit 1
  elif [ -e "$data" ]; then
    info "kept data dir: $data"
  fi
}