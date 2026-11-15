# shellcheck shell=bash
# shellcheck disable=SC2034 # variables are used by the other lib files
# Shared paths, logging and small helpers. Every path derives from HOME so tests and
# `brew test` can run against a temporary home.

CDT_VERSION="0.1.0"
CDT_NAME="claude-desktop-twins"
CDT_BUNDLE_PREFIX="local.claude-desktop-twins"

CLAUDE_APP="${CLAUDE_APP:-/Applications/Claude.app}"
CDT_APPS_DIR="${CDT_APPS_DIR:-$HOME/Applications/Claude Desktop Twins}"
CDT_DATA_ROOT="${CDT_DATA_ROOT:-$HOME/Library/Application Support/claude-desktop-twins}"
CDT_ACCOUNTS_DIR="$CDT_DATA_ROOT/accounts"
CDT_PROFILES_DIR="$CDT_DATA_ROOT/profiles"
CDT_BACKUPS_DIR="$CDT_DATA_ROOT/backups"
CDT_BIN_DIR="$CDT_DATA_ROOT/bin"
CDT_ICONS_DIR="$CDT_DATA_ROOT/icons"
CDT_DEFAULT_DATA_DIR="$HOME/Library/Application Support/Claude"
CDT_TRANSCRIPTS_DIR="${CDT_TRANSCRIPTS_DIR:-$HOME/.claude/projects}"
CDT_LSREGISTER="${CDT_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err() { printf 'cdt: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

# Run a command; on failure print it and return 1. Used for build steps where each
# failure must stop the build but must not exit the whole CLI.
step() {
  "$@" || { err "step failed: $*"; return 1; }
}

# Lowercase, keep only [a-z0-9]: "Work@Example.com" -> "workexamplecom".
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

bundle_id_for() { printf '%s.%s' "$CDT_BUNDLE_PREFIX" "$1"; }

# File name for a clone: the label with path separators replaced.
app_name_for() { printf '%s' "$1" | tr '/:' '--'; }

plist_get() { # file key -> value, empty on missing
  plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

plist_set_string() { # file key value
  plutil -replace "$2" -string "$3" "$1"
}

claude_version() {
  plist_get "$CLAUDE_APP/Contents/Info.plist" CFBundleShortVersionString
}

claude_app_ok() { [ -x "$CLAUDE_APP/Contents/MacOS/Claude" ] && [ -f "$CLAUDE_APP/Contents/Info.plist" ]; }

# Numeric dotted-version compare: prints -1, 0 or 1.
version_cmp() {
  local a="$1" b="$2" x y
  while [ -n "$a" ] || [ -n "$b" ]; do
    x="${a%%.*}"; y="${b%%.*}"
    # Keep digits only, so "6-beta" compares as 6 instead of failing under set -u.
    x="$(printf '%s' "$x" | tr -cd '0-9')"; y="$(printf '%s' "$y" | tr -cd '0-9')"
    [ "$a" = "${a#*.}" ] && a="" || a="${a#*.}"
    [ "$b" = "${b#*.}" ] && b="" || b="${b#*.}"
    x=$((10#${x:-0})); y=$((10#${y:-0}))
    [ "$x" -lt "$y" ] && { echo -1; return; }
    [ "$x" -gt "$y" ] && { echo 1; return; }
  done
  echo 0
}

dir_is_empty() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }

# Ask a yes/no question on stdin; default no.
confirm() {
  local answer
  printf '%s [y/N] ' "$1" >&2
  read -r answer || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Move a path to the user's Trash without needing Finder automation permission.
move_to_trash() {
  local src="$1" dest
  mkdir -p "$HOME/.Trash"
  dest="$HOME/.Trash/$(basename "$src") $(date +%Y%m%d-%H%M%S)"
  mv "$src" "$dest" && info "moved to Trash: $src"
}
